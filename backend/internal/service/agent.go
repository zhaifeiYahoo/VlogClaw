package service

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"vlogclaw/internal/domain"
	"vlogclaw/internal/llm"
	"vlogclaw/internal/wda"
)

// AgentService orchestrates the screenshot→analyze→execute agent loop.
type AgentService struct {
	wdaClient *wda.Client
	llmCfg    interface {
		NewProvider(model string) (llm.Provider, error)
	}
	mu    sync.RWMutex
	tasks map[string]*domain.Task
}

// LLMConfig is a minimal interface for creating LLM providers.
type LLMConfig interface {
	NewProvider(model string) (llm.Provider, error)
}

// llmProviderFactory wraps the llm.NewProvider function.
type llmProviderFactory struct {
	cfg any // will be replaced with proper type
}

// NewAgentService creates a new agent service.
func NewAgentService(wdaClient *wda.Client) *AgentService {
	return &AgentService{
		wdaClient: wdaClient,
		tasks:     make(map[string]*domain.Task),
	}
}

// SetLLMFactory sets the LLM provider factory function.
func (s *AgentService) SetLLMFactory(factory func(model string) (llm.Provider, error)) {
	s.llmCfg = &providerFactory{fn: factory}
}

type providerFactory struct {
	fn func(model string) (llm.Provider, error)
}

func (f *providerFactory) NewProvider(model string) (llm.Provider, error) {
	return f.fn(model)
}

// ExecuteTask runs the agent loop for the given task.
func (s *AgentService) ExecuteTask(ctx context.Context, task *domain.Task) error {
	provider, err := s.llmCfg.NewProvider(task.Model)
	if err != nil {
		return fmt.Errorf("create llm provider: %w", err)
	}

	// Get screen size
	screenSize, err := s.wdaClient.GetWindowSize(ctx)
	if err != nil {
		return fmt.Errorf("get window size: %w", err)
	}

	s.storeTask(task)
	s.updateStatus(task.ID, domain.TaskStatusRunning)

	history := make([]domain.Turn, 0, task.MaxSteps)

	for i := 0; i < task.MaxSteps; i++ {
		select {
		case <-ctx.Done():
			s.updateStatus(task.ID, domain.TaskStatusCancelled)
			return ctx.Err()
		default:
		}

		// 1. Take screenshot
		screenshot, err := s.wdaClient.Screenshot(ctx)
		if err != nil {
			s.failTask(task.ID, fmt.Sprintf("screenshot failed at step %d: %v", i, err))
			return fmt.Errorf("screenshot step %d: %w", i, err)
		}

		// 2. Send to LLM for analysis
		llmResp, err := provider.Analyze(ctx, domain.LLMRequest{
			Screenshot:  screenshot,
			Instruction: task.Instruction,
			History:     history,
			ScreenSize:  screenSize,
		})
		if err != nil {
			s.failTask(task.ID, fmt.Sprintf("LLM analysis failed at step %d: %v", i, err))
			return fmt.Errorf("llm step %d: %w", i, err)
		}

		// 3. Record step
		step := domain.Step{
			Index:      i,
			Screenshot: screenshot,
			Analysis:   llmResp.Analysis,
			Actions:    llmResp.Actions,
			Timestamp:  time.Now(),
		}
		s.addStep(task.ID, step)

		history = append(history, domain.Turn{
			Role:       "assistant",
			Analysis:   llmResp.Analysis,
			Actions:    llmResp.Actions,
		})

		slog.Info("agent step", "task", task.ID, "step", i,
			"analysis", llmResp.Analysis, "actions", len(llmResp.Actions))

		// 4. Execute actions
		for _, action := range llmResp.Actions {
			if action.Type == domain.ActionTerminate {
				s.updateStatus(task.ID, domain.TaskStatusCompleted)
				slog.Info("task completed", "task", task.ID, "steps", i+1)
				return nil
			}
			if err := s.wdaClient.ExecuteAction(ctx, action); err != nil {
				slog.Warn("action failed", "action", action.Type, "error", err)
			}
		}

		// 5. Check if done
		if llmResp.Done {
			s.updateStatus(task.ID, domain.TaskStatusCompleted)
			slog.Info("task completed (LLM marked done)", "task", task.ID, "steps", i+1)
			return nil
		}
	}

	s.updateStatus(task.ID, domain.TaskStatusFailed)
	s.failTask(task.ID, fmt.Sprintf("max steps (%d) reached", task.MaxSteps))
	return fmt.Errorf("max steps reached")
}

// GetTask returns a task by ID.
func (s *AgentService) GetTask(id string) (*domain.Task, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	t, ok := s.tasks[id]
	return t, ok
}

// ListTasks returns all tasks.
func (s *AgentService) ListTasks() []*domain.Task {
	s.mu.RLock()
	defer s.mu.RUnlock()
	result := make([]*domain.Task, 0, len(s.tasks))
	for _, t := range s.tasks {
		result = append(result, t)
	}
	return result
}

func (s *AgentService) storeTask(task *domain.Task) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.tasks[task.ID] = task
}

func (s *AgentService) updateStatus(id string, status domain.TaskStatus) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if t, ok := s.tasks[id]; ok {
		t.Status = status
		t.UpdatedAt = time.Now()
	}
}

func (s *AgentService) addStep(id string, step domain.Step) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if t, ok := s.tasks[id]; ok {
		t.Steps = append(t.Steps, step)
		t.UpdatedAt = time.Now()
	}
}

func (s *AgentService) failTask(id string, errMsg string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if t, ok := s.tasks[id]; ok {
		t.Status = domain.TaskStatusFailed
		t.Error = errMsg
		t.UpdatedAt = time.Now()
	}
}

// TaskRequest is the JSON body for creating a new task.
type TaskRequest struct {
	Instruction string `json:"instruction" binding:"required"`
	BundleID    string `json:"bundle_id"`
	Model       string `json:"model" binding:"required"`
	MaxSteps    int    `json:"max_steps,omitempty"`
}

// TaskResponse is the JSON response for task operations.
type TaskResponse struct {
	Success bool        `json:"success"`
	Data    any         `json:"data,omitempty"`
	Error   string      `json:"error,omitempty"`
}

// ToJSON is a helper for debugging.
func ToJSON(v any) string {
	b, _ := json.Marshal(v)
	return string(b)
}
