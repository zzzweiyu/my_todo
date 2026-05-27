import Foundation
import Security

enum AIModelProvider: String, Codable, CaseIterable, Identifiable {
    case openAI
    case alibabaBailian
    case alibabaCodingPlan
    case deepSeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .alibabaBailian:
            return "阿里云百炼"
        case .alibabaCodingPlan:
            return "阿里云 Coding Plan"
        case .deepSeek:
            return "DeepSeek"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI:
            return "gpt-5-mini"
        case .alibabaBailian:
            return "qwen-plus"
        case .alibabaCodingPlan:
            return "qwen3-coder-plus"
        case .deepSeek:
            return "deepseek-v4-flash"
        }
    }

    var defaultBaseURL: String? {
        switch self {
        case .openAI:
            return nil
        case .alibabaBailian:
            return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .alibabaCodingPlan:
            return "https://coding-intl.dashscope.aliyuncs.com/v1"
        case .deepSeek:
            return "https://api.deepseek.com"
        }
    }
}

struct AIProviderConfiguration: Codable, Equatable {
    var provider: AIModelProvider
    var model: String
    var baseURL: String?
    var apiKey: String

    static var empty: AIProviderConfiguration {
        AIProviderConfiguration(
            provider: .openAI,
            model: AIModelProvider.openAI.defaultModel,
            baseURL: nil,
            apiKey: ""
        )
    }
}

final class APIKeyStore: ObservableObject {
    enum KeyStoreError: Error {
        case unexpectedStatus(OSStatus)
    }

    @Published private(set) var configuration: AIProviderConfiguration?

    private let service = "com.local.MyTodo.openai"
    private let account = "weekly-report-ai-configuration"
    private let legacyAccount = "weekly-report-api-key"

    var hasConfiguration: Bool {
        configuration?.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    init() {
        self.configuration = nil
    }

    @discardableResult
    func reloadConfiguration() throws -> AIProviderConfiguration? {
        let loadedConfiguration = try readConfiguration()
        self.configuration = loadedConfiguration
        return loadedConfiguration
    }

    func readConfiguration() throws -> AIProviderConfiguration? {
        if let configurationData = try readData(account: account) {
            return try JSONDecoder().decode(AIProviderConfiguration.self, from: configurationData)
        }

        if let legacyData = try readData(account: legacyAccount),
           let legacyKey = String(data: legacyData, encoding: .utf8),
           !legacyKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AIProviderConfiguration(
                provider: .openAI,
                model: AIModelProvider.openAI.defaultModel,
                baseURL: nil,
                apiKey: legacyKey
            )
        }

        return nil
    }

    func saveConfiguration(_ configuration: AIProviderConfiguration) throws {
        var cleanConfiguration = configuration
        cleanConfiguration.apiKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanConfiguration.model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanConfiguration.baseURL = normalizedOptionalText(configuration.baseURL)
        if cleanConfiguration.model.isEmpty {
            cleanConfiguration.model = cleanConfiguration.provider.defaultModel
        }

        guard !cleanConfiguration.apiKey.isEmpty else {
            try deleteConfiguration()
            return
        }

        let data = try JSONEncoder().encode(cleanConfiguration)
        try saveData(data, account: account)
        try deleteData(account: legacyAccount)
        self.configuration = cleanConfiguration
    }

    func deleteConfiguration() throws {
        try deleteData(account: account)
        try deleteData(account: legacyAccount)
        self.configuration = nil
    }

    private func readData(account: String) throws -> Data? {
        var query = baseQuery()
        query[kSecAttrAccount as String] = account
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeyStoreError.unexpectedStatus(status)
        }

        guard let data = item as? Data else {
            return nil
        }

        return data
    }

    private func saveData(_ data: Data, account: String) throws {
        var query = baseQuery()
        query[kSecAttrAccount as String] = account

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeyStoreError.unexpectedStatus(addStatus)
            }
        } else if status == errSecSuccess {
            let updateStatus = SecItemUpdate(
                query as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw KeyStoreError.unexpectedStatus(updateStatus)
            }
        } else {
            throw KeyStoreError.unexpectedStatus(status)
        }
    }

    private func deleteData(account: String) throws {
        var query = baseQuery()
        query[kSecAttrAccount as String] = account
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyStoreError.unexpectedStatus(status)
        }
    }

    private func normalizedOptionalText(_ text: String?) -> String? {
        let cleanText = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleanText.isEmpty ? nil : cleanText
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
    }
}
