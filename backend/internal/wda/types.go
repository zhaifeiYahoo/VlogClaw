package wda

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
	Value    ElementValue `json:"value"`
	SessionID string      `json:"sessionId"`
}

// ElementValue holds element metadata.
type ElementValue struct {
	ELEMENT string `json:"ELEMENT"`
}

// SessionResponse is the WDA response for creating a session.
type SessionResponse struct {
	Value SessionValue `json:"value"`
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

// SwipeRequest is the body for a swipe action.
type SwipeRequest struct {
	StartX  float64 `json:"startX"`
	StartY  float64 `json:"startY"`
	EndX    float64 `json:"endX"`
	EndY    float64 `json:"endY"`
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
