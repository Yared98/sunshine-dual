<#
    revert-session2-elevated.ps1 -- undo setup-session2-elevated.ps1.
    Running Apollo-2 elevated broke app launching (CreateProcess error 5), so
    this reverts to the non-elevated Startup launcher (which could launch apps).
    Self-elevates (single UAC).

      1. remove SwitchGamer from the local Administrators group,
      2. unregister the elevated 'apollo-switchgamer' task,
      3. restore the non-elevated Startup launcher,
      4. log the SwitchGamer session off for a clean re-login.
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

$user = 'SwitchGamer'
$cmd  = 'C:\Users\Public\apollo-s2\start-apollo.cmd'

try { Remove-LocalGroupMember -Group 'Administrators' -Member $user -ErrorAction Stop; Write-Host "[revert] removed $user from Administrators." }
catch { Write-Host "[revert] admin removal: $($_.Exception.Message)" }

if (Get-ScheduledTask -TaskName 'apollo-switchgamer' -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName 'apollo-switchgamer' -Confirm:$false
    Write-Host "[revert] unregistered elevated task."
}

$startup = "C:\Users\$user\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
if (Test-Path $cmd) {
    New-Item -ItemType Directory -Force -Path $startup | Out-Null
    Copy-Item $cmd (Join-Path $startup 'start-apollo.cmd') -Force
    Write-Host "[revert] restored non-elevated Startup launcher."
}

$line = qwinsta 2>$null | Select-String "\b$user\b"
if ($line -and ($line.ToString() -match '\s(\d+)\s+(Active|Disc|Disconnected)')) {
    logoff $Matches[1] 2>$null
    Write-Host "[revert] logged off $user session $($Matches[1])."
}

Write-Host "`nReverted to non-elevated. Run session-up to bring Apollo-2 back."
Write-Host "`nPress Enter to close..."
[void][System.Console]::ReadLine()
