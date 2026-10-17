#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_DIR="$ROOT/.run"

SHEET_PUSH_PID_FILE="$RUN_DIR/sheet_push_watch.pid"

pid_running() {
  kill -0 "$1" 2>/dev/null
}

stop_pid_from_file() {
  local pid_file="$1"
  local label="$2"

  [[ ! -f "$pid_file" ]] && return 0

  local pid
  pid="$(tr -d '[:space:]' < "$pid_file" || true)"

  if [[ -z "$pid" ]]; then
    rm -f "$pid_file"
    return 0
  fi

  if pid_running "$pid"; then
    echo "Stopping $label (pid $pid)..."
    kill -TERM "$pid" 2>/dev/null || true
    for _ in {1..30}; do
      pid_running "$pid" || break
      sleep 0.2
    done
    if pid_running "$pid"; then
      echo "Force stopping $label (pid $pid)..."
      kill -9 "$pid" 2>/dev/null || true
    fi
  else
    echo "$label is already stopped."
  fi

  rm -f "$pid_file"
}

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

echo "Cleaning up kluky processes..."

stop_pid_from_file "$SHEET_PUSH_PID_FILE" "Sheet push watcher"

if command -v crontab &>/dev/null; then
  remove_google_sync_cron
fi

echo ""
echo "Done. Close the OpenCode terminal window manually if still open."
