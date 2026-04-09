package llm

import (
	"context"
	"fmt"

	"github.com/openai/openai-go"
	"github.com/openai/openai-go/option"
	"github.com/openai/openai-go/packages/param"

	"vlogclaw/internal/domain"
)

// OpenAIProvider implements Provider using the OpenAI API.
type OpenAIProvider struct {
	client *openai.Client
	model  string
}

// NewOpenAIProvider creates a new OpenAI provider.
func NewOpenAIProvider(apiKey, model string) *OpenAIProvider {
	client := openai.NewClient(option.WithAPIKey(apiKey))
	return &OpenAIProvider{client: &client, model: model}
}

// Analyze sends a screenshot to OpenAI and returns parsed actions.
func (p *OpenAIProvider) Analyze(ctx context.Context, req domain.LLMRequest) (*domain.LLMResponse, error) {
	userMsg := BuildUserMessage(req)

	params := openai.ChatCompletionNewParams{
		Model: p.model,
		Messages: []openai.ChatCompletionMessageParamUnion{
			openai.SystemMessage(BuildSystemPrompt()),
			openai.UserMessage([]openai.ChatCompletionContentPartUnionParam{
				openai.TextContentPart(userMsg),
				openai.ImageContentPart(openai.ChatCompletionContentPartImageImageURLParam{
					URL: fmt.Sprintf("data:image/png;base64,%s", req.Screenshot),
				}),
			}),
		},
		MaxCompletionTokens: param.NewOpt(int64(1024)),
		Temperature:         param.NewOpt(0.1),
	}

	completion, err := p.client.Chat.Completions.New(ctx, params)
	if err != nil {
		return nil, fmt.Errorf("openai completion: %w", err)
	}

	if len(completion.Choices) == 0 {
		return nil, fmt.Errorf("openai returned no choices")
	}

	return parseLLMResponse(completion.Choices[0].Message.Content)
}
