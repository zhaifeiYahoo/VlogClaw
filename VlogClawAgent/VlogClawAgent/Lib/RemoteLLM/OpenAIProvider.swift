import Foundation

/// OpenAI API provider (GPT-4o, GPT-4V, etc.)
public class OpenAIProvider: LLMProvider {

    public let apiKey: String
    public let baseURL: String
    public let model: String

    public init(apiKey: String, baseURL: String? = nil, model: String = "gpt-4o") {
        self.apiKey = apiKey
        self.baseURL = baseURL ?? "https://api.openai.com/v1"
        self.model = model
    }

    public func buildRequest(messages: [Message]) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw RemoteLLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "messages": try messages.map { msg -> [String: Any] in
                switch msg.content {
                case .text(let text):
                    return ["role": msg.role, "content": text]
                case .multimodal(let parts):
                    let content = try parts.map { part -> [String: Any] in
                        switch part {
                        case .text(let text):
                            return ["type": "text", "text": text]
                        case .image(let url):
                            return ["type": "image_url", "image_url": ["url": url]]
                        }
                    }
                    return ["role": msg.role, "content": content]
                }
            },
            "temperature": 0.7,
            "max_tokens": 4096
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public func parseResponse(data: Data, response: URLResponse) throws -> String {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteLLMError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw RemoteLLMError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let content = message?["content"] as? String

        guard let content else {
            throw RemoteLLMError.invalidResponse
        }
        return content
    }
}
