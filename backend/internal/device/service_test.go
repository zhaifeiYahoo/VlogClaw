package device

import (
	"context"
	"errors"
	"testing"
	"time"

	"vlogclaw/internal/sib"
)

type fakeTool struct {
	devices       []sib.DeviceEvent
	validateErr   error
	startErr      error
	startedUDIDs  []string
	stoppedUDIDs  []string
	sessionURL    string
	startedSignal chan struct{}
}

func (f *fakeTool) GetDevices() ([]sib.DeviceEvent, error) {
	return f.devices, nil
}

func (f *fakeTool) ValidateStartConfig(productVersion string) error {
	return f.validateErr
}

func (f *fakeTool) StartWDA(ctx context.Context, udid, productVersion, bundleID string) (*sib.WDASession, error) {
	f.startedUDIDs = append(f.startedUDIDs, udid)
	if f.startedSignal != nil {
		close(f.startedSignal)
	}
	if f.startErr != nil {
		return nil, f.startErr
	}
	return &sib.WDASession{
		UDID:   udid,
		WDAURL: f.sessionURL,
	}, nil
}

func (f *fakeTool) StopWDA(udid string) {
	f.stoppedUDIDs = append(f.stoppedUDIDs, udid)
}

func (f *fakeTool) StopAll() {}

func TestConnectDeviceTransitionsToConnected(t *testing.T) {
	tool := &fakeTool{
		devices: []sib.DeviceEvent{
			{
				SerialNumber: "device-1",
				DeviceDetail: sib.DeviceDetail{
					DeviceName:     "My iPhone",
					ProductVersion: "17.4",
				},
			},
		},
		sessionURL:    "http://127.0.0.1:8100",
		startedSignal: make(chan struct{}),
	}
	service := NewService(tool, sib.DefaultWDABundleID)

	if err := service.ConnectDevice(context.Background(), "device-1"); err != nil {
		t.Fatalf("ConnectDevice() error: %v", err)
	}

	select {
	case <-tool.startedSignal:
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for StartWDA")
	}

	info, err := service.GetDevice(context.Background(), "device-1")
	if err != nil {
		t.Fatalf("GetDevice() error: %v", err)
	}
	if info.Status != StateConnected {
		t.Fatalf("expected connected state, got %q", info.Status)
	}
	if info.WDAURL != "http://127.0.0.1:8100" {
		t.Fatalf("unexpected WDA URL %q", info.WDAURL)
	}
}

func TestConnectDeviceStoresErrorState(t *testing.T) {
	tool := &fakeTool{
		devices: []sib.DeviceEvent{
			{
				SerialNumber: "device-1",
				DeviceDetail: sib.DeviceDetail{
					DeviceName:     "My iPhone",
					ProductVersion: "16.7",
				},
			},
		},
		startErr:      errors.New("boom"),
		startedSignal: make(chan struct{}),
	}
	service := NewService(tool, sib.DefaultWDABundleID)

	if err := service.ConnectDevice(context.Background(), "device-1"); err != nil {
		t.Fatalf("ConnectDevice() error: %v", err)
	}

	select {
	case <-tool.startedSignal:
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for StartWDA")
	}

	info, err := service.GetDevice(context.Background(), "device-1")
	if err != nil {
		t.Fatalf("GetDevice() error: %v", err)
	}
	if info.Status != StateError {
		t.Fatalf("expected error state, got %q", info.Status)
	}
	if info.LastError == "" {
		t.Fatal("expected last error to be populated")
	}
}

func TestListDevicesPrunesOfflineConnectedSession(t *testing.T) {
	tool := &fakeTool{
		devices: []sib.DeviceEvent{
			{
				SerialNumber: "device-1",
				DeviceDetail: sib.DeviceDetail{
					DeviceName:     "Still Online",
					ProductVersion: "17.0",
				},
			},
		},
	}
	service := NewService(tool, sib.DefaultWDABundleID)
	service.entries["device-2"] = &entry{
		detail: sib.DeviceDetail{
			DeviceName:     "Offline",
			ProductVersion: "17.0",
		},
		state: StateConnected,
		session: &sib.WDASession{
			UDID:   "device-2",
			WDAURL: "http://127.0.0.1:8102",
		},
	}

	devices, err := service.ListDevices(context.Background())
	if err != nil {
		t.Fatalf("ListDevices() error: %v", err)
	}
	if len(devices) != 1 {
		t.Fatalf("expected 1 online device, got %d", len(devices))
	}
	if len(tool.stoppedUDIDs) != 1 || tool.stoppedUDIDs[0] != "device-2" {
		t.Fatalf("unexpected stopped devices: %v", tool.stoppedUDIDs)
	}
}

func TestDisconnectDeviceStopsSession(t *testing.T) {
	tool := &fakeTool{}
	service := NewService(tool, sib.DefaultWDABundleID)
	service.entries["device-1"] = &entry{
		state: StateConnected,
		session: &sib.WDASession{
			UDID:   "device-1",
			WDAURL: "http://127.0.0.1:8100",
		},
	}

	if err := service.DisconnectDevice("device-1"); err != nil {
		t.Fatalf("DisconnectDevice() error: %v", err)
	}
	if len(tool.stoppedUDIDs) != 1 || tool.stoppedUDIDs[0] != "device-1" {
		t.Fatalf("unexpected stopped devices: %v", tool.stoppedUDIDs)
	}
}
