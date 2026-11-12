<#
    session-down.ps1 -- tear down the SwitchGamer second session.
    Logs the SwitchGamer session off (closes its apps). Run as the console user
    or elevated. No-op if there is no such session.
#>
param([string]$User = 'SwitchGamer')
$ErrorActionPreference = 'Continue'

function Get-UserSession([string]$u) {
    $out = qwinsta 2>$null
    foreach ($line in $out) {
        if ($line -match "\b$([regex]::Escape($u))\b" -and
            $line -match '(\d+)\s+(Active|Disc|Disconnected|Conn|ConnQ|Shadow|Idle|Down)') {
            $st = $Matches[2]; if ($st -eq 'Disc') { $st = 'Disconnected' }
            return [pscustomobject]@{ Id = [int]$Matches[1]; State = $st }
        }
    }
    return $null
}

$s = Get-UserSession $User
if (-not $s) { Write-Host "[down] no $User session."; exit 0 }

$id = $s.Id
logoff $id 2>$null
Start-Sleep -Milliseconds 800
$after = Get-UserSession $User
if (-not $after -or $after.State -ne 'Active') {
    Write-Host "[down] logged off $User session $id."
    exit 0
} else {
    Write-Host "[down] could NOT log off $User session $id -- run elevated (logging off another user's session needs admin)."
    exit 1
}
