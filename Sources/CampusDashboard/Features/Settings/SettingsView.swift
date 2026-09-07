import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: DashboardModel
    @State private var deadlineOffsetsText = "1440, 180, 60"
    @State private var pendingDestructiveAction: SettingsDestructiveAction?
    @State private var deepSeekKey = ""
    @State private var schoolPolicyConfirmed = false
    @State private var showDeepSeekDisclosure = false
    @State private var runRequestBudget = "10"
    @State private var dailyRequestBudget = "50"
    @State private var runTokenBudget = "20000"
    @State private var dailyTokenBudget = "100000"
    @State private var canvasBaseURL = ""
    @State private var canvasToken = ""

    var body: some View {
        PageContainer(title: model.text("Settings"), subtitle: model.text("Calendar access is user-controlled and limited to one dedicated calendar")) {
            ScenarioContent(
                model: model,
                scenario: model.scenario,
                emptyTitle: "No integrations configured",
                emptyMessage: "Stage 01 intentionally has no source accounts, permissions, or external services."
            ) {
                VStack(spacing: 18) {
                    settingsCard(model.text("Release setup checklist"), icon: "checklist.checked") {
                        ForEach(model.setupItems) { item in
                            HStack(alignment: .top) {
                                Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isComplete ? .green : .secondary)
                                    .accessibilityLabel(model.text(item.isComplete ? "Configured" : "Needs setup"))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(model.text(item.integration.rawValue)).font(.headline)
                                    Text(model.text(item.detail)).font(.caption).foregroundStyle(.secondary)
                                    Text(model.text(item.minimumData)).font(.caption2).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                if item.integration.isOptional { Badge(text: model.text("Optional"), color: .secondary) }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    settingsCard(model.text("Language"), icon: "globe") {
                        Picker(model.text("Interface language"), selection: $model.language) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.rawValue).tag(language)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 360)
                    }
                    settingsCard(model.text("Data sources"), icon: "externaldrive.connected.to.line.below") {
                        Text(model.text("Canvas — exact HTTPS school host and a read-only access token"))
                            .font(.headline)
                        TextField(model.text("Canvas HTTPS address"), text: $canvasBaseURL)
                            .textFieldStyle(.roundedBorder)
                        SecureField(model.text("Canvas access token (saved only to Keychain)"), text: $canvasToken)
                            .textFieldStyle(.roundedBorder).privacySensitive()
                        HStack {
                            Button(model.text("Save or reauthorize Canvas")) {
                                model.configureCanvas(baseURL: canvasBaseURL, token: canvasToken)
                                canvasToken = ""
                            }
                            .disabled(canvasBaseURL.isEmpty || canvasToken.isEmpty)
                            Button(model.text("Remove Canvas credential"), role: .destructive) { model.revokeCanvas() }
                        }
                        Text(model.text(model.canvasSetupMessage)).font(.caption).foregroundStyle(.secondary)
                        Divider()
                        Text(model.text("SIweb — MPU read-only timetable session"))
                            .font(.headline)
                        HStack {
                            Button(model.text("Authorize or reauthorize SIweb in app")) {
                                model.isSIwebAuthorizationPresented = true
                            }
                            Button(model.text("Remove SIweb authorization"), role: .destructive) { model.revokeSIweb() }
                        }
                        Text(model.text(model.siwebSetupMessage)).font(.caption).foregroundStyle(.secondary)
                        Text(model.text("The sign-in page uses a non-persistent browser. Login fields are not inspected; only an eligible secure wapps2 session is kept in Keychain."))
                            .font(.caption2).foregroundStyle(.tertiary)
                        Divider()
                        ForEach(Array(model.sourceHealth.enumerated()), id: \.element.id) { index, source in
                            if index > 0 { Divider() }
                            sourceRow(
                                source.source,
                                detail: model.text(source.message) + " " + model.text(source.recoveryAction),
                                state: model.text(source.category.rawValue)
                            )
                        }
                    }
                    if !model.courseMappingDecisions.isEmpty {
                        settingsCard(model.text("Course reconciliation"), icon: "arrow.triangle.merge") {
                            Text(model.text("Canvas and SIweb records stay unchanged. Confirmed mappings only provide one local dashboard identity."))
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(model.courseMappingDecisions.enumerated()), id: \.element.id) { index, decision in
                                if index > 0 { Divider() }
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(model.text(mappingStateLabel(decision.state))).font(.headline)
                                        Spacer()
                                        Text("\(Int((decision.confidence * 100).rounded()))%")
                                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    sourceCourseRow("Canvas", name: decision.canvasName, code: decision.canvasCode)
                                    sourceCourseRow("SIweb", name: decision.siwebName, code: decision.siwebCode)
                                    Text(model.text(mappingReasonLabel(decision.origin)))
                                        .font(.caption).foregroundStyle(.secondary)
                                    HStack {
                                        if decision.state == .proposed {
                                            Button(model.text("Map")) { model.mapCourses(decision.id) }
                                                .buttonStyle(.borderedProminent)
                                                .accessibilityIdentifier("course-map-\(decision.id.uuidString)")
                                            Button(model.text("Keep separate")) { model.keepCoursesSeparate(decision.id) }
                                                .accessibilityIdentifier("course-separate-\(decision.id.uuidString)")
                                        } else {
                                            if decision.canUndo {
                                                Button(model.text("Undo")) { model.undoCourseMapping(decision.id) }
                                                    .accessibilityIdentifier("course-undo-\(decision.id.uuidString)")
                                            }
                                            Button(model.text("Reset")) { model.resetCourseMapping(decision.id) }
                                                .accessibilityIdentifier("course-reset-\(decision.id.uuidString)")
                                        }
                                    }
                                }
                                .accessibilityElement(children: .contain)
                            }
                        }
                    }
                    settingsCard(model.text("School Outlook"), icon: "pause.circle") {
                        Label(model.text("Paused for school-policy review"), systemImage: "pause.circle.fill")
                            .font(.headline).foregroundStyle(.secondary)
                        Text(model.text("Outlook has no setup controls, background authorization, token lookup, mailbox probe, or network traffic in this release."))
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("outlook-paused-no-traffic")
                    }
                    if !model.recoveryItems.isEmpty {
                        settingsCard(model.text("Recovery center"), icon: "cross.case") {
                            ForEach(model.recoveryItems) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack { Text(model.text(item.subsystem)).font(.headline); Spacer(); Badge(text: model.text(item.category.rawValue), color: .orange) }
                                    Text(model.text(item.detail)).font(.caption)
                                    Text(model.text(item.category.unaffectedFeatures)).font(.caption).foregroundStyle(.secondary)
                                    Button(model.text(item.category.recoveryAction)) { model.performRecovery(item) }
                                        .accessibilityLabel(model.text("Recover") + " " + model.text(item.subsystem))
                                }
                                Divider()
                            }
                        }
                    }
                    settingsCard(model.text("Sync"), icon: "arrow.triangle.2.circlepath") {
                        Toggle(model.text("Automatic sync (60-minute target)"), isOn: Binding(
                            get: { model.backgroundConfiguration.enabled },
                            set: { enabled in Task { await model.setBackgroundEnabled(enabled) } }
                        ))
                        .disabled(model.isBackgroundBusy)
                        Text(model.text(model.backgroundMessage))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(model.text("This is a target interval only. The app cannot run while the Mac is asleep, off, or no user is logged in."))
                            .font(.caption).foregroundStyle(.orange)
                        Button(model.text("Open macOS Login Items settings")) {
                            model.openLoginItemSettings()
                        }
                    }
                    settingsCard(model.text("System integrations"), icon: "switch.2") {
                        calendarControls
                        Divider()
                        notificationControls
                    }
                    settingsCard(model.text("AI assistance"), icon: "sparkles") {
                        HStack {
                            Label(model.text(model.aiSettings.enabled ? "DeepSeek enabled" : "DeepSeek disabled"),
                                  systemImage: model.aiSettings.enabled ? "checkmark.shield" : "shield.slash")
                            Spacer()
                            if model.aiSettings.enabled {
                                Button(model.text("Disable and revoke consent"), role: .destructive) {
                                    model.revokeDeepSeekConsent()
                                }
                            } else {
                                Button(model.text("Review and enable DeepSeek…")) {
                                    showDeepSeekDisclosure = true
                                }
                            }
                        }
                        Text(model.text(model.aiMessage))
                            .font(.caption).foregroundStyle(.secondary)
                        Label("DeepSeek · \(DeepSeekDisclosure.model)", systemImage: "network.badge.shield.half.filled")
                            .font(.caption)
                            .accessibilityLabel(model.text("Current provider and model") + ": DeepSeek, \(DeepSeekDisclosure.model)")
                        HStack {
                            SecureField(model.text("DeepSeek API key (saved only to Keychain)"), text: $deepSeekKey)
                                .textFieldStyle(.roundedBorder).privacySensitive()
                            Button(model.text("Save key")) {
                                model.saveDeepSeekAPIKey(deepSeekKey); deepSeekKey = ""
                            }.disabled(deepSeekKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button(model.text("Remove key"), role: .destructive) { model.removeDeepSeekAPIKey() }
                                .disabled(!model.aiHasKey)
                        }
                        Text(model.text(model.aiHasKey ? "API key is stored in Keychain." : "No DeepSeek API key is stored."))
                            .font(.caption).foregroundStyle(.secondary)
                        Divider()
                        Toggle(model.text("Connect directly only for DeepSeek API"), isOn: Binding(
                            get: { model.aiSettings.directHTTPSForDeepSeek },
                            set: { model.setDeepSeekDirectHTTPS($0) }
                        ))
                        Text(model.text("Off by default. When enabled, only HTTPS requests to api.deepseek.com bypass the macOS system proxy. This does not change FlClash, VPN, or global network settings. Other hosts and apps continue using their normal settings."))
                            .font(.caption).foregroundStyle(.orange)
                        Text("\(model.text("Today's aggregate usage")): \(model.deepSeekUsage.requestCount) \(model.text("requests")), \(model.deepSeekUsage.inputTokens) \(model.text("input tokens")), \(model.deepSeekUsage.outputTokens) \(model.text("output tokens")), \(model.deepSeekUsage.estimatedCostMicrousd) µUSD \(model.text("estimated maximum-rate cost"))")
                            .font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup(model.text("Request and token budgets")) {
                            Grid(alignment: .leading) {
                                GridRow { Text(model.text("Per run requests")); TextField("", text: $runRequestBudget) }
                                GridRow { Text(model.text("Daily requests")); TextField("", text: $dailyRequestBudget) }
                                GridRow { Text(model.text("Per run tokens")); TextField("", text: $runTokenBudget) }
                                GridRow { Text(model.text("Daily tokens")); TextField("", text: $dailyTokenBudget) }
                            }.textFieldStyle(.roundedBorder)
                            Button(model.text("Apply budgets")) {
                                guard let rr = Int(runRequestBudget), let dr = Int(dailyRequestBudget),
                                      let rt = Int(runTokenBudget), let dt = Int(dailyTokenBudget) else { return }
                                model.updateDeepSeekBudgets(runRequests: rr, dailyRequests: dr,
                                                            runTokens: rt, dailyTokens: dt)
                            }
                        }
                        Button(model.text("Clear local AI results…"), role: .destructive) {
                            pendingDestructiveAction = .localData(.aiHistory)
                        }
                    }
                    if let metrics = model.outcomeMetrics {
                        settingsCard(model.text("Release outcome metrics"), icon: "chart.bar.xaxis") {
                            Text(model.text("Local aggregate operational measurements only. Synthetic QA runs must be reported separately and are not treated as real-user outcomes."))
                                .font(.caption).foregroundStyle(.secondary)
                            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                                metricRow("Sync completed / failed", "\(metrics.completedSyncs) / \(metrics.failedSyncs)")
                                metricRow("Average sync latency", metrics.averageSyncLatencySeconds.map { String(format: "%.1f s", $0) } ?? "—")
                                metricRow("Reviewed corrections", "\(metrics.reviewedCorrections)")
                                metricRow("Critical misses corrected from Other", "\(metrics.criticalCorrectionsFromOther)")
                                metricRow("Provider failure / recovery", "\(metrics.providerFailures) / \(metrics.recoveredProviderFailures)")
                                metricRow("Duplicate / unsafe Calendar writes", "\(metrics.duplicateActiveBindings) / \(metrics.unsafeCalendarBindings)")
                                metricRow("Duplicate notification keys", "\(metrics.duplicateNotificationKeys)")
                                metricRow("Handling-time samples", "\(metrics.observedHandlingSamples)")
                            }
                        }
                    }
                    settingsCard(model.text("Privacy"), icon: "lock") {
                        Label(model.text("Calendar writes are restricted to the verified dedicated calendar and bound events"), systemImage: "checkmark.shield")
                            .foregroundStyle(.green)
                        Text(model.text(model.privacyMessage))
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("privacy-status")
                        Divider()
                        Text(model.text("Clear local data by category")).font(.subheadline.weight(.semibold))
                        ForEach(LocalDataCategory.allCases) { category in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.text(category.rawValue))
                                    Text(model.text(category.explanation))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(model.text("Clear…"), role: .destructive) {
                                    pendingDestructiveAction = .localData(category)
                                }
                                .disabled(model.isPrivacyBusy)
                                .accessibilityLabel(model.text("Clear") + " " + model.text(category.rawValue))
                            }
                        }
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.text("Credentials in Keychain"))
                                Text(model.text("This is separate from cached-data clearing and does not remove Calendar events."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(model.text("Clear credentials…"), role: .destructive) {
                                pendingDestructiveAction = .credentials
                            }
                            .disabled(model.isPrivacyBusy)
                        }
                        Divider()
                        HStack {
                            Button(model.text("Preview Apple Calendar cleanup")) {
                                Task { await model.previewCalendarCleanup() }
                            }
                            .disabled(model.isPrivacyBusy)
                            Spacer()
                            if !model.calendarCleanupPreview.isEmpty {
                                Button(model.text("Delete previewed events…"), role: .destructive) {
                                    pendingDestructiveAction = .calendarEvents
                                }
                                .disabled(model.isPrivacyBusy)
                            }
                        }
                        Text(model.text("Calendar cleanup is never part of ordinary local-data clearing. Only bindings revalidated in the dedicated calendar appear here."))
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(model.calendarCleanupPreview) { item in
                            Label {
                                Text("\(item.title) · \(model.format(item.startsAt))")
                            } icon: { Image(systemName: "calendar.badge.minus") }
                            .accessibilityLabel(model.text("App-owned event eligible for cleanup") + ": " + item.title)
                        }
                    }
                    settingsCard(model.text("Redacted diagnostics"), icon: "stethoscope") {
                        Text(model.text("The export is allowlisted: status categories, recovery actions, schema version, and aggregate counts only."))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(model.text("Refresh diagnostics")) { Task { await model.refreshDiagnostics() } }
                                .keyboardShortcut("d", modifiers: [.command, .shift])
                            Button(model.text("Export redacted diagnostics…")) {
                                Task { await model.exportDiagnosticsFromUserAction() }
                            }
                        }
                        DisclosureGroup(model.text("View redacted diagnostic report")) {
                            ScrollView(.horizontal) {
                                Text(model.diagnosticPreview)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .accessibilityIdentifier("redacted-diagnostic-preview")
                            }
                            .frame(maxHeight: 240)
                        }
                    }
                }
            }
        }
        .task {
            try? await model.refreshCalendarConfiguration()
            await model.refreshNotificationConfiguration()
            await model.refreshBackgroundConfiguration()
            model.refreshAIConfiguration()
            await model.refreshDiagnostics()
            model.refreshReleaseReadiness()
            deadlineOffsetsText = model.notificationPreferences.deadlineOffsetsMinutes
                .map(String.init).joined(separator: ", ")
            runRequestBudget = String(model.aiSettings.perRunRequestBudget)
            dailyRequestBudget = String(model.aiSettings.dailyRequestBudget)
            runTokenBudget = String(model.aiSettings.perRunTokenBudget)
            dailyTokenBudget = String(model.aiSettings.dailyTokenBudget)
        }
        .sheet(isPresented: $showDeepSeekDisclosure) { deepSeekConsentSheet }
        .sheet(isPresented: $model.isSIwebAuthorizationPresented) { SIwebAuthorizationView(model: model) }
        .confirmationDialog(
            model.text("Confirm separate destructive operation"),
            isPresented: Binding(
                get: { pendingDestructiveAction != nil },
                set: { if !$0 { pendingDestructiveAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            switch pendingDestructiveAction {
            case .localData(let category):
                Button(model.text("Clear") + " " + model.text(category.rawValue), role: .destructive) {
                    Task { await model.clearLocalData(category) }
                }
            case .credentials:
                Button(model.text("Clear credentials from Keychain"), role: .destructive) {
                    Task { await model.clearCredentials() }
                }
            case .calendarEvents:
                Button(model.text("Delete only previewed app-owned events"), role: .destructive) {
                    Task { await model.removePreviewedCalendarEvents() }
                }
            case nil:
                EmptyView()
            }
            Button(model.text("Cancel"), role: .cancel) {}
        } message: {
            Text(model.text(pendingDestructiveAction?.explanation ?? ""))
        }
    }

    @ViewBuilder
    private func sourceCourseRow(_ source: String, name: String, code: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Badge(text: source, color: source == "Canvas" ? .red : .blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                if !code.isEmpty { Text(code).font(.caption.monospaced()).foregroundStyle(.secondary) }
            }
        }
    }

    private func mappingStateLabel(_ state: CourseMappingDecisionState) -> String {
        switch state {
        case .proposed: "Mapping needs confirmation"
        case .confirmed: "Mapped locally"
        case .separate: "Kept separate locally"
        case .undone: "Mapping decision undone"
        }
    }

    private func mappingReasonLabel(_ origin: String) -> String {
        switch origin {
        case "auto_full_code_title": "Matched by full module code and title."
        case "auto_code_family_unique_title": "Matched by compatible module-code family and unique title."
        case "proposed_unique_title_code_conflict": "The title is uniquely shared, but the module-code families disagree. Review both sources before mapping."
        case "user_map": "You confirmed this local mapping."
        case "user_keep_separate": "You chose to keep these source records separate."
        case "user_reset": "This decision was reset for review."
        case "user_undo": "The most recent local decision was undone."
        default: "Local course reconciliation decision."
        }
    }

    private var deepSeekConsentSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.text("Enable external AI processing")).font(.title2.weight(.semibold))
            Label("DeepSeek · \(DeepSeekDisclosure.model)", systemImage: "network")
            Text(model.text("Selected text leaves this Mac and is processed or stored in the People's Republic of China or outside your region."))
                .foregroundStyle(.orange)
            GroupBox(model.text("Fields this feature may transmit")) {
                Text(model.text(DeepSeekDisclosure.transmittedFields))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(model.text("Retention warning: no fixed API-input deletion period is disclosed. Inputs may be retained for service, legal, security, and improvement purposes."))
            HStack {
                Link(model.text("Privacy policy"), destination: URL(string: DeepSeekDisclosure.privacyURL)!)
                Text(DeepSeekDisclosure.privacyReviewed).font(.caption)
                Link(model.text("Open Platform terms"), destination: URL(string: DeepSeekDisclosure.termsURL)!)
                Text(DeepSeekDisclosure.termsReviewed).font(.caption)
            }
            Toggle(model.text("I confirmed that my school policy permits sending these selected fields to this external provider."),
                   isOn: $schoolPolicyConfirmed)
            Text(model.text("If school policy forbids external processing, do not enable DeepSeek."))
                .font(.caption).foregroundStyle(.red)
            HStack {
                Button(model.text("Cancel")) { showDeepSeekDisclosure = false }
                Spacer()
                Button(model.text("Consent and enable")) {
                    guard schoolPolicyConfirmed else { return }
                    model.grantDeepSeekConsent(schoolPolicyConfirmed: schoolPolicyConfirmed)
                    showDeepSeekDisclosure = false
                    schoolPolicyConfirmed = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(!schoolPolicyConfirmed || !model.aiHasKey)
            }
        }
        .padding(24).frame(width: 720)
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        GridRow { Text(model.text(title)).foregroundStyle(.secondary); Text(value).monospacedDigit() }
    }

    @ViewBuilder
    private var notificationControls: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.text("Local notifications")).font(.headline)
                Text(model.text(model.notificationMessage))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(model.text("Enable / Refresh")) {
                Task { await model.enableNotificationsFromUserAction() }
            }
            .disabled(model.isNotificationBusy)
        }
        Toggle(model.text("Notification master switch"), isOn: Binding(
            get: { model.notificationPreferences.enabled },
            set: { enabled in Task { await model.setNotificationsEnabled(enabled) } }
        ))
        .disabled(model.notificationAccessStatus != .authorized || model.isNotificationBusy)
        HStack {
            TextField(model.text("Deadline lead minutes"), text: $deadlineOffsetsText)
                .textFieldStyle(.roundedBorder)
            Button(model.text("Apply")) {
                let values = deadlineOffsetsText.split(separator: ",")
                    .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                Task { await model.updateNotificationTiming(deadlineOffsets: values) }
            }
            .disabled(deadlineOffsetsText.split(separator: ",").compactMap {
                Int($0.trimmingCharacters(in: .whitespaces))
            }.isEmpty)
        }
        Text(model.text("Comma-separated minutes before a deadline; defaults are 1440, 180, and 60."))
            .font(.caption).foregroundStyle(.secondary)
        Picker(model.text("Class reminder lead"), selection: Binding(
            get: { model.notificationPreferences.classLeadMinutes },
            set: { value in Task { await model.updateNotificationTiming(classLead: value) } }
        )) {
            ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) \(model.text("minutes"))").tag($0) }
        }
        HStack {
            Picker(model.text("Quiet starts"), selection: Binding(
                get: { model.notificationPreferences.quietStartMinutes },
                set: { value in Task { await model.updateNotificationTiming(quietStart: value) } }
            )) {
                ForEach(Array(stride(from: 0, to: 1_440, by: 30)), id: \.self) { minute in
                    Text(timeLabel(minute)).tag(minute)
                }
            }
            Picker(model.text("Quiet ends"), selection: Binding(
                get: { model.notificationPreferences.quietEndMinutes },
                set: { value in Task { await model.updateNotificationTiming(quietEnd: value) } }
            )) {
                ForEach(Array(stride(from: 0, to: 1_440, by: 30)), id: \.self) { minute in
                    Text(timeLabel(minute)).tag(minute)
                }
            }
        }
        Text(model.text("Notifications in quiet hours move to quiet-end only when still useful; otherwise they are discarded."))
            .font(.caption).foregroundStyle(.secondary)
        if !model.notificationCourses.isEmpty {
            Divider()
            Text(model.text("Course notifications")).font(.subheadline.weight(.semibold))
            ForEach(model.notificationCourses) { course in
                Toggle(course.name, isOn: Binding(
                    get: { course.enabled },
                    set: { enabled in Task { await model.setCourseNotifications(enabled, courseID: course.id) } }
                ))
            }
        }
        Button(model.text("Schedule synthetic test notification")) {
            Task { await model.sendTestNotification() }
        }
        .disabled(model.notificationAccessStatus != .authorized || !model.notificationPreferences.enabled)
    }

    private func timeLabel(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    @ViewBuilder
    private var calendarControls: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.text("Apple Calendar")).font(.headline)
                Text(model.text(model.calendarMessage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(model.text("Enable / Refresh")) {
                Task { await model.enableCalendarFromUserAction() }
            }
            .disabled(model.isCalendarBusy)
        }
        if model.calendarAccessStatus == .fullAccess {
            Picker(model.text("Calendar source"), selection: $model.selectedCalendarSourceID) {
                ForEach(model.calendarSources, id: \.identifier) { source in
                    Text("\(source.title) · \(model.text(source.kind.rawValue))").tag(Optional(source.identifier))
                }
            }
            HStack {
                Button(model.text("Create dedicated Campus Dashboard calendar")) {
                    Task { await model.createDedicatedCalendar() }
                }
                .disabled(model.selectedCalendarSourceID == nil || model.isCalendarBusy)
                Spacer()
            }
            Picker(model.text("Existing dedicated calendar"), selection: $model.selectedDedicatedCalendarID) {
                Text(model.text("Select a calendar")).tag(Optional<String>.none)
                ForEach(model.writableCalendars, id: \.identifier) { calendar in
                    Text("\(calendar.title) · \(calendar.source.title)").tag(Optional(calendar.identifier))
                }
            }
            HStack {
                Button(model.text("Use selected dedicated calendar")) {
                    Task { await model.selectDedicatedCalendar() }
                }
                .disabled(model.selectedDedicatedCalendarID == nil || model.isCalendarBusy)
                Spacer()
            }
            Text(model.text("Select only a calendar dedicated to Campus Dashboard. Names are never used as identity."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func settingsCard<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: icon).font(.headline)
                content()
            }
        }
    }

    private func sourceRow(_ title: String, detail: String, state: String) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Badge(text: state, color: .blue)
        }
    }
}

private enum SettingsDestructiveAction: Identifiable {
    case localData(LocalDataCategory)
    case credentials
    case calendarEvents

    var id: String {
        switch self {
        case .localData(let category): "local-\(category.rawValue)"
        case .credentials: "credentials"
        case .calendarEvents: "calendar-events"
        }
    }

    var explanation: String {
        switch self {
        case .localData(let category): category.explanation
        case .credentials: "Removes Canvas and SIweb credentials from Keychain only. Cached data and Calendar events remain."
        case .calendarEvents: "Deletes only events shown in the preview after their app ownership is revalidated."
        }
    }
}
