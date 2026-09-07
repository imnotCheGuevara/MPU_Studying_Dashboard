import Foundation

struct DeterministicOrganizationRules: Sendable {
    func normalizedType(title: String, officialType: String) -> String? {
        let value = title.lowercased()
        if value.contains("quiz") || value.contains("test") { return "quiz" }
        if value.contains("read") || value.contains("chapter") { return "reading" }
        if ["assignment", "quiz", "reading"].contains(officialType.lowercased()) {
            return officialType.lowercased()
        }
        return nil
    }
}

struct DeterministicFakeAIProvider: AIParsingProvider {
    let providerName = "Campus Dashboard deterministic fixture"
    let modelName = "fixture-v1"

    func structuredSuggestion(for input: AIParseInput) async throws -> Data {
        let normalizedType = DeterministicOrganizationRules().normalizedType(
            title: input.title, officialType: input.officialType
        )
        let suggestedDate = firstMarker("date", in: input.minimalText).flatMap {
            ISO8601DateFormatter().date(from: $0)
        }
        let related = markers("related", in: input.minimalText)
        let actions = markers("action", in: input.minimalText)
        let explicitlyUncertain = input.minimalText.contains("[uncertain]")
        let normalizedTitle = input.title.replacingOccurrences(
            of: #"\s*\[[^\]]+\]"#, with: "", options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let response = AIProviderResponse(
            normalizedTitle: normalizedTitle,
            suggestedType: normalizedType,
            officialDateEcho: input.officialDueAt,
            suggestedDate: suggestedDate,
            relatedObjectIDs: related,
            actionItems: actions,
            confidence: normalizedType == nil ? 0.45 : 0.98,
            rationale: "Deterministic synthetic provider output; source fields remain authoritative.",
            hasConflict: explicitlyUncertain,
            changeSummary: suggestedDate == nil
                ? (normalizedType == nil ? "No deterministic classification." : "Suggested a local display type.")
                : "Suggested a local display type and an inferred date.",
            uncertain: normalizedType == nil || explicitlyUncertain
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(response)
    }

    private func firstMarker(_ name: String, in text: String) -> String? {
        markers(name, in: text).first
    }

    private func markers(_ name: String, in text: String) -> [String] {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let expression = try? NSRegularExpression(
            pattern: "\\[\(escaped):([^\\]]+)\\]"
        ) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let valueRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[valueRange])
        }
    }
}
