<#
    migrate-apps.ps1 -- copy the game/app list from Sunshine into Apollo.
    Apollo is a Sunshine fork and reads the same app schema. This MERGES: it
    adds Sunshine's apps that Apollo does not already have (matched by name),
    keeping Apollo's own defaults. Backs up Apollo's apps.json first, then
    restarts ApolloService so the new list loads. Self-elevates (single UAC).

    Non-destructive: a timestamped backup of Apollo's apps.json is kept next to
    it, and Sunshine's config is only read.
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

$sun = 'C:\Program Files\Sunshine\config\apps.json'
$apo = 'C:\Program Files\Apollo\config\apps.json'
if (-not (Test-Path $sun)) { throw "Sunshine apps.json not found at $sun" }
if (-not (Test-Path $apo)) { throw "Apollo apps.json not found at $apo" }

$sApps = (Get-Content $sun -Raw | ConvertFrom-Json).apps
$aJson = Get-Content $apo -Raw | ConvertFrom-Json
$existing = @($aJson.apps | ForEach-Object { $_.name.Trim().ToLower() })

$list = [System.Collections.ArrayList]@($aJson.apps)
$added = 0
foreach ($src in $sApps) {
    $nm = ([string]$src.name).Trim()
    if ($existing -contains $nm.ToLower()) { Write-Host "skip (already in Apollo): $nm"; continue }
    $obj = [ordered]@{}
    foreach ($p in $src.PSObject.Properties) { $obj[$p.Name] = $p.Value }
    $obj['name'] = $nm
    $obj['uuid'] = [guid]::NewGuid().ToString().ToUpper()
    [void]$list.Add([pscustomobject]$obj)
    $added++
    Write-Host "added: $nm"
}

$aJson.apps = $list.ToArray()

$backup = "$apo.bak-$(Get-Date -Format yyyyMMddHHmmss)"
Copy-Item $apo $backup -Force
Write-Host "backup: $backup"

$json = $aJson | ConvertTo-Json -Depth 30
[IO.File]::WriteAllText($apo, $json, (New-Object Text.UTF8Encoding($false)))
Write-Host "merged $added app(s) into Apollo's apps.json."

try {
    Restart-Service -Name 'ApolloService' -ErrorAction Stop
    Write-Host 'restarted ApolloService (new app list loaded).'
} catch {
    Write-Host "could not restart ApolloService: $($_.Exception.Message) -- restart it manually."
}

Write-Host "`nNote: 'Zelda: Breath of the Wil' keeps your original (typo) name -- rename in Apollo's web UI if you like."
Write-Host "Game commands reference paths like F:\Games\... and Steam; they must be reachable in the SwitchGamer session too."
Write-Host "`nPress Enter to close..."
[void][System.Console]::ReadLine()
