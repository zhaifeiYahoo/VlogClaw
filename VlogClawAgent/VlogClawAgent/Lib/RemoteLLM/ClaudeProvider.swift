import Foundation

/// Anthropic Claude API provider
public class ClaudeProvider: LLMProvider {

    public let apiKey: String
    public let baseURL: String
    public let model: String

    public init(apiKey: String, baseURL: String? = nil, model: String = "claude-sonnet-4-20250514") {
        self.apiKey = apiKey
        self.baseURL = baseURL ?? "https://api.anthropic.com/v1"
        self.model = model
    }

    public func buildRequest(messages: [Message]) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/messages") else {
            throw RemoteLLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        // Claude API: separate system prompt from messages
        var systemPrompt = ""
        var chatMessages: [[String: Any]] = []

        for msg in messages {
            if msg.role == "system" {
                if case .text(let text) = msg.content { systemPrompt = text }
                continue
            }
            switch msg.content {
            case .text(let text):
                chatMessages.append(["role": msg.role, "content": text])
            case .multimodal(let parts):
                let content = try parts.map { part -> [String: Any] in
                    switch part {
                    case .text(let text):
                        return ["type": "text", "text": text]
                    case .image(let url):
                        // Claude uses base64 source format
                        if url.hasPrefix("data:image/png;base64,") {
                            let base64 = String(url.dropFirst("data:image/png;base64,".count))
                            return [
                                "type": "image",
                                "source": [
                                    "type": "base64",
                                    "media_type": "image/png",
                                    "data": base64
                                ]
                            ]
                        }
                        return ["type": "text", "text": url]
                    }
                }
                chatMessages.append(["role": msg.role, "content": content])
            }
        }

        var body: [String: Any] = [
            "model": model,
            "messages": chatMessages,
            "max_tokens": 4096
        ]
        if !systemPrompt.isEmpty {
            body["system"] = systemPrompt
        }

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
        let content = json?["content"] as? [[String: Any]]
        let text = content?.first(where: { $0["type"] as? String == "text" })?["text"] as? String

        guard let text else {
            throw RemoteLLMError.invalidResponse
        }
        return text
    }
}
