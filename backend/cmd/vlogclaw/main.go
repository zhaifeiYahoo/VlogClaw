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
	"vlogclaw/internal/handler"
	"vlogclaw/internal/llm"
	"vlogclaw/internal/service"
	"vlogclaw/internal/wda"
)

func main() {
	cfg := config.Load()

	// Setup structured logging
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	})))

	// Create WDA client
	wdaClient := wda.NewClient(cfg.WDA.BaseURL())

	// Create agent service
	agent := service.NewAgentService(wdaClient)
	agent.SetLLMFactory(func(model string) (llm.Provider, error) {
		return llm.NewProvider(cfg.LLM, model)
	})

	// Setup HTTP server
	taskHandler := handler.NewTaskHandler(agent)
	router := handler.SetupRouter(taskHandler)

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

	slog.Info("server stopped")
}
