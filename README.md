# kluky-setup

One-command setup for the hey-kluky voice assistant on macOS.

## Quick Start

```bash
git clone https://github.com/tp-tim-11/kluky-setup.git
cd kluky-setup
chmod +x install.sh start.sh stop.sh
./install.sh
```

After install completes:

1. Edit `.env` and fill in your API keys
2. Run `./start.sh`
3. In the OpenCode terminal that opens, run `/connect` to set up your LLM provider and choose a model (first time only)

## Daily Usage

```bash
./start.sh    # Starts everything, press Ctrl+C to stop
```

If something crashes and Ctrl+C didn't clean up:

```bash
./stop.sh     # Cleans up leftover processes and cron jobs
```

## What Gets Installed

- **uv** — Python package manager
- **opencode** — AI coding assistant CLI
- **hey-kluky** — voice assistant (cloned repo)
- **kluky_mcp** — MCP server for OpenCode (cloned repo)
- **google-workspace-sync** — Google Workspace sync tool (cloned repo)

## What start.sh Does

1. Opens the OpenCode TUI in a new Terminal window
2. Starts the Google Sheet push watcher in the background
3. Installs a cron job for Google Workspace sync (every 5 min)
4. Runs the voice assistant in the foreground
5. On Ctrl+C: cleans up background processes and cron job

## Configuration

Edit `.env` for API keys. All paths are handled automatically.

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENAI_API_KEY` | Yes | OpenAI API |
| `ELEVENLABS_API_KEY` | Yes | ElevenLabs API key for TTS and STT |
| `ELEVENLABS_VOICE_ID` | No | Custom voice ID |
| `ELEVENLABS_MODEL_ID` | No | Custom TTS model |
| `STT_LANGUAGE` | No | Language code (default: sk) |
