import Foundation

enum AIStructuredOutputValidator {
    static let maximumOutputBytes = 32_768
    static let maximumNormalizedTitleLength = 240
    static let maximumSuggestedTypeLength = 80

    private static let keys: Set<String> = [
        "normalizedTitle", "suggestedType", "officialDateEcho", "suggestedDate",
        "relatedObjectIDs", "actionItems", "confidence", "rationale", "hasConflict",
        "changeSummary", "uncertain"
    ]

    static func decode(_ data: Data, input: AIParseInput) throws -> AIProviderResponse {
        guard data.count <= maximumOutputBytes else {
            throw AIParsingError.invalidOutput("provider output exceeds maximum byte size")
        }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) }
        catch { throw AIParsingError.invalidOutput("not valid JSON") }
        guard let dictionary = object as? [String: Any], Set(dictionary.keys) == keys else {
            throw AIParsingError.invalidOutput("schema keys do not match exactly")
        }
        guard dictionary["confidence"] is NSNumber,
              dictionary["rationale"] is String,
              dictionary["hasConflict"] is NSNumber,
              dictionary["changeSummary"] is String,
              dictionary["uncertain"] is NSNumber,
              dictionary["relatedObjectIDs"] is [Any],
              dictionary["actionItems"] is [Any]
        else { throw AIParsingError.invalidOutput("a required field has the wrong type") }
        for nullable in ["normalizedTitle", "suggestedType", "officialDateEcho", "suggestedDate"] {
            let value = dictionary[nullable]
            guard value is NSNull || value is String else {
                throw AIParsingError.invalidOutput("\(nullable) must be a string or null")
            }
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response: AIProviderResponse
        do { response = try decoder.decode(AIProviderResponse.self, from: data) }
        catch { throw AIParsingError.invalidOutput("typed decoding failed") }

        guard response.confidence.isFinite, (0...1).contains(response.confidence) else {
            throw AIParsingError.invalidOutput("confidence must be between zero and one")
        }
        guard !response.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              response.rationale.count <= 600,
              response.changeSummary.count <= 240,
              response.normalizedTitle.map({ !$0.isEmpty && $0.count <= maximumNormalizedTitleLength }) ?? true,
              response.suggestedType.map({ !$0.isEmpty && $0.count <= maximumSuggestedTypeLength }) ?? true,
              response.actionItems.count <= 8,
              response.relatedObjectIDs.count <= 8,
              response.actionItems.allSatisfy({ !$0.isEmpty && $0.count <= 240 }),
              response.relatedObjectIDs.allSatisfy({ !$0.isEmpty && $0.count <= 128 })
        else { throw AIParsingError.invalidOutput("output exceeds bounded field limits") }

        let allowedRelatedIDs = Set(input.knownObjectSummaries.map(\.objectID))
        guard response.relatedObjectIDs.allSatisfy(allowedRelatedIDs.contains) else {
            throw AIParsingError.invalidOutput("related object ID was not provided in known-object context")
        }

        if let echo = response.officialDateEcho {
            guard let official = input.officialDueAt, abs(echo.timeIntervalSince(official)) < 1 else {
                throw AIParsingError.invalidOutput("official-date echo conflicts with the source")
            }
        } else if input.officialDueAt != nil {
            throw AIParsingError.invalidOutput("official-date echo is required when a source date exists")
        }
        return response
    }
}
