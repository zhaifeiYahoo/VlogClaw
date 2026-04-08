package llm

import (
	"fmt"
	"strings"

	"vlogclaw/internal/domain"
)

// BuildSystemPrompt constructs the system prompt for the LLM.
func BuildSystemPrompt() string {
	return `You are an iOS UI automation agent. You analyze screenshots of iOS apps and decide what actions to take to fulfill the user's instruction.

You MUST respond in the following JSON format (no markdown, no code fences):
{
  "analysis": "Your reasoning about what's on screen and what to do next",
  "actions": [
    {"type": "tap", "x": 200, "y": 300, "label": "Tap the Login button"}
  ],
  "done": false
}

Available action types:
- tap: Tap at coordinates. Required: x, y. Optional: label.
- swipe: Swipe gesture. Required: x, y, dx, dy. Optional: duration (seconds).
- type: Type text. Required: text.
- scroll: Scroll vertically. Required: x, y, dy.
- press: Press hardware button. Required: label (e.g. "home", "volumeUp").
- wait: Wait for some time. Required: duration (seconds).
- terminate: Stop the agent loop. Use when task is complete or unrecoverable.

Rules:
- Use exact pixel coordinates based on the screenshot.
- Be precise with tap locations — aim for the center of the target element.
- Set "done": true when the user's instruction has been fully completed.
- Multiple actions can be specified in a single step if they are independent.`
}

// BuildUserMessage constructs the user message content for the current step.
func BuildUserMessage(instruction string, screenSize domain.Size, history []domain.Turn) string {
	var b strings.Builder
	b.WriteString(fmt.Sprintf("Screen size: %.0fx%.0f\n", screenSize.Width, screenSize.Height))
	b.WriteString(fmt.Sprintf("Instruction: %s\n", instruction))

	if len(history) > 0 {
		b.WriteString("\nPrevious steps:\n")
		for i, turn := range history {
			if turn.Role == "assistant" {
				b.WriteString(fmt.Sprintf("Step %d: %s\n", i+1, turn.Analysis))
				for _, a := range turn.Actions {
					b.WriteString(fmt.Sprintf("  - %s: %s\n", a.Type, a.Label))
				}
			}
		}
	}

	b.WriteString("\nAnalyze the current screenshot and decide the next actions.")
	return b.String()
}
