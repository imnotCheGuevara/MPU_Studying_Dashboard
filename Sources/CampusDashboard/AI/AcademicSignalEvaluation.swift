import Foundation

struct AcademicSignalEvaluationCase: Sendable {
    let expectedPrimary: AcademicSignalCategory
    let expectedSignals: Set<AcademicSignalCategory>
    let output: AcademicSignalProviderResponse
}

struct AcademicCategoryMetrics: Equatable, Sendable {
    let truePositive: Int
    let falsePositive: Int
    let falseNegative: Int
    let trueNegative: Int
    let precision: Double
    let recall: Double
    let f1: Double
}

struct AcademicSignalEvaluationReport: Equatable, Sendable {
    static let minimumPrecision = 0.90
    static let minimumRecall = 0.90

    let metrics: [AcademicSignalCategory: AcademicCategoryMetrics]
    let primaryConfusion: [AcademicSignalCategory: [AcademicSignalCategory: Int]]

    var passesThresholds: Bool {
        AcademicSignalCategory.allCases.allSatisfy {
            guard let value = metrics[$0] else { return false }
            return value.precision >= Self.minimumPrecision && value.recall >= Self.minimumRecall
        }
    }
}

enum AcademicSignalEvaluator {
    static func evaluate(_ cases: [AcademicSignalEvaluationCase]) -> AcademicSignalEvaluationReport {
        var metrics: [AcademicSignalCategory: AcademicCategoryMetrics] = [:]
        var confusion: [AcademicSignalCategory: [AcademicSignalCategory: Int]] = [:]
        for category in AcademicSignalCategory.allCases {
            var tp = 0, fp = 0, fn = 0, tn = 0
            for item in cases {
                let expected = category == .other
                    ? item.expectedPrimary == .other : item.expectedSignals.contains(category)
                let predictedCategories = Set(item.output.signals.map(\.category))
                let predicted = category == .other
                    ? item.output.primaryCategory == .other : predictedCategories.contains(category)
                switch (expected, predicted) {
                case (true, true): tp += 1
                case (false, true): fp += 1
                case (true, false): fn += 1
                case (false, false): tn += 1
                }
            }
            let precision = tp + fp == 0 ? 1 : Double(tp) / Double(tp + fp)
            let recall = tp + fn == 0 ? 1 : Double(tp) / Double(tp + fn)
            let f1 = precision + recall == 0 ? 0 : 2 * precision * recall / (precision + recall)
            metrics[category] = AcademicCategoryMetrics(
                truePositive: tp, falsePositive: fp, falseNegative: fn, trueNegative: tn,
                precision: precision, recall: recall, f1: f1
            )
        }
        for item in cases {
            confusion[item.expectedPrimary, default: [:]][item.output.primaryCategory, default: 0] += 1
        }
        return AcademicSignalEvaluationReport(metrics: metrics, primaryConfusion: confusion)
    }
}
