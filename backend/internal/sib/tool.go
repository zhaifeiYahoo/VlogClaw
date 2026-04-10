package sib

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	// DefaultWDABundleID is the default runner bundle identifier used by this project.
	DefaultWDABundleID = "com.vlogclaw.WebDriverAgentRunner"

	wdaReadyMarker       = "ServerURLHere->"
	sibWDAStartTimeout   = 60 * time.Second
	xcodeWDAStartTimeout = 5 * time.Minute
	iproxySettleDelay    = 1 * time.Second
)

// DeviceDetail contains rich metadata returned by `sib devices -d`.
type DeviceDetail struct {
	DeviceName     string `json:"deviceName"`
	GenerationName string `json:"generationName"`
	ProductVersion string `json:"productVersion"`
	ProductType    string `json:"productType"`
	ProductName    string `json:"productName"`
	CPUArch        string `json:"cpuArchitecture"`
	DeviceClass    string `json:"deviceClass"`
	BuildVersion   string `json:"buildVersion"`
	TimeZone       string `json:"timeZone"`
	UniqueDeviceID string `json:"uniqueDeviceID"`
}

// DeviceEvent is one device entry from `sib devices -d`.
type DeviceEvent struct {
	Status       string       `json:"status"`
	SerialNumber string       `json:"serialNumber"`
	DeviceDetail DeviceDetail `json:"deviceDetail"`
}

// WDASession describes one started WDA process set for a device.
type WDASession struct {
	UDID      string
	WDAPort   int
	MJPEGPort int
	WDAURL    string

	processes []*exec.Cmd
}

// Stop kills all processes owned by the session.
func (s *WDASession) Stop() {
	for _, p := range s.processes {
		if p != nil && p.Process != nil {
			_ = p.Process.Kill()
		}
	}
}

type deviceListOutput struct {
	DeviceList []struct {
		SerialNumber string       `json:"serialNumber"`
		Status       string       `json:"status"`
		DeviceDetail DeviceDetail `json:"deviceDetail"`
	} `json:"deviceList"`
}

// ToolOption configures a Tool.
type ToolOption func(*Tool)

// WithWorkspacePath sets the Xcode workspace path used for iOS 17+ devices.
func WithWorkspacePath(path string) ToolOption {
	return func(t *Tool) {
		t.workspacePath = path
	}
}

// WithProjectPath sets the Xcode project path used for iOS 17+ devices.
func WithProjectPath(path string) ToolOption {
	return func(t *Tool) {
		t.projectPath = path
	}
}

// WithIProxyPath sets the iproxy binary path used for real-device port forwarding.
func WithIProxyPath(path string) ToolOption {
	return func(t *Tool) {
		t.iproxyPath = path
	}
}

// WithScheme sets the xcodebuild scheme used for iOS 17+ devices.
func WithScheme(scheme string) ToolOption {
	return func(t *Tool) {
		t.scheme = scheme
	}
}

// Tool wraps the sib binary and manages WDA processes per device.
type Tool struct {
	binaryPath    string
	iproxyPath    string
	projectPath   string
	workspacePath string
	scheme        string

	startWDAViaSibFn        func(ctx context.Context, udid, bundleID string, wdaPort, mjpegPort int) (*WDASession, error)
	startWDAViaXcodebuildFn func(ctx context.Context, udid, projectPath string, wdaPort, mjpegPort int) (*WDASession, error)

	mu       sync.Mutex
	sessions map[string]*WDASession
}

// NewTool creates a Tool.
func NewTool(binaryPath string, opts ...ToolOption) *Tool {
	t := &Tool{
		binaryPath:    binaryPath,
		iproxyPath:    os.Getenv("IPROXY_PATH"),
		projectPath:   os.Getenv("WDA_XCODE_PROJECT_PATH"),
		workspacePath: os.Getenv("WDA_XCODE_WORKSPACE_PATH"),
		scheme:        envOrDefault("WDA_RUNNER_SCHEME", "WebDriverAgentRunner"),
		sessions:      make(map[string]*WDASession),
	}
	for _, opt := range opts {
		opt(t)
	}
	t.startWDAViaSibFn = t.startWDAViaSib
	t.startWDAViaXcodebuildFn = t.startWDAViaXcodebuild
	return t
}

// BinaryPath returns the resolved sib path.
func (t *Tool) BinaryPath() string {
	return t.binaryPath
}

// IProxyPath returns the configured iproxy path.
func (t *Tool) IProxyPath() string {
	return t.iproxyPath
}

// ProjectPath returns the configured Xcode project path.
func (t *Tool) ProjectPath() string {
	return t.projectPath
}

// WorkspacePath returns the configured Xcode workspace path.
func (t *Tool) WorkspacePath() string {
	return t.workspacePath
}

// Scheme returns the configured Xcode scheme.
func (t *Tool) Scheme() string {
	return t.scheme
}

// ValidateStartConfig validates WDA startup prerequisites for the given iOS version.
func (t *Tool) ValidateStartConfig(productVersion, projectPath string) error {
	if !versionAtLeast(productVersion, 17, 0) {
		return nil
	}

	if resolvedProjectPath := strings.TrimSpace(projectPath); resolvedProjectPath != "" {
		_, err := t.resolveProjectPath(resolvedProjectPath)
		return err
	}

	if resolvedProjectPath := strings.TrimSpace(t.projectPath); resolvedProjectPath != "" {
		_, err := t.resolveProjectPath(resolvedProjectPath)
		return err
	}

	if strings.TrimSpace(t.workspacePath) == "" {
		return fmt.Errorf("missing WDA project/workspace path for iOS 17+ device; set WDA project path or run `cd VlogClawAgent && pod install` first")
	}
	if _, err := os.Stat(t.workspacePath); err != nil {
		return fmt.Errorf("WDA workspace not found at %s; run `cd VlogClawAgent && pod install` first", t.workspacePath)
	}
	return nil
}

// FindSib locates a sib binary on the host.
func FindSib() (string, error) {
	if envPath := os.Getenv("SIB_PATH"); strings.TrimSpace(envPath) != "" {
		if _, err := os.Stat(envPath); err == nil {
			return envPath, nil
		}
		return "", fmt.Errorf("SIB_PATH=%q does not exist", envPath)
	}

	exePath, _ := os.Executable()
	for _, path := range bundledSIBCandidates(exePath) {
		if _, err := os.Stat(path); err == nil {
			return path, nil
		}
	}

	for _, name := range []string{"sib", "sonic-ios-bridge"} {
		if path, err := exec.LookPath(name); err == nil {
			return path, nil
		}
	}

	var candidates []string
	switch runtime.GOOS {
	case "darwin":
		candidates = []string{"/opt/homebrew/bin/sib", "/usr/local/bin/sib"}
	case "linux":
		candidates = []string{"/usr/local/bin/sib", "/usr/bin/sib"}
	case "windows":
		candidates = []string{`C:\Program Files\sib\sib.exe`}
	}
	for _, path := range candidates {
		if _, err := os.Stat(path); err == nil {
			return path, nil
		}
	}
	return "", fmt.Errorf("sib (sonic-ios-bridge) binary not found")
}

func bundledSIBCandidates(exePath string) []string {
	candidates := make([]string, 0, 4)
	if trimmed := strings.TrimSpace(exePath); trimmed != "" {
		candidates = append(candidates, filepath.Join(filepath.Dir(trimmed), "plugins", "sonic-ios-bridge"))
	}

	if extra := strings.TrimSpace(os.Getenv("SIB_CANDIDATE_PATHS")); extra != "" {
		for _, candidate := range strings.Split(extra, string(os.PathListSeparator)) {
			candidate = strings.TrimSpace(candidate)
			if candidate != "" {
				candidates = append(candidates, candidate)
			}
		}
	}

	return candidates
}

// FindIProxy locates an iproxy binary on the host.
func FindIProxy() (string, error) {
	if envPath := os.Getenv("IPROXY_PATH"); strings.TrimSpace(envPath) != "" {
		if _, err := os.Stat(envPath); err == nil {
			return envPath, nil
		}
		return "", fmt.Errorf("IPROXY_PATH=%q does not exist", envPath)
	}

	exePath, _ := os.Executable()
	for _, path := range bundledIProxyCandidates(exePath) {
		if _, err := os.Stat(path); err == nil {
			return path, nil
		}
	}

	if path, err := exec.LookPath("iproxy"); err == nil {
		return path, nil
	}

	var candidates []string
	switch runtime.GOOS {
	case "darwin":
		candidates = []string{
			"/opt/homebrew/bin/iproxy",
			"/usr/local/bin/iproxy",
			"/opt/homebrew/opt/libimobiledevice/bin/iproxy",
			"/usr/local/opt/libimobiledevice/bin/iproxy",
			"/opt/homebrew/opt/libusbmuxd/bin/iproxy",
			"/usr/local/opt/libusbmuxd/bin/iproxy",
		}
	case "linux":
		candidates = []string{"/usr/local/bin/iproxy", "/usr/bin/iproxy"}
	}
	for _, path := range candidates {
		if _, err := os.Stat(path); err == nil {
			return path, nil
		}
	}
	return "", fmt.Errorf("iproxy binary not found")
}

func bundledIProxyCandidates(exePath string) []string {
	candidates := make([]string, 0, 4)
	if trimmed := strings.TrimSpace(exePath); trimmed != "" {
		candidates = append(candidates, filepath.Join(filepath.Dir(trimmed), "plugins", "iproxy"))
	}

	if extra := strings.TrimSpace(os.Getenv("IPROXY_CANDIDATE_PATHS")); extra != "" {
		for _, candidate := range strings.Split(extra, string(os.PathListSeparator)) {
			candidate = strings.TrimSpace(candidate)
			if candidate != "" {
				candidates = append(candidates, candidate)
			}
		}
	}

	return candidates
}

func (t *Tool) resolveIProxyPath() (string, error) {
	if configured := strings.TrimSpace(t.iproxyPath); configured != "" {
		if _, err := os.Stat(configured); err == nil {
			return configured, nil
		}
		return "", fmt.Errorf("configured iproxy path %q does not exist", configured)
	}

	path, err := FindIProxy()
	if err != nil {
		return "", fmt.Errorf("resolve iproxy: %w; set IPROXY_PATH or install libimobiledevice", err)
	}
	return path, nil
}

// GetDevices returns all online devices.
func (t *Tool) GetDevices() ([]DeviceEvent, error) {
	cmd := exec.Command(t.binaryPath, "devices", "-d")
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("sib devices: %w", err)
	}

	var result deviceListOutput
	if err := json.Unmarshal(out, &result); err != nil {
		return nil, fmt.Errorf("sib devices: parse output: %w", err)
	}

	events := make([]DeviceEvent, 0, len(result.DeviceList))
	for _, d := range result.DeviceList {
		if d.Status != "online" {
			continue
		}
		events = append(events, DeviceEvent{
			Status:       d.Status,
			SerialNumber: d.SerialNumber,
			DeviceDetail: d.DeviceDetail,
		})
	}
	return events, nil
}

// StartWDA starts WDA for the given device and records the session.
func (t *Tool) StartWDA(ctx context.Context, udid, productVersion, bundleID, projectPath string) (*WDASession, error) {
	if bundleID == "" {
		bundleID = DefaultWDABundleID
	}
	if err := t.ValidateStartConfig(productVersion, projectPath); err != nil {
		return nil, err
	}

	t.StopWDA(udid)

	wdaPort, err := findFreePort()
	if err != nil {
		return nil, fmt.Errorf("start WDA %s: %w", udid, err)
	}
	mjpegPort, err := findFreePort()
	if err != nil {
		return nil, fmt.Errorf("start WDA %s: %w", udid, err)
	}

	var session *WDASession
	if versionAtLeast(productVersion, 17, 0) {
		session, err = t.startWDAViaXcodebuildFn(ctx, udid, projectPath, wdaPort, mjpegPort)
	} else {
		session, err = t.startWDAViaSibFn(ctx, udid, bundleID, wdaPort, mjpegPort)
	}
	if err != nil {
		return nil, err
	}

	t.mu.Lock()
	t.sessions[udid] = session
	t.mu.Unlock()
	return session, nil
}

// StopWDA stops the session for one device.
func (t *Tool) StopWDA(udid string) {
	t.mu.Lock()
	session, ok := t.sessions[udid]
	delete(t.sessions, udid)
	t.mu.Unlock()
	if ok && session != nil {
		session.Stop()
	}
}

// GetSession returns the active session for one device.
func (t *Tool) GetSession(udid string) (*WDASession, bool) {
	t.mu.Lock()
	defer t.mu.Unlock()
	session, ok := t.sessions[udid]
	return session, ok
}

// StopAll stops every tracked WDA session.
func (t *Tool) StopAll() {
	t.mu.Lock()
	udids := make([]string, 0, len(t.sessions))
	for udid := range t.sessions {
		udids = append(udids, udid)
	}
	t.mu.Unlock()

	for _, udid := range udids {
		t.StopWDA(udid)
	}
}

func (t *Tool) startWDAViaSib(ctx context.Context, udid, bundleID string, wdaPort, mjpegPort int) (*WDASession, error) {
	cmd := exec.Command(
		t.binaryPath, "run", "wda",
		"-u", udid,
		"-b", bundleID,
		"--server-remote-port", "8100",
		"--mjpeg-remote-port", "9100",
		fmt.Sprintf("--server-local-port=%d", wdaPort),
		fmt.Sprintf("--mjpeg-local-port=%d", mjpegPort),
	)
	cmd.Stderr = os.Stderr

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, fmt.Errorf("start WDA via sib %s: stdout pipe: %w", udid, err)
	}
	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("start WDA via sib %s: start: %w", udid, err)
	}

	readyC := make(chan error, 1)
	go func() {
		scanner := bufio.NewScanner(stdout)
		signalled := false
		for scanner.Scan() {
			line := scanner.Text()
			log.Printf("[sib][wda][%s] %s", udid, line)
			if !signalled && strings.Contains(line, wdaReadyMarker) {
				signalled = true
				readyC <- nil
			}
		}
		if !signalled {
			readyC <- fmt.Errorf("sib run wda for %s exited before ready marker", udid)
		}
		_ = cmd.Wait()
	}()

	return waitForReady(ctx, udid, wdaPort, mjpegPort, sibWDAStartTimeout, readyC, []*exec.Cmd{cmd})
}

func (t *Tool) startWDAViaXcodebuild(ctx context.Context, udid, projectPath string, wdaPort, mjpegPort int) (*WDASession, error) {
	args := []string{"xcodebuild"}
	if resolvedProjectPath, err := t.resolveProjectPath(projectPath); err != nil {
		return nil, err
	} else if resolvedProjectPath != "" {
		args = append(args, "-project", resolvedProjectPath)
	} else {
		args = append(args, "-workspace", t.workspacePath)
	}
	args = append(
		args,
		"-scheme", t.scheme,
		"-destination", fmt.Sprintf("id=%s", udid),
		"test",
	)

	xcodecmd := exec.Command(args[0], args[1:]...)
	xcodecmd.Stderr = os.Stderr

	stdout, err := xcodecmd.StdoutPipe()
	if err != nil {
		return nil, fmt.Errorf("start WDA via xcodebuild %s: stdout pipe: %w", udid, err)
	}
	if err := xcodecmd.Start(); err != nil {
		return nil, fmt.Errorf("start WDA via xcodebuild %s: start: %w", udid, err)
	}

	readyC := make(chan error, 1)
	iproxyC := make(chan *exec.Cmd, 1)

	go func() {
		scanner := bufio.NewScanner(stdout)
		signalled := false
		for scanner.Scan() {
			line := scanner.Text()
			log.Printf("[sib][xcodebuild][%s] %s", udid, line)
			if signalled || !strings.Contains(line, wdaReadyMarker) {
				continue
			}
			signalled = true

			iproxyPath, err := t.resolveIProxyPath()
			if err != nil {
				iproxyC <- nil
				readyC <- fmt.Errorf("start iproxy for %s: %w", udid, err)
				return
			}

			iCmd := exec.Command(
				iproxyPath,
				"-u", udid,
				fmt.Sprintf("%d:8100", wdaPort),
				fmt.Sprintf("%d:9100", mjpegPort),
				"-s", "0.0.0.0",
			)
			iCmd.Stderr = os.Stderr
			if err := iCmd.Start(); err != nil {
				iproxyC <- nil
				readyC <- fmt.Errorf("start iproxy for %s: %w", udid, err)
				return
			}
			go func() {
				_ = iCmd.Wait()
			}()
			iproxyC <- iCmd
			time.Sleep(iproxySettleDelay)
			readyC <- nil
		}
		if !signalled {
			iproxyC <- nil
			readyC <- fmt.Errorf("xcodebuild for %s exited before ready marker", udid)
		}
		_ = xcodecmd.Wait()
	}()

	var iproxyCmd *exec.Cmd
	select {
	case iproxyCmd = <-iproxyC:
	case <-ctx.Done():
		if xcodecmd.Process != nil {
			_ = xcodecmd.Process.Kill()
		}
		return nil, fmt.Errorf("start WDA via xcodebuild %s: %w", udid, ctx.Err())
	}

	processes := []*exec.Cmd{xcodecmd}
	if iproxyCmd != nil {
		processes = append(processes, iproxyCmd)
	}
	return waitForReady(ctx, udid, wdaPort, mjpegPort, xcodeWDAStartTimeout, readyC, processes)
}

func (t *Tool) resolveProjectPath(projectPath string) (string, error) {
	candidate := strings.TrimSpace(projectPath)
	if candidate == "" {
		candidate = strings.TrimSpace(t.projectPath)
	}
	if candidate == "" {
		return "", nil
	}

	candidate = filepath.Clean(candidate)
	info, err := os.Stat(candidate)
	if err != nil {
		return "", fmt.Errorf("WDA project path not found at %s", candidate)
	}
	if !info.IsDir() {
		return "", fmt.Errorf("WDA project path must be a .xcodeproj bundle or a directory containing one: %s", candidate)
	}
	if strings.HasSuffix(candidate, ".xcodeproj") {
		return candidate, nil
	}

	matches, err := filepath.Glob(filepath.Join(candidate, "*.xcodeproj"))
	if err != nil {
		return "", fmt.Errorf("resolve WDA project path %s: %w", candidate, err)
	}
	switch len(matches) {
	case 0:
		return "", fmt.Errorf("no .xcodeproj found under %s", candidate)
	case 1:
		return filepath.Clean(matches[0]), nil
	default:
		return "", fmt.Errorf("multiple .xcodeproj bundles found under %s; choose one explicitly", candidate)
	}
}

func waitForReady(ctx context.Context, udid string, wdaPort, mjpegPort int, timeout time.Duration, readyC <-chan error, processes []*exec.Cmd) (*WDASession, error) {
	startCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	select {
	case err := <-readyC:
		if err != nil {
			for _, p := range processes {
				if p != nil && p.Process != nil {
					_ = p.Process.Kill()
				}
			}
			return nil, err
		}
	case <-startCtx.Done():
		for _, p := range processes {
			if p != nil && p.Process != nil {
				_ = p.Process.Kill()
			}
		}
		if ctx.Err() != nil {
			return nil, fmt.Errorf("WDA start for %s cancelled: %w", udid, ctx.Err())
		}
		return nil, fmt.Errorf("WDA start for %s timed out after %v", udid, timeout)
	}

	return &WDASession{
		UDID:      udid,
		WDAPort:   wdaPort,
		MJPEGPort: mjpegPort,
		WDAURL:    fmt.Sprintf("http://127.0.0.1:%d", wdaPort),
		processes: processes,
	}, nil
}

func findFreePort() (int, error) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, fmt.Errorf("find free TCP port: %w", err)
	}
	defer ln.Close()
	return ln.Addr().(*net.TCPAddr).Port, nil
}

func versionAtLeast(version string, major, minor int) bool {
	parts := strings.Split(strings.TrimSpace(version), ".")
	if len(parts) == 0 || parts[0] == "" {
		return false
	}
	gotMajor, err := strconv.Atoi(parts[0])
	if err != nil {
		return false
	}
	gotMinor := 0
	if len(parts) > 1 {
		gotMinor, err = strconv.Atoi(parts[1])
		if err != nil {
			return false
		}
	}
	if gotMajor != major {
		return gotMajor > major
	}
	return gotMinor >= minor
}

func envOrDefault(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}
