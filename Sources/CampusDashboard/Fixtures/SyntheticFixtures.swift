import Foundation

enum SyntheticFixtures {
    static let referenceDate = makeDate(2026, 9, 7, 8, 0)

    static let interactionDesign = Course(
        id: uuid("00000000-0000-0000-0000-000000000101"),
        sourceAccountID: "synthetic-canvas-account",
        sourceObjectID: "synthetic-course-101",
        name: "Interaction Design Studio",
        code: "DES-214",
        term: "Autumn 2026",
        colorName: "indigo"
    )

    static let environmentalScience = Course(
        id: uuid("00000000-0000-0000-0000-000000000102"),
        sourceAccountID: "synthetic-siweb-account",
        sourceObjectID: "synthetic-course-102",
        name: "Urban Environmental Science",
        code: "ENV-132",
        term: "Autumn 2026",
        colorName: "green"
    )

    static let dataStorytelling = Course(
        id: uuid("00000000-0000-0000-0000-000000000103"),
        sourceAccountID: "synthetic-canvas-account",
        sourceObjectID: "synthetic-course-103",
        name: "Data Storytelling",
        code: "COM-241",
        term: "Autumn 2026",
        colorName: "orange"
    )

    static let populated = DashboardSnapshot(
        sourceHealth: [
            SourceHealth(
                id: uuid("00000000-0000-0000-0000-000000000201"),
                source: .canvas,
                level: .healthy,
                detail: "Synthetic preview data is current",
                lastSuccessfulSync: makeDate(2026, 9, 7, 7, 42)
            ),
            SourceHealth(
                id: uuid("00000000-0000-0000-0000-000000000202"),
                source: .siweb,
                level: .warning,
                detail: "Previewing a delayed source",
                lastSuccessfulSync: makeDate(2026, 9, 6, 18, 15)
            )
        ],
        courses: [interactionDesign, environmentalScience, dataStorytelling],
        meetings: [
            CourseMeeting(
                id: uuid("00000000-0000-0000-0000-000000000301"),
                courseID: environmentalScience.id,
                title: "Urban Environmental Science",
                start: makeDate(2026, 9, 7, 9, 0),
                end: makeDate(2026, 9, 7, 10, 30),
                location: "Harbor Hall · Room 204",
                source: .siweb,
                isCancelled: false
            ),
            CourseMeeting(
                id: uuid("00000000-0000-0000-0000-000000000302"),
                courseID: interactionDesign.id,
                title: "Interaction Design Studio",
                start: makeDate(2026, 9, 7, 13, 30),
                end: makeDate(2026, 9, 7, 16, 0),
                location: "Design Annex · Studio 3",
                source: .siweb,
                isCancelled: false
            ),
            CourseMeeting(
                id: uuid("00000000-0000-0000-0000-000000000303"),
                courseID: dataStorytelling.id,
                title: "Data Storytelling Lab",
                start: makeDate(2026, 9, 8, 11, 0),
                end: makeDate(2026, 9, 8, 12, 30),
                location: "Library Media Lab",
                source: .siweb,
                isCancelled: true
            )
        ],
        tasks: [
            LearningTask(
                id: uuid("00000000-0000-0000-0000-000000000401"),
                sourceAccountID: "synthetic-canvas-account",
                sourceObjectID: "synthetic-task-401",
                courseID: interactionDesign.id,
                title: "Prototype critique notes",
                kind: .assignment,
                officialDueAt: makeDate(2026, 9, 7, 17, 0),
                suggestedCompleteAt: makeDate(2026, 9, 7, 15, 30),
                suggestedDateConfirmed: true,
                source: .canvas,
                isLocallyComplete: false,
                localPriority: .high
            ),
            LearningTask(
                id: uuid("00000000-0000-0000-0000-000000000402"),
                sourceAccountID: "synthetic-canvas-account",
                sourceObjectID: "synthetic-task-402",
                courseID: dataStorytelling.id,
                title: "Chart annotation quiz",
                kind: .quiz,
                officialDueAt: makeDate(2026, 9, 9, 20, 0),
                suggestedCompleteAt: nil,
                suggestedDateConfirmed: false,
                source: .canvas,
                isLocallyComplete: false,
                localPriority: .medium
            ),
            LearningTask(
                id: uuid("00000000-0000-0000-0000-000000000403"),
                sourceAccountID: "synthetic-canvas-account",
                sourceObjectID: "synthetic-task-403",
                courseID: environmentalScience.id,
                title: "Read: cooling the compact city",
                kind: .reading,
                officialDueAt: nil,
                suggestedCompleteAt: makeDate(2026, 9, 10, 18, 0),
                suggestedDateConfirmed: false,
                source: .canvas,
                isLocallyComplete: false,
                localPriority: .low
            )
        ],
        announcements: [
            Announcement(
                id: uuid("00000000-0000-0000-0000-000000000501"),
                sourceObjectID: "synthetic-announcement-501",
                courseID: environmentalScience.id,
                title: "Field walk meeting point",
                summary: "Meet beside the east greenhouse instead of the main entrance. Bring a notebook.",
                publishedAt: makeDate(2026, 9, 7, 7, 15),
                source: .canvas,
                isLocallyRead: false
            ),
            Announcement(
                id: uuid("00000000-0000-0000-0000-000000000502"),
                sourceObjectID: "synthetic-announcement-502",
                courseID: interactionDesign.id,
                title: "Studio materials for Monday",
                summary: "The synthetic class will use paper components during the afternoon studio.",
                publishedAt: makeDate(2026, 9, 6, 16, 40),
                source: .canvas,
                isLocallyRead: true
            )
        ],
        confirmations: [
            ConfirmationCandidate(
                id: uuid("00000000-0000-0000-0000-000000000601"),
                courseID: environmentalScience.id,
                kind: .inferredDate,
                sourceSummary: "The reading note says ‘before Thursday’s workshop’ without an official due date.",
                suggestion: "Suggested completion: Thu, 10 Sep at 6:00 PM",
                confidence: 0.74,
                rationale: "The date is inferred from synthetic text and must be confirmed before any future calendar or reminder use."
            ),
            ConfirmationCandidate(
                id: uuid("00000000-0000-0000-0000-000000000602"),
                courseID: dataStorytelling.id,
                kind: .normalizedType,
                sourceSummary: "Canvas labels ‘Chart annotation’ as an assignment.",
                suggestion: "Display locally as Quiz",
                confidence: 0.91,
                rationale: "The title and synthetic metadata resemble a quiz; the official source type remains unchanged."
            )
        ]
    )

    private static func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "Asia/Shanghai")
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }

    private static func uuid(_ string: String) -> UUID {
        UUID(uuidString: string)!
    }
}
