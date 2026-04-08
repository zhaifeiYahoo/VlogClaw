import Foundation

/// Plans complex multi-step workflows via remote LLM (e.g. video upload flow).
public class WorkflowPlanner {

    private let remoteLLM: RemoteLLMService

    public init(remoteLLM: RemoteLLMService) {
        self.remoteLLM = remoteLLM
    }

    /// Plan a workflow for a given instruction
    /// - Parameter instruction: Natural language instruction (e.g. "Upload a video to Douyin")
    /// - Returns: Array of workflow steps
    public func plan(instruction: String) async throws -> [WorkflowStep] {
        let systemPrompt = """
        You are a mobile app automation workflow planner.
        Given a user's instruction, break it down into a sequence of concrete steps
        that can be executed on an iOS device.

        Each step should describe:
        - The app to interact with
        - The UI element to find
        - The action to perform
        - What to verify after the action

        Output a JSON array of steps. No other text.
        """

        let prompt = """
        Plan the workflow for: \(instruction)

        Output format:
        [
          {
            "step": 1,
            "app": "com.apple.mobilesafari",
            "description": "Open Safari",
            "action": "open_app",
            "target": "Safari app icon",
            "verification": "Safari is open"
          }
        ]
        """

        let response = try await remoteLLM.generate(prompt: prompt, system: systemPrompt)
        return try parseWorkflowSteps(response)
    }

    private func parseWorkflowSteps(_ response: String) throws -> [WorkflowStep] {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "["),
              let end = trimmed.lastIndex(of: "]") else {
            throw WorkflowPlannerError.invalidResponse
        }
        let jsonString = String(trimmed[start...end])
        guard let data = jsonString.data(using: .utf8) else {
            throw WorkflowPlannerError.invalidResponse
        }
        return try JSONDecoder().decode([WorkflowStep].self, from: data)
    }
}

// MARK: - Data Models

public struct WorkflowStep: Codable {
    public let step: Int
    public let app: String?
    public let description: String
    public let action: String
    public let target: String?
    public let verification: String?
    public let parameters: [String: String]?
}

public enum WorkflowPlannerError: LocalizedError {
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Failed to parse workflow plan from LLM response"
        }
    }
}
