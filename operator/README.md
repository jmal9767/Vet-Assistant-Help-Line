# Paid-question verification

Do not accept an email as a new paid question merely because it contains a
transaction number. The native app binds each purchase to the submission UUID
with StoreKit's `appAccountToken` and includes Apple's signed transaction JWS.
This operator tool derives both identifiers from that verified JWS, checks fresh
transaction data with Apple's official App Store Server Library, and atomically
records a one-way transaction hash so the same purchase cannot be accepted
twice. Transaction and submission text copied from the editable email body is
never verifier input.

This is a launch requirement, not an optional diagnostic. A direct new-thread
question without valid Apple-signed Production proof and a transaction available
for first redemption in the operator ledger is free administrative support only
and must not receive a new paid educational answer. An authorized same-thread
replacement and an exact technical resend are reconciled to the canonical paid
thread under the operator workflow; neither reruns or redeems the transaction.

## One-time setup

1. Install Python 3.12 and create a dedicated Python 3.12 virtual environment
   outside the repository or in an ignored `.venv` directory. The checked-in lock
   is generated and tested for Python 3.12; do not use an ambient older runtime.
2. Install the fully pinned, hash-locked dependency set:

   ```sh
   python3.12 -m venv .venv
   .venv/bin/pip install --require-hashes --requirement operator/requirements.lock
   ```

3. Download the current Apple root certificates directly from
   [Apple PKI](https://www.apple.com/certificateauthority/). Keep the DER files
   outside source control, verify their published fingerprints through a second
   trusted Apple-controlled source, and review Apple's list when certificates
   change. Never use a certificate supplied by a customer or attached to an
   incoming message.
4. Find the app's numeric Apple ID in App Store Connect. This is not the bundle
   ID or StoreKit transaction ID.
5. In App Store Connect, create an In-App Purchase API key and record its key ID
   and issuer ID. Keep the `.p8` private key outside source control in a protected
   secret location readable only by the operator.
6. Choose an encrypted, access-controlled location outside the repository for
   `production-redemptions.sqlite3`; back it up and restrict it to the operator.
7. Generate a separate 32-byte-or-longer random HMAC key, store it outside the
   repository with mode `0600`, and back it up separately. Do not overwrite or
   simply rotate it: the ledger contains only one-way hashes, so a replacement key
   cannot recreate or check the earlier digests. If the key is lost or exposed,
   stop paid acceptance and new sales, preserve the ledger and incident evidence,
   and use a separately reviewed, versioned multi-key/new-epoch recovery procedure.
   If the old key is unavailable, replay safety cannot be restored from the ledger
   alone; reconcile affected purchases and refund or wind down as necessary.

On its first use, a new empty ledger pins its schema version, environment, and a
one-way HMAC key fingerprint. Every later run must match all three. The tool
refuses a populated older ledger that lacks this metadata because it cannot prove
which key created the existing hashes. If that occurs, stop paid acceptance,
preserve the ledger and key, and complete a separately reviewed migration; never
delete or recreate the ledger to bypass the check.

The tool verifies the archived emailed JWS against its Apple-signed date, derives
the signed transaction ID and `appAccountToken`, validates its product fields,
and only then queries Apple's App Store Server API. It verifies that fresh server
JWS with current-time certificate and online revocation checks and compares the
identifiers, product, quantity, and refund or revocation state. The historical
mode preserves the published non-expiring-credit behavior without weakening the
required fresh Apple proof. Do not put signing keys, HMAC keys, mailbox
credentials, customer emails, questions, or JWS files in this repository or in
the redemption ledger.

`requirements.txt` is the reviewed direct-dependency input;
`requirements.lock` is the Python 3.12 transitive lock used for every install. To
update it, use an isolated Python 3.12 environment with `pip-tools==7.5.3`, run
`pip-compile --generate-hashes`, review every version and hash change, run the full
contract suite, and scan the resulting lock with a reviewed vulnerability-audit
tool before adoption. Treat Dependabot output as a review request, never an
automatic production update.

## Verify and redeem an incoming production submission

1. Copy only the compact JWS from the message's
   `APPLE-SIGNED TRANSACTION PROOF (JWS)` block.
2. Run the tool, repeating `--root-certificate` for every current Apple root you
   downloaded:

   ```sh
   .venv/bin/python operator/redeem_question_credit.py \
     --ledger /secure/operator/production-redemptions.sqlite3 \
     --ledger-key-file /secure/operator/redemption-hmac.key \
     --private-key /secure/app-store/SubscriptionKey_ABC123.p8 \
     --key-id ABC123 \
     --issuer-id 01234567-89ab-cdef-0123-456789abcdef \
     --app-apple-id 1234567890 \
     --root-certificate /secure/apple-roots/AppleRootCA-G2.cer \
     --root-certificate /secure/apple-roots/AppleRootCA-G3.cer
   ```

   The command prompts for the JWS with terminal echo disabled. Paste the one-line
   value and press Return. The tool rejects input larger than 32 KiB. Clear the
   clipboard afterward. Use `--jws-file` only when an approved secure workflow
   requires a temporary file. The tool requires that file to be a regular,
   non-symlink file no larger than 32 KiB and, on POSIX systems, readable only by
   its owner (mode `0600`).

3. Accept the message as a new paid submission only when the command returns
   exit code `0` and prints `ACCEPTED`.
4. If a temporary JWS file was used, securely remove it after reconciliation.
   Keep the email only under the documented retention schedule.

`REJECTED` (exit `2`) means the archived emailed signature or signed fields did
not pass, or the fresh Apple-signed transaction did not match the required
environment, bundle, product, transaction identifier, token, type, quantity, or
revocation state.
`REPLAYED` (exit `3`) means that verified transaction is already in the ledger.
For a replay, first check whether the message is an exact technical resend in the
original thread. Never accept it as a second paid question.
`UNAVAILABLE` (exit `4`) means no safe verdict was reached because Apple lookup,
online certificate checking, credentials, dependencies, or the protected ledger
was unavailable or inconsistent. Leave the payment verdict undecided, add
`PAYMENT-HOLD`, do not alter the ledger, retry the exact proof, and immediately
pause new sales while any hold remains unresolved. Resume only under the tested
health and capacity conditions in the operator workflow.

## Testing

Sandbox must use a separate ledger and the explicit
`--allow-test-environment` flag. The production workflow must never accept an
Xcode or Sandbox proof. A successful Sandbox run prints `TEST-ONLY SANDBOX
VERIFIED`, never `ACCEPTED`, and explicitly says it is not a paid submission. The
ledger also refuses any attempt to mix Sandbox and Production or to change its
HMAC key.

Run the complete operator suite in the isolated environment after installing the
hash-locked dependency set:

```sh
.venv/bin/python -m unittest discover -s operator -p 'test_*.py'
```

Before launch and after changing Apple roots or the verifier library, also run a
secure, uncommitted aged-transaction fixture through the real installed library.
Confirm that the archived emailed/device JWS verifies using signed-date validation
and that its transaction ID is used to fetch a newly returned server JWS, which
must pass current-time online validation. Test current revocation rejection,
identifier mismatch, a temporary OCSP/API failure (`UNAVAILABLE`), and replay.
Never commit the fixture JWS, credentials, roots, or ledger.

The CLI materially improves a small, manual email operation, but it is not a
remote submission backend. It cannot prove inbox delivery, prevent a person from
sending arbitrary email, or bind the final editable Mail body to the signed
transaction. Replace it with an immutable server submission and atomic remote
redemption before scaling beyond a manually reconciled volume.
