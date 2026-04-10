import Foundation

/// Remote LLM service supporting multiple API providers (OpenAI, Claude).
/// Implements the same LLMEngine protocol for transparent switching.
public class RemoteLLMService {

    public let provider: LLMProvider
    private let session: URLSession

    public init(provider: String, apiKey: String, baseURL: String?) throws {
        let factory = LLMProviderFactory()
        self.provider = try factory.create(provider: provider, apiKey: apiKey, baseURL: baseURL)
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    /// Send a text prompt and get a response
    public func generate(prompt: String, system: String? = nil) async throws -> String {
        let request = try provider.buildRequest(messages: [
            .init(role: "system", content: .text(system ?? "")),
            .init(role: "user", content: .text(prompt))
        ])
        let (data, response) = try await session.data(for: request)
        return try provider.parseResponse(data: data, response: response)
    }

    /// Send a multimodal prompt (text + image) and get a response
    public func generateWithImage(prompt: String, imageBase64: String, system: String? = nil) async throws -> String {
        let messages = [
            Message(role: "system", content: .text(system ?? "")),
            Message(role: "user", content: .multimodal([
                .text(prompt),
                .image(url: "data:image/png;base64,\(imageBase64)")
            ]))
        ]
        let request = try provider.buildRequest(messages: messages)
        let (data, response) = try await session.data(for: request)
        return try provider.parseResponse(data: data, response: response)
    }
}

// MARK: - Message Types

public struct Message: Encodable {
    public let role: String
    public let content: MessageContent
}

public enum MessageContent: Encodable {
    case text(String)
    case multimodal([ContentPart])

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let text):
            var container = encoder.singleValueContainer()
            try container.encode(text)
        case .multimodal(let parts):
            var container = encoder.singleValueContainer()
            try container.encode(parts)
        }
    }
}

public enum ContentPart: Encodable {
    case text(String)
    case image(url: String)

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(["type": "text", "text": text])
        case .image(let url):
            try container.encode(["type": "image_url", "image_url": ["url": url]])
        }
    }
}
