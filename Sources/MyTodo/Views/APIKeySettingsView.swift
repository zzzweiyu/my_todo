import SwiftUI

struct APIKeySettingsView: View {
    @ObservedObject var keyStore: APIKeyStore
    var onClose: () -> Void
    @State private var provider: AIModelProvider = .openAI
    @State private var model = AIModelProvider.openAI.defaultModel
    @State private var baseURL = ""
    @State private var apiKey = ""
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("配置大模型")
                .font(.headline)

            Picker("厂商", selection: providerSelection) {
                ForEach(AIModelProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .pickerStyle(.segmented)

            Text(providerDetailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            TextField("模型", text: $model)
                .textFieldStyle(.roundedBorder)

            if provider.defaultBaseURL != nil {
                TextField("服务地址", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            SecureField("API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)

            Text(configurationHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("删除") {
                    deleteConfiguration()
                }
                .disabled(!keyStore.hasConfiguration)

                Spacer()

                Button("取消") {
                    onClose()
                }

                Button("保存") {
                    saveConfiguration()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 340)
        .onAppear(perform: loadConfiguration)
    }

    private var providerSelection: Binding<AIModelProvider> {
        Binding {
            provider
        } set: { newProvider in
            guard provider != newProvider else {
                return
            }
            provider = newProvider
            model = newProvider.defaultModel
            baseURL = newProvider.defaultBaseURL ?? ""
            message = nil
        }
    }

    private var providerDetailText: String {
        switch provider {
        case .openAI:
            return "使用 OpenAI Responses API。默认模型：\(AIModelProvider.openAI.defaultModel)。"
        case .alibabaBailian:
            return "使用阿里云百炼 OpenAI 兼容接口。默认模型：\(AIModelProvider.alibabaBailian.defaultModel)。"
        case .alibabaCodingPlan:
            return "使用阿里云 Coding Plan 兼容接口。默认模型：\(AIModelProvider.alibabaCodingPlan.defaultModel)。"
        case .deepSeek:
            return "使用 DeepSeek OpenAI 兼容接口。默认模型：\(AIModelProvider.deepSeek.defaultModel)。"
        }
    }

    private var configurationHelpText: String {
        switch provider {
        case .openAI:
            return keyStore.hasConfiguration ? "已保存配置。留空保存会删除当前配置。" : "配置会保存到 macOS Keychain，不写入任务 JSON。"
        case .alibabaBailian:
            return "普通百炼地址默认使用中国大陆 DashScope，可按地域调整。"
        case .alibabaCodingPlan:
            return "Coding Plan 默认地址为 coding-intl.dashscope.aliyuncs.com/v1。"
        case .deepSeek:
            return "DeepSeek 默认地址为 api.deepseek.com，兼容 /chat/completions。"
        }
    }

    private func loadConfiguration() {
        do {
            _ = try keyStore.reloadConfiguration()
            message = nil
        } catch {
            message = "无法读取大模型配置。"
        }

        if let configuration = keyStore.configuration {
            provider = configuration.provider
            model = configuration.model
            baseURL = configuration.baseURL ?? configuration.provider.defaultBaseURL ?? ""
            apiKey = configuration.apiKey
        } else {
            baseURL = provider.defaultBaseURL ?? ""
        }
    }

    private func saveConfiguration() {
        do {
            try keyStore.saveConfiguration(AIProviderConfiguration(
                provider: provider,
                model: model,
                baseURL: baseURL,
                apiKey: apiKey
            ))
            onClose()
        } catch {
            message = "无法保存大模型配置。"
        }
    }

    private func deleteConfiguration() {
        do {
            try keyStore.deleteConfiguration()
            apiKey = ""
            model = provider.defaultModel
            onClose()
        } catch {
            message = "无法删除大模型配置。"
        }
    }
}
