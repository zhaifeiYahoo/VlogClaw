package service

import (
	"strings"
	"testing"

	"vlogclaw/internal/domain"
)

func TestResolveInstructionForXiaohongshuPost(t *testing.T) {
	task := &domain.Task{
		Workflow:    domain.WorkflowXiaohongshuPost,
		BundleID:    "com.xingin.discover",
		Title:       "春季穿搭",
		Body:        "今天分享一套通勤穿搭。",
		ImageCount:  3,
		ImageHint:   "选择最新的三张穿搭图",
		PublishMode: domain.PublishModePublish,
	}

	instruction := resolveInstruction(task)

	expectedSnippets := []string{
		"Launch Xiaohongshu",
		"com.xingin.discover",
		"Select 3 image(s)",
		"春季穿搭",
		"今天分享一套通勤穿搭。",
		"选择最新的三张穿搭图",
		"final publish button",
	}
	for _, snippet := range expectedSnippets {
		if !strings.Contains(instruction, snippet) {
			t.Fatalf("instruction %q does not contain %q", instruction, snippet)
		}
	}
}
