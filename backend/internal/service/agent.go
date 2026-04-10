package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"sync"
	"time"

	"vlogclaw/internal/device"
	"vlogclaw/internal/domain"
	"vlogclaw/internal/llm"
	"vlogclaw/internal/wda"
)

var (
	// ErrDeviceBusy means another task is already using the same real device.
	ErrDeviceBusy = errors.New("device already has a running task")
)

// WDAClient is the subset of WDA behavior used by task execution.
type WDAClient interface {
	Status(ctx context.Context) (*wda.StatusResponse, error)
	CreateSession(ctx context.Context, deviceUDID string) error
	Close(ctx context.Context) error
	Screenshot(ctx context.Context) (string, error)
	GetWindowSize(ctx context.Context) (domain.Size, error)
	LaunchApp(ctx context.Context, bundleID string) error
	ExecuteAction(ctx context.Context, action domain.Action) error
}

// AgentService orchestrates the screenshot→analyze→execute agent loop.
type AgentService struct {
	devices interface {
		GetConnectedDevice(udid string) (device.ConnectedDevice, error)
	}
	llmCfg interface {
		NewProvider(model string) (llm.Provider, error)
	}
	newWDAClient func(baseURL string) WDAClient

	mu          sync.RWMutex
	tasks       map[string]*domain.Task
	deviceTasks map[string]string
}

// NewAgentService creates a new agent service.
func NewAgentService(devices interface {
	GetConnectedDevice(udid string) (device.ConnectedDevice, error)
}) *AgentService {
	return &AgentService{
		devices:      devices,
		newWDAClient: nil,
		tasks:        make(map[string]*domain.Task),
		deviceTasks:  make(map[string]string),
	}
}

// SetLLMFactory sets the LLM provider factory function.
func (s *AgentService) SetLLMFactory(factory func(model string) (llm.Provider, error)) {
	s.llmCfg = &providerFactory{fn: factory}
}

// SetWDAClientFactory sets the WDA client factory used for task execution.
func (s *AgentService) SetWDAClientFactory(factory func(baseURL string) WDAClient) {
	s.newWDAClient = factory
}

type providerFactory struct {
	fn func(model string) (llm.Provider, error)
}

func (f *providerFactory) NewProvider(model string) (llm.Provider, error) {
	return f.fn(model)
}

// StartTask reserves the target device and launches task execution asynchronously.
func (s *AgentService) StartTask(task *domain.Task) error {
	if strings.TrimSpace(task.DeviceUDID) == "" {
		return device.ErrDeviceNotConnected
	}
	if _, err := s.devices.GetConnectedDevice(task.DeviceUDID); err != nil {
		return err
	}

	s.mu.Lock()
	if runningTaskID, ok := s.deviceTasks[task.DeviceUDID]; ok && runningTaskID != "" {
		s.mu.Unlock()
		return ErrDeviceBusy
	}
	s.deviceTasks[task.DeviceUDID] = task.ID
	s.tasks[task.ID] = task
	s.mu.Unlock()

	go s.executeTask(context.Background(), task)
	return nil
}

func (s *AgentService) executeTask(ctx context.Context, task *domain.Task) {
	defer s.releaseDevice(task.DeviceUDID, task.ID)

	if err := s.ExecuteTask(ctx, task); err != nil {
		slog.Error("task execution failed", "task", task.ID, "device_udid", task.DeviceUDID, "error", err)
	}
}

// ExecuteTask runs the agent loop for the given task.
func (s *AgentService) ExecuteTask(ctx context.Context, task *domain.Task) error {
	if s.llmCfg == nil {
		return fmt.Errorf("llm factory is not configured")
	}
	if s.newWDAClient == nil {
		return fmt.Errorf("wda client factory is not configured")
	}

	provider, err := s.llmCfg.NewProvider(task.Model)
	if err != nil {
		s.failTask(task.ID, fmt.Sprintf("create llm provider failed: %v", err))
		return fmt.Errorf("create llm provider: %w", err)
	}

	instruction := resolveInstruction(task)
	if instruction == "" {
		s.failTask(task.ID, "task instruction is empty")
		return fmt.Errorf("task instruction is empty")
	}

	connectedDevice, err := s.devices.GetConnectedDevice(task.DeviceUDID)
	if err != nil {
		s.failTask(task.ID, fmt.Sprintf("device connection unavailable: %v", err))
		return err
	}

	client := s.newWDAClient(connectedDevice.WDAURL)
	if client == nil {
		s.failTask(task.ID, "wda client factory returned nil")
		return fmt.Errorf("wda client factory returned nil")
	}
	defer func() {
		if err := client.Close(context.Background()); err != nil {
			slog.Warn("failed to close WDA session", "task", task.ID, "device_udid", task.DeviceUDID, "error", err)
		}
	}()

	status, err := client.Status(ctx)
	if err != nil {
		s.failTask(task.ID, fmt.Sprintf("WDA status failed: %v", err))
		return fmt.Errorf("get WDA status: %w", err)
	}
	if !status.Value.Ready {
		s.failTask(task.ID, "WDA is not ready")
		return fmt.Errorf("wda is not ready")
	}
	if err := client.CreateSession(ctx, task.DeviceUDID); err != nil {
		s.failTask(task.ID, fmt.Sprintf("create session failed: %v", err))
		return fmt.Errorf("create WDA session: %w", err)
	}

	screenSize, err := client.GetWindowSize(ctx)
	if err != nil {
		s.failTask(task.ID, fmt.Sprintf("get window size failed: %v", err))
		return fmt.Errorf("get window size: %w", err)
	}

	s.updateStatus(task.ID, domain.TaskStatusRunning)

	if task.BundleID != "" {
		if err := client.LaunchApp(ctx, task.BundleID); err != nil {
			s.failTask(task.ID, fmt.Sprintf("launch app failed: %v", err))
			return fmt.Errorf("launch app %s: %w", task.BundleID, err)
		}
		select {
		case <-time.After(2 * time.Second):
		case <-ctx.Done():
			s.updateStatus(task.ID, domain.TaskStatusCancelled)
			return ctx.Err()
		}
	}

	history := make([]domain.Turn, 0, task.MaxSteps)
	for i := 0; i < task.MaxSteps; i++ {
		select {
		case <-ctx.Done():
			s.updateStatus(task.ID, domain.TaskStatusCancelled)
			return ctx.Err()
		default:
		}

		screenshot, err := client.Screenshot(ctx)
		if err != nil {
			s.failTask(task.ID, fmt.Sprintf("screenshot failed at step %d: %v", i, err))
			return fmt.Errorf("screenshot step %d: %w", i, err)
		}

		llmResp, err := provider.Analyze(ctx, domain.LLMRequest{
			Screenshot:  screenshot,
			Instruction: instruction,
			History:     history,
			ScreenSize:  screenSize,
			BundleID:    task.BundleID,
			Workflow:    task.Workflow,
			Title:       task.Title,
			Body:        task.Body,
			ImageCount:  task.ImageCount,
			ImageHint:   task.ImageHint,
			PublishMode: task.PublishMode,
		})
		if err != nil {
			s.failTask(task.ID, fmt.Sprintf("LLM analysis failed at step %d: %v", i, err))
			return fmt.Errorf("llm step %d: %w", i, err)
		}

		step := domain.Step{
			Index:      i,
			Screenshot: screenshot,
			Analysis:   llmResp.Analysis,
			Actions:    llmResp.Actions,
			Timestamp:  time.Now(),
		}
		s.addStep(task.ID, step)

		history = append(history, domain.Turn{
			Role:     "assistant",
			Analysis: llmResp.Analysis,
			Actions:  llmResp.Actions,
		})

		slog.Info("agent step", "task", task.ID, "device_udid", task.DeviceUDID, "step", i, "actions", len(llmResp.Actions))

		for _, action := range llmResp.Actions {
			if action.Type == domain.ActionTerminate {
				s.updateStatus(task.ID, domain.TaskStatusCompleted)
				return nil
			}
			if err := client.ExecuteAction(ctx, action); err != nil {
				slog.Warn("action failed", "task", task.ID, "device_udid", task.DeviceUDID, "action", action.Type, "error", err)
			}
		}

		if llmResp.Done {
			s.updateStatus(task.ID, domain.TaskStatusCompleted)
			return nil
		}
	}

	s.failTask(task.ID, fmt.Sprintf("max steps (%d) reached", task.MaxSteps))
	return fmt.Errorf("max steps reached")
}

// GetTask returns a task by ID.
func (s *AgentService) GetTask(id string) (*domain.Task, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	task, ok := s.tasks[id]
	return task, ok
}

// ListTasks returns all tasks.
func (s *AgentService) ListTasks() []*domain.Task {
	s.mu.RLock()
	defer s.mu.RUnlock()
	result := make([]*domain.Task, 0, len(s.tasks))
	for _, task := range s.tasks {
		result = append(result, task)
	}
	return result
}

func (s *AgentService) updateStatus(id string, status domain.TaskStatus) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if task, ok := s.tasks[id]; ok {
		task.Status = status
		task.UpdatedAt = time.Now()
	}
}

func (s *AgentService) addStep(id string, step domain.Step) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if task, ok := s.tasks[id]; ok {
		task.Steps = append(task.Steps, step)
		task.UpdatedAt = time.Now()
	}
}

func (s *AgentService) failTask(id string, errMsg string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if task, ok := s.tasks[id]; ok {
		task.Status = domain.TaskStatusFailed
		task.Error = errMsg
		task.UpdatedAt = time.Now()
	}
}

func (s *AgentService) releaseDevice(udid, taskID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if runningTaskID, ok := s.deviceTasks[udid]; ok && runningTaskID == taskID {
		delete(s.deviceTasks, udid)
	}
}

// TaskRequest is the JSON body for creating a new task.
type TaskRequest struct {
	Instruction string `json:"instruction"`
	DeviceUDID  string `json:"device_udid"`
	BundleID    string `json:"bundle_id"`
	Workflow    string `json:"workflow,omitempty"`
	Model       string `json:"model"`
	MaxSteps    int    `json:"max_steps,omitempty"`
	Title       string `json:"title,omitempty"`
	Body        string `json:"body,omitempty"`
	ImageCount  int    `json:"image_count,omitempty"`
	ImageHint   string `json:"image_selection_hint,omitempty"`
	PublishMode string `json:"publish_mode,omitempty"`
}

// TaskResponse is the JSON response for task operations.
type TaskResponse struct {
	Success bool   `json:"success"`
	Data    any    `json:"data,omitempty"`
	Error   string `json:"error,omitempty"`
}

// ToJSON is a helper for debugging.
func ToJSON(v any) string {
	b, _ := json.Marshal(v)
	return string(b)
}

func resolveInstruction(task *domain.Task) string {
	if strings.TrimSpace(task.Workflow) != domain.WorkflowXiaohongshuPost {
		return strings.TrimSpace(task.Instruction)
	}

	imageCount := task.ImageCount
	if imageCount <= 0 {
		imageCount = 1
	}

	publishMode := task.PublishMode
	if publishMode == "" {
		publishMode = domain.PublishModePublish
	}

	parts := []string{
		"Launch Xiaohongshu and complete a new image-and-text post from the current device state.",
		fmt.Sprintf("Use bundle id %s when the app is not already foregrounded.", task.BundleID),
		fmt.Sprintf("Select %d image(s) from the on-device photo picker.", imageCount),
	}
	if task.ImageHint != "" {
		parts = append(parts, fmt.Sprintf("Prefer images matching this hint: %s.", task.ImageHint))
	} else {
		parts = append(parts, "If multiple images are available, prefer the most recent visible ones.")
	}
	if task.Title != "" {
		parts = append(parts, fmt.Sprintf("If a dedicated title field exists, enter exactly this title: %q.", task.Title))
	}
	if task.Body != "" {
		parts = append(parts, fmt.Sprintf("Enter exactly this caption/body text: %q.", task.Body))
	}
	if publishMode == domain.PublishModeDraft {
		parts = append(parts, "Finish by saving the post as a draft.")
	} else {
		parts = append(parts, "Finish by pressing the final publish button only after the images and text are visible on screen.")
	}
	parts = append(parts, "Handle permission dialogs only when they unblock the publish flow.")
	if extra := strings.TrimSpace(task.Instruction); extra != "" {
		parts = append(parts, fmt.Sprintf("Additional user instruction: %s", extra))
	}
	return strings.Join(parts, " ")
}
