<#
    02-install-apollo.ps1 — run the Apollo installer (ClassicOldSong/Apollo).
    Apollo bundles the IddCx virtual display driver + ViGEmBus, which is why we
    use it instead of stock Sunshine for the headless second session.

    The installer is NOT code-signed, so Windows SmartScreen may warn ("More
    info" -> "Run anyway"). This script launches it and waits for it to finish;
    complete the installer's own wizard. Requires elevation.

    -Installer <path>  use a specific installer exe (default: staged copy, else
                       re-download v0.4.6 from the official GitHub release).
#>
param(
    [string]$Installer
)
$ErrorActionPreference = 'Stop'

$version = '0.4.6'
$url     = "https://github.com/ClassicOldSong/Apollo/releases/download/v$version/Apollo-$version.exe"
$repoRoot = Split-Path $PSScriptRoot -Parent
$staged   = Join-Path $repoRoot ".staging-apollo\Apollo-$version.exe"

if (-not $Installer) { $Installer = $staged }

if (-not (Test-Path $Installer)) {
    Write-Host "[apollo] installer not found at $Installer — downloading v$version from GitHub..."
    New-Item -ItemType Directory -Force -Path (Split-Path $Installer) | Out-Null
    Invoke-WebRequest -Uri $url -OutFile $Installer -UseBasicParsing
}

$f = Get-Item $Installer
Write-Host "[apollo] installer: $($f.FullName) ($($f.Length) bytes)"
Write-Host "[apollo] sha256   : $((Get-FileHash $Installer -Algorithm SHA256).Hash)"
$sig = Get-AuthenticodeSignature $Installer
Write-Host "[apollo] signature: $($sig.Status) (unsigned is expected for Apollo)"

Write-Host '[apollo] launching installer — complete the wizard (defaults are fine).'
$p = Start-Process -FilePath $Installer -PassThru -Wait
Write-Host "[apollo] installer exit code: $($p.ExitCode)"

Start-Sleep -Seconds 2
$apolloSvc = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Apollo' }
if ($apolloSvc) {
    Write-Host "[apollo] service installed: $($apolloSvc.Name) ($($apolloSvc.Status))"
} else {
    Write-Host '[apollo] WARNING: no Apollo service detected yet — verify the install completed.'
}
$vdd = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Idd|Virtual Display|Apollo' }
if ($vdd) { Write-Host "[apollo] virtual display device(s): $($vdd.FriendlyName -join ', ')" }
