<#
    set-switchgamer-foreground.ps1 -- let games launched by Apollo grab the
    foreground in the SwitchGamer session, so they actually receive controller
    (ViGEm) input. Self-elevates (single UAC).

    Games launched by another process (Apollo) normally flash in the taskbar
    instead of taking focus (Windows foreground lock). A background game does not
    read the virtual controller, so input "does nothing". Setting
    ForegroundLockTimeout = 0 for SwitchGamer removes that lock so the game comes
    to the front and reads the controller.

    SwitchGamer must be logged in (its hive loaded) when you run this. Re-login
    (session-up) afterwards so the session picks it up.
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

$sid = (Get-LocalUser SwitchGamer).SID.Value
$loaded = Test-Path "Registry::HKEY_USERS\$sid"
$unload = $false
if (-not $loaded) {
    # Load SwitchGamer's hive from their profile if they are not logged in.
    $dat = "C:\Users\SwitchGamer\NTUSER.DAT"
    if (Test-Path $dat) { reg load "HKU\$sid" "$dat" | Out-Null; $unload = $true; $loaded = $true }
}
if (-not $loaded) { throw "SwitchGamer hive not available (log SwitchGamer in first)." }

$key = "Registry::HKEY_USERS\$sid\Control Panel\Desktop"
New-ItemProperty -Path $key -Name 'ForegroundLockTimeout' -Value 0 -PropertyType DWord -Force | Out-Null
Write-Host "[fg] ForegroundLockTimeout = 0 set for SwitchGamer."

if ($unload) { [gc]::Collect(); reg unload "HKU\$sid" | Out-Null }

# Log the SwitchGamer session off so the next logon (session-up) applies it.
$line = qwinsta 2>$null | Select-String '\bSwitchGamer\b'
if ($line -and ($line.ToString() -match '\s(\d+)\s+(Active|Disc|Disconnected)')) {
    logoff $Matches[1] 2>$null
    Write-Host "[fg] logged off SwitchGamer session $($Matches[1]); re-login with session-up."
}

Write-Host "`nDone. Run session-up to log SwitchGamer back in, then the son launches"
Write-Host "a game (it should come to the front) and tries the controller."
Write-Host "`nPress Enter to close..."
[void][System.Console]::ReadLine()
