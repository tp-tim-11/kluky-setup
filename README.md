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

1. Edit `.env.example` and fill in your API keys
2. Rename `.env.example` to `.env`
3. Run `./start.sh`

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
| `OPENAI_API_KEY` | Yes | OpenAI API for indexer |
| `ELEVENLABS_API_KEY` | Yes | ElevenLabs API key for TTS and STT |
| `DB_PASSWORD` | Yes | Password for supabase DB |
| `GOOGLE_DRIVE_DOCUMENTS_FOLDER_ID` | Yes | Folder id of googledrive docs |
| `GOOGLE_SHEETS_RANGE` | Yes | Range for google sheets |
| `GOOGLE_SHEETS_ID` | Yes | Id of google sheets |

## Custom OpenAI-compatible provider

If you decide to fill in custom provider you have to also fill all of these variables as well.

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENCODE_PROVIDER_BASE_URL` | Optional | Base url of provider |
| `OPENCODE_PROVIDER_MODELS` | Optional | Model names, separated with comma |
| `OPENCODE_PROVIDER_API_KEY` | Optional | Api key for provider |
