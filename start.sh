#!/usr/bin/env bash
set -euo pipefail

LAUNCHER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$LAUNCHER_DIR/.run"
mkdir -p "$RUN_DIR"

SHEET_PUSH_PID_FILE="$RUN_DIR/sheet_push_watch.pid"
SHEET_PUSH_LOG_FILE="$RUN_DIR/sheet_push_watch.log"

# --- Hardcoded paths ---
export TEST_OPENCODE_DIR="$LAUNCHER_DIR/opencode-workspace"
export GOOGLE_WORKSPACE_SYNC_DIR="$LAUNCHER_DIR/google_workspace_sync"
OPENCODE_URL="http://127.0.0.1:4096"
OPENCODE_HOST="127.0.0.1"
OPENCODE_PORT="4096"
export OPENCODE_URL

# --- Load .env ---
if [[ ! -f "$LAUNCHER_DIR/.env" ]]; then
  echo "ERROR: .env not found. Run ./install.sh first, then edit .env."
  exit 1
fi
set -a
source "$LAUNCHER_DIR/.env"
set +a

# --- Symlink .env into repos so each config.py finds it ---
ln -sf "$LAUNCHER_DIR/.env" "$LAUNCHER_DIR/hey-kluky/.env"
ln -sf "$LAUNCHER_DIR/.env" "$LAUNCHER_DIR/kluky_mcp/.env"
ln -sf "$LAUNCHER_DIR/.env" "$LAUNCHER_DIR/google_workspace_sync/.env"

# --- Validate required vars ---
if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "ERROR: OPENAI_API_KEY is not set in .env"
  exit 1
fi
if [[ -z "${ELEVENLABS_API_KEY:-}" ]]; then
  echo "ERROR: ELEVENLABS_API_KEY is not set in .env"
  exit 1
fi

# --- Helpers ---
is_listening() {
  nc -z "$1" "$2" 2>/dev/null
}

wait_for_port() {
  local host="$1"
  local port="$2"
  local timeout="${3:-45}"
  local i
  for ((i=0; i<timeout; i++)); do
    if is_listening "$host" "$port"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

pid_running() {
  kill -0 "$1" 2>/dev/null
}

# --- Install google_workspace_sync cron job ---
install_google_sync_cron() {
  local project_dir="$GOOGLE_WORKSPACE_SYNC_DIR"
  local log_dir="$project_dir/logs"
  local lock_dir="/tmp/gws_all.lck"
  local mark_start="# >>> google_workspace_sync (managed) >>>"
  local mark_end="# <<< google_workspace_sync (managed) <<<"

  if [[ ! -d "$project_dir" ]]; then
    echo "WARNING: google_workspace_sync directory not found, skipping cron install."
    return 0
  fi

  mkdir -p "$log_dir"

  local uv_bin bash_bin
  uv_bin="$(command -v uv)"
  bash_bin="$(command -v bash)"

  local inner
  inner="cd \"$project_dir\" && \"$uv_bin\" run google_workspace_sync sync --mode all >> \"$log_dir/all-sync.log\" 2>&1"

  local locked_inner
  locked_inner="mkdir $lock_dir 2>/dev/null || exit 0; trap \"rmdir $lock_dir\" EXIT; $inner"

  local cron_line
  cron_line="*/5 * * * * $bash_bin -lc '$locked_inner'"

  local managed_block
  managed_block="$mark_start
# Managed by kluky-setup/start.sh
$cron_line
$mark_end"

  local existing
  existing="$(crontab -l 2>/dev/null || true)"

  local cleaned
  cleaned="$(printf '%s\n' "$existing" | awk -v s="$mark_start" -v e="$mark_end" '
    $0 == s {skip=1; next}
    $0 == e {skip=0; next}
    !skip {print}
  ')"

  local new_crontab
  if [[ -n "$cleaned" ]]; then
    new_crontab="$cleaned
$managed_block
"
  else
    new_crontab="$managed_block
"
  fi

  printf '%s' "$new_crontab" | crontab -
  echo "Installed cron: google_workspace_sync every 5 minutes."
}

# --- Remove google_workspace_sync cron job ---
remove_google_sync_cron() {
  local mark_start="# >>> google_workspace_sync (managed) >>>"
  local mark_end="# <<< google_workspace_sync (managed) <<<"

  local existing
  existing="$(crontab -l 2>/dev/null || true)"
  [[ -z "$existing" ]] && return 0

  local cleaned
  cleaned="$(printf '%s\n' "$existing" | awk -v s="$mark_start" -v e="$mark_end" '
    $0 == s {skip=1; next}
    $0 == e {skip=0; next}
    !skip {print}
  ')"

  [[ "$cleaned" == "$existing" ]] && return 0

  if [[ -n "$cleaned" ]]; then
    printf '%s\n' "$cleaned" | crontab -
  else
    crontab -r 2>/dev/null || true
  fi
  echo "Removed google_workspace_sync cron."
}

# --- Cleanup on exit ---
SHEET_PUSH_STARTED=0
SHEET_PUSH_PID=""

cleanup() {
  set +e
  echo ""

  # Stop sheet push watcher
  if [[ "$SHEET_PUSH_STARTED" -eq 1 && -n "$SHEET_PUSH_PID" ]] && pid_running "$SHEET_PUSH_PID"; then
    echo "Stopping Sheet push watcher (pid $SHEET_PUSH_PID)..."
    kill -TERM "$SHEET_PUSH_PID" 2>/dev/null || true
    for _ in {1..30}; do
      pid_running "$SHEET_PUSH_PID" || break
      sleep 0.2
    done
    if pid_running "$SHEET_PUSH_PID"; then
      kill -9 "$SHEET_PUSH_PID" 2>/dev/null || true
    fi
  fi
  [[ "$SHEET_PUSH_STARTED" -eq 1 ]] && rm -f "$SHEET_PUSH_PID_FILE"

  # Remove cron
  if command -v crontab &>/dev/null; then
    remove_google_sync_cron
  fi

  echo "Cleanup complete. Close the OpenCode terminal window manually."
}
trap cleanup EXIT INT TERM

# --- Start sheet push watcher ---
echo "Starting Google Sheet push watcher..."

if [[ -f "$SHEET_PUSH_PID_FILE" ]]; then
  existing_pid="$(tr -d '[:space:]' < "$SHEET_PUSH_PID_FILE" || true)"
  if [[ -n "$existing_pid" ]] && pid_running "$existing_pid"; then
    SHEET_PUSH_PID="$existing_pid"
    echo "Sheet push watcher already running (pid $SHEET_PUSH_PID), reusing."
  else
    rm -f "$SHEET_PUSH_PID_FILE"
  fi
fi

if [[ -z "$SHEET_PUSH_PID" ]]; then
  if [[ -d "$GOOGLE_WORKSPACE_SYNC_DIR" ]]; then
    (
      cd "$GOOGLE_WORKSPACE_SYNC_DIR"
      exec uv run google_workspace_sync watch-sheet-push \
        > "$SHEET_PUSH_LOG_FILE" 2>&1
    ) &
    SHEET_PUSH_PID="$!"
    echo "$SHEET_PUSH_PID" > "$SHEET_PUSH_PID_FILE"
    SHEET_PUSH_STARTED=1

    sleep 1
    if ! pid_running "$SHEET_PUSH_PID"; then
      echo "WARNING: Sheet push watcher exited during startup. See: $SHEET_PUSH_LOG_FILE"
      rm -f "$SHEET_PUSH_PID_FILE"
      SHEET_PUSH_STARTED=0
      SHEET_PUSH_PID=""
    else
      echo "Sheet push watcher started (pid $SHEET_PUSH_PID)."
    fi
  else
    echo "WARNING: google_workspace_sync not found, skipping sheet push watcher."
  fi
fi

# --- Install cron ---
install_google_sync_cron

# --- Open OpenCode TUI in a new Terminal window ---
echo "Opening OpenCode TUI on port $OPENCODE_PORT..."
if ! is_listening "$OPENCODE_HOST" "$OPENCODE_PORT"; then
  osascript -e "tell application \"Terminal\" to do script \"cd '$LAUNCHER_DIR/opencode-workspace' && opencode --port $OPENCODE_PORT\""

  echo "Waiting for OpenCode to start (up to 45s)..."
  if ! wait_for_port "$OPENCODE_HOST" "$OPENCODE_PORT" 45; then
    echo "ERROR: OpenCode failed to start on port $OPENCODE_PORT"
    exit 1
  fi
  echo "OpenCode is ready."
else
  echo "OpenCode already listening on port $OPENCODE_PORT."
fi

# --- Run main.py ---
echo ""
echo "Starting hey-kluky..."
echo "Press Ctrl+C to stop."
echo ""

cd "$LAUNCHER_DIR/hey-kluky"
uv run python main.py
