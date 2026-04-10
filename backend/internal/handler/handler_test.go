package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"

	"vlogclaw/internal/device"
	"vlogclaw/internal/domain"
	"vlogclaw/internal/llm"
	"vlogclaw/internal/service"
	"vlogclaw/internal/wda"
)

type fakeDeviceHandlerService struct {
	listResponse  []device.Info
	getResponse   device.Info
	listErr       error
	getErr        error
	connectErr    error
	disconnectErr error
}

func (f *fakeDeviceHandlerService) ListDevices(ctx context.Context) ([]device.Info, error) {
	return f.listResponse, f.listErr
}

func (f *fakeDeviceHandlerService) GetDevice(ctx context.Context, udid string) (device.Info, error) {
	return f.getResponse, f.getErr
}

func (f *fakeDeviceHandlerService) ConnectDevice(ctx context.Context, udid string) error {
	return f.connectErr
}

func (f *fakeDeviceHandlerService) DisconnectDevice(udid string) error {
	return f.disconnectErr
}

type fakeConnectedRegistry struct {
	err error
}

func (f *fakeConnectedRegistry) GetConnectedDevice(udid string) (device.ConnectedDevice, error) {
	if f.err != nil {
		return device.ConnectedDevice{}, f.err
	}
	return device.ConnectedDevice{
		UDID:   udid,
		WDAURL: "http://127.0.0.1:8100",
	}, nil
}

type fakeProvider struct {
	release <-chan struct{}
}

type fakeCopywriter struct {
	resp *llm.XiaohongshuCopyResponse
	err  error
}

func (f *fakeCopywriter) GenerateXiaohongshuCopy(ctx context.Context, req llm.XiaohongshuCopyRequest) (*llm.XiaohongshuCopyResponse, error) {
	if f.err != nil {
		return nil, f.err
	}
	return f.resp, nil
}

func (p *fakeProvider) Analyze(ctx context.Context, req domain.LLMRequest) (*domain.LLMResponse, error) {
	if p.release != nil {
		select {
		case <-p.release:
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}
	return &domain.LLMResponse{Analysis: "done", Done: true}, nil
}

type fakeWDAClient struct{}

func (f *fakeWDAClient) Status(ctx context.Context) (*wda.StatusResponse, error) {
	return &wda.StatusResponse{Value: wda.StatusValue{Ready: true}}, nil
}
func (f *fakeWDAClient) CreateSession(ctx context.Context, deviceUDID string) error { return nil }
func (f *fakeWDAClient) Close(ctx context.Context) error                            { return nil }
func (f *fakeWDAClient) Screenshot(ctx context.Context) (string, error)             { return "img", nil }
func (f *fakeWDAClient) GetWindowSize(ctx context.Context) (domain.Size, error) {
	return domain.Size{Width: 100, Height: 200}, nil
}
func (f *fakeWDAClient) LaunchApp(ctx context.Context, bundleID string) error { return nil }
func (f *fakeWDAClient) ExecuteAction(ctx context.Context, action domain.Action) error {
	return nil
}

func TestDeviceRoutes(t *testing.T) {
	gin.SetMode(gin.TestMode)

	deviceSvc := &fakeDeviceHandlerService{
		listResponse: []device.Info{{UDID: "device-1", DeviceName: "iPhone", Status: device.StateConnected}},
		getResponse:  device.Info{UDID: "device-1", DeviceName: "iPhone", Status: device.StateConnected},
	}
	router := SetupRouter(
		NewTaskHandler(service.NewAgentService(&fakeConnectedRegistry{err: device.ErrDeviceNotConnected})),
		&DeviceHandler{devices: deviceSvc},
	)

	t.Run("list", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/api/v1/devices", nil)
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d", rec.Code)
		}
	})

	t.Run("connect", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodPost, "/api/v1/devices/device-1/connect", nil)
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, req)
		if rec.Code != http.StatusAccepted {
			t.Fatalf("expected 202, got %d", rec.Code)
		}
	})

	t.Run("disconnect", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodDelete, "/api/v1/devices/device-1/connect", nil)
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, req)
		if rec.Code != http.StatusOK {
			t.Fatalf("expected 200, got %d", rec.Code)
		}
	})
}

func TestTaskCreateRequiresDeviceUDID(t *testing.T) {
	gin.SetMode(gin.TestMode)

	agent := service.NewAgentService(&fakeConnectedRegistry{err: device.ErrDeviceNotConnected})
	router := SetupRouter(NewTaskHandler(agent), &DeviceHandler{devices: &fakeDeviceHandlerService{}})

	body := map[string]any{
		"model":       "openai",
		"instruction": "open app",
	}
	payload, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/tasks", bytes.NewReader(payload))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", rec.Code)
	}
}

func TestTaskCreateReturnsConflictWhenDeviceNotConnected(t *testing.T) {
	gin.SetMode(gin.TestMode)

	agent := service.NewAgentService(&fakeConnectedRegistry{err: device.ErrDeviceNotConnected})
	router := SetupRouter(NewTaskHandler(agent), &DeviceHandler{devices: &fakeDeviceHandlerService{}})

	body := map[string]any{
		"model":       "openai",
		"instruction": "open app",
		"device_udid": "device-1",
	}
	payload, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/tasks", bytes.NewReader(payload))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusConflict {
		t.Fatalf("expected 409, got %d", rec.Code)
	}
}

func TestTaskCreateRejectsConcurrentTaskOnSameDevice(t *testing.T) {
	gin.SetMode(gin.TestMode)

	release := make(chan struct{})
	agent := service.NewAgentService(&fakeConnectedRegistry{})
	agent.SetLLMFactory(func(model string) (llm.Provider, error) {
		return &fakeProvider{release: release}, nil
	})
	agent.SetWDAClientFactory(func(baseURL string) service.WDAClient {
		return &fakeWDAClient{}
	})

	router := SetupRouter(NewTaskHandler(agent), &DeviceHandler{devices: &fakeDeviceHandlerService{}})

	body := map[string]any{
		"model":       "openai",
		"instruction": "open app",
		"device_udid": "device-1",
	}
	payload, _ := json.Marshal(body)

	req1 := httptest.NewRequest(http.MethodPost, "/api/v1/tasks", bytes.NewReader(payload))
	req1.Header.Set("Content-Type", "application/json")
	rec1 := httptest.NewRecorder()
	router.ServeHTTP(rec1, req1)
	if rec1.Code != http.StatusAccepted {
		t.Fatalf("expected first request 202, got %d", rec1.Code)
	}

	req2 := httptest.NewRequest(http.MethodPost, "/api/v1/tasks", bytes.NewReader(payload))
	req2.Header.Set("Content-Type", "application/json")
	rec2 := httptest.NewRecorder()
	router.ServeHTTP(rec2, req2)
	if rec2.Code != http.StatusConflict {
		t.Fatalf("expected second request 409, got %d", rec2.Code)
	}

	close(release)
	time.Sleep(50 * time.Millisecond)
}

func TestDeviceGetReturnsNotFound(t *testing.T) {
	gin.SetMode(gin.TestMode)

	router := SetupRouter(
		NewTaskHandler(service.NewAgentService(&fakeConnectedRegistry{err: device.ErrDeviceNotConnected})),
		&DeviceHandler{devices: &fakeDeviceHandlerService{getErr: device.ErrDeviceNotFound}},
	)

	req := httptest.NewRequest(http.MethodGet, "/api/v1/devices/missing", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", rec.Code)
	}
}

func TestDeviceConnectFailureReturnsServerError(t *testing.T) {
	gin.SetMode(gin.TestMode)

	router := SetupRouter(
		NewTaskHandler(service.NewAgentService(&fakeConnectedRegistry{err: device.ErrDeviceNotConnected})),
		&DeviceHandler{devices: &fakeDeviceHandlerService{connectErr: errors.New("workspace missing")}},
	)

	req := httptest.NewRequest(http.MethodPost, "/api/v1/devices/device-1/connect", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500, got %d", rec.Code)
	}
}

func TestGenerateXiaohongshuCopy(t *testing.T) {
	gin.SetMode(gin.TestMode)

	taskHandler := NewTaskHandler(service.NewAgentService(&fakeConnectedRegistry{err: device.ErrDeviceNotConnected}))
	taskHandler.SetXiaohongshuCopywriter(&fakeCopywriter{
		resp: &llm.XiaohongshuCopyResponse{
			Title:              "春日轻通勤穿搭",
			Body:               "今天分享一套轻通勤穿搭，适合上班也适合下班后约会。",
			Hashtags:           []string{"#通勤穿搭", "#春日灵感"},
			ImageSelectionHint: "选择最近的三张穿搭近景照片",
		},
	})
	router := SetupRouter(taskHandler, &DeviceHandler{devices: &fakeDeviceHandlerService{}})

	body := map[string]any{
		"description": "帮我写一条春季通勤穿搭的小红书文案",
	}
	payload, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/workflows/xiaohongshu/copy", bytes.NewReader(payload))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()

	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}
}
