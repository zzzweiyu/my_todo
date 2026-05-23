import SwiftUI
import TodoCore

struct ProjectsPanelView: View {
    @ObservedObject var store: TodoStore
    @AppStorage("myTodo.showArchivedProjects") private var showArchivedProjects = false
    @State private var newProjectTitle = ""
    @State private var newStepTitles: [UUID: String] = [:]
    @State private var projectDraftTitles: [UUID: String] = [:]
    @State private var stepDraftTitles: [UUID: String] = [:]
    @State private var expandedProjectIDs: Set<UUID> = []
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private var visibleProjects: [Project] {
        store.projects(showArchived: showArchivedProjects)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(spacing: 8) {
                TextField("新增长期项目", text: $newProjectTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addProject)

                Button(action: addProject) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .help("新增项目")
                .disabled(newProjectTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Divider()

            if visibleProjects.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(visibleProjects) { project in
                            projectSection(project)
                        }
                    }
                }
                .frame(maxHeight: 360)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if let successMessage {
                Text(successMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("项目")
                    .font(.headline)

                Text("\(store.projects(showArchived: false).count) 个活跃项目")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showArchivedProjects.toggle()
            } label: {
                Image(systemName: showArchivedProjects ? "archivebox.fill" : "archivebox")
            }
            .buttonStyle(.borderless)
            .help(showArchivedProjects ? "隐藏归档项目" : "显示归档项目")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(showArchivedProjects ? "还没有项目" : "还没有活跃项目")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("先创建一个长期项目，再添加可执行步骤。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }

    private func projectSection(_ project: Project) -> some View {
        DisclosureGroup(isExpanded: expandedBinding(for: project.id)) {
            VStack(alignment: .leading, spacing: 8) {
                if project.steps.isEmpty {
                    Text("还没有步骤")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 24)
                } else {
                    ForEach(project.steps) { step in
                        stepRow(step, project: project)
                    }
                }

                HStack(spacing: 8) {
                    TextField("新增步骤", text: newStepBinding(for: project.id))
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addStep(to: project) }

                    Button {
                        addStep(to: project)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .help("新增步骤")
                    .disabled((newStepTitles[project.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.leading, 24)
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    TextField("项目标题", text: projectTitleBinding(for: project))
                        .textFieldStyle(.plain)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(project.isArchived ? .secondary : .primary)
                        .onSubmit { commitProjectTitle(project) }

                    HStack(spacing: 6) {
                        ProgressView(value: completionFraction(for: project))
                            .controlSize(.small)
                            .frame(maxWidth: 90)
                            .opacity(project.totalStepCount == 0 ? 0.35 : 1)

                        Text(projectProgressText(for: project))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let nextStep = nextActionableStep(in: project) {
                        Text("下一步：\(nextStep.title)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if project.totalStepCount > 0 {
                        Text(project.completedStepCount == project.totalStepCount ? "步骤已完成" : "今天已安排")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button {
                    scheduleNextStep(in: project)
                } label: {
                    Image(systemName: nextActionableStep(in: project) == nil ? "calendar.badge.checkmark" : "calendar.badge.plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(nextActionableStep(in: project) == nil ? "没有可加入今天的下一步" : "加入下一步到今天")
                .disabled(project.isArchived || nextActionableStep(in: project) == nil)

                Button {
                    archive(project, isArchived: !project.isArchived)
                } label: {
                    Image(systemName: project.isArchived ? "arrow.uturn.backward" : "archivebox")
                }
                .buttonStyle(.plain)
                .help(project.isArchived ? "取消归档" : "归档项目")
            }
        }
        .padding(8)
        .background(projectSectionBackground(for: project))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onDisappear { commitProjectTitle(project) }
    }

    private func stepRow(_ step: ProjectStep, project: Project) -> some View {
        HStack(spacing: 8) {
            Button {
                setStepCompleted(step, project: project, isCompleted: !step.isCompleted)
            } label: {
                Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(step.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(step.isCompleted ? "标记为未完成" : "标记完成")

            TextField("步骤标题", text: stepTitleBinding(for: step))
                .textFieldStyle(.plain)
                .foregroundStyle(step.isCompleted ? .secondary : .primary)
                .strikethrough(step.isCompleted)
                .lineLimit(1)
                .onSubmit { commitStepTitle(step, project: project) }

            Button {
                schedule(step, project: project)
            } label: {
                Image(systemName: step.scheduledTodoID == nil ? "calendar.badge.plus" : "calendar.badge.checkmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(step.scheduledTodoID == nil ? "加入今天" : "已加入今天")
            .disabled(step.scheduledTodoID != nil || step.isCompleted)

            Button {
                deleteStep(step, project: project)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("删除步骤")
        }
        .padding(.vertical, 3)
        .background(step.scheduledTodoID == nil ? Color.clear : Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .padding(.leading, 24)
        .onDisappear { commitStepTitle(step, project: project) }
    }

    private func completionFraction(for project: Project) -> Double {
        guard project.totalStepCount > 0 else {
            return 0
        }

        return Double(project.completedStepCount) / Double(project.totalStepCount)
    }

    private func projectProgressText(for project: Project) -> String {
        if project.totalStepCount == 0 {
            return "还没有步骤"
        }

        return "\(project.completedStepCount)/\(project.totalStepCount) 已完成"
    }

    private func nextActionableStep(in project: Project) -> ProjectStep? {
        project.steps.first { !$0.isCompleted && $0.scheduledTodoID == nil }
    }

    private func projectSectionBackground(for project: Project) -> Color {
        if project.isArchived {
            return Color.secondary.opacity(0.08)
        }

        if nextActionableStep(in: project) != nil {
            return Color.accentColor.opacity(0.05)
        }

        return Color.clear
    }

    private func expandedBinding(for projectID: UUID) -> Binding<Bool> {
        Binding {
            expandedProjectIDs.contains(projectID)
        } set: { isExpanded in
            if isExpanded {
                expandedProjectIDs.insert(projectID)
            } else {
                expandedProjectIDs.remove(projectID)
            }
        }
    }

    private func projectTitleBinding(for project: Project) -> Binding<String> {
        Binding {
            projectDraftTitles[project.id] ?? project.title
        } set: { value in
            projectDraftTitles[project.id] = value
        }
    }

    private func stepTitleBinding(for step: ProjectStep) -> Binding<String> {
        Binding {
            stepDraftTitles[step.id] ?? step.title
        } set: { value in
            stepDraftTitles[step.id] = value
        }
    }

    private func newStepBinding(for projectID: UUID) -> Binding<String> {
        Binding {
            newStepTitles[projectID] ?? ""
        } set: { value in
            newStepTitles[projectID] = value
        }
    }

    private func addProject() {
        do {
            let project = try store.addProject(title: newProjectTitle)
            expandedProjectIDs.insert(project.id)
            newProjectTitle = ""
            successMessage = nil
            errorMessage = nil
        } catch {
            successMessage = nil
            errorMessage = "无法新增项目。"
        }
    }

    private func commitProjectTitle(_ project: Project) {
        guard let draft = projectDraftTitles[project.id], draft != project.title else {
            return
        }

        do {
            try store.updateProjectTitle(project.id, title: draft)
            projectDraftTitles[project.id] = nil
            successMessage = nil
            errorMessage = nil
        } catch {
            projectDraftTitles[project.id] = project.title
            successMessage = nil
            errorMessage = "项目标题不能为空。"
        }
    }

    private func archive(_ project: Project, isArchived: Bool) {
        do {
            try store.setProjectArchived(project.id, isArchived: isArchived)
            successMessage = nil
            errorMessage = nil
        } catch {
            successMessage = nil
            errorMessage = "无法更新项目归档状态。"
        }
    }

    private func addStep(to project: Project) {
        do {
            _ = try store.addStep(project.id, title: newStepTitles[project.id] ?? "")
            newStepTitles[project.id] = ""
            expandedProjectIDs.insert(project.id)
            successMessage = nil
            errorMessage = nil
        } catch {
            successMessage = nil
            errorMessage = "无法新增步骤。"
        }
    }

    private func commitStepTitle(_ step: ProjectStep, project: Project) {
        guard let draft = stepDraftTitles[step.id], draft != step.title else {
            return
        }

        do {
            try store.updateStepTitle(projectID: project.id, stepID: step.id, title: draft)
            stepDraftTitles[step.id] = nil
            successMessage = nil
            errorMessage = nil
        } catch {
            stepDraftTitles[step.id] = step.title
            successMessage = nil
            errorMessage = "步骤标题不能为空。"
        }
    }

    private func setStepCompleted(_ step: ProjectStep, project: Project, isCompleted: Bool) {
        do {
            try store.setStepCompleted(projectID: project.id, stepID: step.id, isCompleted: isCompleted)
            successMessage = nil
            errorMessage = nil
        } catch {
            successMessage = nil
            errorMessage = "无法更新步骤状态。"
        }
    }

    private func schedule(_ step: ProjectStep, project: Project) {
        do {
            _ = try store.scheduleStepForToday(projectID: project.id, stepID: step.id)
            successMessage = "已加入今天：\(step.title)"
            errorMessage = nil
        } catch TodoStore.StoreError.stepAlreadyScheduled {
            successMessage = nil
            errorMessage = "这个步骤已经加入今天。"
        } catch {
            successMessage = nil
            errorMessage = "无法加入今天。"
        }
    }

    private func scheduleNextStep(in project: Project) {
        guard let step = nextActionableStep(in: project) else {
            return
        }

        schedule(step, project: project)
        expandedProjectIDs.insert(project.id)
    }

    private func deleteStep(_ step: ProjectStep, project: Project) {
        do {
            try store.deleteStep(projectID: project.id, stepID: step.id)
            stepDraftTitles[step.id] = nil
            successMessage = nil
            errorMessage = nil
        } catch {
            successMessage = nil
            errorMessage = "无法删除步骤。"
        }
    }
}
