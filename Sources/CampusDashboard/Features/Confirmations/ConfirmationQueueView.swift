import SwiftUI

struct ConfirmationQueueView: View {
    @ObservedObject var model: DashboardModel
    @State private var correctionTarget: AIParseRecord?
    @State private var academicCorrectionTarget: AcademicCorrectionTarget?

    var body: some View {
        PageContainer(title: model.text("AI Confirmation Queue"), subtitle: model.text("Review suggestions before any inferred value can be used downstream")) {
            ScenarioContent(
                model: model,
                scenario: model.scenarioForEmpty(
                    !model.usesPersistentAIQueue && model.snapshot.confirmations.isEmpty
                ),
                emptyTitle: "Nothing awaiting confirmation",
                emptyMessage: "There are no inferred dates or organization suggestions in the queue."
            ) {
                VStack(spacing: 16) {
                    Card {
                        Label(model.text(model.aiSettings.enabled ? "Local deterministic AI fixture enabled" : "AI assistance is off"), systemImage: "lock.shield")
                            .font(.headline)
                        Text(model.text("Official values always win. Dates extracted from text stay inferred until you confirm them; AI never calls Calendar or notifications."))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(model.text(model.aiMessage))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if model.usesPersistentAIQueue {
                        persistentContent
                    } else {
                        ForEach(model.snapshot.confirmations) { item in syntheticCard(item) }
                    }
                }
            }
        }
        .sheet(item: $correctionTarget) { record in
            CorrectionSheet(record: record, language: model.language, timeZone: model.presentationTimeZone) { title, type, date in
                Task {
                    await model.correctAIResult(record.id, title: title, type: type, date: date)
                    correctionTarget = nil
                }
            }
        }
        .sheet(item: $academicCorrectionTarget) { target in
            AcademicSignalCorrectionSheet(model: model, target: target) {
                academicCorrectionTarget = nil
            }
        }
        .sheet(item: $model.calendarChangePreview) { preview in
            CalendarChangePreviewSheet(model: model, preview: preview)
        }
        .task { model.refreshAIConfiguration() }
    }

    @ViewBuilder
    private var persistentContent: some View {
        let signalAnalysisIDs = Set(model.academicSignals.map(\.analysisID))
        let emptyOrFallback = model.academicAnalyses.filter { !signalAnalysisIDs.contains($0.id) }
        if model.aiConfirmations.isEmpty && model.academicSignals.isEmpty && emptyOrFallback.isEmpty {
            ContentUnavailableView(
                model.text("Nothing awaiting confirmation"), systemImage: "checkmark.circle",
                description: Text(model.text("Deterministic sync and all non-AI features remain available."))
            )
        } else {
            ForEach(model.aiConfirmations) { item in persistentCard(item) }
            ForEach(emptyOrFallback) { item in academicAnalysisCard(item) }
            ForEach(model.academicSignals) { item in academicSignalCard(item) }
        }
        if !model.aiHistory.isEmpty {
            Card {
                Text(model.text("Recent decisions")).font(.headline)
                ForEach(model.aiHistory) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.changeSummary.isEmpty ? item.rationale : item.changeSummary).lineLimit(1)
                            Spacer()
                            Badge(text: model.text(item.confirmationState.rawValue), color: .secondary)
                            Button(model.text("Undo")) {
                                Task { await model.undoAIResult(item.id) }
                            }
                        }
                        let finalValues = [
                            item.adoptedNormalizedTitle,
                            item.adoptedType,
                            item.adoptedDate.map { model.format($0) }
                        ].compactMap { $0 }
                        if !finalValues.isEmpty {
                            Text(model.text("Final adopted value") + ": " + finalValues.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func academicAnalysisCard(_ item: AcademicAnnouncementAnalysis) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Badge(text: model.text(model.ignoredAcademicAnalysisIDs.contains(item.id) ? "ignored" : (item.primaryCategory == .other ? "Other / no actionable result" : "Provider fallback")), color: .orange)
                    Spacer()
                    Text("\(item.provider) · \(item.model) · \(model.text("prompt")) \(item.promptVersion) · \(model.text("schema")) \(item.schemaVersion)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                if let failure = AcademicProviderFailurePresentation.safe(item.failureCategory) {
                    Text(model.text(failure.categoryKey)).font(.caption.weight(.semibold))
                    Text(model.text(failure.recoveryKey)).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(model.text("No actionable academic signal was found. You can correct this result locally or ignore it."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button(model.text("Correct analysis…")) {
                        if let announcement = model.snapshot.announcements.first(where: { $0.id == item.announcementID }) {
                            academicCorrectionTarget = .init(analysis: item, signal: nil, courseID: announcement.courseID)
                        }
                    }
                    Button(model.text("Reprocess")) { Task { await model.reprocessAcademicSignals(for: item.announcementID) } }
                    if model.ignoredAcademicAnalysisIDs.contains(item.id) {
                        Button(model.text("Undo")) { model.setAcademicAnalysisIgnored(item.id, ignored: false) }
                    } else {
                        Button(model.text("Ignore"), role: .destructive) { model.setAcademicAnalysisIgnored(item.id, ignored: true) }
                    }
                }
            }
        }
    }

    private func academicSignalCard(_ item: AcademicSignalRecord) -> some View {
        let effectiveCategory = item.adoptedCategory ?? item.category
        let effectiveDate = item.adoptedDate ?? item.inferredDate
        let unsafeSchedule = effectiveCategory == .courseScheduleChange
            && (item.targetMeetingID == nil || item.audienceResolution != .resolved)
        return Card {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Badge(text: model.text(item.confirmationState.rawValue), color: item.confirmationState == .pending ? .purple : .secondary)
                    Badge(text: model.text(categoryLabel(effectiveCategory)), color: .secondary)
                    if !item.conflicts.isEmpty { Badge(text: model.text("Conflict / uncertain"), color: .orange) }
                    if unsafeSchedule { Badge(text: model.text("Section needs review"), color: .orange) }
                    if model.calendarWrittenSignalIDs.contains(item.id) {
                        Badge(text: model.text("Calendar written"), color: .green)
                    }
                    Spacer()
                    Text(item.confidence, format: .percent.precision(.fractionLength(0)))
                }
                labeled("Original target", "announcement · \(item.sourceObjectID)")
                if let source = model.snapshot.announcements.first(where: { $0.id == item.announcementID })?.sourceURL,
                   let url = URL(string: source) {
                    Link(model.text("Open original source"), destination: url)
                }
                labeled("Evidence", item.evidence)
                labeled("Key requirement", item.adoptedKeyRequirement ?? item.keyRequirement)
                if let date = effectiveDate {
                    labeled("Inferred date (not yet authorized)", model.format(date))
                }
                if let section = item.affectedSection { labeled("Affected section", section) }
                if let role = item.scheduleDateRole { labeled("Schedule date role", role.rawValue) }
                labeled("Reason", item.reason)
                Text("\(item.provider) · \(item.model) · \(model.text("prompt")) \(item.promptVersion) · \(model.text("schema")) \(item.schemaVersion)")
                    .font(.caption2).foregroundStyle(.tertiary)
                HStack {
                    if item.confirmationState == .pending {
                        Button(model.text(effectiveCategory == .courseScheduleChange
                            ? "Preview Calendar change…"
                            : (effectiveDate == nil ? "Confirm locally" : "Preview Calendar change…"))) {
                            if effectiveCategory != .courseScheduleChange && effectiveDate == nil {
                                model.confirmAcademicSignal(item.id)
                            }
                            else { Task { await model.previewAcademicSignal(item.id) } }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(effectiveCategory == .courseScheduleChange
                            && item.audienceResolution != .resolved)
                        Button(model.text("Correct…")) {
                            let courseID = item.courseID ?? model.snapshot.announcements.first(where: { $0.id == item.announcementID })?.courseID
                            if let courseID { academicCorrectionTarget = .init(analysis: nil, signal: item, courseID: courseID) }
                        }
                        Button(model.text("Ignore"), role: .destructive) { model.rejectAcademicSignal(item.id) }
                    } else if item.confirmationState == .notRequired || unsafeSchedule {
                        Button(model.text("Correct…")) {
                            let courseID = item.courseID ?? model.snapshot.announcements.first(where: { $0.id == item.announcementID })?.courseID
                            if let courseID { academicCorrectionTarget = .init(analysis: nil, signal: item, courseID: courseID) }
                        }
                        Button(model.text("Ignore"), role: .destructive) { model.rejectAcademicSignal(item.id) }
                    } else {
                        Button(model.text("Undo")) { model.undoAcademicSignal(item.id) }
                        if item.decisionOrigin == .userCorrection {
                            Button(model.text("Reset")) { model.resetAcademicSignal(item.id) }
                        }
                    }
                }
                if unsafeSchedule {
                    Text(model.text(item.decisionOrigin == .userCorrection
                        ? "Correction saved locally, but the selected date does not match exactly one SIweb meeting. A new makeup class cannot be added to Schedule or Calendar from this control."
                        : "Correct this item to an exact SIweb meeting before previewing it."))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .contain)
            .onAppear { model.beginAcademicReview(item.id) }
        }
    }

    private func categoryLabel(_ value: AcademicSignalCategory) -> String {
        switch value {
        case .courseScheduleChange: "Course schedule change"
        case .makeupClass: "Make-up class"
        case .assignmentDeadline: "Assignment deadline"
        case .examTime: "Exam or Quiz time"
        case .other: "Other"
        }
    }

    private func persistentCard(_ item: AIParseRecord) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Badge(text: model.text(item.suggestedDate == nil ? "Organization" : "Inferred date"), color: .purple)
                    if item.hasConflict { Badge(text: model.text("Conflict / uncertain"), color: .orange) }
                    Spacer()
                    Text(item.confidence, format: .percent.precision(.fractionLength(0))).font(.headline)
                }
                labeled("Original target", "\(item.targetObjectType) · \(item.targetObjectID)")
                if !item.sourceSummary.isEmpty { labeled("Original context", item.sourceSummary) }
                if let value = item.sourceURL, let url = URL(string: value) {
                    Link(model.text("Open original source"), destination: url)
                }
                if let title = item.normalizedTitle { labeled("Normalized title", title) }
                if let type = item.suggestedType { labeled("Suggested type", type) }
                if let date = item.suggestedDate {
                    labeled("Inferred date (not yet authorized)", model.format(date))
                }
                if !item.relatedObjectIDs.isEmpty {
                    labeled("Related-item suggestions only", item.relatedObjectIDs.joined(separator: ", "))
                }
                if !item.actionItems.isEmpty { labeled("Action items", item.actionItems.joined(separator: " · ")) }
                Text(item.rationale).font(.caption).foregroundStyle(.secondary)
                Text("\(item.provider) · \(item.model) · \(model.text("prompt")) \(item.promptVersion) · \(model.text("schema")) \(item.schemaVersion)")
                    .font(.caption2).foregroundStyle(.tertiary)
                HStack {
                    Button(model.text("Confirm locally")) {
                        Task { await model.confirmAIResult(item.id) }
                    }
                        .buttonStyle(.borderedProminent)
                    Button(model.text("Correct…")) { correctionTarget = item }
                    Button(model.text("Reject"), role: .destructive) { model.rejectAIResult(item.id) }
                }
            }
        }
    }

    private func syntheticCard(_ item: ConfirmationCandidate) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Badge(text: model.text(item.kind.rawValue), color: .purple)
                    Text(courseName(item.courseID)).foregroundStyle(.secondary)
                    Spacer()
                    Text(item.confidence, format: .percent.precision(.fractionLength(0))).font(.headline)
                }
                labeled("Original context", item.sourceSummary)
                labeled("Suggestion", item.suggestion)
                Text(item.rationale).font(.caption).foregroundStyle(.secondary)
                Text(model.text("Preview only; persistent audit actions require the app database."))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.text(title)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value)
        }
    }

    private func courseName(_ id: UUID) -> String {
        model.snapshot.course(for: id)?.name ?? model.text("Unknown course")
    }
}

struct CalendarChangePreviewSheet: View {
    @ObservedObject var model: DashboardModel
    let preview: CalendarChangePreview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: preview.semantic == .exam ? "graduationcap.fill" : "calendar.badge.exclamationmark")
                    .font(.title).accessibilityHidden(true)
                Text(model.text("Calendar change preview")).font(.title2.weight(.semibold))
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                row("Operation", preview.operation.rawValue)
                row("Dedicated calendar", preview.calendarTitle)
                row("Course", preview.courseTitle)
                row("Event type", preview.semantic.rawValue)
                row("Accessible title marker", preview.displayMarker)
                if let startsAt = preview.startsAt { row("Starts", model.format(startsAt)) }
                if let endsAt = preview.endsAt { row("Ends", model.format(endsAt)) }
                row("Affected event", preview.affectedBoundEvent)
                row("Undo effect", preview.undoEffect)
            }
            Text(model.text("This preview has not changed Calendar. Confirming records the local decision and idempotently reconciles only the app-owned bound event."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(model.text("Cancel")) { dismiss() }
                Spacer()
                Button(model.text("Confirm and allow Calendar reconciliation")) {
                    model.confirmCalendarChangePreview(); dismiss()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(model.text("Confirm") + " " + model.text(preview.semantic.rawValue) + " " + preview.displayMarker)
            }
        }
        .padding(24).frame(width: 620)
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(model.text(title)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(model.text(value))
        }
    }
}

private struct CorrectionSheet: View {
    let record: AIParseRecord
    let language: AppLanguage
    let timeZone: TimeZone
    let save: (String?, String?, Date?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var type: String
    @State private var includeDate: Bool
    @State private var date: Date

    init(record: AIParseRecord, language: AppLanguage, timeZone: TimeZone,
         save: @escaping (String?, String?, Date?) -> Void) {
        self.record = record
        self.language = language
        self.timeZone = timeZone
        self.save = save
        _title = State(initialValue: record.normalizedTitle ?? "")
        _type = State(initialValue: record.suggestedType ?? "")
        _includeDate = State(initialValue: record.suggestedDate != nil)
        _date = State(initialValue: record.suggestedDate ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Localizer.text("Correct suggestion", language: language)).font(.title2.weight(.semibold))
            TextField(Localizer.text("Normalized title", language: language), text: $title)
            TextField(Localizer.text("Suggested type", language: language), text: $type)
            Toggle(Localizer.text("Include inferred date", language: language), isOn: $includeDate)
            if includeDate { DatePicker(Localizer.text("Inferred date", language: language), selection: $date) }
            Text(Localizer.text("A corrected date remains inferred. Saving is the explicit confirmation recorded in the audit trail.", language: language))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(Localizer.text("Cancel", language: language)) { dismiss() }
                Button(Localizer.text("Save correction", language: language)) { save(title, type, includeDate ? date : nil) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24).frame(width: 500)
    }
}
