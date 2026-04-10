package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"vlogclaw/internal/config"
	"vlogclaw/internal/device"
	"vlogclaw/internal/handler"
	"vlogclaw/internal/llm"
	"vlogclaw/internal/service"
	"vlogclaw/internal/sib"
	"vlogclaw/internal/wda"
)

func main() {
	cfg := config.Load()

	// Setup structured logging
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	})))

	sibPath := cfg.WDA.SIBPath
	var deviceTool device.Tool
	if sibPath == "" {
		var err error
		sibPath, err = sib.FindSib()
		if err != nil {
			slog.Warn("sib unavailable, starting backend without device bridge", "error", err)
			deviceTool = &unavailableTool{err: err}
		}
	}

	if deviceTool == nil {
		deviceTool = sib.NewTool(
			sibPath,
			sib.WithWorkspacePath(cfg.WDA.WorkspacePath),
			sib.WithScheme(cfg.WDA.RunnerScheme),
		)
	}
	deviceService := device.NewService(deviceTool, cfg.WDA.BundleID)

	// Create agent service
	agent := service.NewAgentService(deviceService)
	agent.SetLLMFactory(func(model string) (llm.Provider, error) {
		return llm.NewProvider(cfg.LLM, model)
	})
	agent.SetWDAClientFactory(func(baseURL string) service.WDAClient {
		return wda.NewClient(baseURL)
	})

	// Setup HTTP server
	taskHandler := handler.NewTaskHandler(agent)
	taskHandler.SetXiaohongshuCopywriter(llm.NewOpenAIXiaohongshuCopywriter(cfg.LLM.OpenAIKey, cfg.LLM.OpenAIModel))
	deviceHandler := handler.NewDeviceHandler(deviceService)
	router := handler.SetupRouter(taskHandler, deviceHandler)

	srv := &http.Server{
		Addr:    fmt.Sprintf(":%d", cfg.Server.Port),
		Handler: router,
	}

	// Graceful shutdown
	go func() {
		slog.Info("server starting", "port", cfg.Server.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("server error", "error", err)
			os.Exit(1)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	slog.Info("shutting down...")
	ctx, cancel := context.WithTimeout(context.Background(), 30)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		slog.Error("forced shutdown", "error", err)
	}
	deviceService.StopAll()

	slog.Info("server stopped")
}

type unavailableTool struct {
	err error
}

func (t *unavailableTool) GetDevices() ([]sib.DeviceEvent, error) {
	return nil, fmt.Errorf("device bridge unavailable: %w", t.err)
}

func (t *unavailableTool) ValidateStartConfig(productVersion string) error {
	return fmt.Errorf("device bridge unavailable: %w", t.err)
}

func (t *unavailableTool) StartWDA(ctx context.Context, udid, productVersion, bundleID string) (*sib.WDASession, error) {
	return nil, fmt.Errorf("cannot start WDA: %w", t.err)
}

func (t *unavailableTool) StopWDA(udid string) {}

func (t *unavailableTool) StopAll() {}
