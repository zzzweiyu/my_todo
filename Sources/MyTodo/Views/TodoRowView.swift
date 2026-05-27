import SwiftUI
import TodoCore

struct TodoRowView: View {
    let item: TodoItem
    @Binding var title: String
    let projectTitle: String?
    let deleteHelp: String
    var isHighlighted = false
    let onToggle: () -> Void
    let onCommitTitle: () -> Void
    let onDelete: () -> Void
    var onUpdateWeeklyReport: (WeeklyReportStatus, String?) -> Void = { _, _ in }
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(item.isCompleted ? "标记为未完成" : "标记完成")

            VStack(alignment: .leading, spacing: 2) {
                TextField("任务标题", text: $title)
                    .textFieldStyle(.plain)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .strikethrough(item.isCompleted)
                    .lineLimit(1)
                    .focused($isTitleFocused)
                    .onSubmit(onCommitTitle)
                    .onChange(of: isTitleFocused) { _, isFocused in
                        if !isFocused {
                            onCommitTitle()
                        }
                    }

                if let projectTitle {
                    Text(projectTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            WeeklyReportTagButton(
                status: item.weeklyReportStatus,
                note: item.weeklyReportNote,
                onSave: onUpdateWeeklyReport
            )

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(deleteHelp)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onDisappear(perform: onCommitTitle)
    }

    private var rowBackground: Color {
        if isHighlighted {
            return Color.accentColor.opacity(0.14)
        }

        if item.isCompleted {
            return Color.secondary.opacity(0.08)
        }

        return Color.clear
    }
}
