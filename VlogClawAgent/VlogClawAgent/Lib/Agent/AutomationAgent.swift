import Foundation
import CoreImage

// MARK: - Data Models

/// A structured automation action returned by the LLM
public struct AgentAction: Codable {
    public let type: String           // tap, long_press, type, swipe, press_button, open_app, wait, done
    public let x: Double?             // normalized x (0.0-1.0) for tap/long_press
    public let y: Double?             // normalized y (0.0-1.0) for tap/long_press
    public let text: String?          // text for type action
    public let direction: String?     // up/down/left/right for swipe
    public let button: String?        // home/volume_up/volume_down for press_button
    public let bundleId: String?      // bundle ID for open_app
    public let duration: Double?      // duration for wait/long_press
    public let reasoning: String?     // LLM's explanation
}

/// Result of a single agent step
public struct AgentStepResult: Codable {
    public let action: AgentAction
    public let screenshotDescription: String?
    public let isGoalComplete: Bool
    public let stepIndex: Int
}

/// Result of a full agent loop
public struct AgentLoopResult: Codable {
    public let goal: String
    public let steps: [AgentStepResult]
    public let completed: Bool
    public let totalSteps: Int
    public let error: String?
}

// MARK: - Agent

/// Core automation agent that routes between local and remote LLM.
///
/// **Local path**: Screenshot analysis → UI control recognition → basic action decision
/// **Remote path**: Complex reasoning → content generation → workflow planning → instruction decomposition
public class AutomationAgent {

    private let localLLM: MLXLocalLLMService
    private let remoteLLM: RemoteLLMService?
    private let promptBuilder = AutomationPromptBuilder()
    private let actionParser = ActionParser()

    public init(localLLM: MLXLocalLLMService, remoteLLM: RemoteLLMService? = nil) {
        self.localLLM = localLLM
        self.remoteLLM = remoteLLM
    }

    // MARK: - Single Step Analysis (Local LLM)

    /// Analyze a screenshot and suggest the next action using local Gemma 4
    public func analyzeScreenshot(
        base64: String,
        goal: String,
        actionHistory: [AgentAction]
    ) async throws -> AgentStepResult {
        let prompt = promptBuilder.buildUIAnalysisPrompt(
            goal: goal,
            actionHistory: actionHistory
        )

        // Use local LLM for vision analysis
        let image = decodeBase64Image(base64)
        let response = try await generateWithLocalLLM(prompt: prompt, image: image)

        let action = try actionParser.parse(response)

        return AgentStepResult(
            action: action,
            screenshotDescription: action.reasoning,
            isGoalComplete: action.type == "done",
            stepIndex: actionHistory.count
        )
    }

    // MARK: - Full Agent Loop

    /// Execute a full automation loop: screenshot → analyze → act → repeat
    public func executeLoop(goal: String, maxSteps: Int) async throws -> AgentLoopResult {
        var history: [AgentStepResult] = []
        var actionHistory: [AgentAction] = []

        for step in 0..<maxSteps {
            // 1. Take screenshot (via WDA)
            let screenshot = try await takeScreenshot()

            // 2. Analyze with local LLM
            let stepResult = try await analyzeScreenshot(
                base64: screenshot,
                goal: goal,
                actionHistory: actionHistory
            )

            history.append(stepResult)
            actionHistory.append(stepResult.action)

            // 3. Check if goal is complete
            if stepResult.isGoalComplete {
                return AgentLoopResult(
                    goal: goal,
                    steps: history,
                    completed: true,
                    totalSteps: step + 1,
                    error: nil
                )
            }

            // 4. Execute the action
            do {
                try await executeAction(stepResult.action)
            } catch {
                return AgentLoopResult(
                    goal: goal,
                    steps: history,
                    completed: false,
                    totalSteps: step + 1,
                    error: "Action execution failed at step \(step + 1): \(error.localizedDescription)"
                )
            }

            // 5. Wait for UI to settle
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
        }

        return AgentLoopResult(
            goal: goal,
            steps: history,
            completed: false,
            totalSteps: maxSteps,
            error: "Max steps (\(maxSteps)) reached without completing goal"
        )
    }

    /// Single step: take screenshot, analyze, return result (action not executed)
    public func singleStep(goal: String, actionHistory: [AgentAction]) async throws -> AgentStepResult {
        let screenshot = try await takeScreenshot()
        return try await analyzeScreenshot(
            base64: screenshot,
            goal: goal,
            actionHistory: actionHistory
        )
    }

    // MARK: - Private Helpers

    private func generateWithLocalLLM(prompt: String, image: CIImage?) async throws -> String {
        var images: [CIImage] = []
        if let image { images.append(image) }

        let stream = try await localLLM.generateStream(
            prompt: prompt,
            images: images,
            audios: []
        )

        var result = ""
        for try await chunk in stream {
            result += chunk
        }
        return result
    }

    private func decodeBase64Image(_ base64: String) -> CIImage? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return CIImage(data: data)
    }

    private func takeScreenshot() async throws -> String {
        // This will be called from ObjC via WDA's screenshot infrastructure
        // For now, return a placeholder that the ObjC side will override
        // The actual screenshot is taken by FBAgentCommands using XCUIDevice
        return ""
    }

    private func executeAction(_ action: AgentAction) async throws {
        // Action execution is handled by the ObjC side (WDA XCTest APIs)
        // This is a placeholder; the actual execution happens in FBAgentCommands
        // which calls XCUIElement tap/swipe/type APIs
    }
}
