import Foundation

/// Parses LLM text output into structured AgentAction objects.
/// Handles malformed output, extra text around JSON, and unknown action types.
public class ActionParser {

    /// Known valid action types
    private let validActions: Set<String> = [
        "tap", "long_press", "type", "swipe",
        "press_button", "open_app", "wait", "done"
    ]

    /// Parse LLM output string into an AgentAction
    public func parse(_ output: String) throws -> AgentAction {
        // Step 1: Extract JSON from the output (handle surrounding text)
        let jsonString = extractJSON(from: output)

        guard let data = jsonString.data(using: .utf8) else {
            throw ActionParserError.invalidOutput("Cannot convert to data")
        }

        // Step 2: Parse JSON
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ActionParserError.invalidOutput("Not a valid JSON object")
        }

        // Step 3: Extract and validate action type
        guard let actionType = json["action"] as? String else {
            throw ActionParserError.missingField("action")
        }

        let normalizedType = actionType.lowercased()
        let validType = validActions.contains(normalizedType) ? normalizedType : "done"

        // Step 4: Build AgentAction from JSON fields
        return AgentAction(
            type: validType,
            x: json["x"] as? Double,
            y: json["y"] as? Double,
            text: json["text"] as? String,
            direction: json["direction"] as? String,
            button: json["button"] as? String,
            bundleId: json["bundleId"] as? String,
            duration: json["duration"] as? Double,
            reasoning: json["reasoning"] as? String ?? json["summary"] as? String
        )
    }

    /// Extract JSON object from text that may contain extra content
    private func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Case 1: The entire text is the JSON
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
            return trimmed
        }

        // Case 2: Find first { ... } block
        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }

        // Case 3: Try to find JSON in markdown code blocks
        if let range = trimmed.range(of: "```(?:json)?\\s*\\n?\\{(.*?)\\}\\s*\\n?```", options: .regularExpression) {
            let codeBlock = String(trimmed[range])
            if let start = codeBlock.firstIndex(of: "{"),
               let end = codeBlock.lastIndex(of: "}") {
                return String(codeBlock[start...end])
            }
        }

        // Fallback: return as-is and let JSON parsing fail
        return trimmed
    }
}

// MARK: - Errors

public enum ActionParserError: LocalizedError {
    case invalidOutput(String)
    case missingField(String)

    public var errorDescription: String? {
        switch self {
        case .invalidOutput(let msg): return "Action parse error: \(msg)"
        case .missingField(let field): return "Missing required field: \(field)"
        }
    }
}
