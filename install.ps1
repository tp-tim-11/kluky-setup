#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot

if ($env:OS -ne 'Windows_NT') {
    throw 'install.ps1 only supports Windows.'
}

function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath"
}

function Ensure-Git {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Host 'git already installed.'
        return
    }
    Write-Host 'git not found. Attempting winget install...'
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'winget is unavailable. Install Git for Windows manually: https://git-scm.com/download/win and re-run install.ps1.'
    }
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
    Refresh-Path
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'git install via winget did not put git on PATH. Open a new terminal and re-run install.ps1.'
    }
    Write-Host 'git installed.'
}

function Ensure-Uv {
    if (Get-Command uv -ErrorAction SilentlyContinue) {
        Write-Host 'uv already installed.'
        return
    }
    Write-Host 'Installing uv...'
    Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
    $env:Path = "$env:USERPROFILE\.local\bin;$env:Path"
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        Refresh-Path
    }
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        throw 'uv install completed but uv is not on PATH. Open a new terminal and re-run install.ps1.'
    }
}

function Ensure-Opencode {
    if (Get-Command opencode -ErrorAction SilentlyContinue) {
        Write-Host 'opencode already installed.'
        return
    }
    Write-Host 'Installing opencode...'
    try {
        Invoke-RestMethod https://opencode.ai/install.ps1 | Invoke-Expression
    } catch {
        throw "opencode PowerShell installer failed. Fallback: 'npm i -g opencode-ai' (requires Node.js). Error: $_"
    }
    Refresh-Path
    if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) {
        throw 'opencode installer ran but opencode is not on PATH. Open a new terminal and re-run install.ps1.'
    }
}

function Clone-IfMissing($dir, $url) {
    $name = Split-Path $dir -Leaf
    if (Test-Path $dir) {
        Write-Host "$name already exists, skipping clone. Run 'git -C `"$dir`" pull' to update."
    } else {
        Write-Host "Cloning $name..."
        git clone $url $dir
    }
}

Ensure-Git
Ensure-Uv
Ensure-Opencode

Clone-IfMissing (Join-Path $Root 'hey-kluky')             'https://github.com/tp-tim-11/hey-kluky.git'
Clone-IfMissing (Join-Path $Root 'kluky_mcp')             'https://github.com/tp-tim-11/kluky_mcp.git'
Clone-IfMissing (Join-Path $Root 'google_workspace_sync') 'https://github.com/tp-tim-11/google_workspace_sync.git'

foreach ($p in 'hey-kluky', 'kluky_mcp', 'google_workspace_sync') {
    $projectDir = Join-Path $Root $p
    if (Test-Path (Join-Path $projectDir 'pyproject.toml')) {
        Write-Host "Installing dependencies for $p..."
        Push-Location $projectDir
        try { uv sync } finally { Pop-Location }
    }
}

$envFile = Join-Path $Root '.env'
$envExample = Join-Path $Root '.env.example'
if (-not (Test-Path $envFile) -and (Test-Path $envExample)) {
    Copy-Item $envExample $envFile
    Write-Host ''
    Write-Host 'Created .env from template.'
}

Write-Host ''
Write-Host '============================================'
Write-Host '  Installation complete!'
Write-Host '============================================'
Write-Host ''
Write-Host 'Next steps:'
Write-Host '  1. Edit .env and fill in your API keys'
Write-Host '  2. Run .\start.ps1'
Write-Host '  3. In the OpenCode terminal that opens,'
Write-Host '     run /connect to set up your LLM provider'
Write-Host '     and choose a model (first time only)'
Write-Host ''
