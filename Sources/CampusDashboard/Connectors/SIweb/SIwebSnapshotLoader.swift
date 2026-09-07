import Foundation

struct SIwebSnapshot: Equatable, Sendable {
    let meetings: [SIwebMeetingPayload]
}

struct SIwebSnapshotLoader: Sendable {
    let service: any SIwebService
    let maximumPages: Int

    init(service: any SIwebService, maximumPages: Int = 100) {
        self.service = service
        self.maximumPages = max(1, maximumPages)
    }

    func load() async throws -> SIwebSnapshot {
        var token: String?
        var seenTokens = Set<String>()
        var records: [String: SIwebMeetingPayload] = [:]
        var pageCount = 0
        repeat {
            pageCount += 1
            guard pageCount <= maximumPages else { throw SIwebConnectorError.structural(.unsafeRoute) }
            let page = try await service.meetings(pageToken: token)
            for meeting in page.values {
                if let existing = records[meeting.sourceObjectID], existing != meeting {
                    throw SIwebConnectorError.structural(.structuralChange)
                }
                records[meeting.sourceObjectID] = meeting
            }
            token = page.nextPageToken
            if let token, !seenTokens.insert(token).inserted {
                throw SIwebConnectorError.structural(.unsafeRoute)
            }
        } while token != nil
        return SIwebSnapshot(meetings: records.values.sorted { $0.sourceObjectID < $1.sourceObjectID })
    }
}
