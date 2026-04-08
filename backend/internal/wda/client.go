package wda

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"vlogclaw/internal/domain"
)

// Client is an HTTP client for WebDriverAgent.
type Client struct {
	baseURL    string
	httpClient *http.Client
}

// NewClient creates a new WDA client.
func NewClient(baseURL string) *Client {
	return &Client{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// Screenshot takes a screenshot and returns it as base64 PNG.
func (c *Client) Screenshot(ctx context.Context) (string, error) {
	var resp ScreenshotResponse
	if err := c.post(ctx, "/screenshot", nil, &resp); err != nil {
		return "", fmt.Errorf("screenshot: %w", err)
	}
	return resp.Value, nil
}

// GetWindowSize returns the screen dimensions.
func (c *Client) GetWindowSize(ctx context.Context) (domain.Size, error) {
	var resp WindowSizeResponse
	if err := c.get(ctx, "/window/size", &resp); err != nil {
		return domain.Size{}, fmt.Errorf("window size: %w", err)
	}
	return domain.Size{Width: resp.Value.Width, Height: resp.Value.Height}, nil
}

// Source returns the raw UI source tree XML.
func (c *Client) Source(ctx context.Context) (string, error) {
	var resp SourceResponse
	if err := c.get(ctx, "/source", &resp); err != nil {
		return "", fmt.Errorf("source: %w", err)
	}
	return resp.Value, nil
}

// Tap performs a tap at the given coordinates.
func (c *Client) Tap(ctx context.Context, x, y float64) error {
	return c.post(ctx, "/wda/tap/0", TapRequest{X: x, Y: y}, nil)
}

// Swipe performs a swipe gesture.
func (c *Client) Swipe(ctx context.Context, sx, sy, ex, ey, duration float64) error {
	return c.post(ctx, "/wda/swipe", SwipeRequest{
		StartX: sx, StartY: sy, EndX: ex, EndY: ey, Duration: duration,
	}, nil)
}

// Type types text into the currently focused element.
func (c *Client) Type(ctx context.Context, text string) error {
	chars := make([]string, len(text))
	for i, r := range text {
		chars[i] = string(r)
	}
	return c.post(ctx, "/wda/keys", TypeRequest{Value: chars}, nil)
}

// PressButton presses a hardware/special button.
func (c *Client) PressButton(ctx context.Context, name string, duration float64) error {
	return c.post(ctx, "/wda/pressButton", PressRequest{Name: name, Duration: duration}, nil)
}

// ExecuteAction executes a domain action via WDA.
func (c *Client) ExecuteAction(ctx context.Context, action domain.Action) error {
	switch action.Type {
	case domain.ActionTap:
		return c.Tap(ctx, action.X, action.Y)
	case domain.ActionSwipe:
		return c.Swipe(ctx, action.X, action.Y, action.X+action.DX, action.Y+action.DY, action.Duration)
	case domain.ActionInputText:
		return c.Type(ctx, action.Text)
	case domain.ActionPress:
		return c.PressButton(ctx, action.Label, action.Duration)
	case domain.ActionWait:
		select {
		case <-time.After(time.Duration(action.Duration * float64(time.Second))):
			return nil
		case <-ctx.Done():
			return ctx.Err()
		}
	case domain.ActionScroll:
		// scroll is implemented as a vertical swipe
		return c.Swipe(ctx, action.X, action.Y, action.X, action.Y+action.DY, 0.5)
	default:
		return fmt.Errorf("unsupported action type: %s", action.Type)
	}
}

func (c *Client) get(ctx context.Context, path string, result any) error {
	return c.do(ctx, http.MethodGet, path, nil, result)
}

func (c *Client) post(ctx context.Context, path string, body any, result any) error {
	return c.do(ctx, http.MethodPost, path, body, result)
}

func (c *Client) do(ctx context.Context, method, path string, body any, result any) error {
	var bodyReader io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("marshal request: %w", err)
		}
		bodyReader = bytes.NewReader(b)
	}

	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, bodyReader)
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("http request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		respBody, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("wda error %d: %s", resp.StatusCode, string(respBody))
	}

	if result != nil {
		if err := json.NewDecoder(resp.Body).Decode(result); err != nil {
			return fmt.Errorf("decode response: %w", err)
		}
	}

	return nil
}
