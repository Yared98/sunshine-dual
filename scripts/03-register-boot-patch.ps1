<#
    03-register-boot-patch.ps1 — install the patcher to a stable location and
    register a boot-time scheduled task that re-applies the termsrv
    single-session patch on every startup (the in-memory patch does not survive
    a reboot). Requires elevation.

    Creates:
      C:\Program Files\sunshine-dual\sunshine_dual.exe
      C:\Program Files\sunshine-dual\boot-apply-patch.ps1
      scheduled task "sunshine-dual multiseat patch" (SYSTEM, at startup)
      C:\ProgramData\sunshine-dual\boot-patch.log

    Undo with rollback.ps1.
#>
param(
    [string]$BuildExe
)
$ErrorActionPreference = 'Stop'

$taskName   = 'sunshine-dual multiseat patch'
$installDir = 'C:\Program Files\sunshine-dual'
$logDir     = 'C:\ProgramData\sunshine-dual'
$repoRoot   = Split-Path $PSScriptRoot -Parent

if (-not $BuildExe) { $BuildExe = Join-Path $repoRoot 'build-win\sunshine_dual.exe' }
if (-not (Test-Path $BuildExe)) { throw "built exe not found at $BuildExe — build it first (cmake --build build-win --target sunshine_dual)" }

New-Item -ItemType Directory -Force -Path $installDir | Out-Null
New-Item -ItemType Directory -Force -Path $logDir     | Out-Null

Copy-Item $BuildExe (Join-Path $installDir 'sunshine_dual.exe') -Force
Copy-Item (Join-Path $PSScriptRoot 'boot-apply-patch.ps1') (Join-Path $installDir 'boot-apply-patch.ps1') -Force
Write-Host "[boot] installed exe + wrapper to $installDir"

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $installDir 'boot-apply-patch.ps1'))
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "[boot] registered scheduled task '$taskName' (SYSTEM, at startup)."

# Validate immediately: run it once and show the log tail. Because TermService is
# already up, it applies now (or reports ALREADY PATCHED if this session is
# already patched) — either way exit 0.
Write-Host '[boot] running the task once to validate...'
Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 8
$log = Join-Path $logDir 'boot-patch.log'
if (Test-Path $log) {
    Write-Host '[boot] --- boot-patch.log (tail) ---'
    Get-Content $log -Tail 8 | ForEach-Object { Write-Host "    $_" }
} else {
    Write-Host '[boot] WARNING: no log produced yet — check Task Scheduler history.'
}
