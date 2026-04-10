import Foundation

/// Builds prompts for the local Gemma 4 model to analyze iOS UI screenshots
/// and decide the next automation action.
public class AutomationPromptBuilder {

    /// System prompt for iOS UI automation agent
    private let systemPrompt = """
    You are an iOS UI automation agent. You analyze screenshots of iOS devices and decide the next action to achieve a user's goal.

    Available actions (output exactly ONE JSON object, no other text):
    - {"action": "tap", "x": 0.5, "y": 0.3, "reasoning": "Tapping the Settings icon"}
    - {"action": "long_press", "x": 0.5, "y": 0.3, "duration": 1.0, "reasoning": "Long pressing to open context menu"}
    - {"action": "type", "text": "hello world", "reasoning": "Entering text in the search field"}
    - {"action": "swipe", "direction": "up", "reasoning": "Scrolling down to see more options"}
    - {"action": "press_button", "button": "home", "reasoning": "Going to home screen"}
    - {"action": "open_app", "bundleId": "com.apple.Preferences", "reasoning": "Opening Settings app"}
    - {"action": "wait", "duration": 2.0, "reasoning": "Waiting for content to load"}
    - {"action": "done", "reasoning": "Goal is complete", "summary": "Successfully changed the wallpaper"}

    Rules:
    - Coordinates are normalized (0.0-1.0). Top-left is (0,0), bottom-right is (1,1).
    - direction must be one of: up, down, left, right.
    - button must be one of: home, volume_up, volume_down.
    - Output ONLY the JSON object, no markdown, no explanation outside JSON.
    - If the goal is already achieved, output action "done".
    """

    /// Build a prompt for UI screenshot analysis
    public func buildUIAnalysisPrompt(
        goal: String,
        actionHistory: [AgentAction]
    ) -> String {
        var prompt = ""

        // Add action history context
        if actionHistory.isEmpty {
            prompt += "Current goal: \(goal)\n"
            prompt += "This is the first step. Analyze the screenshot and decide the first action.\n"
        } else {
            prompt += "Current goal: \(goal)\n"
            prompt += "Previous actions taken:\n"
            for (i, action) in actionHistory.enumerated() {
                prompt += "  Step \(i + 1): \(action.type)"
                if let x = action.x, let y = action.y {
                    prompt += " at (\(x), \(y))"
                }
                if let text = action.text {
                    prompt += " text=\"\(text)\""
                }
                if let direction = action.direction {
                    prompt += " \(direction)"
                }
                if let reasoning = action.reasoning {
                    prompt += " - \(reasoning)"
                }
                prompt += "\n"
            }
            prompt += "Step \(actionHistory.count + 1): Analyze the current screenshot and decide the next action.\n"
        }

        return prompt
    }

    /// Get the system prompt for the local LLM
    public func getSystemPrompt() -> String {
        return systemPrompt
    }
}
