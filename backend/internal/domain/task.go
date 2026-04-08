package domain

import "time"

// TaskStatus represents the current state of an automation task.
type TaskStatus string

const (
	TaskStatusPending   TaskStatus = "pending"
	TaskStatusRunning   TaskStatus = "running"
	TaskStatusCompleted TaskStatus = "completed"
	TaskStatusFailed    TaskStatus = "failed"
	TaskStatusCancelled TaskStatus = "cancelled"
)

// Task represents an automation task submitted by the caller.
type Task struct {
	ID          string     `json:"id"`
	Instruction string     `json:"instruction"` // natural language instruction
	BundleID    string     `json:"bundle_id"`   // target app bundle ID
	Model       string     `json:"model"`       // LLM model to use: "openai", "claude"
	MaxSteps    int        `json:"max_steps"`
	Status      TaskStatus `json:"status"`
	Steps       []Step     `json:"steps"`
	Error       string     `json:"error,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

// Step represents a single step in the agent loop.
type Step struct {
	Index      int       `json:"index"`
	Screenshot string    `json:"screenshot,omitempty"` // base64 encoded
	Analysis   string    `json:"analysis"`             // LLM analysis text
	Actions    []Action  `json:"actions"`
	Timestamp  time.Time `json:"timestamp"`
}
