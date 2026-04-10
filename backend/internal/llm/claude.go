package llm

import (
	"context"
	"fmt"

	"github.com/anthropics/anthropic-sdk-go"
	"github.com/anthropics/anthropic-sdk-go/option"

	"vlogclaw/internal/domain"
)

// ClaudeProvider implements Provider using the Anthropic Claude API.
type ClaudeProvider struct {
	client *anthropic.Client
	model  string
}

// NewClaudeProvider creates a new Claude provider.
func NewClaudeProvider(apiKey, model string) *ClaudeProvider {
	client := anthropic.NewClient(option.WithAPIKey(apiKey))
	return &ClaudeProvider{client: &client, model: model}
}

// Analyze sends a screenshot to Claude and returns parsed actions.
func (p *ClaudeProvider) Analyze(ctx context.Context, req domain.LLMRequest) (*domain.LLMResponse, error) {
	userMsg := BuildUserMessage(req)

	params := anthropic.MessageNewParams{
		MaxTokens: 1024,
		Model:     p.model,
		System: []anthropic.TextBlockParam{
			{Text: BuildSystemPrompt()},
		},
		Messages: []anthropic.MessageParam{
			anthropic.NewUserMessage(
				anthropic.NewTextBlock(userMsg),
				anthropic.NewImageBlockBase64("image/png", req.Screenshot),
			),
		},
	}

	message, err := p.client.Messages.New(ctx, params)
	if err != nil {
		return nil, fmt.Errorf("claude completion: %w", err)
	}

	for _, block := range message.Content {
		if block.Type == "text" {
			return parseLLMResponse(block.Text)
		}
	}

	return nil, fmt.Errorf("claude returned no text content")
}
