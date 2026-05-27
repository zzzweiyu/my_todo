import SwiftUI
import TodoCore

private struct WeeklyEvidenceGroup: Identifiable {
    let id: String
    let title: String
    let emptyText: String
    let items: [WeeklyEvidenceItem]
}

struct WeekPanelView: View {
    @ObservedObject var store: TodoStore
    @StateObject private var apiKeyStore = APIKeyStore()
    @State private var selectedDay = TodoStore.currentDayString()
    @State private var isDraftPresented = false
    @State private var isAPIKeySettingsPresented = false

    private var summary: WeeklySummary {
        store.weeklySummary(containing: selectedDay)
    }

    private var groups: [WeeklyEvidenceGroup] {
        [
            WeeklyEvidenceGroup(
                id: "open",
                title: "待完成",
                emptyText: "本周没有待完成任务",
                items: summary.open.filter { $0.status == .normal }
            ),
            WeeklyEvidenceGroup(
                id: "blockers",
                title: "卡点",
                emptyText: "本周没有卡点",
                items: summary.blockers
            ),
            WeeklyEvidenceGroup(
                id: "follow-ups",
                title: "待跟进",
                emptyText: "本周没有待跟进事项",
                items: summary.followUps
            ),
            WeeklyEvidenceGroup(
                id: "completed",
                title: "已完成",
                emptyText: "本周还没有完成项",
                items: summary.completed
            )
        ]
    }

    private var weeklyListHeight: CGFloat {
        let groupHeight = groups.reduce(CGFloat.zero) { total, group in
            let visibleRows = max(group.items.count, 1)
            return total + 30 + CGFloat(visibleRows) * 48
        }
        return min(groupHeight + CGFloat(max(groups.count - 1, 0)) * 10, 470)
    }

    @ViewBuilder
    var body: some View {
        if isDraftPresented {
            WeeklyReportDraftView(
                store: store,
                keyStore: apiKeyStore,
                summary: summary
            ) {
                isDraftPresented = false
            }
        } else if isAPIKeySettingsPresented {
            APIKeySettingsView(keyStore: apiKeyStore) {
                isAPIKeySettingsPresented = false
            }
        } else {
            weekContent
        }
    }

    private var weekContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            metricGrid

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(groups) { group in
                        evidenceGroup(group)
                    }
                }
            }
            .frame(height: weeklyListHeight)

            Button(action: generateWeeklyReport) {
                Label("生成 AI 周报", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(summary.evidence.isEmpty)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                shiftWeek(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .help("上一周")

            VStack(alignment: .leading, spacing: 2) {
                Text("本周")
                    .font(.headline)
                Text("\(summary.range.startDay) - \(summary.range.endDay)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isAPIKeySettingsPresented = true
            } label: {
                Image(systemName: apiKeyStore.hasConfiguration ? "key.fill" : "key")
            }
            .buttonStyle(.borderless)
            .help(apiKeyStore.hasConfiguration ? "大模型配置已保存" : "配置大模型厂商和 API Key")

            Button {
                selectedDay = TodoStore.currentDayString()
            } label: {
                Image(systemName: "calendar")
            }
            .buttonStyle(.borderless)
            .help("回到本周")

            Button {
                shiftWeek(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .help("下一周")
        }
    }

    private var metricGrid: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                metricCard(title: "完成", value: "\(summary.completed.count)", color: .green)
                metricCard(title: "卡点", value: "\(summary.blockers.count)", color: .red)
            }
            GridRow {
                metricCard(title: "跟进", value: "\(summary.followUps.count)", color: .orange)
                metricCard(title: "完成率", value: completionPercentText, color: .accentColor)
            }
        }
    }

    private func metricCard(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func evidenceGroup(_ group: WeeklyEvidenceGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(group.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(group.items.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(Capsule())
                Spacer()
            }
            .padding(.horizontal, 4)

            if group.items.isEmpty {
                Text(group.emptyText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 8)
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(group.items) { item in
                        evidenceRow(item)
                    }
                }
            }
        }
    }

    private func evidenceRow(_ item: WeeklyEvidenceItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.isCompleted ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                HStack(spacing: 4) {
                    if let projectPath = item.projectPath {
                        Text(projectPath)
                    } else {
                        Text("临时任务")
                    }

                    if let note = item.note {
                        Text("·")
                        Text(note)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            if item.status != .normal {
                Text(item.status.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(item.status.tint)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(item.isCompleted ? 0.08 : 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var completionPercentText: String {
        guard !summary.evidence.isEmpty else {
            return "0%"
        }
        return "\(Int((summary.completionFraction * 100).rounded()))%"
    }

    private func shiftWeek(by offset: Int) {
        guard let date = TodoStore.date(fromDay: selectedDay),
              let shiftedDate = Calendar.current.date(byAdding: .day, value: offset * 7, to: date) else {
            return
        }
        selectedDay = Self.dayFormatter.string(from: shiftedDate)
    }

    private func generateWeeklyReport() {
        isDraftPresented = true
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
