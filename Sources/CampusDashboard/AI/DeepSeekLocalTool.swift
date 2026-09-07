import Foundation

enum DeepSeekLocalTool {
    private struct Evidence: Codable {
        let status: String
        let category: String?
        let model: String
        let requestCount: Int
        let inputTokens: Int
        let outputTokens: Int
        let directHTTPS: Bool
        let httpCategory: String
        let parsingCategory: String
        let classificationCategory: String
        let withinConfiguredBudget: Bool
        let cacheHitVerified: Bool
        let containedPrivateContent: Bool
        let containedCredential: Bool
    }

    static func smokeTest(resultPath: String) async -> Int32 {
        var directHTTPS = false
        do {
            let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                                   in: .userDomainMask, appropriateFor: nil, create: true)
            let directory = base.appendingPathComponent(
                Bundle.main.bundleIdentifier ?? "com.campusdashboard.desktop", isDirectory: true)
            let database = try SQLiteDatabase(path: directory.appendingPathComponent("campus-dashboard.sqlite3").path)
            let configuration = DeepSeekConfigurationService(
                database: database,
                secrets: KeychainSecretStore(service: DeepSeekConfigurationService.keychainService)
            )
            let provider = DeepSeekAIProvider(database: database, configuration: configuration)
            directHTTPS = configuration.usesDirectHTTPS()
            let before = try aggregate(database)
            let syntheticInput = AIParseInput(
                source: .canvas, objectType: "announcement", objectID: "synthetic-smoke",
                title: "Synthetic campus notice", officialType: "announcement", courseName: "Synthetic course",
                officialDueAt: nil, minimalText: "A synthetic class exercise is available next week.",
                language: "en", knownObjectSummaries: [], sourceURL: nil
            )
            _ = try await provider.structuredSuggestion(for: syntheticInput)
            let afterFirst = try aggregate(database)
            _ = try await provider.structuredSuggestion(for: syntheticInput)
            let afterSecond = try aggregate(database)
            let settings = try AIPersistence(database: database).settings()
            let requestCount = max(0, afterFirst.0 - before.0)
            let inputTokens = max(0, afterFirst.1 - before.1)
            let outputTokens = max(0, afterFirst.2 - before.2)
            try write(Evidence(status: "pass", category: nil, model: DeepSeekDisclosure.model,
                               requestCount: requestCount,
                               inputTokens: inputTokens,
                               outputTokens: outputTokens,
                               directHTTPS: directHTTPS,
                               httpCategory: "success_2xx",
                               parsingCategory: "strict_schema_pass",
                               classificationCategory: "stage11_provider_contract_only",
                               withinConfiguredBudget: requestCount <= settings.perRunRequestBudget
                                   && requestCount <= settings.dailyRequestBudget
                                   && inputTokens + outputTokens <= settings.perRunTokenBudget
                                   && inputTokens + outputTokens <= settings.dailyTokenBudget,
                               cacheHitVerified: afterSecond == afterFirst,
                               containedPrivateContent: false, containedCredential: false), to: resultPath)
            return 0
        } catch {
            let category: String
            if let value = error as? DeepSeekProviderError { category = value.category.rawValue }
            else if error as? AIParsingError == .missingCredential { category = "missing_credential" }
            else if error as? AIParsingError == .consentRequired { category = "consent_required" }
            else if error as? AIParsingError == .budgetExceeded { category = "budget_exceeded" }
            else { category = "failed" }
            try? write(Evidence(status: "blocked", category: category, model: DeepSeekDisclosure.model,
                                requestCount: 0, inputTokens: 0, outputTokens: 0,
                                directHTTPS: directHTTPS, httpCategory: "not_completed",
                                parsingCategory: "not_completed",
                                classificationCategory: "not_completed",
                                withinConfiguredBudget: false, cacheHitVerified: false,
                                containedPrivateContent: false, containedCredential: false), to: resultPath)
            return 2
        }
    }

    private static func aggregate(_ database: SQLiteDatabase) throws -> (Int, Int, Int) {
        let row = try database.query(
            "SELECT COALESCE(SUM(request_count),0) AS requests, COALESCE(SUM(input_tokens),0) AS input, COALESCE(SUM(output_tokens),0) AS output FROM ai_provider_usage"
        ).first
        return (Int(row?.int("requests") ?? 0), Int(row?.int("input") ?? 0), Int(row?.int("output") ?? 0))
    }

    private static func write(_ evidence: Evidence, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let data = try JSONEncoder().encode(evidence)
        try data.write(to: url, options: .atomic)
    }
}
