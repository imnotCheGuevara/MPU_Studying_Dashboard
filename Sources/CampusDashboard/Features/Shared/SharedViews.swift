import SwiftUI

struct PageContainer<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.largeTitle.bold())
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                content
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .navigationTitle(title)
    }
}

struct ScenarioContent<Content: View>: View {
    @ObservedObject var model: DashboardModel
    let scenario: DemoScenario
    let emptyTitle: String
    let emptyMessage: String
    @ViewBuilder let content: Content

    var body: some View {
        switch scenario {
        case .populated:
            content
        case .empty:
            StatePanel(
                icon: "tray",
                title: model.text(emptyTitle),
                message: model.text(emptyMessage),
                tint: .secondary
            )
        case .loading:
            StatePanel(
                icon: "arrow.triangle.2.circlepath",
                title: model.text("Loading preview data"),
                message: model.text("The interface remains responsive while local data is prepared."),
                tint: .blue,
                showsProgress: true
            )
        case .error:
            StatePanel(
                icon: "exclamationmark.triangle",
                title: model.text("Preview sync failed"),
                message: model.text("Synthetic source data could not be refreshed. Use Refresh to recover this demo state."),
                tint: .orange
            )
        case .permissionDenied:
            StatePanel(
                icon: "hand.raised",
                title: model.text("Permission denied"),
                message: model.text("This preview demonstrates a denied integration. Core local pages remain available; no system permission is requested in Stage 01."),
                tint: .red
            )
        }
    }
}

struct StatePanel: View {
    let icon: String
    let title: String
    let message: String
    let tint: Color
    var showsProgress = false

    var body: some View {
        VStack(spacing: 12) {
            if showsProgress {
                ProgressView()
                    .controlSize(.large)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(24)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct PreviewOperationalState: View {
    @ObservedObject var model: DashboardModel

    var body: some View {
        switch model.scenario {
        case .loading:
            StatePanel(icon: "arrow.triangle.2.circlepath", title: model.text("Loading preview data"),
                       message: model.text("The interface remains responsive while local data is prepared."), tint: .blue, showsProgress: true)
        case .error:
            StatePanel(icon: "exclamationmark.triangle", title: model.text("Preview sync failed"),
                       message: model.text("Synthetic source data could not be refreshed. Use Refresh to recover this demo state."), tint: .orange)
        case .permissionDenied:
            StatePanel(icon: "hand.raised", title: model.text("Permission denied"),
                       message: model.text("This preview demonstrates a denied integration. Core local pages remain available; no system permission is requested in Stage 01."), tint: .red)
        case .populated, .empty:
            EmptyView()
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.separator.opacity(0.65))
            }
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
    }
}

extension Date {
    var shortDateTime: String {
        formatted(date: .abbreviated, time: .shortened)
    }
}

extension SourceKind {
    var tint: Color {
        switch self {
        case .canvas: .red
        case .siweb: .blue
        }
    }
}
