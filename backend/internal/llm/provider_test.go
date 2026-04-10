package llm

import (
	"testing"

	"vlogclaw/internal/domain"
)

func TestParseLLMResponseExtractsJSONFromWrappedText(t *testing.T) {
	content := "Here is the result:\n```json\n{\"analysis\":\"ready\",\"actions\":[{\"type\":\"launch_app\",\"bundle_id\":\"com.xingin.discover\"}],\"done\":false}\n```"

	resp, err := parseLLMResponse(content)
	if err != nil {
		t.Fatalf("parseLLMResponse returned error: %v", err)
	}

	if resp.Analysis != "ready" {
		t.Fatalf("unexpected analysis: %q", resp.Analysis)
	}
	if len(resp.Actions) != 1 {
		t.Fatalf("expected 1 action, got %d", len(resp.Actions))
	}
	if resp.Actions[0].Type != domain.ActionLaunchApp {
		t.Fatalf("unexpected action type: %s", resp.Actions[0].Type)
	}
	if resp.Actions[0].BundleID != "com.xingin.discover" {
		t.Fatalf("unexpected bundle id: %q", resp.Actions[0].BundleID)
	}
}
