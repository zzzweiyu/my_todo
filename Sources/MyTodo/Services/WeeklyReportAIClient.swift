import Foundation
import TodoCore

@MainActor
protocol WeeklyReportAIClientProtocol {
    func generate(summary: WeeklySummary, configuration: AIProviderConfiguration) async throws -> String
}

enum WeeklyReportAIError: Error, LocalizedError {
    case missingAPIKey
    case invalidEndpoint
    case invalidResponse
    case apiFailure(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "请先配置大模型厂商和 API Key。"
        case .invalidEndpoint:
            return "大模型服务地址不正确。"
        case .invalidResponse:
            return "AI 返回格式不可识别。"
        case .apiFailure(let message):
            return message
        }
    }
}

struct OpenAIWeeklyReportAIClient: WeeklyReportAIClientProtocol {
    var session: URLSession = .shared
    private let promptBuilder = WeeklyReportPromptBuilder()

    func generate(summary: WeeklySummary, configuration: AIProviderConfiguration) async throws -> String {
        let cleanKey = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else {
            throw WeeklyReportAIError.missingAPIKey
        }

        switch configuration.provider {
        case .openAI:
            return try await generateWithResponsesAPI(
                summary: summary,
                configuration: configuration,
                apiKey: cleanKey
            )
        case .alibabaBailian:
            return try await generateWithChatCompletionsAPI(
                summary: summary,
                configuration: configuration,
                apiKey: cleanKey
            )
        case .alibabaCodingPlan:
            return try await generateWithChatCompletionsAPI(
                summary: summary,
                configuration: configuration,
                apiKey: cleanKey
            )
        case .deepSeek:
            return try await generateWithChatCompletionsAPI(
                summary: summary,
                configuration: configuration,
                apiKey: cleanKey
            )
        }
    }

    private func generateWithResponsesAPI(
        summary: WeeklySummary,
        configuration: AIProviderConfiguration,
        apiKey: String
    ) async throws -> String {
        let endpoint = URL(string: "https://api.openai.com/v1/responses")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(ResponseRequest(
            model: resolvedModel(configuration),
            instructions: promptBuilder.systemInstructions,
            input: promptBuilder.prompt(for: summary, variationSeed: UUID().uuidString)
        ))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WeeklyReportAIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorMessage = parseErrorMessage(from: data) ?? "AI 生成失败（HTTP \(httpResponse.statusCode)）。"
            throw WeeklyReportAIError.apiFailure(errorMessage)
        }

        let decoded = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        if let outputText = decoded.outputText?.trimmingCharacters(in: .whitespacesAndNewlines), !outputText.isEmpty {
            return outputText
        }

        let joinedText = decoded.output
            .flatMap(\.content)
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !joinedText.isEmpty else {
            throw WeeklyReportAIError.invalidResponse
        }

        return joinedText
    }

    private func generateWithChatCompletionsAPI(
        summary: WeeklySummary,
        configuration: AIProviderConfiguration,
        apiKey: String
    ) async throws -> String {
        guard let endpoint = chatCompletionsEndpoint(for: configuration) else {
            throw WeeklyReportAIError.invalidEndpoint
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(ChatCompletionRequest(
            model: resolvedModel(configuration),
            messages: [
                ChatMessage(role: "system", content: promptBuilder.systemInstructions),
                ChatMessage(role: "user", content: promptBuilder.prompt(for: summary, variationSeed: UUID().uuidString))
            ],
            temperature: 0.7
        ))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WeeklyReportAIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorMessage = parseErrorMessage(from: data) ?? "AI 生成失败（HTTP \(httpResponse.statusCode)）。"
            throw WeeklyReportAIError.apiFailure(errorMessage)
        }

        let decoded = try JSONDecoder().decode(ChatCompletionEnvelope.self, from: data)
        let text = decoded.choices
            .compactMap(\.message.content)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw WeeklyReportAIError.invalidResponse
        }

        return text
    }

    private func resolvedModel(_ configuration: AIProviderConfiguration) -> String {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? configuration.provider.defaultModel : model
    }

    private func chatCompletionsEndpoint(for configuration: AIProviderConfiguration) -> URL? {
        let rawBaseURL = configuration.baseURL ?? configuration.provider.defaultBaseURL
        guard var endpoint = rawBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !endpoint.isEmpty else {
            return nil
        }

        while endpoint.hasSuffix("/") {
            endpoint.removeLast()
        }

        if !endpoint.hasSuffix("/chat/completions") {
            endpoint += "/chat/completions"
        }

        return URL(string: endpoint)
    }

    private func parseErrorMessage(from data: Data) -> String? {
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            return envelope.error.message
        }

        if let envelope = try? JSONDecoder().decode(TopLevelErrorEnvelope.self, from: data),
           let message = envelope.message {
            if let code = envelope.code, !code.isEmpty {
                return "\(message)（\(code)）"
            }
            return message
        }

        return nil
    }
}

private struct ResponseRequest: Encodable {
    let model: String
    let instructions: String
    let input: String
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
}

private struct ChatMessage: Encodable, Decodable {
    let role: String
    let content: String?
}

private struct ChatCompletionEnvelope: Decodable {
    let choices: [ChatChoice]
}

private struct ChatChoice: Decodable {
    let message: ChatMessage
}

private struct ResponseEnvelope: Decodable {
    let outputText: String?
    let output: [ResponseOutputItem]

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }
}

private struct ResponseOutputItem: Decodable {
    let content: [ResponseContentItem]
}

private struct ResponseContentItem: Decodable {
    let text: String?
}

private struct ErrorEnvelope: Decodable {
    let error: APIError
}

private struct APIError: Decodable {
    let message: String
}

private struct TopLevelErrorEnvelope: Decodable {
    let code: String?
    let message: String?
}
