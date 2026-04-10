package llm

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/openai/openai-go"
	"github.com/openai/openai-go/option"
	"github.com/openai/openai-go/packages/param"
)

// XiaohongshuCopyRequest describes the user intent and optional reference images.
type XiaohongshuCopyRequest struct {
	Description   string   `json:"description"`
	Tone          string   `json:"tone,omitempty"`
	Audience      string   `json:"audience,omitempty"`
	ImageDataURLs []string `json:"image_data_urls,omitempty"`
}

// XiaohongshuCopyResponse is the structured copy returned to the desktop app.
type XiaohongshuCopyResponse struct {
	Title              string   `json:"title"`
	Body               string   `json:"body"`
	Hashtags           []string `json:"hashtags"`
	ImageSelectionHint string   `json:"image_selection_hint,omitempty"`
}

// OpenAIXiaohongshuCopywriter generates Xiaohongshu copy with the configured OpenAI model.
type OpenAIXiaohongshuCopywriter struct {
	apiKey string
	client *openai.Client
	model  string
}

// NewOpenAIXiaohongshuCopywriter creates a copywriter that reuses the backend OpenAI configuration.
func NewOpenAIXiaohongshuCopywriter(apiKey, model string) *OpenAIXiaohongshuCopywriter {
	client := openai.NewClient(option.WithAPIKey(apiKey))
	return &OpenAIXiaohongshuCopywriter{
		apiKey: strings.TrimSpace(apiKey),
		client: &client,
		model:  strings.TrimSpace(model),
	}
}

// GenerateXiaohongshuCopy creates a structured title/body/hashtag suggestion.
func (w *OpenAIXiaohongshuCopywriter) GenerateXiaohongshuCopy(ctx context.Context, req XiaohongshuCopyRequest) (*XiaohongshuCopyResponse, error) {
	if w == nil || strings.TrimSpace(w.apiKey) == "" {
		return nil, fmt.Errorf("OPENAI_API_KEY is required to generate Xiaohongshu copy")
	}

	description := strings.TrimSpace(req.Description)
	if description == "" && len(req.ImageDataURLs) == 0 {
		return nil, fmt.Errorf("description or image_data_urls is required")
	}

	parts := []openai.ChatCompletionContentPartUnionParam{
		openai.TextContentPart(buildXiaohongshuCopyPrompt(req)),
	}
	for _, image := range req.ImageDataURLs {
		normalized := normalizeImageDataURL(image)
		if normalized == "" {
			continue
		}
		parts = append(parts, openai.ImageContentPart(openai.ChatCompletionContentPartImageImageURLParam{
			URL: normalized,
		}))
	}

	params := openai.ChatCompletionNewParams{
		Model: w.model,
		Messages: []openai.ChatCompletionMessageParamUnion{
			openai.SystemMessage(`You are a senior Xiaohongshu content strategist.
Return only valid JSON with the exact fields: title, body, hashtags, image_selection_hint.
Write concise, concrete, publish-ready Chinese copy.`),
			openai.UserMessage(parts),
		},
		MaxCompletionTokens: param.NewOpt(int64(900)),
		Temperature:         param.NewOpt(0.7),
	}

	completion, err := w.client.Chat.Completions.New(ctx, params)
	if err != nil {
		return nil, fmt.Errorf("openai completion: %w", err)
	}
	if len(completion.Choices) == 0 {
		return nil, fmt.Errorf("openai returned no choices")
	}

	var parsed XiaohongshuCopyResponse
	if err := json.Unmarshal([]byte(extractJSONObject(completion.Choices[0].Message.Content)), &parsed); err != nil {
		return nil, fmt.Errorf("parse copy response: %w", err)
	}
	parsed.Title = strings.TrimSpace(parsed.Title)
	parsed.Body = strings.TrimSpace(parsed.Body)
	parsed.ImageSelectionHint = strings.TrimSpace(parsed.ImageSelectionHint)
	parsed.Hashtags = normalizeHashtags(parsed.Hashtags)

	if parsed.Title == "" || parsed.Body == "" {
		return nil, fmt.Errorf("copy response missing title or body")
	}
	if parsed.ImageSelectionHint == "" {
		parsed.ImageSelectionHint = fallbackImageHint(req)
	}
	return &parsed, nil
}

func buildXiaohongshuCopyPrompt(req XiaohongshuCopyRequest) string {
	var b strings.Builder
	b.WriteString("请基于下面的需求，为小红书图文内容生成结构化发布文案。\n")
	if description := strings.TrimSpace(req.Description); description != "" {
		b.WriteString("内容描述：")
		b.WriteString(description)
		b.WriteString("\n")
	}
	if tone := strings.TrimSpace(req.Tone); tone != "" {
		b.WriteString("语气风格：")
		b.WriteString(tone)
		b.WriteString("\n")
	}
	if audience := strings.TrimSpace(req.Audience); audience != "" {
		b.WriteString("目标人群：")
		b.WriteString(audience)
		b.WriteString("\n")
	}
	if len(req.ImageDataURLs) > 0 {
		b.WriteString(fmt.Sprintf("请结合 %d 张参考图片的视觉信息来写文案。\n", len(req.ImageDataURLs)))
	}
	b.WriteString(`输出 JSON:
{
  "title": "20字内的标题",
  "body": "2到4段正文，适合直接发布，包含轻量 CTA",
  "hashtags": ["#标签1", "#标签2", "#标签3"],
  "image_selection_hint": "给自动化流程的选图提示，简短明确"
}`)
	return b.String()
}

func normalizeImageDataURL(raw string) string {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return ""
	}
	if strings.HasPrefix(trimmed, "data:image/") {
		return trimmed
	}
	return "data:image/jpeg;base64," + trimmed
}

func normalizeHashtags(tags []string) []string {
	if len(tags) == 0 {
		return []string{"#小红书", "#图文分享", "#日常记录"}
	}
	result := make([]string, 0, len(tags))
	for _, tag := range tags {
		trimmed := strings.TrimSpace(tag)
		if trimmed == "" {
			continue
		}
		if !strings.HasPrefix(trimmed, "#") {
			trimmed = "#" + trimmed
		}
		result = append(result, trimmed)
	}
	if len(result) == 0 {
		return []string{"#小红书", "#图文分享", "#日常记录"}
	}
	return result
}

func fallbackImageHint(req XiaohongshuCopyRequest) string {
	description := strings.TrimSpace(req.Description)
	if description == "" {
		return "选择最近添加、主体清晰的图片"
	}
	return description
}
