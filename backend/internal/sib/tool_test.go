package sib

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

func TestFindSibPrefersEnvOverride(t *testing.T) {
	dir := t.TempDir()
	binary := filepath.Join(dir, "sib")
	if err := os.WriteFile(binary, []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatalf("write binary: %v", err)
	}

	t.Setenv("SIB_PATH", binary)
	t.Setenv("PATH", "")

	got, err := FindSib()
	if err != nil {
		t.Fatalf("FindSib() error: %v", err)
	}
	if got != binary {
		t.Fatalf("got %q, want %q", got, binary)
	}
}

func TestFindSibFallsBackToCandidatePaths(t *testing.T) {
	dir := t.TempDir()
	binary := filepath.Join(dir, "sonic-ios-bridge")
	if err := os.WriteFile(binary, []byte("#!/bin/sh\nexit 0\n"), 0o755); err != nil {
		t.Fatalf("write binary: %v", err)
	}

	t.Setenv("SIB_PATH", "")
	t.Setenv("PATH", "")
	t.Setenv("SIB_CANDIDATE_PATHS", binary)

	got, err := FindSib()
	if err != nil {
		t.Fatalf("FindSib() error: %v", err)
	}
	if got != binary {
		t.Fatalf("got %q, want %q", got, binary)
	}
}

func TestGetDevicesParsesOnlineDevices(t *testing.T) {
	dir := t.TempDir()
	binary := filepath.Join(dir, "sib")
	script := `#!/bin/sh
if [ "$1" = "devices" ] && [ "$2" = "-d" ]; then
  printf '%s' '{"deviceList":[{"serialNumber":"udid-1","status":"online","deviceDetail":{"deviceName":"iPhone 1","productVersion":"16.7"}},{"serialNumber":"udid-2","status":"offline","deviceDetail":{"deviceName":"iPhone 2","productVersion":"17.4"}}]}'
  exit 0
fi
exit 1
`
	if err := os.WriteFile(binary, []byte(script), 0o755); err != nil {
		t.Fatalf("write binary: %v", err)
	}

	tool := NewTool(binary)
	devices, err := tool.GetDevices()
	if err != nil {
		t.Fatalf("GetDevices() error: %v", err)
	}
	if len(devices) != 1 {
		t.Fatalf("expected 1 online device, got %d", len(devices))
	}
	if devices[0].SerialNumber != "udid-1" {
		t.Fatalf("unexpected UDID %q", devices[0].SerialNumber)
	}
}

func TestStartWDAChoosesStartupPathByIOSVersion(t *testing.T) {
	tool := NewTool("/tmp/sib", WithWorkspacePath("/tmp/fake.xcworkspace"))

	var started string
	tool.startWDAViaSibFn = func(ctx context.Context, udid, bundleID string, wdaPort, mjpegPort int) (*WDASession, error) {
		started = "sib"
		return &WDASession{UDID: udid, WDAURL: "http://127.0.0.1:8100"}, nil
	}
	tool.startWDAViaXcodebuildFn = func(ctx context.Context, udid string, wdaPort, mjpegPort int) (*WDASession, error) {
		started = "xcodebuild"
		return &WDASession{UDID: udid, WDAURL: "http://127.0.0.1:8101"}, nil
	}

	if _, err := tool.StartWDA(context.Background(), "udid-16", "16.7", DefaultWDABundleID); err != nil {
		t.Fatalf("StartWDA(iOS 16) error: %v", err)
	}
	if started != "sib" {
		t.Fatalf("expected sib startup, got %q", started)
	}

	workspace := filepath.Join(t.TempDir(), "VlogClawAgent.xcworkspace")
	if err := os.WriteFile(workspace, []byte("dummy"), 0o644); err != nil {
		t.Fatalf("write workspace: %v", err)
	}
	tool.workspacePath = workspace

	if _, err := tool.StartWDA(context.Background(), "udid-17", "17.4", DefaultWDABundleID); err != nil {
		t.Fatalf("StartWDA(iOS 17) error: %v", err)
	}
	if started != "xcodebuild" {
		t.Fatalf("expected xcodebuild startup, got %q", started)
	}
}

func TestValidateStartConfigRequiresWorkspaceForIOS17(t *testing.T) {
	tool := NewTool("/tmp/sib")
	if err := tool.ValidateStartConfig("17.0"); err == nil {
		t.Fatal("expected validation error for missing workspace")
	}
}
