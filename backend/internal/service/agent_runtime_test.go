package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"vlogclaw/internal/device"
	"vlogclaw/internal/domain"
	"vlogclaw/internal/llm"
	"vlogclaw/internal/wda"
)

type fakeDeviceRegistry struct {
	connected device.ConnectedDevice
	err       error
}

func (f *fakeDeviceRegistry) GetConnectedDevice(udid string) (device.ConnectedDevice, error) {
	if f.err != nil {
		return device.ConnectedDevice{}, f.err
	}
	return f.connected, nil
}

type blockingProvider struct {
	release <-chan struct{}
}

func (p *blockingProvider) Analyze(ctx context.Context, req domain.LLMRequest) (*domain.LLMResponse, error) {
	if p.release != nil {
		select {
		case <-p.release:
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}
	return &domain.LLMResponse{
		Analysis: "done",
		Done:     true,
	}, nil
}

type fakeWDAClient struct{}

func (f *fakeWDAClient) Status(ctx context.Context) (*wda.StatusResponse, error) {
	return &wda.StatusResponse{
		Value: wda.StatusValue{Ready: true},
	}, nil
}

func (f *fakeWDAClient) CreateSession(ctx context.Context, deviceUDID string) error { return nil }
func (f *fakeWDAClient) Close(ctx context.Context) error                            { return nil }
func (f *fakeWDAClient) Screenshot(ctx context.Context) (string, error)             { return "base64", nil }
func (f *fakeWDAClient) GetWindowSize(ctx context.Context) (domain.Size, error) {
	return domain.Size{Width: 100, Height: 200}, nil
}
func (f *fakeWDAClient) LaunchApp(ctx context.Context, bundleID string) error { return nil }
func (f *fakeWDAClient) ExecuteAction(ctx context.Context, action domain.Action) error {
	return nil
}

func TestStartTaskRejectsUnconnectedDevice(t *testing.T) {
	svc := NewAgentService(&fakeDeviceRegistry{err: device.ErrDeviceNotConnected})

	err := svc.StartTask(&domain.Task{
		ID:         "task-1",
		DeviceUDID: "device-1",
		Model:      "openai",
	})
	if !errors.Is(err, device.ErrDeviceNotConnected) {
		t.Fatalf("expected ErrDeviceNotConnected, got %v", err)
	}
}

func TestStartTaskRejectsBusyDevice(t *testing.T) {
	release := make(chan struct{})
	svc := NewAgentService(&fakeDeviceRegistry{
		connected: device.ConnectedDevice{UDID: "device-1", WDAURL: "http://127.0.0.1:8100"},
	})
	svc.SetLLMFactory(func(model string) (llm.Provider, error) {
		return &blockingProvider{release: release}, nil
	})
	svc.SetWDAClientFactory(func(baseURL string) WDAClient {
		return &fakeWDAClient{}
	})

	task1 := &domain.Task{
		ID:         "task-1",
		DeviceUDID: "device-1",
		Model:      "openai",
		MaxSteps:   1,
		Workflow:   domain.WorkflowXiaohongshuPost,
		BundleID:   "com.xingin.discover",
	}
	task2 := &domain.Task{
		ID:          "task-2",
		DeviceUDID:  "device-1",
		Model:       "openai",
		MaxSteps:    1,
		Instruction: "do something",
	}

	if err := svc.StartTask(task1); err != nil {
		t.Fatalf("StartTask(task1) error: %v", err)
	}

	err := svc.StartTask(task2)
	if !errors.Is(err, ErrDeviceBusy) {
		t.Fatalf("expected ErrDeviceBusy, got %v", err)
	}

	close(release)
	time.Sleep(50 * time.Millisecond)
}
