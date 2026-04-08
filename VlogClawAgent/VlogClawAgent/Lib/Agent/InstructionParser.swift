import Foundation

/// Decomposes natural language instructions into automation action sequences via remote LLM.
public class InstructionParser {

    private let remoteLLM: RemoteLLMService

    public init(remoteLLM: RemoteLLMService) {
        self.remoteLLM = remoteLLM
    }

    /// Decompose a natural language instruction into a sequence of automation steps
    /// - Parameter instruction: Natural language (e.g. "Post a Douyin video about my cat")
    /// - Returns: Array of automation steps
    public func decompose(instruction: String) async throws -> [DecomposedStep] {
        let systemPrompt = """
        You are an iOS automation instruction parser.
        Given a natural language instruction, break it down into a precise sequence of
        UI automation actions that can be executed on an iPhone.

        Each action must be one of:
        - tap: Tap at normalized coordinates (x: 0.0-1.0, y: 0.0-1.0)
        - type: Type text into the focused field
        - swipe: Swipe in a direction (up/down/left/right)
        - press_button: Press hardware button (home/volume_up/volume_down)
        - open_app: Open an app by bundle ID
        - wait: Wait for UI to settle
        - long_press: Long press at coordinates
        - scroll_to_text: Scroll until specific text is visible

        Be specific about coordinates and text. Consider common app layouts.
        Output a JSON array. No other text.
        """

        let prompt = """
        Decompose this instruction into automation steps: "\(instruction)"

        Consider the typical flow:
        1. What app needs to be opened?
        2. What navigation is needed?
        3. What content needs to be entered?
        4. What buttons need to be tapped?
        5. How to verify success?

        Output format:
        [
          {
            "step": 1,
            "action": "open_app",
            "params": {"bundleId": "com.apple.Preferences"},
            "description": "Open Settings app"
          },
          {
            "step": 2,
            "action": "tap",
            "params": {"x": 0.5, "y": 0.3},
            "description": "Tap on Wi-Fi option"
          }
        ]
        """

        let response = try await remoteLLM.generate(prompt: prompt, system: systemPrompt)
        return try parseDecomposedSteps(response)
    }

    private func parseDecomposedSteps(_ response: String) throws -> [DecomposedStep] {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "["),
              let end = trimmed.lastIndex(of: "]") else {
            throw InstructionParserError.invalidResponse
        }
        let jsonString = String(trimmed[start...end])
        guard let data = jsonString.data(using: .utf8) else {
            throw InstructionParserError.invalidResponse
        }
        return try JSONDecoder().decode([DecomposedStep].self, from: data)
    }
}

// MARK: - Data Models

public struct DecomposedStep: Codable {
    public let step: Int
    public let action: String
    public let params: [String: String]?
    public let description: String
}

public enum InstructionParserError: LocalizedError {
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Failed to parse decomposed instructions from LLM response"
        }
    }
}
