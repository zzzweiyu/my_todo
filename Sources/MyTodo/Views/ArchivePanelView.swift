import SwiftUI
import TodoCore

struct ArchivePanelView: View {
    @ObservedObject var store: TodoStore
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private var archivedItems: [TodoItem] {
        store.archivedItems()
    }

    private var archiveListHeight: CGFloat {
        let rowsHeight = CGFloat(archivedItems.count) * 64
        let spacingHeight = CGFloat(max(archivedItems.count - 1, 0)) * 4
        return min(rowsHeight + spacingHeight, 460)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            statusMessage

            if archivedItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(archivedItems) { item in
                            archiveRow(item)
                        }
                    }
                }
                .frame(height: archiveListHeight)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("历史")
                    .font(.headline)

                Text(archivedItems.isEmpty ? "没有历史完成任务" : "\(archivedItems.count) 个已归档任务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var statusMessage: some View {
        HStack(spacing: 6) {
            if let errorMessage {
                Image(systemName: "exclamationmark.circle")
                Text(errorMessage)
            } else if let successMessage {
                Image(systemName: "checkmark.circle")
                Text(successMessage)
            } else {
                Text("恢复会把任务放回今天，并标记为未完成。")
            }
        }
        .font(.caption)
        .foregroundStyle(messageColor)
        .lineLimit(1)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("还没有历史任务")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("跨日完成的任务会留在这里，可恢复到今天。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 24)
    }

    private func archiveRow(_ item: TodoItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .strikethrough()

                HStack(spacing: 4) {
                    Text(item.day)

                    if let projectPath = store.projectPath(for: item) {
                        Text("·")
                        Text(projectPath)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()

            Button {
                restore(item)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("恢复到今天")

            Button {
                delete(item)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("永久删除")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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

    private func restore(_ item: TodoItem) {
        do {
            try store.restoreArchivedItemToToday(item.id)
            errorMessage = nil
            successMessage = "已恢复到今天：\(item.title)"
            clearSuccessLater("已恢复到今天：\(item.title)")
        } catch {
            successMessage = nil
            errorMessage = "无法恢复任务。"
        }
    }

    private func delete(_ item: TodoItem) {
        do {
            try store.delete(item.id)
            errorMessage = nil
            successMessage = "已删除：\(item.title)"
            clearSuccessLater("已删除：\(item.title)")
        } catch {
            successMessage = nil
            errorMessage = "无法删除任务。"
        }
    }

    private func clearSuccessLater(_ message: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if successMessage == message {
                successMessage = nil
            }
        }
    }
}
