package llm

import (
	"context"
	"encoding/json"
	"fmt"

	"vlogclaw/internal/config"
	"vlogclaw/internal/domain"
)

// Provider defines the interface for LLM providers.
type Provider interface {
	// Analyze analyzes a screenshot and returns actions to execute.
	Analyze(ctx context.Context, req domain.LLMRequest) (*domain.LLMResponse, error)
}

// NewProvider creates the appropriate LLM provider based on model name.
func NewProvider(cfg config.LLMConfig, model string) (Provider, error) {
	switch model {
	case "openai":
		if cfg.OpenAIKey == "" {
			return nil, fmt.Errorf("OPENAI_API_KEY is required for openai model")
		}
		return NewOpenAIProvider(cfg.OpenAIKey, cfg.OpenAIModel), nil
	case "claude":
		if cfg.ClaudeKey == "" {
			return nil, fmt.Errorf("CLAUDE_API_KEY is required for claude model")
		}
		return NewClaudeProvider(cfg.ClaudeKey, cfg.ClaudeModel), nil
	default:
		return nil, fmt.Errorf("unsupported model: %s (use 'openai' or 'claude')", model)
	}
}

// parseLLMResponse parses the JSON response from the LLM.
func parseLLMResponse(content string) (*domain.LLMResponse, error) {
	var resp struct {
		Analysis string          `json:"analysis"`
		Actions  []domain.Action `json:"actions"`
		Done     bool            `json:"done"`
	}

	if err := json.Unmarshal([]byte(content), &resp); err != nil {
		return nil, fmt.Errorf("parse llm response: %w (content: %s)", err, content)
	}

	return &domain.LLMResponse{
		Analysis: resp.Analysis,
		Actions:  resp.Actions,
		Done:     resp.Done,
	}, nil
}
