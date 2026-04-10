package device

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"sort"
	"strings"
	"sync"
	"time"

	"vlogclaw/internal/sib"
)

var (
	// ErrDeviceNotFound is returned when the requested device is not online.
	ErrDeviceNotFound = errors.New("device not found")
	// ErrDeviceNotConnected is returned when a task targets a device without an active WDA connection.
	ErrDeviceNotConnected = errors.New("device not connected")
)

// ConnectionState is the public device connection state.
type ConnectionState string

const (
	StateDisconnected ConnectionState = "disconnected"
	StateConnecting   ConnectionState = "connecting"
	StateConnected    ConnectionState = "connected"
	StateError        ConnectionState = "error"
)

// Tool is the subset of sib.Tool used by the device service.
type Tool interface {
	GetDevices() ([]sib.DeviceEvent, error)
	ValidateStartConfig(productVersion, projectPath string) error
	StartWDA(ctx context.Context, udid, productVersion, bundleID, projectPath string) (*sib.WDASession, error)
	StopWDA(udid string)
	StopAll()
}

// Info is the public device view returned by the API.
type Info struct {
	UDID           string          `json:"udid"`
	DeviceName     string          `json:"device_name"`
	GenerationName string          `json:"generation_name,omitempty"`
	ProductVersion string          `json:"product_version,omitempty"`
	ProductType    string          `json:"product_type,omitempty"`
	Status         ConnectionState `json:"status"`
	WDAURL         string          `json:"wda_url,omitempty"`
	MJPEGPort      int             `json:"mjpeg_port,omitempty"`
	MJPEGURL       string          `json:"mjpeg_url,omitempty"`
	LastError      string          `json:"last_error,omitempty"`
	UpdatedAt      time.Time       `json:"updated_at,omitempty"`
}

// ConnectedDevice is the internal connection data needed by task execution.
type ConnectedDevice struct {
	UDID   string
	WDAURL string
}

type entry struct {
	detail    sib.DeviceDetail
	state     ConnectionState
	session   *sib.WDASession
	lastError string
	updatedAt time.Time
}

// Service owns device connection state and WDA lifecycle.
type Service struct {
	tool     Tool
	bundleID string

	mu      sync.RWMutex
	entries map[string]*entry
}

// NewService creates a new device service.
func NewService(tool Tool, bundleID string) *Service {
	if strings.TrimSpace(bundleID) == "" {
		bundleID = sib.DefaultWDABundleID
	}
	return &Service{
		tool:     tool,
		bundleID: bundleID,
		entries:  make(map[string]*entry),
	}
}

// ListDevices returns online devices merged with connection state.
func (s *Service) ListDevices(ctx context.Context) ([]Info, error) {
	online, err := s.tool.GetDevices()
	if err != nil {
		return nil, err
	}

	onlineMap := make(map[string]sib.DeviceDetail, len(online))
	for _, dev := range online {
		onlineMap[dev.SerialNumber] = dev.DeviceDetail
	}

	s.mu.Lock()
	now := time.Now()
	for udid, item := range s.entries {
		if _, ok := onlineMap[udid]; ok {
			continue
		}
		if item.session != nil {
			s.tool.StopWDA(udid)
			item.session = nil
		}
		if item.state == StateConnected || item.state == StateConnecting {
			item.state = StateDisconnected
			item.lastError = "device offline"
			item.updatedAt = now
		}
	}

	infos := make([]Info, 0, len(online))
	for _, dev := range online {
		item := s.ensureEntryLocked(dev.SerialNumber)
		item.detail = dev.DeviceDetail
		if item.state == "" {
			item.state = StateDisconnected
			item.updatedAt = now
		}
		infos = append(infos, infoFromEntry(dev.SerialNumber, item))
	}
	s.mu.Unlock()

	sort.Slice(infos, func(i, j int) bool {
		if infos[i].DeviceName == infos[j].DeviceName {
			return infos[i].UDID < infos[j].UDID
		}
		return infos[i].DeviceName < infos[j].DeviceName
	})
	return infos, nil
}

// GetDevice returns one device, including last known state if it is offline.
func (s *Service) GetDevice(ctx context.Context, udid string) (Info, error) {
	if _, err := s.ListDevices(ctx); err != nil {
		return Info{}, err
	}

	s.mu.RLock()
	defer s.mu.RUnlock()
	item, ok := s.entries[udid]
	if !ok {
		return Info{}, ErrDeviceNotFound
	}
	return infoFromEntry(udid, item), nil
}

// ConnectDevice marks the device as connecting and starts WDA asynchronously.
func (s *Service) ConnectDevice(ctx context.Context, udid, projectPath, bundleID string) error {
	devices, err := s.tool.GetDevices()
	if err != nil {
		return err
	}

	var detail sib.DeviceDetail
	found := false
	for _, dev := range devices {
		if dev.SerialNumber == udid {
			detail = dev.DeviceDetail
			found = true
			break
		}
	}
	if !found {
		return ErrDeviceNotFound
	}
	if err := s.tool.ValidateStartConfig(detail.ProductVersion, projectPath); err != nil {
		return err
	}

	s.mu.Lock()
	item := s.ensureEntryLocked(udid)
	item.detail = detail
	if item.state == StateConnected || item.state == StateConnecting {
		s.mu.Unlock()
		return nil
	}
	item.state = StateConnecting
	item.session = nil
	item.lastError = ""
	item.updatedAt = time.Now()
	s.mu.Unlock()

	slog.Info("device connect requested",
		"phase", "connect_requested",
		"udid", udid,
		"device_name", detail.DeviceName,
		"product_version", detail.ProductVersion)

	go s.connect(udid, detail, projectPath, bundleID)
	return nil
}

// DisconnectDevice stops WDA and marks the device disconnected.
func (s *Service) DisconnectDevice(udid string) error {
	s.mu.Lock()
	item, ok := s.entries[udid]
	if !ok {
		s.mu.Unlock()
		return ErrDeviceNotFound
	}
	item.state = StateDisconnected
	item.session = nil
	item.lastError = ""
	item.updatedAt = time.Now()
	s.mu.Unlock()

	s.tool.StopWDA(udid)
	return nil
}

// GetConnectedDevice returns the WDA endpoint for task execution.
func (s *Service) GetConnectedDevice(udid string) (ConnectedDevice, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	item, ok := s.entries[udid]
	if !ok || item.state != StateConnected || item.session == nil {
		return ConnectedDevice{}, ErrDeviceNotConnected
	}
	return ConnectedDevice{
		UDID:   udid,
		WDAURL: item.session.WDAURL,
	}, nil
}

// StopAll stops all WDA processes managed by the service.
func (s *Service) StopAll() {
	s.tool.StopAll()

	s.mu.Lock()
	defer s.mu.Unlock()
	now := time.Now()
	for _, item := range s.entries {
		item.state = StateDisconnected
		item.session = nil
		item.updatedAt = now
	}
}

func (s *Service) connect(udid string, detail sib.DeviceDetail, projectPath, bundleID string) {
	resolvedBundleID := strings.TrimSpace(bundleID)
	if resolvedBundleID == "" {
		resolvedBundleID = s.bundleID
	}

	slog.Info("starting WDA for device",
		"phase", "start_wda",
		"udid", udid,
		"device_name", detail.DeviceName,
		"product_version", detail.ProductVersion,
		"project_path", strings.TrimSpace(projectPath),
		"bundle_id", resolvedBundleID)

	session, err := s.tool.StartWDA(context.Background(), udid, detail.ProductVersion, resolvedBundleID, projectPath)

	s.mu.Lock()
	defer s.mu.Unlock()

	item := s.ensureEntryLocked(udid)
	item.detail = detail
	item.updatedAt = time.Now()

	if err != nil {
		item.state = StateError
		item.session = nil
		item.lastError = err.Error()
		slog.Error("device connect failed",
			"phase", "connect_failed",
			"udid", udid,
			"device_name", detail.DeviceName,
			"error", err)
		return
	}

	item.state = StateConnected
	item.session = session
	item.lastError = ""
	slog.Info("device connected",
		"phase", "connected",
		"udid", udid,
		"device_name", detail.DeviceName,
		"wda_url", session.WDAURL)
}

func (s *Service) ensureEntryLocked(udid string) *entry {
	item, ok := s.entries[udid]
	if !ok {
		item = &entry{
			state:     StateDisconnected,
			updatedAt: time.Now(),
		}
		s.entries[udid] = item
	}
	return item
}

func infoFromEntry(udid string, item *entry) Info {
	info := Info{
		UDID:           udid,
		DeviceName:     item.detail.DeviceName,
		GenerationName: item.detail.GenerationName,
		ProductVersion: item.detail.ProductVersion,
		ProductType:    item.detail.ProductType,
		Status:         item.state,
		LastError:      item.lastError,
		UpdatedAt:      item.updatedAt,
	}
	if item.session != nil {
		info.WDAURL = item.session.WDAURL
		info.MJPEGPort = item.session.MJPEGPort
		if item.session.MJPEGPort > 0 {
			info.MJPEGURL = fmt.Sprintf("http://127.0.0.1:%d", item.session.MJPEGPort)
		}
	}
	return info
}
