#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$RunDir = Join-Path $Root '.run'
$SheetPushPidFile = Join-Path $RunDir 'sheet_push_watch.pid'
$TaskName = 'kluky_google_workspace_sync'

function Pid-Running($id) {
    if (-not $id) { return $false }
    return [bool](Get-Process -Id $id -ErrorAction SilentlyContinue)
}

function Stop-PidFromFile($pidFile, $label) {
    if (-not (Test-Path $pidFile)) { return }

    $raw = (Get-Content -LiteralPath $pidFile -Raw).Trim()
    if (-not $raw) {
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
        return
    }

    $pidNum = 0
    if (-not [int]::TryParse($raw, [ref]$pidNum)) {
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
        return
    }

    if (Pid-Running $pidNum) {
        Write-Host "Stopping $label (pid $pidNum)..."
        try {
            $proc = Get-Process -Id $pidNum -ErrorAction SilentlyContinue
            if ($proc) { $null = $proc.CloseMainWindow() }
        } catch {}
        for ($i = 0; $i -lt 30; $i++) {
            if (-not (Pid-Running $pidNum)) { break }
            Start-Sleep -Milliseconds 200
        }
        if (Pid-Running $pidNum) {
            Write-Host "Force stopping $label (pid $pidNum)..."
            Stop-Process -Id $pidNum -Force -ErrorAction SilentlyContinue
        }
    } else {
        Write-Host "$label is already stopped."
    }

    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}

function Remove-SyncTask {
    & schtasks.exe /Query /TN $TaskName 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { return }
    & schtasks.exe /Delete /TN $TaskName /F | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'Removed google_workspace_sync scheduled task.'
    }
}

Write-Host 'Cleaning up kluky processes...'

Stop-PidFromFile $SheetPushPidFile 'Sheet push watcher'
Remove-SyncTask

Write-Host ''
Write-Host 'Done. Close the OpenCode terminal window manually if still open.'
