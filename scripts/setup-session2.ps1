<#
    setup-session2.ps1 -- set up the dedicated Apollo instance that streams the
    SwitchGamer second session. Self-elevates (single UAC).

    Apollo must be started by the user's NORMAL login shell (explorer) so it gets
    an interactive token that can launch games. A scheduled-task launch gives a
    token that fails to spawn child processes (CreateProcess error 5). So this
    installs a Startup-folder launcher in SwitchGamer's profile instead, and
    removes any old scheduled task. It also logs off the current SwitchGamer
    session so the next logon (session-up) picks up the launcher.

    Reversible: rollback removes the Startup item.
#>
param([switch]$Elevated)
$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-Elevated'
    )
    return
}

. (Join-Path $PSScriptRoot 'config.ps1')
$user    = $SD_User
$src     = $SD_StartLauncher
$startup = "C:\Users\$user\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"

# Remove the old scheduled task (its token can't launch games).
if (Get-ScheduledTask -TaskName 'apollo-switchgamer' -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName 'apollo-switchgamer' -Confirm:$false
    Write-Host "[s2] removed old scheduled task 'apollo-switchgamer'."
}

# Create the launcher if it is missing (working dir MUST be the Apollo install
# dir or sunshine.exe can't find assets\shaders and crashes with 0xC0000005).
if (-not (Test-Path $src)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $src) | Out-Null
    @"
@echo off
cd /d "$SD_ApolloDir"
start "" "sunshine.exe" "$SD_InstanceConf"
"@ | Set-Content -Path $src -Encoding ASCII
    Write-Host "[s2] created launcher $src"
}
if (-not (Test-Path $SD_InstanceConf)) {
    Write-Host "[s2] WARNING: $SD_InstanceConf not found."
    Write-Host "     Create the second-instance config first (own port/file_apps/state/cert)."
}
if (-not (Test-Path "C:\Users\$user")) { throw "profile C:\Users\$user not found (log $user in once first)" }
New-Item -ItemType Directory -Force -Path $startup | Out-Null
Copy-Item $src (Join-Path $startup 'start-apollo.cmd') -Force
Write-Host "[s2] installed Startup launcher for $user."

# Log off the current SwitchGamer session so the next logon runs the launcher.
$line = qwinsta 2>$null | Select-String "\b$user\b"
if ($line -and ($line.ToString() -match '\s(\d+)\s+(Active|Disc|Disconnected)')) {
    $sid = $Matches[1]
    logoff $sid 2>$null
    Write-Host "[s2] logged off current $user session $sid (re-login with session-up)."
} else {
    Write-Host "[s2] no active $user session to recycle."
}

Write-Host "`nDone. Now run session-up (no -Shell) to log $user in; Apollo-2 will"
Write-Host "start from Startup with an interactive token that can launch games."
Write-Host "`nPress Enter to close..."
[void][System.Console]::ReadLine()
