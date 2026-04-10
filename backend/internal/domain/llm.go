package domain

// LLMRequest is the input to an LLM provider.
type LLMRequest struct {
	Screenshot  string // base64 encoded screenshot
	Instruction string // original user instruction
	History     []Turn // previous turns in this session
	ScreenSize  Size   // device screen dimensions
	BundleID    string // target app bundle id for app launch or recovery
	Workflow    string // higher-level workflow name
	Title       string // structured title text for publish flows
	Body        string // structured body/caption text for publish flows
	ImageCount  int    // number of images to select from the picker
	ImageHint   string // hint for which images to choose on device
	PublishMode string // publish or draft
}

// LLMResponse is the parsed output from an LLM provider.
type LLMResponse struct {
	Analysis string   // LLM's reasoning about the current screen
	Actions  []Action // parsed actions to execute
	Done     bool     // true if the task is complete
}

// Turn represents one round of the agent loop for conversation history.
type Turn struct {
	Role       string   // "user" (screenshot context) or "assistant"
	Screenshot string   // base64, only for user turns
	Analysis   string   // LLM analysis text
	Actions    []Action // actions taken
}

// Size represents screen dimensions.
type Size struct {
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
}
