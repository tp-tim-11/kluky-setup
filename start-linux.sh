#!/usr/bin/env bash
# start-linux.sh — thin Linux wrapper around start.sh.
#
# start.sh is portable to Linux except for one macOS-only call:
#   osascript -e "tell application \"Terminal\" to do script \"<cmd>\""
# which opens the OpenCode TUI in a new Terminal.app window.
#
# This wrapper exports a bash-function shim named `osascript` that runs
# <cmd> in a Linux terminal emulator instead, then exec's start.sh.
# The exported function shadows the missing osascript binary inside the
# child bash process that runs start.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "ERROR: start-linux.sh is for Linux. Use ./start.sh on macOS."
  exit 1
fi

if [[ ! -f "$ROOT/start.sh" ]]; then
  echo "ERROR: start.sh not found next to start-linux.sh."
  exit 1
fi

osascript() {
  local arg="${2:-}"
  local cmd
  cmd="${arg#*do script \"}"
  cmd="${cmd%\"}"
  cmd="${cmd//\\\"/\"}"

  if command -v gnome-terminal &>/dev/null; then
    gnome-terminal -- bash -c "$cmd; exec bash" >/dev/null 2>&1 &
  elif command -v konsole &>/dev/null; then
    konsole -e bash -c "$cmd; exec bash" >/dev/null 2>&1 &
  elif command -v xfce4-terminal &>/dev/null; then
    xfce4-terminal -e "bash -c '$cmd; exec bash'" >/dev/null 2>&1 &
  elif command -v x-terminal-emulator &>/dev/null; then
    x-terminal-emulator -e bash -c "$cmd; exec bash" >/dev/null 2>&1 &
  elif command -v xterm &>/dev/null; then
    xterm -e bash -c "$cmd; exec bash" >/dev/null 2>&1 &
  else
    echo "ERROR: No supported terminal emulator (gnome-terminal/konsole/xfce4-terminal/xterm)." >&2
    return 1
  fi
}
export -f osascript

exec bash "$ROOT/start.sh"
