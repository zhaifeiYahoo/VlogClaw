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
- launch_app: Launch or foreground an app by bundle identifier. Required: bundle_id.
- terminate: Stop the agent loop. Use when task is complete or unrecoverable.

Rules:
- Use exact pixel coordinates based on the screenshot.
- Be precise with tap locations — aim for the center of the target element.
- Prefer a single next action unless two consecutive actions are obviously safe together.
- If the target app is not on screen and a bundle identifier is provided, use launch_app first instead of guessing.
- Set "done": true when the user's instruction has been fully completed.
- Do not mark done until the final success state is visible on screen.
- Multiple actions can be specified in a single step if they are independent.`
}

// BuildUserMessage constructs the user message content for the current step.
func BuildUserMessage(req domain.LLMRequest) string {
	var b strings.Builder
	b.WriteString(fmt.Sprintf("Screen size: %.0fx%.0f\n", req.ScreenSize.Width, req.ScreenSize.Height))
	if req.BundleID != "" {
		b.WriteString(fmt.Sprintf("Target bundle id: %s\n", req.BundleID))
	}
	if req.Workflow != "" {
		b.WriteString(fmt.Sprintf("Workflow: %s\n", req.Workflow))
	}
	b.WriteString(fmt.Sprintf("Instruction: %s\n", req.Instruction))

	if req.Workflow == domain.WorkflowXiaohongshuPost {
		b.WriteString("\nXiaohongshu publish requirements:\n")
		imageCount := req.ImageCount
		if imageCount <= 0 {
			imageCount = 1
		}
		b.WriteString(fmt.Sprintf("- Create a new image-and-text post and select %d image(s) from the device photo picker.\n", imageCount))
		if req.ImageHint != "" {
			b.WriteString(fmt.Sprintf("- Prefer images matching this hint: %s\n", req.ImageHint))
		} else {
			b.WriteString("- If no other hint is given, select the most recent images visible in the picker.\n")
		}
		if req.Title != "" {
			b.WriteString(fmt.Sprintf("- If a separate title field exists, enter this exact title: %q\n", req.Title))
		}
		if req.Body != "" {
			b.WriteString(fmt.Sprintf("- Enter this exact caption/body text: %q\n", req.Body))
		}
		if req.PublishMode == domain.PublishModeDraft {
			b.WriteString("- Finish by saving the post as a draft.\n")
		} else {
			b.WriteString("- Finish by pressing the final publish/post button only after images and text are confirmed on screen.\n")
		}
		b.WriteString("- Handle permission dialogs only when they unblock publishing.\n")
	}

	if len(req.History) > 0 {
		b.WriteString("\nPrevious steps:\n")
		for i, turn := range req.History {
			if turn.Role == "assistant" {
				b.WriteString(fmt.Sprintf("Step %d: %s\n", i+1, turn.Analysis))
				for _, a := range turn.Actions {
					label := a.Label
					if label == "" && a.BundleID != "" {
						label = a.BundleID
					}
					b.WriteString(fmt.Sprintf("  - %s: %s\n", a.Type, label))
				}
			}
		}
	}

	b.WriteString("\nAnalyze the current screenshot and decide the next actions.")
	return b.String()
}
