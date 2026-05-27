import SwiftUI
import TodoCore

struct WeeklyReportTagButton: View {
    let status: WeeklyReportStatus
    let note: String?
    let onSave: (WeeklyReportStatus, String?) -> Void
    @State private var isPresented = false
    @State private var draftStatus: WeeklyReportStatus = .normal
    @State private var draftNote = ""

    var body: some View {
        Button {
            draftStatus = status
            draftNote = note ?? ""
            isPresented = true
        } label: {
            Image(systemName: status.systemImage)
                .foregroundStyle(status.tint)
        }
        .buttonStyle(.plain)
        .help(status.helpText)
        .popover(isPresented: $isPresented, arrowEdge: .trailing) {
            editor
                .frame(width: 260)
                .padding(12)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("周报标记")
                .font(.headline)

            Picker("周报标记", selection: $draftStatus) {
                ForEach(WeeklyReportStatus.allCases, id: \.self) { status in
                    Text(status.title).tag(status)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            TextField("周报备注", text: $draftNote, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...3)

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("将作为 AI 周报证据")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Spacer()

                Button("取消") {
                    isPresented = false
                }

                Button("保存") {
                    onSave(draftStatus, draftNote)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

extension WeeklyReportStatus {
    var title: String {
        switch self {
        case .normal:
            return "普通"
        case .blocker:
            return "卡点"
        case .followUp:
            return "待跟进"
        }
    }

    var systemImage: String {
        switch self {
        case .normal:
            return "tag"
        case .blocker:
            return "exclamationmark.octagon.fill"
        case .followUp:
            return "arrowshape.turn.up.right.fill"
        }
    }

    var tint: Color {
        switch self {
        case .normal:
            return .secondary
        case .blocker:
            return .red
        case .followUp:
            return .orange
        }
    }

    var helpText: String {
        switch self {
        case .normal:
            return "设置周报标记"
        case .blocker:
            return "周报标记：卡点"
        case .followUp:
            return "周报标记：待跟进"
        }
    }
}
