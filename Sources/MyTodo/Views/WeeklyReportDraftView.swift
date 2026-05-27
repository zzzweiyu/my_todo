import AppKit
import SwiftUI
import TodoCore

private struct WeeklyReportDisplaySection: Identifiable {
    let title: String
    let items: [String]

    var id: String { title }
}

struct WeeklyReportDraftView: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var keyStore: APIKeyStore
    let summary: WeeklySummary
    var onClose: () -> Void
    var client: WeeklyReportAIClientProtocol = OpenAIWeeklyReportAIClient()
    @State private var reportText = ""
    @State private var previousReportText: String?
    @State private var isEditing = false
    @State private var message: String?
    @State private var isMessageError = false
    @State private var isAPIKeySettingsPresented = false
    @State private var isGenerating = false
    private let promptBuilder = WeeklyReportPromptBuilder()

    @ViewBuilder
    var body: some View {
        if isAPIKeySettingsPresented {
            APIKeySettingsView(keyStore: keyStore) {
                isAPIKeySettingsPresented = false
            }
        } else {
            draftContent
        }
    }

    private var draftContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            reportBody

            evidenceList
                .frame(height: 128)

            if let previousReportText {
                VStack(alignment: .leading, spacing: 6) {
                    Text("已替换为新草稿，可恢复上一版。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("恢复上一版") {
                        reportText = previousReportText
                        self.previousReportText = nil
                        message = nil
                        isMessageError = false
                    }
                }
            }

            statusMessage

            actions
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: loadDraft)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 周报草稿")
                        .font(.headline)
                    Text(promptBuilder.sourceSummary(for: summary))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("关闭")
            }

            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .foregroundStyle(.secondary)

                Text(currentModelText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button(isEditing ? "完成编辑" : "编辑") {
                    isEditing.toggle()
                }
                .controlSize(.small)

                Button("切换模型") {
                    isAPIKeySettingsPresented = true
                }
                .controlSize(.small)
            }
        }
    }

    private var reportBody: some View {
        Group {
            if isEditing {
                TextEditor(text: $reportText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(reportSections) { section in
                            reportSectionView(section)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .frame(height: 240)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18))
        }
    }

    private var reportSections: [WeeklyReportDisplaySection] {
        parseReportSections(from: reportText)
    }

    private func reportSectionView(_ section: WeeklyReportDisplaySection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.title)
                .font(.subheadline.weight(.semibold))

            if section.items.isEmpty {
                Text("暂无明确记录")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(section.items.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .top, spacing: 7) {
                            Text("\(index + 1).")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 18, alignment: .trailing)
                            Text(item)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var currentModelText: String {
        guard let configuration = currentConfiguration,
              !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "未配置模型"
        }

        return modelText(for: configuration)
    }

    private var currentConfiguration: AIProviderConfiguration? {
        keyStore.configuration
    }

    private func modelText(for configuration: AIProviderConfiguration) -> String {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = model.isEmpty ? configuration.provider.defaultModel : model
        return "\(configuration.provider.title) · \(resolvedModel)"
    }

    private var evidenceList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("参考依据")
                .font(.subheadline.weight(.semibold))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(summary.evidence) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : item.status.systemImage)
                                    .foregroundStyle(item.isCompleted ? .green : item.status.tint)
                                Text(item.title)
                                    .lineLimit(1)
                            }
                            .font(.caption)

                            if let projectPath = item.projectPath {
                                Text(projectPath)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task {
                    await generate()
                }
            } label: {
                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("重新生成", systemImage: "arrow.clockwise")
                }
            }
            .frame(maxWidth: .infinity)
            .disabled(isGenerating || summary.evidence.isEmpty)

            HStack {
                Button {
                    copyReportText()
                } label: {
                    Label("复制内容", systemImage: "doc.on.doc")
                }
                .disabled(reportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                Button {
                    saveDraft()
                } label: {
                    Label("保存草稿", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(reportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var statusMessage: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
            Text(message ?? "复制前请确认内容准确")
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()

            if isMessageError && message != nil && !keyStore.hasConfiguration {
                Button("配置大模型") {
                    isAPIKeySettingsPresented = true
                }
                .controlSize(.small)
            }
        }
        .font(.caption)
        .foregroundStyle(isMessageError ? .red : .orange)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isMessageError ? Color.red : Color.orange).opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var defaultReportTemplate: String {
        """
        本周完成
        暂无明确记录

        卡点风险
        暂无明确记录

        下周跟进
        暂无明确记录
        """
    }

    private func loadDraft() {
        if let draft = store.weeklyReportDraft(weekStartDay: summary.range.startDay) {
            reportText = normalizedReportText(from: draft.markdown)
        } else if reportText.isEmpty {
            reportText = defaultReportTemplate
        }
    }

    private func generate() async {
        isGenerating = true
        message = nil
        isMessageError = false
        defer { isGenerating = false }

        do {
            let configuration = try configurationForGeneration()
            guard let configuration else {
                throw WeeklyReportAIError.missingAPIKey
            }
            let generationModelText = modelText(for: configuration)
            let generated = try await client.generate(summary: summary, configuration: configuration)
            let generatedReportText = normalizedReportText(from: generated)
            let currentReportText = reportText
            let isSameAsCurrent = normalizedReportText(generatedReportText) == normalizedReportText(currentReportText)

            if shouldKeepPreviousVersion(beforeReplacing: currentReportText, with: generatedReportText) {
                previousReportText = currentReportText
            } else {
                previousReportText = nil
            }
            reportText = generatedReportText
            isEditing = false
            isMessageError = false
            message = isSameAsCurrent
                ? "\(generationModelText)：模型返回内容与当前草稿一致，已确认拿到返回结果。"
                : "已使用 \(generationModelText) 生成并替换草稿"
        } catch {
            let generationModelText = currentConfiguration.map { modelText(for: $0) } ?? "未配置模型"
            let errorText = (error as? LocalizedError)?.errorDescription ?? "AI 生成失败。"
            isMessageError = true
            message = "\(generationModelText)：\(errorText)"
        }
    }

    private func configurationForGeneration() throws -> AIProviderConfiguration? {
        if let configuration = currentConfiguration,
           !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return configuration
        }

        return try keyStore.reloadConfiguration()
    }

    private func shouldKeepPreviousVersion(beforeReplacing currentReportText: String, with generatedReportText: String) -> Bool {
        let cleanReportText = normalizedReportText(currentReportText)
        let cleanTemplate = defaultReportTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanGeneratedReportText = normalizedReportText(generatedReportText)
        return !cleanReportText.isEmpty && cleanReportText != cleanTemplate && cleanReportText != cleanGeneratedReportText
    }

    private func normalizedReportText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedReportText(from text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { cleanReportLine(String($0)) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanReportLine(_ line: String) -> String {
        var cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

        while cleanLine.hasPrefix("#") {
            cleanLine.removeFirst()
            cleanLine = cleanLine.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if cleanLine.hasPrefix("- ") || cleanLine.hasPrefix("* ") {
            cleanLine.removeFirst(2)
            cleanLine = cleanLine.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let firstCharacter = cleanLine.first,
           firstCharacter.isNumber,
           let separatorIndex = cleanLine.firstIndex(where: { $0 == "." || $0 == "、" }),
           separatorIndex < cleanLine.endIndex {
            cleanLine = String(cleanLine[cleanLine.index(after: separatorIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleanLine
    }

    private func parseReportSections(from text: String) -> [WeeklyReportDisplaySection] {
        let defaultTitles = ["本周完成", "卡点风险", "下周跟进"]
        var sections = defaultTitles.map { WeeklyReportDisplaySection(title: $0, items: []) }
        var sectionItems = Dictionary(uniqueKeysWithValues: defaultTitles.map { ($0, [String]()) })
        var currentTitle = defaultTitles[0]

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = cleanReportLine(String(rawLine))
            guard !line.isEmpty else {
                continue
            }

            if defaultTitles.contains(line) {
                currentTitle = line
            } else if line != "暂无明确记录" {
                sectionItems[currentTitle, default: []].append(line)
            }
        }

        sections = defaultTitles.map {
            WeeklyReportDisplaySection(title: $0, items: sectionItems[$0] ?? [])
        }
        return sections
    }

    private func copyReportText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reportText, forType: .string)
        message = nil
        isMessageError = false
    }

    private func saveDraft() {
        do {
            try store.saveWeeklyReportDraft(weekStartDay: summary.range.startDay, markdown: reportText)
            message = nil
            isMessageError = false
            previousReportText = nil
        } catch {
            isMessageError = true
            message = "无法保存草稿。"
        }
    }
}
