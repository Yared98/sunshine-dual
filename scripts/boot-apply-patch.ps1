<#
    boot-apply-patch.ps1 — run at boot by the "sunshine-dual multiseat patch"
    scheduled task (as SYSTEM). Waits for TermService to be running, then applies
    the termsrv single-session patch. Idempotent: if TermService is already
    patched, sunshine_dual reports ALREADY PATCHED and exits 0.

    The in-memory patch does NOT survive a reboot, so this re-applies it on every
    boot. Logs to C:\ProgramData\sunshine-dual\boot-patch.log.
#>
$ErrorActionPreference = 'Stop'

$installDir = 'C:\Program Files\sunshine-dual'
$exe        = Join-Path $installDir 'sunshine_dual.exe'
$logDir     = 'C:\ProgramData\sunshine-dual'
$log        = Join-Path $logDir 'boot-patch.log'

New-Item -ItemType Directory -Force -Path $logDir | Out-Null
function Log($m) { Add-Content -Path $log -Value ("{0}  {1}" -f (Get-Date -Format o), $m) }

Log '--- boot-apply-patch start ---'

if (-not (Test-Path $exe)) { Log "ERROR: exe not found at $exe"; exit 1 }

# Wait for TermService to be running (it may start slightly after this task).
$deadline = (Get-Date).AddSeconds(180)
while ((Get-Date) -lt $deadline) {
    try {
        if ((Get-Service -Name TermService -ErrorAction Stop).Status -eq 'Running') { break }
    } catch { }
    Start-Sleep -Seconds 3
}
$svc = (Get-Service -Name TermService -ErrorAction SilentlyContinue).Status
Log "TermService status: $svc"
if ($svc -ne 'Running') { Log 'ERROR: TermService not running before deadline'; exit 1 }

# Apply (or confirm) the patch.
$out = & $exe patch 2>&1 | Out-String
$code = $LASTEXITCODE
Log ("patch exit=$code :: " + ($out.Trim() -replace '\r?\n', ' | '))
Log '--- boot-apply-patch end ---'
exit $code
