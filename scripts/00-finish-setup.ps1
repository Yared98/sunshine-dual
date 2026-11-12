<#
    00-finish-setup.ps1 -- one-click finisher. Self-elevates (single UAC), then
    runs the whole elevated setup in order and applies the patch now:

      1) swap Sunshine service to Manual (reversible)
      2) install Apollo (complete its wizard)
      3) register the boot-time patch task + validate
      4) apply the termsrv patch to the running TermService now

    Everything here is reversible with rollback.ps1 (and the live patch reverts
    on reboot). Nothing is deleted. Right-click -> "Run with PowerShell", or:
      powershell -ExecutionPolicy Bypass -File .\scripts\00-finish-setup.ps1
#>
param([switch]$Elevated)
$ErrorActionPreference = 'Stop'

# --- self-elevate so a single UAC covers every step ----------------------
$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Requesting elevation (accept the UAC prompt)...'
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-Elevated'
    )
    return
}

$logDir = 'C:\ProgramData\sunshine-dual'
try { New-Item -ItemType Directory -Force -Path $logDir | Out-Null } catch { Write-Host "(log dir: $($_.Exception.Message))" }
try { Start-Transcript -Path (Join-Path $logDir 'finish-setup.log') -Append | Out-Null } catch { Write-Host "(transcript off: $($_.Exception.Message))" }

$repoRoot = Split-Path $PSScriptRoot -Parent
$exe      = Join-Path $repoRoot 'build-win\sunshine_dual.exe'

try {
    # Install Apollo FIRST, before touching Sunshine: if the Apollo wizard is
    # cancelled, the existing Sunshine stack is left running and untouched.
    Write-Host "`n==== 1/5  install Apollo ===="
    & (Join-Path $PSScriptRoot '02-install-apollo.ps1')

    $apolloSvc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Apollo' }
    if (-not $apolloSvc) {
        Write-Host "`nApollo service not detected -- the installer may have been cancelled."
        Write-Host "Leaving Sunshine untouched. Re-run after completing the Apollo install."
        return
    }

    Write-Host "`n==== 2/5  swap Sunshine -> Manual ===="
    & (Join-Path $PSScriptRoot '01-swap-sunshine-to-apollo.ps1')

    Write-Host "`n==== 3/5  start Apollo service ===="
    try {
        Start-Service -Name $apolloSvc.Name -ErrorAction Stop
        Write-Host "[apollo] started service $($apolloSvc.Name)."
    } catch {
        Write-Host "[apollo] could not start $($apolloSvc.Name): $($_.Exception.Message)"
    }

    Write-Host "`n==== 4/5  register boot patch task ===="
    & (Join-Path $PSScriptRoot '03-register-boot-patch.ps1')

    Write-Host "`n==== 5/5  apply patch to the running TermService now ===="
    if (Test-Path $exe) {
        & $exe patch
        Write-Host "apply exit=$LASTEXITCODE"
    } else {
        Write-Host "WARNING: $exe not found -- build first, then rerun."
    }

    Write-Host "`nDone. Next (manual, needs your son's device):"
    Write-Host "  - Open Apollo's web UI at https://localhost:47990 and set a virtual"
    Write-Host "    display + NVENC; pair Moonlight from the handheld."
    Write-Host "  - See scripts/README.md for the SwitchGamer session wiring."
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
}
Write-Host "`nPress Enter to close..."
[void][System.Console]::ReadLine()
