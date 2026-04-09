package wda

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func testCtx(t *testing.T) context.Context {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	t.Cleanup(cancel)
	return ctx
}

func TestStatus(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/status" || r.Method != http.MethodGet {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"value": map[string]any{
				"ready":    true,
				"message":  "ready",
				"platform": "iOS",
			},
		})
	}))
	defer srv.Close()

	resp, err := NewClient(srv.URL).Status(testCtx(t))
	if err != nil {
		t.Fatalf("Status() error: %v", err)
	}
	if !resp.Value.Ready {
		t.Fatalf("expected ready=true")
	}
}

func TestCreateSessionLegacyAndW3C(t *testing.T) {
	t.Run("legacy", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Path != "/session" {
				w.WriteHeader(http.StatusNotFound)
				return
			}
			_ = json.NewEncoder(w).Encode(map[string]any{
				"sessionId": "legacy-session",
				"value":     map[string]any{},
			})
		}))
		defer srv.Close()

		client := NewClient(srv.URL)
		if err := client.CreateSession(testCtx(t), "UDID-1"); err != nil {
			t.Fatalf("CreateSession() error: %v", err)
		}
		if client.SessionID() != "legacy-session" {
			t.Fatalf("got session id %q", client.SessionID())
		}
	})

	t.Run("w3c", func(t *testing.T) {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			_ = json.NewEncoder(w).Encode(map[string]any{
				"value": map[string]any{
					"sessionId": "w3c-session",
				},
			})
		}))
		defer srv.Close()

		client := NewClient(srv.URL)
		if err := client.CreateSession(testCtx(t), ""); err != nil {
			t.Fatalf("CreateSession() error: %v", err)
		}
		if client.SessionID() != "w3c-session" {
			t.Fatalf("got session id %q", client.SessionID())
		}
	})
}

func TestCreateSessionRejectsEmptySessionID(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{
			"value": map[string]any{},
		})
	}))
	defer srv.Close()

	client := NewClient(srv.URL)
	if err := client.CreateSession(testCtx(t), ""); err == nil {
		t.Fatal("expected error for empty session id")
	}
}

func TestSessionScopedCommandsUseSessionPath(t *testing.T) {
	var seen []string

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seen = append(seen, r.Method+" "+r.URL.Path)
		switch r.URL.Path {
		case "/session/test-session/screenshot":
			_ = json.NewEncoder(w).Encode(map[string]any{"value": "base64-image"})
		case "/session/test-session/wda/tap":
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(`{}`))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer srv.Close()

	client := NewClient(srv.URL)
	client.sessionID = "test-session"

	if _, err := client.Screenshot(testCtx(t)); err != nil {
		t.Fatalf("Screenshot() error: %v", err)
	}
	if err := client.Tap(testCtx(t), 10, 20); err != nil {
		t.Fatalf("Tap() error: %v", err)
	}

	if len(seen) != 2 {
		t.Fatalf("expected 2 requests, got %d", len(seen))
	}
}

func TestCloseDeletesSession(t *testing.T) {
	var seenPath string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seenPath = r.URL.Path
		if r.Method != http.MethodDelete {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{}`))
	}))
	defer srv.Close()

	client := NewClient(srv.URL)
	client.sessionID = "abc123"
	if err := client.Close(testCtx(t)); err != nil {
		t.Fatalf("Close() error: %v", err)
	}
	if seenPath != "/session/abc123" {
		t.Fatalf("unexpected path %q", seenPath)
	}
	if client.SessionID() != "" {
		t.Fatalf("expected session to be cleared")
	}
}

func TestLaunchAppFallsBackToAttachedRoute(t *testing.T) {
	var seen []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seen = append(seen, r.URL.Path)
		if strings.HasSuffix(r.URL.Path, "launchUnattached") {
			w.WriteHeader(http.StatusInternalServerError)
			_, _ = w.Write([]byte(`{"value":"failed"}`))
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{}`))
	}))
	defer srv.Close()

	client := NewClient(srv.URL)
	if err := client.LaunchApp(testCtx(t), "com.example.app"); err != nil {
		t.Fatalf("LaunchApp() error: %v", err)
	}

	if len(seen) != 2 || seen[0] != "/wda/apps/launchUnattached" || seen[1] != "/wda/apps/launch" {
		t.Fatalf("unexpected launch sequence: %v", seen)
	}
}
