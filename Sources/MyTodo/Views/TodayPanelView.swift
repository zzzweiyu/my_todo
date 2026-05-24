import SwiftUI
import TodoCore

struct TodayPanelView: View {
    @ObservedObject var store: TodoStore
    @AppStorage("myTodo.showCompleted") private var showCompleted = true
    @State private var newTaskTitle = ""
    @State private var draftTitles: [UUID: String] = [:]
    @State private var errorMessage: String?
    @State private var recentlyAddedTaskID: UUID?
    @State private var successMessage: String?
    @FocusState private var isCaptureFocused: Bool

    private var visibleItems: [TodoItem] {
        store.todayItems(showCompleted: showCompleted)
    }

    private var openCount: Int {
        store.todayItems(showCompleted: false).count
    }

    private var allTodayItems: [TodoItem] {
        store.todayItems(showCompleted: true)
    }

    private var completedCount: Int {
        allTodayItems.filter(\.isCompleted).count
    }

    private var totalCount: Int {
        allTodayItems.count
    }

    private var completionFraction: Double {
        guard totalCount > 0 else {
            return 0
        }

        return Double(completedCount) / Double(totalCount)
    }

    private var todayListHeight: CGFloat {
        let rowsHeight = visibleItems.reduce(CGFloat.zero) { total, item in
            total + (store.projectTitle(for: item) == nil ? 48 : 64)
        }
        let spacingHeight = CGFloat(max(visibleItems.count - 1, 0)) * 4

        return min(rowsHeight + spacingHeight, 420)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            progressSection

            captureSection

            if visibleItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(visibleItems) { item in
                            TodoRowView(
                                item: item,
                                title: binding(for: item),
                                projectTitle: store.projectPath(for: item),
                                deleteHelp: item.projectID == nil ? "删除任务" : "取消今日安排",
                                isHighlighted: item.id == recentlyAddedTaskID,
                                onToggle: { setCompleted(item, isCompleted: !item.isCompleted) },
                                onCommitTitle: { commitTitle(for: item) },
                                onDelete: { delete(item) }
                            )
                        }
                    }
                }
                .frame(height: todayListHeight)
            }
        }
        .onAppear(perform: focusCaptureField)
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("今天")
                    .font(.headline)

                Text(openCount == 0 ? "全部完成" : "\(openCount) 个未完成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showCompleted.toggle()
            } label: {
                Image(systemName: showCompleted ? "eye" : "eye.slash")
            }
            .buttonStyle(.borderless)
            .help(showCompleted ? "隐藏已完成" : "显示已完成")

            Button(action: clearCompletedToday) {
                Image(systemName: "checkmark.circle.badge.xmark")
            }
            .buttonStyle(.borderless)
            .help("清理今天已完成")
            .disabled(completedCount == 0)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(showCompleted ? "今天还没有任务" : "没有未完成任务")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("输入后按回车添加，或从项目步骤加入今天。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if completedCount > 0 {
                    Button("清理已完成", action: clearCompletedToday)
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("移除今天已完成的任务")
                }
            }

            ProgressView(value: completionFraction)
                .controlSize(.small)
                .opacity(totalCount == 0 ? 0.35 : 1)
        }
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.secondary)

                TextField("快速记录今天要做的事", text: $newTaskTitle)
                    .textFieldStyle(.plain)
                    .focused($isCaptureFocused)
                    .onSubmit(addTask)
                    .onExitCommand(perform: clearCapture)

                Button(action: addTask) {
                    Image(systemName: "arrow.turn.down.left")
                }
                .buttonStyle(.bordered)
                .help("添加任务")
                .disabled(trimmedNewTaskTitle.isEmpty)
            }

            HStack(spacing: 6) {
                if let errorMessage {
                    Image(systemName: "exclamationmark.circle")
                    Text(errorMessage)
                } else if let successMessage {
                    Image(systemName: "checkmark.circle")
                    Text(successMessage)
                } else {
                    Text("Return 添加，Esc 清空")
                }
            }
            .font(.caption)
            .foregroundStyle(messageColor)
            .lineLimit(1)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var trimmedNewTaskTitle: String {
        newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var messageColor: Color {
        if errorMessage != nil {
            return .red
        }

        if successMessage != nil {
            return .secondary
        }

        return Color.secondary.opacity(0.75)
    }

    private var progressText: String {
        if totalCount == 0 {
            return "今天还没有任务"
        }

        if openCount == 0 {
            return "今天 \(totalCount) 项全部完成"
        }

        return "完成 \(completedCount)/\(totalCount)，剩余 \(openCount)"
    }

    private func binding(for item: TodoItem) -> Binding<String> {
        Binding {
            draftTitles[item.id] ?? item.title
        } set: { value in
            draftTitles[item.id] = value
        }
    }

    private func addTask() {
        do {
            let item = try store.add(title: newTaskTitle)
            newTaskTitle = ""
            errorMessage = nil
            showAddedFeedback(for: item)
            focusCaptureField()
        } catch {
            successMessage = nil
            errorMessage = trimmedNewTaskTitle.isEmpty ? "先输入任务内容。" : "无法新增任务。"
            focusCaptureField()
        }
    }

    private func clearCapture() {
        newTaskTitle = ""
        errorMessage = nil
        successMessage = nil
        focusCaptureField()
    }

    private func focusCaptureField() {
        DispatchQueue.main.async {
            isCaptureFocused = true
        }
    }

    private func showAddedFeedback(for item: TodoItem) {
        recentlyAddedTaskID = item.id
        successMessage = "已添加"

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if recentlyAddedTaskID == item.id {
                recentlyAddedTaskID = nil
                successMessage = nil
            }
        }
    }

    private func clearCompletedToday() {
        guard completedCount > 0 else {
            return
        }

        let clearedCount = completedCount

        do {
            try store.clearCompletedToday()
            draftTitles = draftTitles.filter { id, _ in
                store.items.contains { $0.id == id }
            }
            errorMessage = nil
            recentlyAddedTaskID = nil
            successMessage = "已清理 \(clearedCount) 项"
            focusCaptureField()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                if successMessage == "已清理 \(clearedCount) 项" {
                    successMessage = nil
                }
            }
        } catch {
            successMessage = nil
            errorMessage = "无法清理已完成。"
            focusCaptureField()
        }
    }

    private func setCompleted(_ item: TodoItem, isCompleted: Bool) {
        do {
            try store.setCompleted(item.id, isCompleted: isCompleted)
            errorMessage = nil
        } catch {
            errorMessage = "无法更新任务状态。"
        }
    }

    private func commitTitle(for item: TodoItem) {
        guard let draft = draftTitles[item.id], draft != item.title else {
            return
        }

        do {
            try store.updateTitle(item.id, title: draft)
            draftTitles[item.id] = nil
            errorMessage = nil
        } catch {
            draftTitles[item.id] = item.title
            errorMessage = "任务标题不能为空。"
        }
    }

    private func delete(_ item: TodoItem) {
        do {
            try store.delete(item.id)
            draftTitles[item.id] = nil
            errorMessage = nil
        } catch {
            errorMessage = "无法删除任务。"
        }
    }
}
