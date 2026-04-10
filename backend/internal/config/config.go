package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// Config holds all application configuration.
type Config struct {
	Server ServerConfig
	WDA    WDAConfig
	LLM    LLMConfig
	Agent  AgentConfig
}

// ServerConfig holds HTTP server settings.
type ServerConfig struct {
	Port int
}

// WDAConfig holds WebDriverAgent connection settings.
type WDAConfig struct {
	Host          string
	Port          int
	SIBPath       string
	IProxyPath    string
	ProjectPath   string
	WorkspacePath string
	RunnerScheme  string
	BundleID      string
}

// LLMConfig holds LLM provider settings.
type LLMConfig struct {
	OpenAIKey   string
	OpenAIModel string
	ClaudeKey   string
	ClaudeModel string
}

// AgentConfig holds agent loop settings.
type AgentConfig struct {
	MaxSteps          int
	ScreenshotQuality int // JPEG quality 1-100
}

// BaseURL returns the WDA base URL.
func (c WDAConfig) BaseURL() string {
	return fmt.Sprintf("http://%s:%d", c.Host, c.Port)
}

// Load reads configuration from environment variables.
func Load() *Config {
	return &Config{
		Server: ServerConfig{
			Port: getEnvInt("SERVER_PORT", 8080),
		},
		WDA: WDAConfig{
			Host:          getEnv("WDA_HOST", "localhost"),
			Port:          getEnvInt("WDA_PORT", 8100),
			SIBPath:       getEnv("SIB_PATH", ""),
			IProxyPath:    getEnv("IPROXY_PATH", ""),
			ProjectPath:   getEnv("WDA_XCODE_PROJECT_PATH", ""),
			WorkspacePath: getEnv("WDA_XCODE_WORKSPACE_PATH", defaultWorkspacePath()),
			RunnerScheme:  getEnv("WDA_RUNNER_SCHEME", "WebDriverAgentRunner"),
			BundleID:      getEnv("WDA_RUNNER_BUNDLE_ID", "com.vlogclaw.WebDriverAgentRunner"),
		},
		LLM: LLMConfig{
			OpenAIKey:   getEnv("OPENAI_API_KEY", ""),
			OpenAIModel: getEnv("OPENAI_MODEL", "gpt-4o"),
			ClaudeKey:   getEnv("CLAUDE_API_KEY", ""),
			ClaudeModel: getEnv("CLAUDE_MODEL", "claude-sonnet-4-20250514"),
		},
		Agent: AgentConfig{
			MaxSteps:          getEnvInt("AGENT_MAX_STEPS", 50),
			ScreenshotQuality: getEnvInt("AGENT_SCREENSHOT_QUALITY", 50),
		},
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getEnvInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if i, err := strconv.Atoi(v); err == nil {
			return i
		}
	}
	return fallback
}

func defaultWorkspacePath() string {
	cwd, err := os.Getwd()
	if err != nil {
		return ""
	}

	candidates := []string{
		filepath.Join(cwd, "VlogClawAgent", "VlogClawAgent.xcworkspace"),
		filepath.Join(cwd, "..", "VlogClawAgent", "VlogClawAgent.xcworkspace"),
	}
	for _, path := range candidates {
		clean := filepath.Clean(path)
		if strings.TrimSpace(clean) == "" {
			continue
		}
		if _, err := os.Stat(clean); err == nil {
			return clean
		}
	}
	return filepath.Clean(candidates[len(candidates)-1])
}
