import Foundation

/// Generates content (titles, descriptions, tags) via remote LLM.
public class ContentGenerator {

    private let remoteLLM: RemoteLLMService

    public init(remoteLLM: RemoteLLMService) {
        self.remoteLLM = remoteLLM
    }

    /// Generate content of the specified type
    /// - Parameters:
    ///   - type: "title", "description", "tags", or "full" (all of the above)
    ///   - context: Context information (video topic, style preferences, etc.)
    /// - Returns: Generated content as a dictionary
    public func generate(type: String, context: String) async throws -> [String: String] {
        let prompt = buildPrompt(type: type, context: context)
        let systemPrompt = """
        You are a content creation assistant for short video platforms.
        Generate engaging, platform-appropriate content.
        Output your response as a JSON object. Do not include any text outside the JSON.
        """

        let response = try await remoteLLM.generate(prompt: prompt, system: systemPrompt)
        return try parseContentResponse(response, type: type)
    }

    private func buildPrompt(type: String, context: String) -> String {
        switch type.lowercased() {
        case "title":
            return """
            Generate 3 catchy short video titles based on this context:
            \(context)

            Output format: {"titles": ["title1", "title2", "title3"]}
            """
        case "description":
            return """
            Generate a video description based on this context:
            \(context)

            Output format: {"description": "your description here"}
            """
        case "tags":
            return """
            Generate relevant hashtags/tags for a short video based on this context:
            \(context)

            Output format: {"tags": ["#tag1", "#tag2", "#tag3"]}
            """
        case "full":
            return """
            Generate complete video content (title, description, tags) based on this context:
            \(context)

            Output format:
            {
              "title": "main title",
              "description": "video description",
              "tags": ["#tag1", "#tag2", "#tag3"],
              "titles": ["alternative title 1", "alternative title 2"]
            }
            """
        default:
            return "Generate content for: \(context)\nOutput as JSON."
        }
    }

    private func parseContentResponse(_ response: String, type: String) throws -> [String: String] {
        // Extract JSON from response
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else {
            return ["raw": response]
        }
        let jsonString = String(trimmed[start...end])
        guard let data = jsonString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["raw": response]
        }

        // Flatten to string values
        var result: [String: String] = [:]
        for (key, value) in json {
            if let stringValue = value as? String {
                result[key] = stringValue
            } else if let arrayValue = value as? [String] {
                result[key] = arrayValue.joined(separator: ", ")
            }
        }
        return result
    }
}
