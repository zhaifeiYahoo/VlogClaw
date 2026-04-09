package handler

import (
	"context"
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"vlogclaw/internal/device"
)

type deviceHandlerService interface {
	ListDevices(ctx context.Context) ([]device.Info, error)
	GetDevice(ctx context.Context, udid string) (device.Info, error)
	ConnectDevice(ctx context.Context, udid string) error
	DisconnectDevice(udid string) error
}

// DeviceHandler handles device discovery and connection requests.
type DeviceHandler struct {
	devices deviceHandlerService
}

// NewDeviceHandler creates a new device handler.
func NewDeviceHandler(devices *device.Service) *DeviceHandler {
	return &DeviceHandler{devices: devices}
}

// ListDevices handles GET /api/v1/devices.
func (h *DeviceHandler) ListDevices(c *gin.Context) {
	devices, err := h.devices.ListDevices(c.Request.Context())
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "data": devices})
}

// GetDevice handles GET /api/v1/devices/:udid.
func (h *DeviceHandler) GetDevice(c *gin.Context) {
	deviceInfo, err := h.devices.GetDevice(c.Request.Context(), c.Param("udid"))
	if err != nil {
		if errors.Is(err, device.ErrDeviceNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "data": deviceInfo})
}

// ConnectDevice handles POST /api/v1/devices/:udid/connect.
func (h *DeviceHandler) ConnectDevice(c *gin.Context) {
	if err := h.devices.ConnectDevice(c.Request.Context(), c.Param("udid")); err != nil {
		switch {
		case errors.Is(err, device.ErrDeviceNotFound):
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": err.Error()})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		}
		return
	}
	c.JSON(http.StatusAccepted, gin.H{"success": true})
}

// DisconnectDevice handles DELETE /api/v1/devices/:udid/connect.
func (h *DeviceHandler) DisconnectDevice(c *gin.Context) {
	if err := h.devices.DisconnectDevice(c.Param("udid")); err != nil {
		if errors.Is(err, device.ErrDeviceNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"success": false, "error": err.Error()})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"success": false, "error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}
