import Foundation

// MARK: - Provider Protocol

/// Protocol for LLM API providers
public protocol LLMProvider {
    func buildRequest(messages: [Message]) throws -> URLRequest
    func parseResponse(data: Data, response: URLResponse) throws -> String
}

// MARK: - Errors

public enum RemoteLLMError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case unsupportedProvider(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .invalidResponse: return "Invalid response from API"
        case .apiError(let code, let msg): return "API error (\(code)): \(msg)"
        case .unsupportedProvider(let name): return "Unsupported provider: \(name)"
        }
    }
}

// MARK: - Factory

public class LLMProviderFactory {

    public init() {}

    public func create(provider: String, apiKey: String, baseURL: String?) throws -> LLMProvider {
        switch provider.lowercased() {
        case "openai":
            return OpenAIProvider(apiKey: apiKey, baseURL: baseURL)
        case "claude", "anthropic":
            return ClaudeProvider(apiKey: apiKey, baseURL: baseURL)
        default:
            throw RemoteLLMError.unsupportedProvider(provider)
        }
    }
}
