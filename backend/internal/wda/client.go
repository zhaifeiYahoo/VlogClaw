package wda

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"vlogclaw/internal/domain"
)

// Client is an HTTP client for WebDriverAgent.
type Client struct {
	baseURL    string
	httpClient *http.Client
	sessionID  string
}

// NewClient creates a new WDA client.
func NewClient(baseURL string) *Client {
	return &Client{
		baseURL: strings.TrimRight(baseURL, "/"),
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// SessionID returns the active WDA session ID.
func (c *Client) SessionID() string {
	return c.sessionID
}

// Status returns the current WDA status.
func (c *Client) Status(ctx context.Context) (*StatusResponse, error) {
	var resp StatusResponse
	if err := c.do(ctx, http.MethodGet, "/status", false, nil, &resp); err != nil {
		return nil, fmt.Errorf("status: %w", err)
	}
	return &resp, nil
}

// CreateSession creates a WDA session and stores the session ID.
func (c *Client) CreateSession(ctx context.Context, deviceUDID string) error {
	caps := map[string]any{
		"shouldUseSingletonTestManager":              true,
		"maxTypingFrequency":                         60,
		"shouldUseTestManagerForVisibilityDetection": false,
	}
	if strings.TrimSpace(deviceUDID) != "" {
		caps["udid"] = strings.TrimSpace(deviceUDID)
	}

	var resp SessionResponse
	if err := c.do(ctx, http.MethodPost, "/session", false, CreateSessionRequest{
		Capabilities: W3CCapabilities{
			AlwaysMatch: caps,
		},
		DesiredCapabilities: caps,
	}, &resp); err != nil {
		return fmt.Errorf("create session: %w", err)
	}

	sessionID := strings.TrimSpace(resp.SessionID)
	if sessionID == "" {
		sessionID = strings.TrimSpace(resp.Value.SessionID)
	}
	if sessionID == "" {
		return fmt.Errorf("wda returned empty session id")
	}
	c.sessionID = sessionID
	return nil
}

// Close deletes the active WDA session.
func (c *Client) Close(ctx context.Context) error {
	if c.sessionID == "" {
		return nil
	}
	if err := c.do(ctx, http.MethodDelete, "/session/"+c.sessionID, false, nil, nil); err != nil {
		return fmt.Errorf("close session: %w", err)
	}
	c.sessionID = ""
	return nil
}

// Screenshot takes a screenshot and returns it as base64 PNG.
func (c *Client) Screenshot(ctx context.Context) (string, error) {
	var resp ScreenshotResponse
	if err := c.do(ctx, http.MethodGet, "/screenshot", true, nil, &resp); err != nil {
		return "", fmt.Errorf("screenshot: %w", err)
	}
	if resp.Value == "" {
		return "", fmt.Errorf("wda returned empty screenshot")
	}
	return resp.Value, nil
}

// GetWindowSize returns the screen dimensions.
func (c *Client) GetWindowSize(ctx context.Context) (domain.Size, error) {
	var resp WindowSizeResponse
	if err := c.do(ctx, http.MethodGet, "/window/size", true, nil, &resp); err != nil {
		return domain.Size{}, fmt.Errorf("window size: %w", err)
	}
	return domain.Size{Width: resp.Value.Width, Height: resp.Value.Height}, nil
}

// Source returns the raw UI source tree XML.
func (c *Client) Source(ctx context.Context) (string, error) {
	var resp SourceResponse
	if err := c.do(ctx, http.MethodGet, "/source", true, nil, &resp); err != nil {
		return "", fmt.Errorf("source: %w", err)
	}
	return resp.Value, nil
}

// Tap performs a tap at the given coordinates.
func (c *Client) Tap(ctx context.Context, x, y float64) error {
	return c.do(ctx, http.MethodPost, "/wda/tap", true, TapRequest{X: x, Y: y}, nil)
}

// Swipe performs a swipe gesture using WDA's coordinate drag endpoint.
func (c *Client) Swipe(ctx context.Context, sx, sy, ex, ey, duration float64) error {
	return c.do(ctx, http.MethodPost, "/wda/dragfromtoforduration", true, DragRequest{
		FromX: sx, FromY: sy, ToX: ex, ToY: ey, Duration: duration,
	}, nil)
}

// Type types text into the currently focused element.
func (c *Client) Type(ctx context.Context, text string) error {
	chars := make([]string, 0, len(text))
	for _, r := range text {
		chars = append(chars, string(r))
	}
	return c.do(ctx, http.MethodPost, "/wda/keys", true, TypeRequest{Value: chars}, nil)
}

// PressButton presses a hardware or special button.
func (c *Client) PressButton(ctx context.Context, name string, duration float64) error {
	return c.do(ctx, http.MethodPost, "/wda/pressButton", true, PressRequest{Name: name, Duration: duration}, nil)
}

// LaunchApp launches an app by bundle identifier.
func (c *Client) LaunchApp(ctx context.Context, bundleID string) error {
	req := LaunchAppRequest{BundleID: bundleID}
	if err := c.do(ctx, http.MethodPost, "/wda/apps/launchUnattached", false, req, nil); err == nil {
		return nil
	}
	return c.do(ctx, http.MethodPost, "/wda/apps/launch", false, req, nil)
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
	case domain.ActionLaunchApp:
		if action.BundleID == "" {
			return fmt.Errorf("launch_app requires bundle_id")
		}
		return c.LaunchApp(ctx, action.BundleID)
	case domain.ActionScroll:
		return c.Swipe(ctx, action.X, action.Y, action.X, action.Y+action.DY, 0.5)
	default:
		return fmt.Errorf("unsupported action type: %s", action.Type)
	}
}

func (c *Client) do(ctx context.Context, method, path string, useSession bool, body any, result any) error {
	urlPath := path
	if useSession && c.sessionID != "" {
		urlPath = "/session/" + c.sessionID + path
	}

	var bodyReader io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("marshal request: %w", err)
		}
		bodyReader = bytes.NewReader(b)
	}

	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+urlPath, bodyReader)
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

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("read response: %w", err)
	}

	if resp.StatusCode >= 400 {
		return fmt.Errorf("wda error %d: %s", resp.StatusCode, strings.TrimSpace(string(respBody)))
	}

	if result != nil {
		if err := json.Unmarshal(respBody, result); err != nil {
			return fmt.Errorf("decode response: %w", err)
		}
	}
	return nil
}
