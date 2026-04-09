package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// SetupRouter creates and configures the Gin router.
func SetupRouter(taskHandler *TaskHandler, deviceHandler *DeviceHandler) *gin.Engine {
	r := gin.Default()

	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	v1 := r.Group("/api/v1")
	{
		devices := v1.Group("/devices")
		{
			devices.GET("", deviceHandler.ListDevices)
			devices.GET("/:udid", deviceHandler.GetDevice)
			devices.POST("/:udid/connect", deviceHandler.ConnectDevice)
			devices.DELETE("/:udid/connect", deviceHandler.DisconnectDevice)
		}

		tasks := v1.Group("/tasks")
		{
			tasks.POST("", taskHandler.CreateTask)
			tasks.GET("", taskHandler.ListTasks)
			tasks.GET("/:id", taskHandler.GetTask)
		}

		workflows := v1.Group("/workflows")
		{
			xiaohongshu := workflows.Group("/xiaohongshu")
			{
				xiaohongshu.POST("/posts", taskHandler.CreateXiaohongshuPost)
			}
		}
	}

	return r
}
