import SwiftUI

struct AnnouncementsView: View {
    @ObservedObject var model: DashboardModel
    @State private var category: AcademicSignalCategory?
    @State private var correctionTarget: AcademicCorrectionTarget?
    @State private var previewError: String?

    var body: some View {
        PageContainer(title: model.text("Announcements"), subtitle: model.text("Source content with local-only read state")) {
            ScenarioContent(
                model: model,
                scenario: model.scenarioForEmpty(model.snapshot.announcements.isEmpty),
                emptyTitle: "No announcements",
                emptyMessage: "There are no synchronized announcements to show."
            ) {
                VStack(spacing: 14) {
                    HStack {
                        Picker(model.text("Academic signal category"), selection: $category) {
                            Text(model.text("All categories")).tag(nil as AcademicSignalCategory?)
                            ForEach(AcademicSignalCategory.allCases) { value in
                                Text(model.text(categoryLabel(value))).tag(value as AcademicSignalCategory?)
                            }
                        }
                        .frame(width: 260)
                        Spacer()
                        Text(model.text("AI labels are local suggestions, not Canvas facts."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let previewError {
                        Text(model.text(previewError)).font(.caption).foregroundStyle(.red)
                    }
                    ForEach(filteredAnnouncements) { announcement in
                        Card {
                            HStack(alignment: .top, spacing: 12) {
                                Circle()
                                    .fill(announcement.isLocallyRead ? .clear : .blue)
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 7)
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(announcement.title).font(.headline)
                                        Spacer()
                                        Badge(text: announcement.source.rawValue, color: announcement.source.tint)
                                    }
                                    Text(courseName(announcement.courseID)).foregroundStyle(.secondary)
                                    Text(announcement.summary)
                                    Text(model.format(announcement.publishedAt)).font(.caption).foregroundStyle(.secondary)
                                    analysisContent(for: announcement)
                                    if let value = announcement.sourceURL, let url = URL(string: value) {
                                        Link(model.text("Open original source"), destination: url).font(.caption)
                                    }
                                }
                                Button(model.text(announcement.isLocallyRead ? "Mark unread" : "Mark read")) {
                                    model.toggleAnnouncement(announcement.id)
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(item: $correctionTarget) { target in
            AcademicSignalCorrectionSheet(model: model, target: target) {
                correctionTarget = nil
            }
        }
        .sheet(item: $model.calendarChangePreview) { preview in
            CalendarChangePreviewSheet(model: model, preview: preview)
        }
        .task { model.refreshAIConfiguration() }
    }

    private var filteredAnnouncements: [Announcement] {
        model.snapshot.announcements
            .filter { announcement in
                guard let category else { return true }
                if category == .other {
                    return model.academicAnalysis(for: announcement.id)?.primaryCategory == .other
                }
                return model.academicSignals(for: announcement.id).contains {
                    ($0.adoptedCategory ?? $0.category) == category
                }
            }
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    @ViewBuilder
    private func analysisContent(for announcement: Announcement) -> some View {
        let analysis = model.academicAnalysis(for: announcement.id)
        let signals = model.academicSignals(for: announcement.id)
        Divider()
        HStack {
            Label(model.text(statusLabel(analysis?.status)), systemImage: "sparkles")
                .font(.caption.weight(.semibold))
            if let analysis {
                Badge(text: model.text(categoryLabel(analysis.primaryCategory)), color: .purple)
            }
            Spacer()
            Button(model.text(model.reprocessingAnnouncementIDs.contains(announcement.id) ? "Processing…" : "Reprocess")) {
                Task { await model.reprocessAcademicSignals(for: announcement.id) }
            }
            .disabled(model.reprocessingAnnouncementIDs.contains(announcement.id))
            .accessibilityHint(model.text("Analyze this announcement again using the current local rules and enabled provider."))
        }
        if let failure = AcademicProviderFailurePresentation.safe(analysis?.failureCategory) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.text(failure.categoryKey)).font(.caption.weight(.semibold))
                Text(model.text(failure.recoveryKey)).font(.caption).foregroundStyle(.secondary)
                if failure.retryable {
                    Text(model.text("This issue is retryable.")).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
        if signals.isEmpty {
            Text(model.text("No actionable academic signal was found."))
                .font(.caption).foregroundStyle(.secondary)
            if let analysis {
                Button(model.text("Correct analysis…")) {
                    correctionTarget = .init(analysis: analysis, signal: nil, courseID: announcement.courseID)
                }
            }
        } else {
            ForEach(signals) { signal in
                VStack(alignment: .leading, spacing: 4) {
                    let effectiveCategory = signal.adoptedCategory ?? signal.category
                    let effectiveDate = signal.adoptedDate ?? signal.inferredDate
                    HStack {
                        Badge(text: model.text(categoryLabel(effectiveCategory)), color: .purple)
                        if !signal.conflicts.isEmpty {
                            Badge(text: model.text("Conflict / uncertain"), color: .orange)
                        }
                        if signal.audienceResolution == .pendingReview {
                            Badge(text: model.text("Section needs review"), color: .orange)
                        }
                        Spacer()
                        Text(signal.confidence, format: .percent.precision(.fractionLength(0)))
                    }
                    labeled("Evidence", signal.evidence)
                    labeled("Key requirement", signal.adoptedKeyRequirement ?? signal.keyRequirement)
                    if let date = effectiveDate {
                        labeled("Inferred date (not yet authorized)",
                                ((signal.adoptedIsAllDay ?? signal.isAllDay) ? model.text("All-day") + " · " : "") + model.format(date))
                    }
                    labeled("Reason", signal.reason)
                    if !signal.conflicts.isEmpty { labeled("Conflicts", signal.conflicts.joined(separator: " · ")) }
                    Text("\(signal.provider) · \(signal.model) · \(model.text("prompt")) \(signal.promptVersion) · \(model.text("schema")) \(signal.schemaVersion)")
                        .font(.caption2).foregroundStyle(.tertiary)
                    if signal.confirmationState == .pending {
                        HStack {
                            Button(model.text(effectiveCategory == .courseScheduleChange || effectiveDate != nil
                                ? "Preview Calendar change…" : "Confirm locally")) {
                                if effectiveCategory == .courseScheduleChange || effectiveDate != nil {
                                    Task {
                                        if !(await model.previewAcademicSignal(signal.id)) {
                                            previewError = "Calendar preview could not be opened. No event was changed."
                                        } else { previewError = nil }
                                    }
                                } else {
                                    model.confirmAcademicSignal(signal.id)
                                }
                            }
                                .buttonStyle(.borderedProminent)
                                .disabled(effectiveCategory == .courseScheduleChange
                                    && signal.audienceResolution != .resolved)
                            Button(model.text("Correct…")) { correctionTarget = .init(analysis: analysis, signal: signal, courseID: announcement.courseID) }
                            Button(model.text("Reject"), role: .destructive) { model.rejectAcademicSignal(signal.id) }
                        }
                        if effectiveCategory == .courseScheduleChange
                            && signal.audienceResolution != .resolved {
                            Text(model.text(signal.decisionOrigin == .userCorrection
                                ? "Correction saved locally, but the selected date does not match exactly one SIweb meeting. A new makeup class cannot be added to Schedule or Calendar from this control."
                                : "Correct this item to an exact SIweb meeting before previewing it."))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    } else if signal.confirmationState == .notRequired {
                        HStack {
                            Button(model.text("Correct…")) { correctionTarget = .init(analysis: analysis, signal: signal, courseID: announcement.courseID) }
                            Button(model.text("Reject"), role: .destructive) { model.rejectAcademicSignal(signal.id) }
                        }
                    } else {
                        HStack {
                            Badge(text: model.text(signal.confirmationState.rawValue), color: .secondary)
                            Button(model.text("Undo")) { model.undoAcademicSignal(signal.id) }
                            if signal.decisionOrigin == .userCorrection {
                                Button(model.text("Reset")) { model.resetAcademicSignal(signal.id) }
                            }
                        }
                    }
                }
                .padding(.top, 5)
                .accessibilityElement(children: .contain)
            }
        }
    }

    private func labeled(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(model.text(key)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.caption)
        }
    }

    private func statusLabel(_ status: AcademicAnalysisStatus?) -> String {
        switch status {
        case .deterministicOnly: "Deterministic analysis"
        case .analyzed: "DeepSeek analysis"
        case .failed: "Provider unavailable; deterministic result retained"
        case .disabled: "AI disabled; deterministic result retained"
        case nil: "Not analyzed"
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

    private func courseName(_ id: UUID) -> String {
        model.snapshot.course(for: id)?.name ?? model.text("Unknown course")
    }
}

struct AcademicCorrectionTarget: Identifiable {
    let analysis: AcademicAnnouncementAnalysis?
    let signal: AcademicSignalRecord?
    let courseID: UUID
    var id: UUID { signal?.id ?? analysis?.id ?? courseID }
}

struct AcademicSignalCorrectionSheet: View {
    @ObservedObject var model: DashboardModel
    let target: AcademicCorrectionTarget
    let completed: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var category: AcademicSignalCategory
    @State private var includeDate: Bool
    @State private var date: Date
    @State private var isAllDay: Bool
    @State private var keyRequirement: String
    @State private var timeZoneIdentifier: String
    @State private var courseID: UUID
    @State private var saveError: String?

    init(model: DashboardModel, target: AcademicCorrectionTarget, completed: @escaping () -> Void) {
        self.model = model; self.target = target; self.completed = completed
        _category = State(initialValue: target.signal?.adoptedCategory ?? target.signal?.category
            ?? target.analysis?.primaryCategory ?? .courseScheduleChange)
        _includeDate = State(initialValue: (target.signal?.adoptedDate ?? target.signal?.inferredDate) != nil)
        _date = State(initialValue: target.signal?.adoptedDate ?? target.signal?.inferredDate ?? Date())
        _isAllDay = State(initialValue: target.signal?.adoptedIsAllDay ?? target.signal?.isAllDay ?? false)
        _keyRequirement = State(initialValue: target.signal?.adoptedKeyRequirement
            ?? target.signal?.keyRequirement ?? "Review this academic update.")
        _timeZoneIdentifier = State(initialValue: target.signal?.adoptedTimeZoneIdentifier
            ?? target.signal?.timeZoneIdentifier ?? TimeZone.current.identifier)
        _courseID = State(initialValue: target.signal?.courseID ?? target.courseID)
        _saveError = State(initialValue: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.text("Correct academic signal")).font(.title2.weight(.semibold))
            Picker(model.text("Category"), selection: $category) {
                Text(model.text("Course schedule change")).tag(AcademicSignalCategory.courseScheduleChange)
                Text(model.text("Make-up class")).tag(AcademicSignalCategory.makeupClass)
                Text(model.text("Assignment deadline")).tag(AcademicSignalCategory.assignmentDeadline)
                Text(model.text("Exam or Quiz time")).tag(AcademicSignalCategory.examTime)
            }
            TextField(model.text("Key requirement"), text: $keyRequirement)
            Picker(model.text("Course"), selection: $courseID) {
                ForEach(model.snapshot.courses) { course in Text(course.name).tag(course.id) }
            }
            Toggle(model.text("Include inferred date"), isOn: $includeDate)
            if includeDate {
                DatePicker(model.text("Inferred date"), selection: $date)
                Toggle(model.text("All-day"), isOn: $isAllDay)
                TextField(model.text("Time zone"), text: $timeZoneIdentifier)
            }
            Text(model.text(category == .courseScheduleChange
                ? "Saving this correction does not authorize Calendar. Preview the exact SIweb meeting, then confirm."
                : (category == .makeupClass
                    ? "Saving a make-up class does not authorize Calendar. Preview the new three-hour event, then confirm."
                    : "A corrected date remains inferred and this save records explicit local confirmation.")))
                .font(.caption).foregroundStyle(.secondary)
            if let saveError {
                Text(model.text(saveError)).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(model.text("Cancel")) { dismiss() }
                Button(model.text("Save correction")) {
                    let saved: Bool
                    if let signal = target.signal {
                        saved = model.correctAcademicSignal(signal.id, category: category,
                            keyRequirement: keyRequirement, date: includeDate ? date : nil,
                            isAllDay: isAllDay, timeZoneIdentifier: includeDate ? timeZoneIdentifier : nil,
                            courseID: courseID)
                    } else if let analysis = target.analysis {
                        saved = model.correctAcademicAnalysis(analysis.id, category: category,
                            keyRequirement: keyRequirement, date: includeDate ? date : nil,
                            isAllDay: isAllDay, timeZoneIdentifier: includeDate ? timeZoneIdentifier : nil,
                            courseID: courseID)
                    } else {
                        saved = false
                    }
                    if saved {
                        completed(); dismiss()
                    } else {
                        saveError = "The academic-signal correction could not be saved."
                    }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 520)
    }
}
