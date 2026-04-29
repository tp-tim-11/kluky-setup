#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$RunDir = Join-Path $Root '.run'
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

$SheetPushPidFile = Join-Path $RunDir 'sheet_push_watch.pid'
$SheetPushLogFile = Join-Path $RunDir 'sheet_push_watch.log'

$env:TEST_OPENCODE_DIR         = Join-Path $Root 'opencode-workspace'
$env:GOOGLE_WORKSPACE_SYNC_DIR = Join-Path $Root 'google_workspace_sync'
$OpencodeHostName = '127.0.0.1'
$OpencodePort = 4096
$env:OPENCODE_URL = "http://${OpencodeHostName}:$OpencodePort"

$TaskName = 'kluky_google_workspace_sync'

function Load-DotEnv($path) {
    $loaded = @{}
    Get-Content -LiteralPath $path | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#')) { return }
        $i = $line.IndexOf('=')
        if ($i -lt 1) { return }
        $k = $line.Substring(0, $i).Trim()
        $v = $line.Substring($i + 1).Trim()
        if ($v.Length -ge 2) {
            $first = $v[0]; $last = $v[$v.Length - 1]
            if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
                $v = $v.Substring(1, $v.Length - 2)
            }
        }
        Set-Item -Path "Env:$k" -Value $v
        $loaded[$k] = $v
    }
    return $loaded
}

if (-not (Test-Path (Join-Path $Root '.env'))) {
    Write-Host 'ERROR: .env not found. Run .\install.ps1 first, then edit .env.'
    exit 1
}
$envVars = Load-DotEnv (Join-Path $Root '.env')

foreach ($p in 'hey-kluky', 'kluky_mcp', 'google_workspace_sync') {
    $projectDir = Join-Path $Root $p
    if (Test-Path $projectDir) {
        Copy-Item (Join-Path $Root '.env') (Join-Path $projectDir '.env') -Force
    }
}

foreach ($req in 'OPENAI_API_KEY', 'ELEVENLABS_API_KEY') {
    if (-not $envVars.ContainsKey($req) -or -not $envVars[$req]) {
        Write-Host "ERROR: $req is not set in .env"
        exit 1
    }
}

function Configure-OpencodeProvider {
    $cfg = Join-Path $Root 'opencode-workspace\opencode.json'
    if (-not (Test-Path $cfg)) {
        Write-Warning "opencode.json not found at $cfg, skipping provider config."
        return
    }
    $base   = $env:OPENCODE_PROVIDER_BASE_URL
    $models = $env:OPENCODE_PROVIDER_MODELS
    $apiKey = $env:OPENCODE_PROVIDER_API_KEY

    if (-not $base) {
        Write-Host 'No OPENCODE_PROVIDER_BASE_URL set; leaving opencode.json untouched.'
        Write-Host 'Connect a provider through the OpenCode TUI if needed.'
        return
    }
    if (-not $models) {
        Write-Host 'ERROR: OPENCODE_PROVIDER_BASE_URL is set but OPENCODE_PROVIDER_MODELS is empty.'
        Write-Host '       Provide a comma-separated list of model IDs.'
        exit 1
    }
    if (-not $apiKey) {
        Write-Host 'ERROR: OPENCODE_PROVIDER_BASE_URL is set but OPENCODE_PROVIDER_API_KEY is empty.'
        Write-Host '       Provide the API key for your OpenAI-compatible endpoint.'
        exit 1
    }

    $modelList = $models.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    if ($modelList.Count -eq 0) {
        Write-Host 'ERROR: OPENCODE_PROVIDER_MODELS contains no valid model IDs.'
        exit 1
    }

    $json = Get-Content -LiteralPath $cfg -Raw | ConvertFrom-Json

    $modelObj = [ordered]@{}
    foreach ($m in $modelList) { $modelObj[$m] = [ordered]@{ name = $m } }

    $providerEntry = [ordered]@{
        npm     = '@ai-sdk/openai-compatible'
        name    = 'My Custom Provider'
        options = [ordered]@{ baseURL = $base; apiKey = $apiKey }
        models  = $modelObj
    }

    if (-not ($json.PSObject.Properties.Name -contains 'provider')) {
        $json | Add-Member -NotePropertyName provider -NotePropertyValue ([pscustomobject]@{})
    }
    if ($json.provider.PSObject.Properties.Name -contains 'my-custom-provider') {
        $json.provider.'my-custom-provider' = $providerEntry
    } else {
        $json.provider | Add-Member -NotePropertyName 'my-custom-provider' -NotePropertyValue $providerEntry
    }

    if ($json.PSObject.Properties.Name -contains 'model') {
        $json.model = "my-custom-provider/$($modelList[0])"
    } else {
        $json | Add-Member -NotePropertyName model -NotePropertyValue "my-custom-provider/$($modelList[0])"
    }

    ($json | ConvertTo-Json -Depth 20) + "`n" | Set-Content -LiteralPath $cfg -Encoding utf8

    Write-Host "Added 'my-custom-provider' to opencode.json at $base with models: $models"
    Write-Host "Default model set to my-custom-provider/$($modelList[0])"
}
Configure-OpencodeProvider

function Test-Port($targetHost, $port) {
    $client = New-Object Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($targetHost, $port, $null, $null)
        $ok  = $iar.AsyncWaitHandle.WaitOne(500, $false)
        if (-not $ok) { return $false }
        $client.EndConnect($iar)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Wait-Port($targetHost, $port, $timeoutSec = 45) {
    for ($i = 0; $i -lt $timeoutSec; $i++) {
        if (Test-Port $targetHost $port) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}

function Pid-Running($id) {
    if (-not $id) { return $false }
    return [bool](Get-Process -Id $id -ErrorAction SilentlyContinue)
}

function Stop-Pid-Graceful($id, $timeoutSec = 6) {
    if (-not (Pid-Running $id)) { return }
    try {
        $proc = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($proc) { $null = $proc.CloseMainWindow() }
    } catch {}
    for ($i = 0; $i -lt ($timeoutSec * 5); $i++) {
        if (-not (Pid-Running $id)) { return }
        Start-Sleep -Milliseconds 200
    }
    Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
}

function Install-SyncTask {
    if (-not (Test-Path $env:GOOGLE_WORKSPACE_SYNC_DIR)) {
        Write-Warning 'google_workspace_sync directory not found, skipping scheduled task install.'
        return
    }
    $logDir = Join-Path $env:GOOGLE_WORKSPACE_SYNC_DIR 'logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null

    $uvCmd = Get-Command uv -ErrorAction SilentlyContinue
    if (-not $uvCmd) {
        Write-Warning 'uv not on PATH; skipping scheduled task install.'
        return
    }
    $uvPath = $uvCmd.Source
    $logFile = Join-Path $logDir 'all-sync.log'

    $tr = "cmd.exe /c cd /d `"$($env:GOOGLE_WORKSPACE_SYNC_DIR)`" && `"$uvPath`" run google_workspace_sync sync --mode all >> `"$logFile`" 2>&1"

    & schtasks.exe /Create /SC MINUTE /MO 5 /TN $TaskName /TR $tr /F | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'Installed scheduled task: google_workspace_sync every 5 minutes.'
    } else {
        Write-Warning "schtasks /Create returned exit code $LASTEXITCODE"
    }
}

function Remove-SyncTask {
    & schtasks.exe /Delete /TN $TaskName /F 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'Removed scheduled task.'
    }
}

$script:SheetPushStarted = $false
$script:SheetPushPid = $null

function Cleanup {
    Write-Host ''
    if ($script:SheetPushStarted -and (Pid-Running $script:SheetPushPid)) {
        Write-Host "Stopping Sheet push watcher (pid $($script:SheetPushPid))..."
        Stop-Pid-Graceful $script:SheetPushPid 6
    }
    if ($script:SheetPushStarted -and (Test-Path $SheetPushPidFile)) {
        Remove-Item $SheetPushPidFile -Force -ErrorAction SilentlyContinue
    }
    Remove-SyncTask
    Write-Host 'Cleanup complete. Close the OpenCode terminal window manually.'
}

try {
    Write-Host 'Starting Google Sheet push watcher...'

    if (Test-Path $SheetPushPidFile) {
        $existing = (Get-Content -LiteralPath $SheetPushPidFile -Raw).Trim()
        if ($existing -and (Pid-Running ([int]$existing))) {
            $script:SheetPushPid = [int]$existing
            Write-Host "Sheet push watcher already running (pid $($script:SheetPushPid)), reusing."
        } else {
            Remove-Item $SheetPushPidFile -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $script:SheetPushPid) {
        if (Test-Path $env:GOOGLE_WORKSPACE_SYNC_DIR) {
            $proc = Start-Process -FilePath 'uv' `
                -ArgumentList @('run', 'google_workspace_sync', 'watch-sheet-push') `
                -WorkingDirectory $env:GOOGLE_WORKSPACE_SYNC_DIR `
                -RedirectStandardOutput $SheetPushLogFile `
                -RedirectStandardError "$SheetPushLogFile.err" `
                -WindowStyle Hidden -PassThru
            $script:SheetPushPid = $proc.Id
            $script:SheetPushStarted = $true
            $proc.Id | Out-File -Encoding ascii -LiteralPath $SheetPushPidFile

            Start-Sleep -Seconds 1
            if (-not (Pid-Running $proc.Id)) {
                Write-Warning "Sheet push watcher exited during startup. See: $SheetPushLogFile"
                Remove-Item $SheetPushPidFile -Force -ErrorAction SilentlyContinue
                $script:SheetPushStarted = $false
                $script:SheetPushPid = $null
            } else {
                Write-Host "Sheet push watcher started (pid $($script:SheetPushPid))."
            }
        } else {
            Write-Warning 'google_workspace_sync not found, skipping sheet push watcher.'
        }
    }

    Install-SyncTask

    Write-Host "Opening OpenCode TUI on port $OpencodePort..."
    if (-not (Test-Port $OpencodeHostName $OpencodePort)) {
        $workspace = Join-Path $Root 'opencode-workspace'

        # Refresh PATH from the registry so opencode (added by its installer to the
        # User PATH) resolves even if this shell was opened before install.ps1 ran.
        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($machinePath -or $userPath) {
            $env:Path = @($machinePath, $userPath, $env:Path) -ne '' -join ';'
        }

        $opencodeCmd = Get-Command opencode -ErrorAction SilentlyContinue
        if (-not $opencodeCmd) {
            Write-Host 'ERROR: opencode is not on PATH.'
            Write-Host '       Open a new terminal (so the installer''s PATH update takes effect) or re-run .\install.ps1.'
            exit 1
        }
        $opencodeExe = $opencodeCmd.Source

        # NOTE: do not put a `;` inside the wt.exe command string — Windows Terminal
        # parses `;` as its own tab/pane separator and swallows everything after it,
        # so the spawned shell never sees the actual command. Use `wt -d <dir>` to
        # set the working directory instead, leaving a single command for powershell.
        $innerCmd = "& `"$opencodeExe`" --port $OpencodePort"
        if (Get-Command wt.exe -ErrorAction SilentlyContinue) {
            Start-Process wt.exe -ArgumentList @('-d', $workspace, 'powershell', '-NoExit', '-Command', $innerCmd) | Out-Null
        } else {
            Start-Process powershell -WorkingDirectory $workspace -ArgumentList @('-NoExit', '-Command', $innerCmd) | Out-Null
        }
        Write-Host 'Waiting for OpenCode to start (up to 45s)...'
        if (-not (Wait-Port $OpencodeHostName $OpencodePort 45)) {
            Write-Host "ERROR: OpenCode failed to start on port $OpencodePort"
            exit 1
        }
        Write-Host 'OpenCode is ready.'
    } else {
        Write-Host "OpenCode already listening on port $OpencodePort."
    }

    Write-Host ''
    Write-Host 'Starting hey-kluky...'
    Write-Host 'Press Ctrl+C to stop.'
    Write-Host ''

    Push-Location (Join-Path $Root 'hey-kluky')
    try {
        uv run python main.py
    } finally {
        Pop-Location
    }
} finally {
    Cleanup
}
