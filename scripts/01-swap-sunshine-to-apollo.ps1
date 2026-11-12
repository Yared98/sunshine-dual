<#
    01-swap-sunshine-to-apollo.ps1 -- stop the existing Sunshine service and set
    it to Manual so Apollo (same fork, same ports 47984/47989/48010/47990) can
    take over. NON-DESTRUCTIVE and reversible: nothing is uninstalled, Sunshine's
    config and pairings stay on disk. Run rollback.ps1 to restore Sunshine.
    Requires elevation.
#>
$ErrorActionPreference = 'Continue'

$svc = Get-Service -Name 'SunshineService' -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host '[swap] SunshineService not present -- nothing to stop.'
    return
}

Write-Host "[swap] SunshineService was: Status=$($svc.Status) StartType=$($svc.StartType)"
if ($svc.Status -eq 'Running') {
    Stop-Service -Name 'SunshineService' -Force
    Write-Host '[swap] stopped SunshineService.'
}
Set-Service -Name 'SunshineService' -StartupType Manual
Write-Host '[swap] SunshineService StartType -> Manual (reversible).'

# Confirm the ports are free now.
$busy = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalPort -in 47984,47989,48010,47990 }
if ($busy) {
    Write-Host '[swap] WARNING: these host ports are still in use:'
    $busy | Select-Object LocalPort,OwningProcess | Format-Table -AutoSize | Out-String | Write-Host
} else {
    Write-Host '[swap] host ports 47984/47989/48010/47990 are free.'
}
