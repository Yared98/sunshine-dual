<#
    rollback.ps1 -- undo the setup. Self-elevates (single UAC). Reverses
    everything NON-DESTRUCTIVELY:
      - unregister the boot-time patch task
      - restore SunshineService to Automatic and start it
    It does NOT uninstall Apollo (use its own uninstaller in
    "Apps & features" if you want that) and does NOT touch data.

    The live in-memory termsrv patch is not reverted here -- a reboot clears it,
    or restart the TermService.
#>
param([switch]$Elevated)
$ErrorActionPreference = 'Continue'

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-Elevated'
    )
    return
}

$taskName = 'sunshine-dual multiseat patch'
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "[rollback] removed scheduled task '$taskName'."
} else {
    Write-Host "[rollback] task '$taskName' not present."
}

$svc = Get-Service -Name 'SunshineService' -ErrorAction SilentlyContinue
if ($svc) {
    Set-Service -Name 'SunshineService' -StartupType Automatic
    try { Start-Service -Name 'SunshineService' } catch { Write-Host "[rollback] start Sunshine: $($_.Exception.Message)" }
    Write-Host '[rollback] SunshineService -> Automatic and started.'
} else {
    Write-Host '[rollback] SunshineService not present.'
}

Write-Host '[rollback] NOTE: Apollo left installed (uninstall via Apps & features if desired).'
Write-Host '[rollback] NOTE: live termsrv patch clears on reboot (or restart TermService).'
Write-Host "`nPress Enter to close..."
[void][System.Console]::ReadLine()
