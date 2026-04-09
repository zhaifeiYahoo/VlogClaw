package domain

// ActionType represents the type of UI action to perform.
type ActionType string

const (
	ActionTap       ActionType = "tap"
	ActionSwipe     ActionType = "swipe"
	ActionInputText ActionType = "type"
	ActionScroll    ActionType = "scroll"
	ActionPress     ActionType = "press"
	ActionWait      ActionType = "wait"
	ActionLaunchApp ActionType = "launch_app"
	ActionTerminate ActionType = "terminate" // stop the agent loop
)

// Action represents a parsed UI action from the LLM response.
type Action struct {
	Type     ActionType `json:"type"`
	X        float64    `json:"x,omitempty"`
	Y        float64    `json:"y,omitempty"`
	DX       float64    `json:"dx,omitempty"` // swipe delta
	DY       float64    `json:"dy,omitempty"`
	Text     string     `json:"text,omitempty"`
	Duration float64    `json:"duration,omitempty"` // seconds, for wait/press
	Label    string     `json:"label,omitempty"`    // human-readable description
	BundleID string     `json:"bundle_id,omitempty"`
}

// Element represents a UI element found on screen.
type Element struct {
	Type    string `json:"type"`
	Label   string `json:"label,omitempty"`
	Name    string `json:"name,omitempty"`
	Value   string `json:"value,omitempty"`
	Rect    Rect   `json:"rect"`
	Enabled bool   `json:"enabled"`
	Visible bool   `json:"visible"`
}

// Rect represents the bounding rectangle of a UI element.
type Rect struct {
	X      float64 `json:"x"`
	Y      float64 `json:"y"`
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
}

// Center returns the center point of the rectangle.
func (r Rect) Center() (x, y float64) {
	return r.X + r.Width/2, r.Y + r.Height/2
}
