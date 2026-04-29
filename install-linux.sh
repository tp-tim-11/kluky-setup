#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- OS check ---
if [[ "$(uname -s)" != "Linux" ]]; then
  echo "ERROR: install-linux.sh is for Linux. Use ./install.sh on macOS."
  exit 1
fi

# --- Install netcat if missing (start.sh uses `nc -z` for the port check) ---
if ! command -v nc &>/dev/null; then
  if command -v apt-get &>/dev/null; then
    echo "Installing netcat (needed for the OpenCode port check)..."
    sudo apt-get update -qq
    sudo apt-get install -y netcat-openbsd
  else
    echo "WARNING: 'nc' not found and apt-get unavailable."
    echo "         Install netcat manually before running ./start-linux.sh."
  fi
fi

# --- Install uv ---
if ! command -v uv &>/dev/null; then
  echo "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  source "$HOME/.local/bin/env" 2>/dev/null || true
else
  echo "uv already installed."
fi

# --- Install opencode ---
if ! command -v opencode &>/dev/null; then
  echo "Installing opencode..."
  curl -fsSL https://opencode.ai/install | bash
  source "$HOME/.bashrc" 2>/dev/null || source "$HOME/.zshrc" 2>/dev/null || true
else
  echo "opencode already installed."
fi

# --- Clone repos ---
clone_if_missing() {
  local dir="$1"
  local url="$2"
  local name
  name="$(basename "$dir")"
  if [[ -d "$dir" ]]; then
    echo "$name already exists, skipping clone. Run 'git -C $dir pull' to update."
  else
    echo "Cloning $name..."
    git clone "$url" "$dir"
  fi
}

clone_if_missing "$ROOT/hey-kluky"              "https://github.com/tp-tim-11/hey-kluky.git"
clone_if_missing "$ROOT/kluky_mcp"              "https://github.com/tp-tim-11/kluky_mcp.git"
clone_if_missing "$ROOT/google_workspace_sync"  "https://github.com/tp-tim-11/google_workspace_sync.git"

# --- Install Python dependencies ---
for project in hey-kluky kluky_mcp google_workspace_sync; do
  if [[ -f "$ROOT/$project/pyproject.toml" ]]; then
    echo "Installing dependencies for $project..."
    (cd "$ROOT/$project" && uv sync)
  fi
done

# --- Create .env from template ---
if [[ ! -f "$ROOT/.env" ]]; then
  cp "$ROOT/.env.example" "$ROOT/.env"
  echo ""
  echo "Created .env from template."
fi

echo ""
echo "============================================"
echo "  Installation complete!"
echo "============================================"
echo ""
echo "Next steps:"
echo "  1. Edit .env and fill in your API keys"
echo "  2. Run ./start-linux.sh"
echo "  3. In the OpenCode terminal that opens,"
echo "     run /connect to set up your LLM provider"
echo "     and choose a model (first time only)"
echo ""
