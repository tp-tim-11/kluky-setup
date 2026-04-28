# kluky-setup (Windows)

One-command setup for the hey-kluky voice assistant on Windows 10 / 11.

## Prerequisites

- **Windows 10 1809+ or Windows 11** (needed for `winget`, used to auto-install Git)
- **PowerShell 5.1+** (ships with Windows) or PowerShell 7+
- **Windows Terminal** is recommended but not required (the start script falls back to a regular PowerShell window)

If your execution policy blocks unsigned scripts, either run each script with `-ExecutionPolicy Bypass` (shown below) or, once per machine, allow local scripts:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## Quick Start

```powershell
git clone https://github.com/tp-tim-11/kluky-setup.git
cd kluky-setup
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

After install completes:

1. Edit `.env` and fill in your API keys
2. Run `.\start.ps1`

## Daily Usage

```powershell
.\start.ps1     # Starts everything, press Ctrl+C to stop
```

If something crashes and Ctrl+C didn't clean up:

```powershell
.\stop.ps1      # Cleans up leftover processes and the scheduled task
```

## What Gets Installed

- **Git for Windows** — installed automatically via `winget` if missing
- **uv** — Python package manager (PowerShell installer from astral.sh)
- **opencode** — AI coding assistant CLI (PowerShell installer from opencode.ai)
- **hey-kluky** — voice assistant (cloned repo)
- **kluky_mcp** — MCP server for OpenCode (cloned repo)
- **google-workspace-sync** — Google Workspace sync tool (cloned repo)

If the opencode PowerShell installer fails, the script will print a message pointing you at the npm fallback (`npm i -g opencode-ai`, requires Node.js).

## What start.ps1 Does

1. Loads `.env` and copies it into each cloned repo so `config.py` finds it
2. Validates required API keys (`OPENAI_API_KEY`, `ELEVENLABS_API_KEY`)
3. Configures the OpenCode custom provider (if `OPENCODE_PROVIDER_BASE_URL` is set)
4. Starts the Google Sheet push watcher in the background (PID at `.run\sheet_push_watch.pid`, logs at `.run\sheet_push_watch.log`)
5. Registers a scheduled task `kluky_google_workspace_sync` that runs `google_workspace_sync sync --mode all` every 5 minutes
6. Opens the OpenCode TUI on `127.0.0.1:4096` in a new Windows Terminal window
7. Runs the voice assistant (`hey-kluky\main.py`) in the foreground
8. On Ctrl+C: stops the watcher and removes the scheduled task

## What stop.ps1 Does

1. Stops the Sheet push watcher (graceful close, then force-kill after ~6s)
2. Deletes the `kluky_google_workspace_sync` scheduled task

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

If you decide to fill in a custom provider you have to also fill all of these variables.

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENCODE_PROVIDER_BASE_URL` | Optional | Base url of provider |
| `OPENCODE_PROVIDER_MODELS` | Optional | Model names, separated with comma |
| `OPENCODE_PROVIDER_API_KEY` | Optional | Api key for provider |

## Notes for Windows users

- The macOS scripts symlink the root `.env` into each repo. On Windows, `start.ps1` **copies** it instead (symlinks need admin or Developer Mode). Edits to root `.env` propagate on the next `.\start.ps1`.
- The macOS scripts use `crontab`. On Windows, the equivalent is a Task Scheduler entry (`schtasks` task named `kluky_google_workspace_sync`). It is created by `start.ps1` and removed on Ctrl+C / by `stop.ps1`. Inspect with:

  ```powershell
  schtasks /Query /TN kluky_google_workspace_sync /V /FO LIST
  ```

- The OpenCode TUI runs in a separate window — close it manually after `Ctrl+C` if you don't need it anymore.
