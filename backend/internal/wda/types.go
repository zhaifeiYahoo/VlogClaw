package wda

// StatusResponse is the WDA response for the /status endpoint.
type StatusResponse struct {
	Value StatusValue `json:"value"`
}

// StatusValue holds WDA readiness metadata.
type StatusValue struct {
	Ready    bool   `json:"ready"`
	Message  string `json:"message"`
	Platform string `json:"platform,omitempty"`
}

// SourceResponse is the WDA response for getting the UI source tree.
type SourceResponse struct {
	Value string `json:"value"` // XML source tree
}

// ScreenshotResponse is the WDA response for taking a screenshot.
type ScreenshotResponse struct {
	Value string `json:"value"` // base64 encoded PNG
}

// ElementResponse is the WDA response for finding an element.
type ElementResponse struct {
	Value     ElementValue `json:"value"`
	SessionID string       `json:"sessionId"`
}

// ElementValue holds element metadata.
type ElementValue struct {
	ELEMENT string `json:"ELEMENT"`
}

// CreateSessionRequest is the body for creating a WDA session.
type CreateSessionRequest struct {
	Capabilities        W3CCapabilities `json:"capabilities"`
	DesiredCapabilities map[string]any  `json:"desiredCapabilities"`
}

// W3CCapabilities wraps alwaysMatch capabilities in W3C format.
type W3CCapabilities struct {
	AlwaysMatch map[string]any `json:"alwaysMatch"`
}

// SessionResponse is the WDA response for creating a session.
type SessionResponse struct {
	SessionID string       `json:"sessionId"`
	Value     SessionValue `json:"value"`
}

// SessionValue holds session details.
type SessionValue struct {
	SessionID string `json:"sessionId"`
}

// WindowSizeResponse is the WDA response for getting window size.
type WindowSizeResponse struct {
	Value WindowSize `json:"value"`
}

// WindowSize holds screen dimensions.
type WindowSize struct {
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
}

// TapRequest is the body for a tap action.
type TapRequest struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
}

// DragRequest is the body for a coordinate drag gesture.
type DragRequest struct {
	FromX    float64 `json:"fromX"`
	FromY    float64 `json:"fromY"`
	ToX      float64 `json:"toX"`
	ToY      float64 `json:"toY"`
	Duration float64 `json:"duration,omitempty"`
}

// TypeRequest is the body for typing text.
type TypeRequest struct {
	Value []string `json:"value"`
}

// PressRequest is the body for pressing a key.
type PressRequest struct {
	Name     string  `json:"name"`
	Duration float64 `json:"duration,omitempty"`
}

// LaunchAppRequest is the body for launching an app by bundle identifier.
type LaunchAppRequest struct {
	BundleID string `json:"bundleId"`
}
