import Foundation

struct AISyntheticEvaluationCase: Sendable {
    let expectedType: String?
    let expectedRelatedObjectIDs: Set<String>
    let expectedDate: Date?
    let shouldBeUncertain: Bool
    let output: AIProviderResponse
}

struct AIEvaluationReport: Equatable, Sendable {
    let sampleCount: Int
    let classificationAccuracy: Double
    let duplicateSuggestionPrecision: Double
    let dateExtractionAccuracy: Double
    let uncertaintyRecall: Double
    let unauthorizedCalendarWrites: Int
    let unauthorizedNotificationWrites: Int
}

enum AISyntheticEvaluator {
    static func evaluate(
        _ cases: [AISyntheticEvaluationCase],
        unauthorizedCalendarWrites: Int,
        unauthorizedNotificationWrites: Int
    ) -> AIEvaluationReport {
        func ratio(_ numerator: Int, _ denominator: Int) -> Double {
            denominator == 0 ? 1 : Double(numerator) / Double(denominator)
        }
        let classifications = cases.filter { $0.expectedType != nil }
        let classificationHits = classifications.filter { $0.output.suggestedType == $0.expectedType }.count

        let suggestedRelations = cases.flatMap { item in
            item.output.relatedObjectIDs.map { (item.expectedRelatedObjectIDs, $0) }
        }
        let correctRelations = suggestedRelations.filter { expected, value in expected.contains(value) }.count

        let dated = cases.filter { $0.expectedDate != nil }
        let dateHits = dated.filter { item in
            guard let expected = item.expectedDate, let actual = item.output.suggestedDate else { return false }
            return abs(expected.timeIntervalSince(actual)) < 1
        }.count

        let uncertain = cases.filter(\.shouldBeUncertain)
        let uncertaintyHits = uncertain.filter { $0.output.uncertain || $0.output.hasConflict }.count
        return AIEvaluationReport(
            sampleCount: cases.count,
            classificationAccuracy: ratio(classificationHits, classifications.count),
            duplicateSuggestionPrecision: ratio(correctRelations, suggestedRelations.count),
            dateExtractionAccuracy: ratio(dateHits, dated.count),
            uncertaintyRecall: ratio(uncertaintyHits, uncertain.count),
            unauthorizedCalendarWrites: unauthorizedCalendarWrites,
            unauthorizedNotificationWrites: unauthorizedNotificationWrites
        )
    }
}
