import Foundation
#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto
#endif

struct SIwebParsedPage: Equatable, Sendable {
    let meetings: [SIwebMeetingPayload]
    let nextPageURL: URL?
}

struct SIwebHTMLParser: Sendable {
    static let version = "siweb-schedule-v1.0.0"
    static let mpuVersion = "mpu-time-stud-v1.0.0"
    private static let contract = "schedule-v1"
    private static let mpuHeaders = [
        "Sem", "Class Code", "Learning Module", "Instructor", "Venue", "Period", "Time",
        "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"
    ]

    let baseURL: URL

    func parse(_ data: Data) throws -> SIwebParsedPage {
        guard let html = Self.decodeHTML(data) else {
            throw SIwebConnectorError.structural(
                .malformedResponse, contractDiagnostic: "encoding=unsupported"
            )
        }
        let contractDiagnostic = Self.contractDiagnostic(for: html)
        do {
            return try parseDecoded(data: data, html: html)
        } catch let error as SIwebConnectorError {
            throw error.withContractDiagnostic(contractDiagnostic)
        }
    }

    private func parseDecoded(data: Data, html: String) throws -> SIwebParsedPage {
        if Self.looksLikeLogin(html) {
            throw SIwebConnectorError.structural(.sessionExpired)
        }
        if Self.mpuHeaders.allSatisfy({ html.localizedCaseInsensitiveContains($0) }) {
            return try parseMPU(data: data, html: html)
        }
        guard html.range(of: #"data-siweb-contract\s*=\s*["']schedule-v1["']"#,
                         options: [.regularExpression, .caseInsensitive]) != nil else {
            throw SIwebConnectorError.structural(.structuralChange)
        }
        guard let completeMarker = html.range(
            of: #"data-siweb-complete\s*=\s*["']true["']"#,
            options: [.regularExpression, .caseInsensitive]
        ), let closingMain = html.range(of: "</main>", options: [.caseInsensitive, .backwards]),
              completeMarker.lowerBound < closingMain.lowerBound else {
            throw SIwebConnectorError.structural(.partialResponse)
        }
        let contentHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        let courseTags = Self.openingTags(named: "article", in: html).filter {
            $0.attributes["data-siweb-course-id"] != nil
        }
        if courseTags.isEmpty {
            guard html.range(of: #"data-siweb-empty\s*=\s*["']true["']"#,
                             options: [.regularExpression, .caseInsensitive]) != nil else {
                throw SIwebConnectorError.structural(.structuralChange)
            }
            return SIwebParsedPage(meetings: [], nextPageURL: try nextPageURL(in: html))
        }

        var meetings: [SIwebMeetingPayload] = []
        var seenIDs = Set<String>()
        var seenCourses: [String: (name: String, code: String?)] = [:]
        for (index, courseTag) in courseTags.enumerated() {
            let end = index + 1 < courseTags.count ? courseTags[index + 1].range.lowerBound : html.endIndex
            let candidateBlock = String(html[courseTag.range.lowerBound..<end])
            guard let articleEnd = candidateBlock.range(of: "</article>", options: [.caseInsensitive]) else {
                throw SIwebConnectorError.structural(.partialResponse)
            }
            let block = String(candidateBlock[..<articleEnd.upperBound])
            guard let courseID = nonempty(courseTag.attributes["data-siweb-course-id"]),
                  let courseName = nonempty(courseTag.attributes["data-siweb-course-name"])
            else { throw SIwebConnectorError.structural(.structuralChange) }
            let courseCode = nonempty(courseTag.attributes["data-siweb-course-code"])
            if let existing = seenCourses[courseID], existing.name != courseName || existing.code != courseCode {
                throw SIwebConnectorError.structural(.structuralChange)
            }
            seenCourses[courseID] = (courseName, courseCode)

            let meetingTags = Self.openingTags(named: "div", in: block).filter {
                $0.attributes["data-siweb-start"] != nil || $0.attributes["data-siweb-meeting-id"] != nil
            }
            if meetingTags.isEmpty && courseTag.attributes["data-siweb-no-meetings"] != "true" {
                throw SIwebConnectorError.structural(.structuralChange)
            }
            for meetingTag in meetingTags {
                let attributes = meetingTag.attributes
                guard let startText = nonempty(attributes["data-siweb-start"]),
                      let endText = nonempty(attributes["data-siweb-end"]),
                      let start = Self.date(startText), let finish = Self.date(endText), start < finish,
                      let timeZone = Self.explicitTimeZone(in: startText)
                else { throw SIwebConnectorError.structural(.structuralChange) }

                let location = nonempty(attributes["data-siweb-location"])
                let meetingID = nonempty(attributes["data-siweb-meeting-id"])
                    ?? Self.derivedID(courseID: courseID, start: startText, end: endText, location: location)
                guard seenIDs.insert(meetingID).inserted else {
                    throw SIwebConnectorError.structural(.structuralChange)
                }
                let status = attributes["data-siweb-status"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard status == nil || ["scheduled", "cancelled", "canceled"].contains(status!) else {
                    throw SIwebConnectorError.structural(.structuralChange)
                }
                meetings.append(SIwebMeetingPayload(
                    sourceObjectID: meetingID,
                    courseSourceObjectID: courseID,
                    courseName: courseName,
                    courseCode: courseCode,
                    startsAt: start,
                    endsAt: finish,
                    timeZoneIdentifier: timeZone,
                    location: location,
                    isCancelled: status == "cancelled" || status == "canceled",
                    sourceURL: try sourceURL(attributes["data-siweb-source-href"]),
                    parserVersion: Self.version,
                    sourceContentHash: contentHash
                ))
            }
        }
        return SIwebParsedPage(
            meetings: meetings.sorted { $0.sourceObjectID < $1.sourceObjectID },
            nextPageURL: try nextPageURL(in: html)
        )
    }

    private static func contractDiagnostic(for html: String) -> String {
        let loginPassword = html.range(
            of: #"<input[^>]+type\s*=\s*["']password["']"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let loginForm = html.range(
            of: #"<form[^>]+(?:action|id)\s*=\s*["'][^"']*(?:login|signin|sso)[^"']*["']"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let expired = html.range(
            of: #"data-siweb-session\s*=\s*["']expired["']"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let schedule = html.range(
            of: #"data-siweb-contract\s*=\s*["']schedule-v1["']"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let complete = html.range(
            of: #"data-siweb-complete\s*=\s*["']true["']"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        let tables = fragments(tag: "table", in: html)
        let tableRows = tables.map { fragments(tag: "tr", in: $0.inner) }
        let firstCellCounts = tableRows.map { rows in
            rows.first.map { cells(in: $0.inner).count } ?? 0
        }
        let firstHeaderMasks = tableRows.map { rows -> String in
            guard let first = rows.first else { return "0" }
            let values = cells(in: first.inner).map(\.text)
            var mask = 0
            for index in 0..<min(values.count, mpuHeaders.count)
            where normalizedHeader(values[index]) == normalizedHeader(mpuHeaders[index]) {
                mask |= 1 << index
            }
            return String(mask, radix: 16)
        }
        let exactFirstHeaders = tableRows.filter { rows in
            rows.first.map { cells(in: $0.inner).map(\.text) == mpuHeaders } == true
        }.count
        let normalizedFirstHeaders = tableRows.filter { rows in
            rows.first.map {
                cells(in: $0.inner).map { normalizedHeader($0.text) }
                    == mpuHeaders.map(normalizedHeader)
            } == true
        }.count
        let rowCellCounts = tableRows.flatMap { rows in
            rows.prefix(24).map { cells(in: $0.inner).count }
        }
        return [
            "login=\(loginPassword ? 1 : 0)\(loginForm ? 1 : 0)\(expired ? 1 : 0)",
            "schedule=\(schedule ? 1 : 0)", "complete=\(complete ? 1 : 0)",
            "tables=\(min(tables.count, 99))",
            "first_cells=\(boundedList(firstCellCounts))",
            "first_masks=\(firstHeaderMasks.prefix(12).joined(separator: ","))",
            "exact_headers=\(min(exactFirstHeaders, 99))",
            "normalized_headers=\(min(normalizedFirstHeaders, 99))",
            "row_cells=\(boundedList(rowCellCounts))"
        ].joined(separator: ";")
    }

    private static func normalizedHeader(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func boundedList(_ values: [Int]) -> String {
        values.prefix(24).map { String(min(max($0, 0), 99)) }.joined(separator: ",")
    }

    private func parseMPU(data: Data, html: String) throws -> SIwebParsedPage {
        let tables = Self.fragments(tag: "table", in: html)
        var matchingTableCount = 0
        for table in tables {
            let rows = Self.fragments(tag: "tr", in: table.inner).map { row in
                Self.cells(in: row.inner)
            }
            guard let first = rows.first else { continue }
            if first.map(\.text) == Self.mpuHeaders { matchingTableCount += 1 }
        }
        guard matchingTableCount == 1 else { throw SIwebConnectorError.structural(.structuralChange) }

        // Re-scan the unique matching table so row boundaries stay explicit.
        guard let table = tables.first(where: { fragment in
            Self.fragments(tag: "tr", in: fragment.inner).first.map {
                Self.cells(in: $0.inner).map(\.text) == Self.mpuHeaders
            } == true
        }) else { throw SIwebConnectorError.structural(.structuralChange) }
        let rawRows = Self.fragments(tag: "tr", in: table.inner).dropFirst().map { Self.cells(in: $0.inner) }
        let contentHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let sourceURL = baseURL.appendingPathComponent("time_stud.asp")

        var currentCourse: (id: String, name: String)?
        var knownCourses: [String: String] = [:]
        var meetings: [SIwebMeetingPayload] = []
        var seenMeetingIDs = Set<String>()

        for rawCells in rawRows {
            if rawCells.count == 1, rawCells[0].colspan == 14 { continue }
            let cells: [MPUCell]
            if rawCells.count == 14, rawCells.allSatisfy({ $0.colspan == 1 }) {
                cells = rawCells
                guard !cells[0].text.isEmpty, !cells[1].text.isEmpty, !cells[2].text.isEmpty else {
                    throw SIwebConnectorError.structural(.structuralChange)
                }
                currentCourse = (cells[1].text, cells[2].text)
                if let prior = knownCourses[cells[1].text], prior != cells[2].text {
                    throw SIwebConnectorError.structural(.structuralChange)
                }
                knownCourses[cells[1].text] = cells[2].text
            } else if rawCells.count == 12, rawCells.first?.colspan == 3, let currentCourse {
                cells = [
                    MPUCell(text: "", inner: "", colspan: 1),
                    MPUCell(text: currentCourse.id, inner: "", colspan: 1),
                    MPUCell(text: currentCourse.name, inner: "", colspan: 1)
                ] + Array(rawCells.dropFirst())
            } else {
                throw SIwebConnectorError.structural(.structuralChange)
            }

            guard let course = currentCourse,
                  let period = Self.mpuPeriod(cells[5].text),
                  let times = Self.mpuTimes(cells[6].text)
            else { throw SIwebConnectorError.structural(.structuralChange) }
            let weekdays = cells[7...13].enumerated().compactMap { offset, cell -> Int? in
                Self.hasMPUDayMarker(cell.inner) ? offset + 1 : nil
            }
            guard !weekdays.isEmpty else { throw SIwebConnectorError.structural(.structuralChange) }

            let generated = try Self.expandMPUMeetings(
                period: period, times: times, weekdays: weekdays, maximum: 400
            )
            let location = cells[4].text.isEmpty ? nil : cells[4].text
            for (start, end) in generated {
                let canonical = [
                    course.id, String(Int(start.timeIntervalSince1970)),
                    String(Int(end.timeIntervalSince1970)), location ?? ""
                ].joined(separator: "\u{1f}")
                let id = "mpu-v1-" + Data(canonical.utf8).base64EncodedString()
                    .replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "=", with: "")
                guard seenMeetingIDs.insert(id).inserted else {
                    throw SIwebConnectorError.structural(.structuralChange)
                }
                meetings.append(SIwebMeetingPayload(
                    sourceObjectID: id,
                    courseSourceObjectID: course.id,
                    courseName: course.name,
                    courseCode: course.id,
                    startsAt: start,
                    endsAt: end,
                    timeZoneIdentifier: "Asia/Macau",
                    location: location,
                    isCancelled: false,
                    sourceURL: sourceURL,
                    parserVersion: Self.mpuVersion,
                    sourceContentHash: contentHash
                ))
            }
            guard meetings.count <= 5_000 else {
                throw SIwebConnectorError.structural(.structuralChange)
            }
        }
        return SIwebParsedPage(
            meetings: meetings.sorted { $0.sourceObjectID < $1.sourceObjectID }, nextPageURL: nil
        )
    }

    private func nextPageURL(in html: String) throws -> URL? {
        let tag = Self.openingTags(named: "a", in: html).first {
            $0.attributes["data-siweb-next"] == "true"
        }
        return try sourceURL(tag?.attributes["href"])
    }

    private func sourceURL(_ raw: String?) throws -> URL? {
        guard let raw = nonempty(raw), let resolved = URL(string: raw, relativeTo: baseURL)?.absoluteURL,
              resolved.scheme?.lowercased() == "https",
              resolved.host?.lowercased() == baseURL.host?.lowercased(),
              (resolved.port ?? 443) == (baseURL.port ?? 443),
              resolved.user == nil, resolved.password == nil
        else {
            if nonempty(raw) == nil { return nil }
            throw SIwebConnectorError.structural(.structuralChange)
        }
        return resolved
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let decoded = Self.decodeEntities(value).trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? nil : decoded
    }

    private static func looksLikeLogin(_ html: String) -> Bool {
        let patterns = [
            #"<input[^>]+type\s*=\s*["']password["']"#,
            #"<form[^>]+(?:action|id)\s*=\s*["'][^"']*(?:login|signin|sso)[^"']*["']"#,
            #"data-siweb-session\s*=\s*["']expired["']"#
        ]
        return patterns.contains { html.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    private static func decodeHTML(_ data: Data) -> String? {
        // NSString encodings store non-built-in CF encodings by setting the high bit.
        // Big-5 is CFStringEncoding 0x0A03, so this value works through Foundation
        // without importing the unavailable public CoreFoundation module on Windows.
        let big5 = String.Encoding(rawValue: 0x80000A03)
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: big5)
    }

    private struct HTMLFragment {
        let attributes: String
        let inner: String
    }

    private struct MPUCell {
        let text: String
        let inner: String
        let colspan: Int
    }

    private static func fragments(tag: String, in html: String) -> [HTMLFragment] {
        let name = NSRegularExpression.escapedPattern(for: tag)
        guard let expression = try? NSRegularExpression(
            pattern: #"<"# + name + #"\b([^>]*)>(.*?)</"# + name + #"\s*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let full = NSRange(html.startIndex..<html.endIndex, in: html)
        return expression.matches(in: html, range: full).compactMap { match in
            guard let attributes = Range(match.range(at: 1), in: html),
                  let inner = Range(match.range(at: 2), in: html) else { return nil }
            return HTMLFragment(attributes: String(html[attributes]), inner: String(html[inner]))
        }
    }

    private static func cells(in html: String) -> [MPUCell] {
        guard let expression = try? NSRegularExpression(
            pattern: #"<t[dh]\b([^>]*)>(.*?)</t[dh]\s*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let full = NSRange(html.startIndex..<html.endIndex, in: html)
        return expression.matches(in: html, range: full).compactMap { match in
            guard let attrsRange = Range(match.range(at: 1), in: html),
                  let innerRange = Range(match.range(at: 2), in: html) else { return nil }
            let attrs = String(html[attrsRange])
            let inner = String(html[innerRange])
            let colspan = attribute("colspan", in: attrs).flatMap(Int.init) ?? 1
            return MPUCell(text: visibleText(inner), inner: inner, colspan: colspan)
        }
    }

    private static func attribute(_ name: String, in attributes: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let expression = try? NSRegularExpression(
            pattern: #"\b"# + escaped + #"\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))"#,
            options: [.caseInsensitive]
        ), let match = expression.firstMatch(
            in: attributes, range: NSRange(attributes.startIndex..<attributes.endIndex, in: attributes)
        ) else { return nil }
        for index in 1...3 where match.range(at: index).location != NSNotFound {
            if let range = Range(match.range(at: index), in: attributes) { return String(attributes[range]) }
        }
        return nil
    }

    private static func visibleText(_ html: String) -> String {
        let noTags = html.replacingOccurrences(
            of: #"<[^>]+>"#, with: " ", options: [.regularExpression, .caseInsensitive]
        )
        return decodeEntities(noTags).replacingOccurrences(of: "\u{00a0}", with: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func hasMPUDayMarker(_ html: String) -> Bool {
        html.range(of: #"(?:^|/)dot\.gif(?:[?\"'])"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func mpuPeriod(_ value: String) -> (DateComponents, DateComponents)? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, let start = mpuDateComponents(String(parts[0])),
              let end = mpuDateComponents(String(parts[1])) else { return nil }
        return (start, end)
    }

    private static func mpuDateComponents(_ value: String) -> DateComponents? {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }

    private static func mpuTimes(_ value: String) -> ((hour: Int, minute: Int), (hour: Int, minute: Int))? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, let start = mpuTime(String(parts[0])), let end = mpuTime(String(parts[1]))
        else { return nil }
        return (start, end)
    }

    private static func mpuTime(_ value: String) -> (hour: Int, minute: Int)? {
        let values = value.split(separator: ":", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard values.count == 2, (0...23).contains(values[0]), (0...59).contains(values[1]) else { return nil }
        return (values[0], values[1])
    }

    private static func expandMPUMeetings(
        period: (DateComponents, DateComponents),
        times: ((hour: Int, minute: Int), (hour: Int, minute: Int)),
        weekdays: [Int],
        maximum: Int
    ) throws -> [(Date, Date)] {
        guard let zone = TimeZone(identifier: "Asia/Macau") else {
            throw SIwebConnectorError.structural(.configuration)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = zone
        guard let first = calendar.date(from: period.0), let last = calendar.date(from: period.1), first <= last,
              calendar.dateComponents([.day], from: first, to: last).day.map({ $0 <= 370 }) == true
        else { throw SIwebConnectorError.structural(.structuralChange) }

        var result: [(Date, Date)] = []
        var day = first
        while day <= last {
            if weekdays.contains(calendar.component(.weekday, from: day)) {
                var startComponents = calendar.dateComponents([.year, .month, .day], from: day)
                startComponents.hour = times.0.hour
                startComponents.minute = times.0.minute
                var endComponents = calendar.dateComponents([.year, .month, .day], from: day)
                endComponents.hour = times.1.hour
                endComponents.minute = times.1.minute
                guard let start = calendar.date(from: startComponents), let end = calendar.date(from: endComponents),
                      start < end else { throw SIwebConnectorError.structural(.structuralChange) }
                result.append((start, end))
                guard result.count <= maximum else {
                    throw SIwebConnectorError.structural(.structuralChange)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else {
                throw SIwebConnectorError.structural(.structuralChange)
            }
            day = next
        }
        return result
    }

    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = formatter.date(from: value) { return result }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func explicitTimeZone(in value: String) -> String? {
        if value.hasSuffix("Z") || value.hasSuffix("z") { return "UTC" }
        guard let match = value.range(of: #"[+-][0-9]{2}:[0-9]{2}$"#, options: .regularExpression) else {
            return nil
        }
        return "UTC" + value[match]
    }

    private static func derivedID(courseID: String, start: String, end: String, location: String?) -> String {
        let canonical = [courseID, start, end, location ?? ""].joined(separator: "\u{1f}")
        return "derived-v1-" + Data(canonical.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private struct Tag {
        let range: Range<String.Index>
        let attributes: [String: String]
    }

    private static func openingTags(named name: String, in html: String) -> [Tag] {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let expression = try? NSRegularExpression(
            pattern: #"<"# + escaped + #"\b[^>]*>"#, options: [.caseInsensitive]
        ) else { return [] }
        let full = NSRange(html.startIndex..<html.endIndex, in: html)
        return expression.matches(in: html, range: full).compactMap { match in
            guard let range = Range(match.range, in: html) else { return nil }
            return Tag(range: range, attributes: attributes(in: String(html[range])))
        }
    }

    private static func attributes(in tag: String) -> [String: String] {
        guard let expression = try? NSRegularExpression(
            pattern: #"([A-Za-z_:][A-Za-z0-9_:.-]*)\s*=\s*(?:\"([^\"]*)\"|'([^']*)')"#
        ) else { return [:] }
        let full = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        var result: [String: String] = [:]
        for match in expression.matches(in: tag, range: full) {
            guard let keyRange = Range(match.range(at: 1), in: tag) else { continue }
            let valueIndex = match.range(at: 2).location != NSNotFound ? 2 : 3
            guard let valueRange = Range(match.range(at: valueIndex), in: tag) else { continue }
            result[String(tag[keyRange]).lowercased()] = String(tag[valueRange])
        }
        return result
    }

    private static func decodeEntities(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
