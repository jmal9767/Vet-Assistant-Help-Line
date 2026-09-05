import Foundation

struct GuidedQuestion: Identifiable, Hashable, Sendable {
    let id: String
    let prompt: String
    let supportingText: String
    let placeholder: String
}

enum QuestionCategory: String, CaseIterable, Identifiable, Sendable {
    case groomingConcepts
    case enrichmentAndRoutines
    case newPetEnvironment
    case routineVisitPreparation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .groomingConcepts:
            "General grooming concepts"
        case .enrichmentAndRoutines:
            "Enrichment & routine basics"
        case .newPetEnvironment:
            "Crate, litter & new-pet environment"
        case .routineVisitPreparation:
            "Routine visit preparation"
        }
    }

    var summary: String {
        switch self {
        case .groomingConcepts:
            "Learn a general, nonmedical grooming concept without asking for an individualized plan or product."
        case .enrichmentAndRoutines:
            "Learn a general enrichment, basic-skill, or household-routine concept."
        case .newPetEnvironment:
            "Learn general crate, litter, home-setup, or settling-in concepts for a new pet."
        case .routineVisitPreparation:
            "Learn how to organize a nonmedical question list and practical preparation for a routine veterinary visit."
        }
    }

    var guidedQuestion: GuidedQuestion {
        switch self {
        case .groomingConcepts:
            GuidedQuestion(
                id: "grooming_concept",
                prompt: "What one general grooming concept would you like explained?",
                supportingText: "Do not include skin, coat, nail, eye, or ear symptoms, or ask for a product or individualized schedule.",
                placeholder: "For example, how to introduce routine brushing gradually"
            )

        case .enrichmentAndRoutines:
            GuidedQuestion(
                id: "enrichment_routine_concept",
                prompt: "What one general enrichment or household-routine concept would you like explained?",
                supportingText: "Do not ask for exercise intensity or frequency, an individual behavior assessment, or help with aggression or sudden behavior changes.",
                placeholder: "For example, ways to rotate simple indoor enrichment activities"
            )

        case .newPetEnvironment:
            GuidedQuestion(
                id: "new_pet_environment_concept",
                prompt: "What one general crate, litter, or new-pet environment concept would you like explained?",
                supportingText: "Do not include symptoms, an individual behavior assessment, or a medical-care question.",
                placeholder: "For example, the basic parts of a quiet settling-in area"
            )

        case .routineVisitPreparation:
            GuidedQuestion(
                id: "routine_visit_preparation",
                prompt: "What one general question do you have about preparing for a routine veterinary visit?",
                supportingText: "Do not list symptoms or ask for urgency, diagnosis, treatment, product, medication, test, or image guidance.",
                placeholder: "For example, how to organize a nonmedical question list"
            )
        }
    }
}
