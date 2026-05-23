import SwiftUI
import TodoCore

struct TodoPanelView: View {
    @ObservedObject var store: TodoStore
    @State private var selectedTab: PanelTab = .today

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Picker("视图", selection: $selectedTab) {
                    ForEach(PanelTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
            }

            switch selectedTab {
            case .today:
                TodayPanelView(store: store)
            case .projects:
                ProjectsPanelView(store: store)
            }
        }
        .padding(14)
        .frame(width: 380)
    }
}

private enum PanelTab: String, CaseIterable, Identifiable {
    case today
    case projects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return "今天"
        case .projects:
            return "项目"
        }
    }
}

