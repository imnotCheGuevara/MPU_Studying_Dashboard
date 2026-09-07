import SwiftUI

struct TasksView: View {
    @ObservedObject var model: DashboardModel
    @State private var filter: TaskKind?

    var body: some View {
        PageContainer(title: model.text("Tasks"), subtitle: model.text("Official deadlines remain distinct from local suggestions")) {
            ScenarioContent(
                model: model,
                scenario: model.scenarioForEmpty(model.snapshot.tasks.isEmpty),
                emptyTitle: "No tasks",
                emptyMessage: "No synchronized tasks match the current filter."
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    Picker(model.text("Task type"), selection: $filter) {
                        Text(model.text("All types")).tag(TaskKind?.none)
                        ForEach(TaskKind.allCases, id: \.self) { kind in
                            Text(model.text(kind.rawValue)).tag(TaskKind?.some(kind))
                        }
                    }
                    .frame(width: 220)

                    ForEach(filteredTasks) { task in
                        Card {
                            HStack(alignment: .top) {
                                Button {
                                    model.toggleTask(task.id)
                                } label: {
                                    Image(systemName: task.isLocallyComplete ? "checkmark.circle.fill" : "circle")
                                        .font(.title2)
                                }
                                .buttonStyle(.plain)
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(task.title)
                                            .font(.headline)
                                            .strikethrough(task.isLocallyComplete)
                                        Badge(text: model.text(task.kind.rawValue), color: .blue)
                                        Spacer()
                                        Badge(text: model.text(task.localPriority.rawValue), color: task.localPriority == .high ? .red : .orange)
                                    }
                                    Text(courseName(task.courseID)).foregroundStyle(.secondary)
                                    HStack(spacing: 16) {
                                        Label(task.officialDueAt.map { "\(model.text("Official")): \(model.format($0))" } ?? model.text("No official due date"), systemImage: "building.columns")
                                        if let suggestion = task.suggestedCompleteAt {
                                            Label("\(model.text("Suggested")): \(model.format(suggestion))", systemImage: "sparkles")
                                                .foregroundStyle(task.suggestedDateConfirmed ? .green : .purple)
                                        }
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var filteredTasks: [LearningTask] {
        guard let filter else { return model.snapshot.tasks }
        return model.snapshot.tasks.filter { $0.kind == filter }
    }

    private func courseName(_ id: UUID) -> String {
        model.snapshot.course(for: id)?.name ?? model.text("Unknown course")
    }
}
