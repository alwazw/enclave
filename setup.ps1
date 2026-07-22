# ═════════════════════════════════════════════════════════════════════════════
#  AEF2 — Local AI Stack  ·  Windows BOOTSTRAP  (setup.ps1)
# ─────────────────────────────────────────────────────────────────────────────
#  On Windows the stack does NOT run natively. The only real path is
#  WSL2 + Docker Desktop, then the same gum-bash onboarding installer that
#  Linux uses. This script is a thin, transparent bootstrapper — NO MSI:
#     1. verify / enable WSL2            (may require an elevated run + reboot)
#     2. ensure a Linux distro exists    (Ubuntu by default)
#     3. verify Docker Desktop + its WSL integration (guided, never silent)
#     4. hand off to  scripts/onboard.sh  INSIDE WSL  (the real installer)
#
#  Usage (from an elevated PowerShell for first-time WSL enable):
#     PowerShell -ExecutionPolicy Bypass -File .\setup.ps1
#     PowerShell -ExecutionPolicy Bypass -File .\setup.ps1 -Path free
#     PowerShell -ExecutionPolicy Bypass -File .\setup.ps1 -Distro Ubuntu
# ═════════════════════════════════════════════════════════════════════════════
[CmdletBinding()]
param(
    [ValidateSet("", "free", "keys")]
    [string]$Path   = "",          # forwarded to onboard.sh (--path)
    [string]$Distro = "",          # WSL distro to use; auto-detected if blank
    [string]$Profile = "core"      # compose profiles, forwarded to onboard.sh
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Log  { param($m) Write-Host "[OK] $m"  -ForegroundColor Green }
function Info { param($m) Write-Host "[i]  $m"  -ForegroundColor Cyan  }
function Warn { param($m) Write-Host "[!]  $m"  -ForegroundColor Yellow }
function Err  { param($m) Write-Host "[X]  $m"  -ForegroundColor Red; exit 1 }
function Step { param($m) Write-Host "`n==  $m  ==" -ForegroundColor Blue }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

Write-Host ""
Write-Host "  ╔════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║     AEF2 Local AI Stack — Windows Bootstrap (WSL2)     ║" -ForegroundColor Cyan
Write-Host "  ╚════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# ── Step 1: WSL2 ─────────────────────────────────────────────────────────────
Step "Checking WSL2"

$wslOk = $false
try {
    # 'wsl --status' exists only when the WSL feature is present.
    wsl.exe --status *> $null
    if ($LASTEXITCODE -eq 0) { $wslOk = $true }
} catch { $wslOk = $false }

if (-not $wslOk) {
    Warn "WSL is not installed / not enabled."
    if (-not (Test-Admin)) {
        Err ("Enabling WSL2 needs an ELEVATED PowerShell. " +
             "Right-click PowerShell -> 'Run as administrator', then re-run:`n" +
             "    PowerShell -ExecutionPolicy Bypass -File .\setup.ps1")
    }
    Info "Enabling WSL2 (this may take a minute)…"
    # 'wsl --install' enables the VM platform + WSL, installs Ubuntu, sets v2 default.
    wsl.exe --install --no-launch
    Log "WSL2 components installed."
    Warn "A REBOOT is required to finish enabling WSL2."
    Warn "Reboot, then re-run this script to continue the install."
    exit 0
}
Log "WSL is available."

# Make sure the default version is 2 (WSL1 can't run Docker Desktop integration).
try { wsl.exe --set-default-version 2 *> $null } catch {}

# ── Step 2: a Linux distro ───────────────────────────────────────────────────
Step "Checking for a Linux distribution"

# List installed distros (strip NUL bytes wsl.exe emits in UTF-16).
$distros = @()
try {
    $raw = (wsl.exe --list --quiet) -replace "`0", ""
    $distros = $raw -split "`r?`n" | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() }
} catch {}

if ($distros.Count -eq 0) {
    Warn "No WSL distro installed."
    Info "Installing Ubuntu…"
    wsl.exe --install -d Ubuntu --no-launch
    Warn "Ubuntu installed. Launch it ONCE from the Start Menu to create your"
    Warn "Linux user, then re-run this script."
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Distro)) {
    if ($distros -contains "Ubuntu") { $Distro = "Ubuntu" } else { $Distro = $distros[0] }
}
Log "Using WSL distro: $Distro"

# ── Step 3: Docker Desktop + WSL integration ─────────────────────────────────
Step "Checking Docker Desktop"

$dockerInWsl = $false
try {
    wsl.exe -d $Distro -- bash -lc "command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1"
    if ($LASTEXITCODE -eq 0) { $dockerInWsl = $true }
} catch { $dockerInWsl = $false }

if (-not $dockerInWsl) {
    Warn "Docker is not reachable inside WSL ($Distro)."
    Write-Host ""
    Write-Host "  To fix (one-time):" -ForegroundColor Yellow
    Write-Host "   1. Install Docker Desktop:  https://www.docker.com/products/docker-desktop/"
    Write-Host "   2. Docker Desktop -> Settings -> General:  'Use the WSL 2 based engine'"
    Write-Host "   3. Settings -> Resources -> WSL Integration:  enable '$Distro'"
    Write-Host "   4. Start Docker Desktop (whale icon steady), then re-run this script."
    Write-Host ""
    Err "Docker Desktop + WSL integration required."
}
Log "Docker is reachable inside WSL."

# ── Step 4: hand off to the real installer inside WSL ────────────────────────
Step "Launching the onboarding installer inside WSL"

# Translate this Windows repo path to its WSL mount path.
$wslRepo = (wsl.exe -d $Distro -- wslpath "'$ScriptDir'").Trim()
Info "Repo path in WSL: $wslRepo"

# Build the onboard.sh argument string.
$args = "--profile '$Profile'"
if ($Path -ne "") { $args += " --path '$Path'" }

Info "Handing off to scripts/onboard.sh — the rest of the experience is the"
Info "same gum-bash TUI that Linux users get."
Write-Host ""

# Ensure the installer is executable, then run it interactively inside WSL so
# the TUI (gum/whiptail) and masked prompts work in the current terminal.
wsl.exe -d $Distro -- bash -lc "cd '$wslRepo' && chmod +x scripts/onboard.sh setup.sh 2>/dev/null; ./scripts/onboard.sh $args"
$code = $LASTEXITCODE

Write-Host ""
if ($code -eq 0) {
    Log "Onboarding finished. Open http://localhost:3000 for Open WebUI."
} else {
    Warn "Onboarding exited with code $code. Re-run inside WSL to retry:"
    Warn "   wsl -d $Distro"
    Warn "   cd $wslRepo && ./scripts/onboard.sh"
}
exit $code
