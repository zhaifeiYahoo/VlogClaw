package handler

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"vlogclaw/internal/domain"
	"vlogclaw/internal/service"
)

// TaskHandler handles HTTP requests for automation tasks.
type TaskHandler struct {
	agent *service.AgentService
}

// NewTaskHandler creates a new task handler.
func NewTaskHandler(agent *service.AgentService) *TaskHandler {
	return &TaskHandler{agent: agent}
}

// CreateTask handles POST /api/v1/tasks
func (h *TaskHandler) CreateTask(c *gin.Context) {
	var req service.TaskRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, service.TaskResponse{
			Success: false,
			Error:   "invalid request: " + err.Error(),
		})
		return
	}

	maxSteps := req.MaxSteps
	if maxSteps <= 0 {
		maxSteps = 50
	}

	task := &domain.Task{
		ID:          uuid.New().String(),
		Instruction: req.Instruction,
		BundleID:    req.BundleID,
		Model:       req.Model,
		MaxSteps:    maxSteps,
		Status:      domain.TaskStatusPending,
		Steps:       []domain.Step{},
		CreatedAt:   time.Now(),
		UpdatedAt:   time.Now(),
	}

	// Run agent loop in background
	go func() {
		_ = h.agent.ExecuteTask(c.Request.Context(), task)
	}()

	c.JSON(http.StatusAccepted, service.TaskResponse{
		Success: true,
		Data:    task,
	})
}

// GetTask handles GET /api/v1/tasks/:id
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

// ListTasks handles GET /api/v1/tasks
func (h *TaskHandler) ListTasks(c *gin.Context) {
	tasks := h.agent.ListTasks()
	c.JSON(http.StatusOK, service.TaskResponse{Success: true, Data: tasks})
}
