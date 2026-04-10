#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/opt/go/libexec/bin:/usr/local/bin:/usr/local/opt/go/libexec/bin:$PATH"

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
OUTPUT_PATH="${1:-$ROOT_DIR/backend/bin/vlogclaw}"
OUTPUT_DIR="$(dirname "$OUTPUT_PATH")"
PLUGINS_DIR="$OUTPUT_DIR/plugins"
SIB_OUTPUT_PATH="$PLUGINS_DIR/sonic-ios-bridge"

find_go_binary() {
  local candidates=()

  if [[ -n "${GO_BIN:-}" ]]; then
    candidates+=("${GO_BIN}")
  fi

  candidates+=(
    "/opt/homebrew/bin/go"
    "/opt/homebrew/opt/go/libexec/bin/go"
    "/usr/local/bin/go"
    "/usr/local/opt/go/libexec/bin/go"
  )

  if command -v go >/dev/null 2>&1; then
    candidates+=("$(command -v go)")
  fi

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  echo "Unable to locate Go toolchain. Set GO_BIN or install Go in /opt/homebrew/bin/go or /usr/local/bin/go." >&2
  return 1
}

find_sib_source() {
  local candidates=()

  if [[ -n "${SIB_SOURCE_PATH:-}" ]]; then
    candidates+=("${SIB_SOURCE_PATH}")
  fi
  if [[ -n "${SIB_PATH:-}" ]]; then
    candidates+=("${SIB_PATH}")
  fi

  for name in sib sonic-ios-bridge; do
    if command -v "$name" >/dev/null 2>&1; then
      candidates+=("$(command -v "$name")")
    fi
  done

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

mkdir -p "$OUTPUT_DIR" "$PLUGINS_DIR"

cd "$ROOT_DIR/backend"
"$(find_go_binary)" build -o "$OUTPUT_PATH" ./cmd/vlogclaw

if SIB_SOURCE="$(find_sib_source)"; then
  cp "$SIB_SOURCE" "$SIB_OUTPUT_PATH"
  chmod +x "$SIB_OUTPUT_PATH"
  echo "Bundled sib binary at: $SIB_OUTPUT_PATH"
else
  echo "Warning: no sib binary found; backend will start without device bridge support." >&2
fi

echo "Built backend binary at: $OUTPUT_PATH"
