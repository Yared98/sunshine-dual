<#
    setup-session2-elevated.ps1 -- run the SwitchGamer-session Apollo instance
    ELEVATED, so it has the privileges the stream needs (desktop access + input
    injection). Fixes the client-launch "permission denied" and the dead
    controller/touch. Self-elevates (single UAC).

    A non-admin user process can't do those privileged operations (the official
    Apollo works because it runs as the SYSTEM service). So this:
      1. adds SwitchGamer to the local Administrators group,
      2. removes the non-elevated Startup launcher,
      3. registers the 'apollo-switchgamer' task with RunLevel Highest (now that
         SwitchGamer is admin it truly elevates) + LogonType Interactive + at
         logon, so Apollo-2 starts elevated inside SwitchGamer's session,
      4. logs the SwitchGamer session off so the next logon (session-up) applies.

    Security tradeoff: SwitchGamer becomes a local admin. Reverse with:
      Remove-LocalGroupMember -Group Administrators -Member SwitchGamer
      Unregister-ScheduledTask -TaskName apollo-switchgamer -Confirm:$false
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

$user    = 'SwitchGamer'
$machine = $env:COMPUTERNAME
$cmd     = 'C:\Users\Public\apollo-s2\start-apollo.cmd'

# 0. ensure the launcher exists (working dir MUST be the Apollo install dir).
if (-not (Test-Path $cmd)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $cmd) | Out-Null
    @"
@echo off
cd /d "C:\Program Files\Apollo"
start "" "sunshine.exe" "C:\Users\Public\apollo-s2\sunshine.conf"
"@ | Set-Content -Path $cmd -Encoding ASCII
}

# 1. make SwitchGamer a local admin (so the Highest task truly elevates).
try { Add-LocalGroupMember -Group 'Administrators' -Member $user -ErrorAction Stop; Write-Host "[elev] added $user to Administrators." }
catch { if ($_.Exception.Message -match 'already') { Write-Host "[elev] $user already an admin." } else { throw } }

# 2. remove the non-elevated Startup launcher (avoid a second, limited instance).
$startup = "C:\Users\$user\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\start-apollo.cmd"
if (Test-Path $startup) { Remove-Item $startup -Force; Write-Host "[elev] removed non-elevated Startup launcher." }

# 3. register the elevated logon task.
$action    = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument "/c `"$cmd`""
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User "$machine\$user"
$principal = New-ScheduledTaskPrincipal -UserId "$machine\$user" -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName 'apollo-switchgamer' -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "[elev] registered elevated task 'apollo-switchgamer' (Highest, at logon)."

# 4. log the current SwitchGamer session off so the next logon runs it elevated.
$line = qwinsta 2>$null | Select-String "\b$user\b"
if ($line -and ($line.ToString() -match '\s(\d+)\s+(Active|Disc|Disconnected)')) {
    logoff $Matches[1] 2>$null
    Write-Host "[elev] logged off $user session $($Matches[1])."
}

Write-Host "`nDone. Run session-up to log $user back in; Apollo-2 starts ELEVATED."
Write-Host "Then the son connects and launches an app + tries the controller."
Write-Host "`nPress Enter to close..."
[void][System.Console]::ReadLine()
