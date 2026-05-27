import SwiftUI
import TodoCore

private enum ProjectFocusField: Hashable {
    case project
    case step(UUID)
}

private enum ProjectStepFilter: String, CaseIterable, Identifiable {
    case all
    case open
    case unscheduled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .open:
            return "未完成"
        case .unscheduled:
            return "未安排"
        }
    }
}

struct ProjectsPanelView: View {
    @ObservedObject var store: TodoStore
    @AppStorage("myTodo.showArchivedProjects") private var showArchivedProjects = false
    @AppStorage("myTodo.projectStepFilter") private var projectStepFilterRaw = ProjectStepFilter.all.rawValue
    @State private var newProjectTitle = ""
    @State private var newStepTitles: [UUID: String] = [:]
    @State private var projectDraftTitles: [UUID: String] = [:]
    @State private var stepDraftTitles: [UUID: String] = [:]
    @State private var expandedProjectIDs: Set<UUID> = []
    @State private var expandedStepIDs: Set<UUID> = []
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @FocusState private var focusedField: ProjectFocusField?

    private var visibleProjects: [Project] {
        store.projects(showArchived: showArchivedProjects)
    }

    private let maxVisibleStepDepth = 2

    private var projectsListHeight: CGFloat {
        let sectionsHeight = visibleProjects.reduce(CGFloat.zero) { total, project in
            total + estimatedProjectSectionHeight(project)
        }
        let spacingHeight = CGFloat(max(visibleProjects.count - 1, 0)) * 8

        return min(sectionsHeight + spacingHeight, 460)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            projectCaptureSection

            stepFilterBar

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
                .frame(height: projectsListHeight)
            }

        }
        .onAppear(perform: focusProjectCapture)
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

    private var projectCaptureSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .foregroundStyle(.secondary)

                TextField("新增长期项目", text: $newProjectTitle)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .project)
                    .onSubmit(addProject)
                    .onExitCommand(perform: clearProjectCapture)

                Button(action: addProject) {
                    Image(systemName: "arrow.turn.down.left")
                }
                .buttonStyle(.bordered)
                .help("新增项目")
                .disabled(trimmedNewProjectTitle.isEmpty)
            }

            projectCaptureMessage
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var projectCaptureMessage: some View {
        HStack(spacing: 6) {
            if let errorMessage {
                Image(systemName: "exclamationmark.circle")
                Text(errorMessage)
            } else if let successMessage {
                Image(systemName: "checkmark.circle")
                Text(successMessage)
            } else {
                Text("Return 添加项目，Esc 清空")
            }
        }
        .font(.caption)
        .foregroundStyle(projectMessageColor)
        .lineLimit(1)
    }

    private var stepFilterBar: some View {
        HStack(spacing: 8) {
            Picker("步骤范围", selection: projectStepFilterBinding) {
                ForEach(ProjectStepFilter.allCases) { filter in
                    Text(filter.title).tag(filter.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Text(stepFilterSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 78, alignment: .trailing)
        }
    }

    private func projectSection(_ project: Project) -> some View {
        DisclosureGroup(isExpanded: expandedBinding(for: project.id)) {
            VStack(alignment: .leading, spacing: 8) {
                let visibleSteps = filteredSteps(project.steps)

                if project.steps.isEmpty {
                    Text("还没有步骤")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 24)
                } else if visibleSteps.isEmpty {
                    Text(stepFilterEmptyText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 24)
                } else {
                    ForEach(visibleSteps) { step in
                        stepNode(step, project: project)
                    }
                }

                stepCaptureSection(for: project)
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

    @ViewBuilder
    private func stepNode(_ step: ProjectStep, project: Project) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let visibleChildren = step.children

            stepRow(step, project: project, depth: 0)

            if !visibleChildren.isEmpty || expandedStepIDs.contains(step.id) {
                if !visibleChildren.isEmpty {
                    ForEach(visibleChildren) { child in
                        childStepNode(child, project: project)
                    }
                }

                childStepCaptureSection(parentStep: step, project: project, depth: 1)
            }
        }
    }

    @ViewBuilder
    private func childStepNode(_ step: ProjectStep, project: Project) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let visibleChildren = step.children

            stepRow(step, project: project, depth: 1)

            if !visibleChildren.isEmpty || expandedStepIDs.contains(step.id) {
                if !visibleChildren.isEmpty {
                    ForEach(visibleChildren) { child in
                        grandchildStepNode(child, project: project)
                    }
                }

                childStepCaptureSection(parentStep: step, project: project, depth: 2)
            }
        }
    }

    private func grandchildStepNode(_ step: ProjectStep, project: Project) -> some View {
        stepRow(step, project: project, depth: 2)
    }

    private func stepCaptureSection(for project: Project) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.secondary)

            TextField("新增步骤", text: newStepBinding(for: project.id))
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .step(project.id))
                .onSubmit { addStep(to: project) }
                .onExitCommand { clearStepCapture(for: project.id) }

            Button {
                addStep(to: project)
            } label: {
                Image(systemName: "arrow.turn.down.left")
            }
            .buttonStyle(.bordered)
            .help("新增步骤")
            .disabled(trimmedNewStepTitle(for: project.id).isEmpty)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.leading, 24)
    }

    private func childStepCaptureSection(parentStep: ProjectStep, project: Project, depth: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.turn.down.right")
                .foregroundStyle(.secondary)

            TextField("新增子任务", text: newStepBinding(for: parentStep.id))
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .step(parentStep.id))
                .onSubmit { addChildStep(to: parentStep, project: project) }
                .onExitCommand { clearStepCapture(for: parentStep.id) }

            Button {
                addChildStep(to: parentStep, project: project)
            } label: {
                Image(systemName: "arrow.turn.down.left")
            }
            .buttonStyle(.bordered)
            .help("新增子任务")
            .disabled(trimmedNewStepTitle(for: parentStep.id).isEmpty)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.leading, stepLeadingPadding(for: depth))
    }

    private func estimatedProjectSectionHeight(_ project: Project) -> CGFloat {
        var height: CGFloat = 86

        if expandedProjectIDs.contains(project.id) {
            let stepsHeight: CGFloat
            if project.steps.isEmpty {
                stepsHeight = 20
            } else {
                stepsHeight = estimatedStepsHeight(filteredSteps(project.steps), depth: 0)
            }

            height += 6 + stepsHeight + 8 + 36
        }

        return height
    }

    private func estimatedStepsHeight(_ steps: [ProjectStep], depth: Int) -> CGFloat {
        steps.reduce(CGFloat.zero) { total, step in
            var height: CGFloat = 38

            if depth < maxVisibleStepDepth && (!step.children.isEmpty || expandedStepIDs.contains(step.id)) {
                height += 6
                height += estimatedStepsHeight(step.children, depth: depth + 1)
                height += 44
            }

            return total + height + 6
        }
    }

    private func stepRow(_ step: ProjectStep, project: Project, depth: Int) -> some View {
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

            if depth < maxVisibleStepDepth {
                Button {
                    showChildCapture(for: step)
                } label: {
                    Image(systemName: "list.bullet.indent")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("添加子任务")
            }

            WeeklyReportTagButton(
                status: step.weeklyReportStatus,
                note: step.weeklyReportNote
            ) { status, note in
                updateStepWeeklyReportMetadata(step, project: project, status: status, note: note)
            }

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
        .padding(.leading, stepLeadingPadding(for: depth))
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

    private var projectStepFilter: ProjectStepFilter {
        ProjectStepFilter(rawValue: projectStepFilterRaw) ?? .all
    }

    private var projectStepFilterBinding: Binding<String> {
        Binding {
            projectStepFilter.rawValue
        } set: { value in
            projectStepFilterRaw = value
        }
    }

    private var stepFilterSummaryText: String {
        let projects = visibleProjects

        switch projectStepFilter {
        case .all:
            let total = projects.reduce(0) { $0 + $1.totalStepCount }
            return "\(total) 个步骤"
        case .open:
            let total = projects.reduce(0) { $0 + $1.openStepCount }
            return "\(total) 个未完成"
        case .unscheduled:
            let total = projects.reduce(0) { $0 + $1.unscheduledOpenStepCount }
            return "\(total) 个未安排"
        }
    }

    private var stepFilterEmptyText: String {
        switch projectStepFilter {
        case .all:
            return "没有可显示的步骤"
        case .open:
            return "没有未完成步骤"
        case .unscheduled:
            return "没有未安排步骤"
        }
    }

    private func filteredSteps(_ steps: [ProjectStep]) -> [ProjectStep] {
        steps.compactMap(filteredStep)
    }

    private func filteredStep(_ step: ProjectStep) -> ProjectStep? {
        let children = filteredSteps(step.children)

        guard stepMatchesCurrentFilter(step) || !children.isEmpty else {
            return nil
        }

        var visibleStep = step
        visibleStep.children = children
        return visibleStep
    }

    private func stepMatchesCurrentFilter(_ step: ProjectStep) -> Bool {
        switch projectStepFilter {
        case .all:
            return true
        case .open:
            return !step.isCompleted
        case .unscheduled:
            return !step.isCompleted && step.scheduledTodoID == nil
        }
    }

    private func nextActionableStep(in project: Project) -> ProjectStep? {
        nextActionableStep(in: project.steps)
    }

    private func nextActionableStep(in steps: [ProjectStep]) -> ProjectStep? {
        for step in steps {
            if !step.isCompleted && step.scheduledTodoID == nil {
                return step
            }

            if let child = nextActionableStep(in: step.children) {
                return child
            }
        }

        return nil
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

    private var projectMessageColor: Color {
        if errorMessage != nil {
            return .red
        }

        if successMessage != nil {
            return .secondary
        }

        return Color.secondary.opacity(0.75)
    }

    private var trimmedNewProjectTitle: String {
        newProjectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func trimmedNewStepTitle(for projectID: UUID) -> String {
        (newStepTitles[projectID] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stepLeadingPadding(for depth: Int) -> CGFloat {
        24 + CGFloat(depth) * 18
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

    private func focusProjectCapture() {
        DispatchQueue.main.async {
            focusedField = .project
        }
    }

    private func focusStepCapture(for projectID: UUID) {
        DispatchQueue.main.async {
            focusedField = .step(projectID)
        }
    }

    private func clearProjectCapture() {
        newProjectTitle = ""
        errorMessage = nil
        successMessage = nil
        focusProjectCapture()
    }

    private func clearStepCapture(for projectID: UUID) {
        newStepTitles[projectID] = ""
        errorMessage = nil
        successMessage = nil
        focusStepCapture(for: projectID)
    }

    private func addProject() {
        do {
            let project = try store.addProject(title: newProjectTitle)
            expandedProjectIDs.insert(project.id)
            newProjectTitle = ""
            successMessage = "已添加项目"
            errorMessage = nil
            focusStepCapture(for: project.id)
        } catch {
            successMessage = nil
            errorMessage = "无法新增项目。"
            focusProjectCapture()
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
            successMessage = "已添加步骤"
            errorMessage = nil
            focusStepCapture(for: project.id)
        } catch {
            successMessage = nil
            errorMessage = "无法新增步骤。"
            focusStepCapture(for: project.id)
        }
    }

    private func addChildStep(to parentStep: ProjectStep, project: Project) {
        do {
            _ = try store.addChildStep(
                projectID: project.id,
                parentStepID: parentStep.id,
                title: newStepTitles[parentStep.id] ?? ""
            )
            newStepTitles[parentStep.id] = ""
            expandedProjectIDs.insert(project.id)
            expandedStepIDs.insert(parentStep.id)
            successMessage = "已添加子任务"
            errorMessage = nil
            focusStepCapture(for: parentStep.id)
        } catch {
            successMessage = nil
            errorMessage = "无法新增子任务。"
            focusStepCapture(for: parentStep.id)
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

    private func showChildCapture(for step: ProjectStep) {
        expandedStepIDs.insert(step.id)
        focusStepCapture(for: step.id)
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

    private func updateStepWeeklyReportMetadata(
        _ step: ProjectStep,
        project: Project,
        status: WeeklyReportStatus,
        note: String?
    ) {
        do {
            try store.updateStepWeeklyReportMetadata(
                projectID: project.id,
                stepID: step.id,
                status: status,
                note: note
            )
            successMessage = "已更新周报标记"
            errorMessage = nil
        } catch {
            successMessage = nil
            errorMessage = "无法更新周报标记。"
        }
    }
}
