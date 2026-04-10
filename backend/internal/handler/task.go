package handler

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"vlogclaw/internal/device"
	"vlogclaw/internal/domain"
	"vlogclaw/internal/llm"
	"vlogclaw/internal/service"
)

// TaskHandler handles HTTP requests for automation tasks.
type TaskHandler struct {
	agent      *service.AgentService
	copywriter xiaohongshuCopywriter
}

type xiaohongshuCopywriter interface {
	GenerateXiaohongshuCopy(ctx context.Context, req llm.XiaohongshuCopyRequest) (*llm.XiaohongshuCopyResponse, error)
}

// NewTaskHandler creates a new task handler.
func NewTaskHandler(agent *service.AgentService) *TaskHandler {
	return &TaskHandler{agent: agent}
}

// SetXiaohongshuCopywriter wires the optional copy generation dependency.
func (h *TaskHandler) SetXiaohongshuCopywriter(copywriter xiaohongshuCopywriter) {
	h.copywriter = copywriter
}

// CreateTask handles POST /api/v1/tasks.
func (h *TaskHandler) CreateTask(c *gin.Context) {
	var req service.TaskRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, service.TaskResponse{
			Success: false,
			Error:   "invalid request: " + err.Error(),
		})
		return
	}

	task, err := buildTask(req)
	if err != nil {
		c.JSON(http.StatusBadRequest, service.TaskResponse{
			Success: false,
			Error:   err.Error(),
		})
		return
	}

	if err := h.agent.StartTask(task); err != nil {
		writeTaskStartError(c, err)
		return
	}

	c.JSON(http.StatusAccepted, service.TaskResponse{
		Success: true,
		Data:    task,
	})
}

// CreateXiaohongshuPost handles POST /api/v1/workflows/xiaohongshu/posts.
func (h *TaskHandler) CreateXiaohongshuPost(c *gin.Context) {
	var req service.TaskRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, service.TaskResponse{
			Success: false,
			Error:   "invalid request: " + err.Error(),
		})
		return
	}
	req.Workflow = domain.WorkflowXiaohongshuPost

	task, err := buildTask(req)
	if err != nil {
		c.JSON(http.StatusBadRequest, service.TaskResponse{
			Success: false,
			Error:   err.Error(),
		})
		return
	}

	if err := h.agent.StartTask(task); err != nil {
		writeTaskStartError(c, err)
		return
	}

	c.JSON(http.StatusAccepted, service.TaskResponse{
		Success: true,
		Data:    task,
	})
}

// GenerateXiaohongshuCopy handles POST /api/v1/workflows/xiaohongshu/copy.
func (h *TaskHandler) GenerateXiaohongshuCopy(c *gin.Context) {
	if h.copywriter == nil {
		c.JSON(http.StatusServiceUnavailable, service.TaskResponse{
			Success: false,
			Error:   "xiaohongshu copywriter is not configured",
		})
		return
	}

	var req llm.XiaohongshuCopyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, service.TaskResponse{
			Success: false,
			Error:   "invalid request: " + err.Error(),
		})
		return
	}
	if strings.TrimSpace(req.Description) == "" && len(req.ImageDataURLs) == 0 {
		c.JSON(http.StatusBadRequest, service.TaskResponse{
			Success: false,
			Error:   "description or image_data_urls is required",
		})
		return
	}

	copyResp, err := h.copywriter.GenerateXiaohongshuCopy(c.Request.Context(), req)
	if err != nil {
		c.JSON(http.StatusBadGateway, service.TaskResponse{
			Success: false,
			Error:   err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, service.TaskResponse{
		Success: true,
		Data:    copyResp,
	})
}

// GetTask handles GET /api/v1/tasks/:id.
func (h *TaskHandler) GetTask(c *gin.Context) {
	id := c.Param("id")
	task, ok := h.agent.GetTask(id)
	if !ok {
		c.JSON(http.StatusNotFound, service.TaskResponse{
			Success: false,
			Error:   "task not found",
		})
		return
	}
	c.JSON(http.StatusOK, service.TaskResponse{Success: true, Data: task})
}

// ListTasks handles GET /api/v1/tasks.
func (h *TaskHandler) ListTasks(c *gin.Context) {
	tasks := h.agent.ListTasks()
	c.JSON(http.StatusOK, service.TaskResponse{Success: true, Data: tasks})
}

func buildTask(req service.TaskRequest) (*domain.Task, error) {
	model := strings.TrimSpace(req.Model)
	if model == "" {
		return nil, errResponse("model is required")
	}

	deviceUDID := strings.TrimSpace(req.DeviceUDID)
	if deviceUDID == "" {
		return nil, errResponse("device_udid is required")
	}

	workflow := strings.TrimSpace(req.Workflow)
	instruction := strings.TrimSpace(req.Instruction)
	if workflow == "" && instruction == "" {
		return nil, errResponse("instruction is required when workflow is empty")
	}

	bundleID := strings.TrimSpace(req.BundleID)
	imageCount := req.ImageCount
	publishMode := strings.ToLower(strings.TrimSpace(req.PublishMode))
	if publishMode == "" {
		publishMode = domain.PublishModePublish
	}
	if publishMode != domain.PublishModePublish && publishMode != domain.PublishModeDraft {
		return nil, errResponse("publish_mode must be either 'publish' or 'draft'")
	}

	hasCustomMaxSteps := req.MaxSteps > 0
	maxSteps := req.MaxSteps
	if maxSteps <= 0 {
		maxSteps = 50
	}

	if workflow == domain.WorkflowXiaohongshuPost {
		if bundleID == "" {
			bundleID = "com.xingin.discover"
		}
		if imageCount <= 0 {
			imageCount = 1
		}
		if !hasCustomMaxSteps {
			maxSteps = 60
		}
	}

	now := time.Now()
	return &domain.Task{
		ID:          uuid.New().String(),
		Instruction: instruction,
		DeviceUDID:  deviceUDID,
		BundleID:    bundleID,
		Workflow:    workflow,
		Model:       model,
		MaxSteps:    maxSteps,
		Title:       req.Title,
		Body:        req.Body,
		ImageCount:  imageCount,
		ImageHint:   strings.TrimSpace(req.ImageHint),
		PublishMode: publishMode,
		Status:      domain.TaskStatusPending,
		Steps:       []domain.Step{},
		CreatedAt:   now,
		UpdatedAt:   now,
	}, nil
}

func writeTaskStartError(c *gin.Context, err error) {
	statusCode := http.StatusInternalServerError
	switch {
	case errors.Is(err, device.ErrDeviceNotConnected), errors.Is(err, service.ErrDeviceBusy):
		statusCode = http.StatusConflict
	case errors.Is(err, device.ErrDeviceNotFound):
		statusCode = http.StatusNotFound
	}

	c.JSON(statusCode, service.TaskResponse{
		Success: false,
		Error:   err.Error(),
	})
}

func errResponse(message string) error {
	return &taskValidationError{message: message}
}

type taskValidationError struct {
	message string
}

func (e *taskValidationError) Error() string {
	return e.message
}
