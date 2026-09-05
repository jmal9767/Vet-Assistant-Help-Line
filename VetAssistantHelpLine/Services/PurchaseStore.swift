import Combine
import Foundation
import StoreKit

@MainActor
final class PurchaseStore: ObservableObject {
    enum State: Equatable {
        case loading
        case ready
        case purchasing
        case finishing
        case handoffUnresolved
        case pending
        case verificationFailed(String)
        case unavailable(String)
    }

    @Published private(set) var product: Product?
    @Published private(set) var credits: [PaidQuestionCredit] = []
    @Published private(set) var state: State = .loading

    private var transactionsByID: [UInt64: Transaction] = [:]
    private var verificationFailuresByTransactionID: [UInt64: String] = [:]
    private var finishingTasks: [UInt64: Task<Void, Never>] = [:]
    private var purchaseInFlight = false
    private var updatesTask: Task<Void, Never>?
    private let userDefaults: UserDefaults

    static let deliveryJournalKey =
        "com.bayareaapps.vetassistanthelpline.deliveredTransactionIDs"
    static let handoffJournalKey =
        "com.bayareaapps.vetassistanthelpline.unresolvedEmailHandoffTransactionIDs"
    static let lastCompletedTransactionIDKey =
        "com.bayareaapps.vetassistanthelpline.lastCompletedTransactionID"
    static let lastCompletedTransactionDateKey =
        "com.bayareaapps.vetassistanthelpline.lastCompletedTransactionDate"
    private static let pendingPurchaseTokenKey =
        "com.bayareaapps.vetassistanthelpline.pendingEducationPurchaseToken"
    private static let pendingPurchaseDateKey =
        "com.bayareaapps.vetassistanthelpline.pendingEducationPurchaseDate"

    var currentCredit: PaidQuestionCredit? {
        credits.first
    }

    var displayPrice: String? {
        product?.displayPrice
    }

    var unresolvedHandoffCredit: PaidQuestionCredit? {
        credits.first { handoffIsUnresolved(for: $0) }
    }

    var lastCompletedTransactionReference: String? {
        let recordedAt = userDefaults.double(
            forKey: Self.lastCompletedTransactionDateKey
        )
        let age = Date().timeIntervalSince1970 - recordedAt
        guard recordedAt > 0,
              age >= 0,
              age <= 90 * 24 * 60 * 60,
              let reference = userDefaults.string(
                forKey: Self.lastCompletedTransactionIDKey
              ),
              (1...32).contains(reference.utf8.count),
              reference.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            return nil
        }
        return reference
    }

    init(
        userDefaults: UserDefaults = .standard,
        startAutomatically: Bool = true
    ) {
        self.userDefaults = userDefaults
        pruneExpiredCompletedTransactionReference()

        if startAutomatically {
            updatesTask = Task { [weak self] in
                for await verificationResult in Transaction.updates {
                    guard let self else { return }
                    await self.receive(verificationResult)
                }
            }

            Task { [weak self] in
                await self?.prepare()
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func prepare() async {
        await recoverUnfinishedCredits()
        await loadProduct()
    }

    func reloadProduct() async {
        product = nil
        await loadProduct()
    }

    func retryTransactionRecovery() async {
        verificationFailuresByTransactionID.removeAll()
        await recoverUnfinishedCredits()
        if product == nil {
            await loadProduct()
        } else {
            refreshOperationalState()
        }
    }

    /// Use only after Apple or the family organizer shows that the pending
    /// approval was declined or expired and cannot produce a transaction update.
    func clearResolvedPendingPurchase() async {
        clearPendingPurchase()
        if product == nil {
            await loadProduct()
        } else {
            refreshOperationalState()
        }
    }

    func purchaseQuestionCredit(appAccountToken: UUID) async -> PurchaseOutcome {
        if !finishingTasks.isEmpty {
            state = .finishing
            return .failed(
                "The previous email handoff is still being finalized. Do not purchase again."
            )
        }

        if unresolvedHandoffCredit != nil {
            state = .handoffUnresolved
            return .failed(
                "Resolve the previous prepared email before using a question credit again."
            )
        }

        if let currentCredit {
            return .verified(currentCredit)
        }

        if purchaseInFlight {
            return .failed("An Apple purchase is already in progress.")
        }

        if pendingPurchaseWasRecorded {
            state = .pending
            return .pending
        }

        if let verificationFailure = firstVerificationFailure {
            state = .verificationFailed(verificationFailure)
            return .failed(verificationFailure)
        }

        guard let product else {
            let message = "Apple's purchase information is not available yet. Please try again."
            state = .unavailable(message)
            return .failed(message)
        }

        guard product.type == .consumable else {
            let message = "The Apple product is not configured as a consumable question credit."
            state = .unavailable(message)
            return .failed(message)
        }

        purchaseInFlight = true
        state = .purchasing
        defer { purchaseInFlight = false }

        do {
            switch try await product.purchase(
                options: [.appAccountToken(appAccountToken)]
            ) {
            case .success(let verificationResult):
                let signedTransactionJWS = verificationResult.jwsRepresentation
                switch verificationResult {
                case .verified(let transaction):
                    verificationFailuresByTransactionID[transaction.id] = nil

                    guard transaction.appAccountToken == appAccountToken else {
                        let message = "Apple returned a purchase that was not bound to this question. Contact support before purchasing again."
                        verificationFailuresByTransactionID[transaction.id] = message
                        state = .verificationFailed(message)
                        return .failed(message)
                    }

                    guard let credit = register(
                        transaction,
                        signedTransactionJWS: signedTransactionJWS
                    ) else {
                        let message = "Apple returned a purchase that could not be validated as this consumable question credit. Contact support before purchasing again."
                        verificationFailuresByTransactionID[transaction.id] = message
                        state = .verificationFailed(message)
                        return .failed(message)
                    }

                    clearPendingPurchase(ifMatching: transaction)
                    refreshOperationalState()
                    return .verified(credit)

                case .unverified(let transaction, _):
                    let message = "Apple could not verify this purchase. No question credit was granted. Contact support before trying another purchase."
                    verificationFailuresByTransactionID[transaction.id] = message
                    state = .verificationFailed(message)
                    return .failed(message)
                }

            case .pending:
                recordPendingPurchase(appAccountToken: appAccountToken)
                state = .pending
                return .pending

            case .userCancelled:
                refreshOperationalState()
                return .cancelled

            @unknown default:
                let message = "Apple returned an unsupported purchase result. Please try again."
                state = .unavailable(message)
                return .failed(message)
            }
        } catch {
            let message = "Apple could not complete the purchase: \(error.localizedDescription)"
            state = .unavailable(message)
            return .failed(message)
        }
    }

    /// Records that a complete paid email is about to be exposed to a mail
    /// provider or pasteboard. This survives relaunch so an uncertain handoff
    /// cannot silently create a second copy of the same paid submission.
    func markEmailHandoffStarted(for credit: PaidQuestionCredit) -> Bool {
        guard credits.contains(credit) || transactionsByID[credit.id] != nil else {
            return false
        }

        var ids = unresolvedHandoffIDs
        ids.insert(String(credit.id))
        unresolvedHandoffIDs = ids
        refreshOperationalState()
        return true
    }

    @discardableResult
    func clearEmailHandoff(for credit: PaidQuestionCredit) -> Bool {
        let transactionID = String(credit.id)
        guard unresolvedHandoffIDs.contains(transactionID) else {
            return false
        }

        var ids = unresolvedHandoffIDs
        ids.remove(transactionID)
        unresolvedHandoffIDs = ids
        refreshOperationalState()
        return true
    }

    func handoffIsUnresolved(for credit: PaidQuestionCredit) -> Bool {
        unresolvedHandoffIDs.contains(String(credit.id))
    }

    /// Journals the email-handoff decision before the async StoreKit finish call so a
    /// process interruption cannot accidentally restore an already-used credit.
    func recordDelivery(for credit: PaidQuestionCredit) -> Bool {
        guard credits.contains(credit) || transactionsByID[credit.id] != nil else {
            return false
        }

        recordDeliveryID(credit.id)
        recordCompletedTransactionReference(credit.id)
        state = .finishing
        return true
    }

    /// Called only after Apple Mail reports `.sent`, or after the client
    /// explicitly confirms that the fallback email was sent.
    func finishRecordedCredit(_ credit: PaidQuestionCredit) async -> Bool {
        guard deliveryWasRecorded(for: credit.id) else {
            state = .unavailable(
                "The email send decision was not recorded, so the paid credit was preserved."
            )
            return false
        }

        if transactionsByID[credit.id] == nil {
            await recoverUnfinishedCredits()

            // Recovery finishes a journaled transaction immediately. In that
            // case there is intentionally no transaction left to finish here.
            if transactionsByID[credit.id] == nil,
               !deliveryWasRecorded(for: credit.id) {
                if product == nil {
                    await loadProduct()
                } else {
                    refreshOperationalState()
                }
                return true
            }
        }

        guard let transaction = transactionsByID[credit.id] else {
            state = .unavailable(
                "The paid question credit could not be found. Please do not purchase again; contact support."
            )
            return false
        }

        await finishAndRemove(transaction)
        if product == nil {
            await loadProduct()
        } else {
            refreshOperationalState()
        }
        return true
    }

    private func loadProduct() async {
        if currentCredit == nil,
           firstVerificationFailure == nil,
           !pendingPurchaseWasRecorded {
            state = .loading
        }

        do {
            let products = try await Product.products(
                for: [HelplineConfig.educationQuestionProductID]
            )

            guard let matchingProduct = products.first(where: {
                $0.id == HelplineConfig.educationQuestionProductID
            }) else {
                setAvailabilityFailure(
                    "Apple's question product is currently unavailable. Please try again later."
                )
                return
            }

            guard matchingProduct.type == .consumable else {
                setAvailabilityFailure(
                    "The Apple product must be configured as a consumable question credit."
                )
                return
            }

            product = matchingProduct
            refreshOperationalState()
        } catch {
            setAvailabilityFailure(
                "Apple's purchase information could not be loaded: \(error.localizedDescription)"
            )
        }
    }

    private func recoverUnfinishedCredits() async {
        for await verificationResult in Transaction.unfinished {
            await receive(verificationResult)
        }
    }

    private func receive(_ verificationResult: VerificationResult<Transaction>) async {
        let signedTransactionJWS = verificationResult.jwsRepresentation

        switch verificationResult {
        case .verified(let transaction):
            guard transaction.productID == HelplineConfig.educationQuestionProductID else {
                return
            }

            verificationFailuresByTransactionID[transaction.id] = nil

            if transaction.revocationDate != nil {
                await finishAndRemove(transaction)
                refreshOperationalState()
                return
            }

            guard transaction.productType == .consumable else {
                let message = "Apple returned a non-consumable transaction for the question product. Contact support before purchasing again."
                verificationFailuresByTransactionID[transaction.id] = message
                state = .verificationFailed(message)
                return
            }

            if deliveryWasRecorded(for: transaction.id) {
                await finishAndRemove(transaction)
                if product == nil {
                    await loadProduct()
                } else {
                    refreshOperationalState()
                }
                return
            }

            if register(
                transaction,
                signedTransactionJWS: signedTransactionJWS
            ) != nil {
                clearPendingPurchase(ifMatching: transaction)
                refreshOperationalState()
            } else {
                let message = "Apple returned an unfinished purchase without the required question binding. Contact support before purchasing again."
                verificationFailuresByTransactionID[transaction.id] = message
                state = .verificationFailed(message)
            }

        case .unverified(let transaction, _):
            guard transaction.productID == HelplineConfig.educationQuestionProductID else {
                return
            }
            let message = "Apple could not verify an unfinished purchase. Contact support before purchasing again."
            verificationFailuresByTransactionID[transaction.id] = message
            state = .verificationFailed(message)
        }
    }

    @discardableResult
    private func register(
        _ transaction: Transaction,
        signedTransactionJWS: String
    ) -> PaidQuestionCredit? {
        guard transaction.productID == HelplineConfig.educationQuestionProductID,
              transaction.productType == .consumable,
              transaction.revocationDate == nil,
              transaction.appAccountToken != nil else {
            return nil
        }

        if let existingCredit = credits.first(where: { $0.id == transaction.id }) {
            transactionsByID[transaction.id] = transaction
            return existingCredit
        }

        let credit = PaidQuestionCredit(
            id: transaction.id,
            productID: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            appAccountToken: transaction.appAccountToken,
            environment: transaction.environment.rawValue,
            signedTransactionJWS: signedTransactionJWS
        )
        transactionsByID[transaction.id] = transaction
        credits.append(credit)
        credits.sort { $0.purchaseDate < $1.purchaseDate }
        return credit
    }

    private func finishAndRemove(_ transaction: Transaction) async {
        if let existingTask = finishingTasks[transaction.id] {
            state = .finishing
            await existingTask.value
            return
        }

        state = .finishing
        transactionsByID[transaction.id] = nil
        credits.removeAll { $0.id == transaction.id }

        let task = Task {
            await transaction.finish()
        }
        finishingTasks[transaction.id] = task
        await task.value
        finishingTasks[transaction.id] = nil

        clearRecordedDelivery(for: transaction.id)
        clearUnresolvedHandoff(for: transaction.id)
        verificationFailuresByTransactionID[transaction.id] = nil
    }

    private func refreshOperationalState() {
        if !finishingTasks.isEmpty {
            state = .finishing
        } else if unresolvedHandoffCredit != nil {
            state = .handoffUnresolved
        } else if currentCredit != nil {
            state = .ready
        } else if let verificationFailure = firstVerificationFailure {
            state = .verificationFailed(verificationFailure)
        } else if pendingPurchaseWasRecorded {
            state = .pending
        } else {
            state = product == nil ? .loading : .ready
        }
    }

    private func setAvailabilityFailure(_ message: String) {
        if !finishingTasks.isEmpty {
            state = .finishing
        } else if unresolvedHandoffCredit != nil {
            state = .handoffUnresolved
        } else if currentCredit != nil {
            state = .ready
        } else if let verificationFailure = firstVerificationFailure {
            state = .verificationFailed(verificationFailure)
        } else if pendingPurchaseWasRecorded {
            state = .pending
        } else {
            state = .unavailable(message)
        }
    }

    private var firstVerificationFailure: String? {
        verificationFailuresByTransactionID
            .sorted { $0.key < $1.key }
            .first?.value
    }

    private var pendingPurchaseWasRecorded: Bool {
        pendingPurchaseToken != nil
    }

    private var pendingPurchaseToken: UUID? {
        guard let value = userDefaults.string(forKey: Self.pendingPurchaseTokenKey) else {
            return nil
        }
        return UUID(uuidString: value)
    }

    private var pendingPurchaseDate: Date? {
        let timestamp = userDefaults.double(forKey: Self.pendingPurchaseDateKey)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    private func recordPendingPurchase(appAccountToken: UUID) {
        userDefaults.set(
            appAccountToken.uuidString,
            forKey: Self.pendingPurchaseTokenKey
        )
        userDefaults.set(
            Date().timeIntervalSince1970,
            forKey: Self.pendingPurchaseDateKey
        )
    }

    private func clearPendingPurchase(ifMatching transaction: Transaction) {
        guard let pendingPurchaseToken,
              transaction.appAccountToken == pendingPurchaseToken else {
            return
        }

        if let pendingPurchaseDate,
           transaction.purchaseDate < pendingPurchaseDate.addingTimeInterval(-5 * 60) {
            return
        }

        clearPendingPurchase()
    }

    private func clearPendingPurchase() {
        userDefaults.removeObject(forKey: Self.pendingPurchaseTokenKey)
        userDefaults.removeObject(forKey: Self.pendingPurchaseDateKey)
    }

    private var recordedDeliveryIDs: Set<String> {
        get {
            Set(userDefaults.stringArray(forKey: Self.deliveryJournalKey) ?? [])
        }
        set {
            userDefaults.set(Array(newValue).sorted(), forKey: Self.deliveryJournalKey)
        }
    }

    private var unresolvedHandoffIDs: Set<String> {
        get {
            Set(userDefaults.stringArray(forKey: Self.handoffJournalKey) ?? [])
        }
        set {
            userDefaults.set(Array(newValue).sorted(), forKey: Self.handoffJournalKey)
        }
    }

    private func deliveryWasRecorded(for transactionID: UInt64) -> Bool {
        recordedDeliveryIDs.contains(String(transactionID))
    }

    private func recordDeliveryID(_ transactionID: UInt64) {
        var ids = recordedDeliveryIDs
        ids.insert(String(transactionID))
        recordedDeliveryIDs = ids
    }

    private func clearRecordedDelivery(for transactionID: UInt64) {
        var ids = recordedDeliveryIDs
        ids.remove(String(transactionID))
        recordedDeliveryIDs = ids
    }

    private func clearUnresolvedHandoff(for transactionID: UInt64) {
        var ids = unresolvedHandoffIDs
        ids.remove(String(transactionID))
        unresolvedHandoffIDs = ids
    }

    private func recordCompletedTransactionReference(_ transactionID: UInt64) {
        userDefaults.set(
            String(transactionID),
            forKey: Self.lastCompletedTransactionIDKey
        )
        userDefaults.set(
            Date().timeIntervalSince1970,
            forKey: Self.lastCompletedTransactionDateKey
        )
    }

    private func pruneExpiredCompletedTransactionReference() {
        guard lastCompletedTransactionReference == nil else { return }
        userDefaults.removeObject(forKey: Self.lastCompletedTransactionIDKey)
        userDefaults.removeObject(forKey: Self.lastCompletedTransactionDateKey)
    }
}
