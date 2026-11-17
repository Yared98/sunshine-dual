<#
    silence-armoury.ps1 -- stop the ASUS/Armoury Crate logon tasks from firing in
    the SwitchGamer streaming session (where they pop a UAC prompt because
    SwitchGamer is a standard user). Self-elevates (single UAC).

    These tasks trigger "at logon of ANY user" with Highest run level. This
    scopes their logon trigger to the console user only (default: the current
    console user), so they still run for you but not for the streaming user.
    Reversible: set the trigger UserId back to empty in Task Scheduler.
#>
param(
    [string]$ConsoleUser,
    [switch]$Elevated
)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'config.ps1')

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-Elevated'
    )
    return
}

if (-not $ConsoleUser) {
    $ConsoleUser = (Get-CimInstance Win32_ComputerSystem).UserName
    if (-not $ConsoleUser -or $ConsoleUser -match [regex]::Escape($SD_User)) { $ConsoleUser = "$env:COMPUTERNAME\$SD_ConsoleUser" }
}
Write-Host "[armoury] scoping logon tasks to: $ConsoleUser"

$names = 'ArmourySocketServer','ASUS AISuiteIII','ASUS DIPAwayMode','AsusDriverHub'
foreach ($n in $names) {
    $t = Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue
    if (-not $t) { Write-Host "[armoury] skip (not found): $n"; continue }
    $changed = $false
    foreach ($trg in $t.Triggers) {
        if ($trg -and $trg.CimClass.CimClassName -match 'LogonTrigger' -and [string]::IsNullOrEmpty($trg.UserId)) {
            $trg.UserId = $ConsoleUser
            $changed = $true
        }
    }
    if ($changed) {
        try { Set-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -Trigger $t.Triggers -ErrorAction Stop | Out-Null
              Write-Host "[armoury] scoped '$($t.TaskPath)$($t.TaskName)' logon trigger to $ConsoleUser." }
        catch { Write-Host "[armoury] FAILED '$n': $($_.Exception.Message)" }
    } else {
        Write-Host "[armoury] '$n': no any-user logon trigger to change."
    }
}
Write-Host "`nDone. These will no longer fire in the SwitchGamer session."
Write-Host "`nPress Enter to close..."
[void][System.Console]::ReadLine()
