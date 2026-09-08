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
                        taskCard(task)
                    }

                    ForEach(placeholderGroups, id: \.courseID) { group in
                        DisclosureGroup("\(model.text("Placeholder assignments")) · \(courseName(group.courseID)) (\(group.tasks.count))") {
                            VStack(spacing: 10) {
                                ForEach(group.tasks) { task in
                                    Card {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(task.title).font(.headline)
                                            Text(model.text("Stored for source continuity; excluded from AI, Calendar, and notifications."))
                                                .font(.caption).foregroundStyle(.secondary)
                                            Toggle(model.text("Always show in task list"), isOn: Binding(
                                                get: { task.placeholderAlwaysShow },
                                                set: { model.setPlaceholderAlwaysShow(task.id, alwaysShow: $0) }
                                            ))
                                        }
                                    }
                                }
                            }.padding(.top, 8)
                        }
                    }
                }
            }
        }
    }

    private var filteredTasks: [LearningTask] {
        Self.normalTasks(in: model.snapshot.tasks, filter: filter)
    }

    private var placeholderGroups: [(courseID: UUID, tasks: [LearningTask])] {
        Dictionary(grouping: Self.groupedPlaceholders(in: model.snapshot.tasks, filter: filter), by: \.courseID)
            .map { ($0.key, $0.value.sorted { $0.title < $1.title }) }
            .sorted { courseName($0.courseID) < courseName($1.courseID) }
    }

    static func normalTasks(in tasks: [LearningTask], filter: TaskKind?) -> [LearningTask] {
        tasks.filter { task in
            task.appearsInNormalTaskList && (filter == nil || task.kind == filter)
        }
    }

    static func groupedPlaceholders(in tasks: [LearningTask], filter: TaskKind?) -> [LearningTask] {
        tasks.filter { task in
            task.isPlaceholder && !task.placeholderAlwaysShow && (filter == nil || task.kind == filter)
        }
    }

    private func taskCard(_ task: LearningTask) -> some View {
        Card {
            HStack(alignment: .top) {
                Button { model.toggleTask(task.id) } label: {
                    Image(systemName: task.isLocallyComplete ? "checkmark.circle.fill" : "circle").font(.title2)
                }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(task.title).font(.headline).strikethrough(task.isLocallyComplete)
                        Badge(text: model.text(task.kind.rawValue), color: .blue)
                        if task.isPlaceholder {
                            Badge(text: model.text("Placeholder"), color: .purple)
                        }
                        Spacer()
                        Badge(text: model.text(task.localPriority.rawValue), color: task.localPriority == .high ? .red : .orange)
                    }
                    Text(courseName(task.courseID)).foregroundStyle(.secondary)
                    Label(task.officialDueAt.map { "\(model.text("Official")): \(model.format($0))" } ?? model.text("No official due date"), systemImage: "building.columns")
                        .font(.caption)
                    if task.isPlaceholder {
                        Text(model.text("Stored for source continuity; excluded from AI, Calendar, and notifications."))
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle(model.text("Always show in task list"), isOn: Binding(
                            get: { task.placeholderAlwaysShow },
                            set: { model.setPlaceholderAlwaysShow(task.id, alwaysShow: $0) }
                        ))
                    }
                }
            }
        }
    }

    private func courseName(_ id: UUID) -> String {
        model.snapshot.course(for: id)?.name ?? model.text("Unknown course")
    }
}
