<#
    session-up.ps1 -- establish the headless SwitchGamer second session.

    The termsrv patch lets a second interactive session coexist with the
    console. This logs SwitchGamer in over an RDP loopback (127.0.0.2) so that
    session exists and has a framebuffer (RDP provides one) for Apollo to
    capture -- without occupying the physical display. Run as the console user
    (no elevation needed to drive mstsc).

    First run: pass -Password once to store the credential in the Windows vault
    (DPAPI-protected, per-user). After that, no password is needed.

      .\session-up.ps1 -Password '<SwitchGamer password>'
      .\session-up.ps1            # uses the stored credential

    Returns exit 0 with the session id once the session is Active.
#>
param(
    [string]$User,                  # default: $SD_User (config.ps1)
    [string]$RdpHost,               # default: $SD_LoopbackHost
    [string]$Password,
    [switch]$Hide,                  # move the mstsc window off-screen (default: leave it visible)
    [string]$Shell,                 # optional: run this program as the session shell
    [int]   $TimeoutSec = 45,
    [int]   $Width,                 # default: $SD_Width
    [int]   $Height                 # default: $SD_Height
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'config.ps1')
if (-not $User)    { $User    = $SD_User }
if (-not $RdpHost) { $RdpHost = $SD_LoopbackHost }
if (-not $Width)   { $Width   = $SD_Width }
if (-not $Height)  { $Height  = $SD_Height }

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

# Already Active?
function Start-LeakMute {
    # Mute the RDP audio leak (mstsc) on the console while the session lives.
    $muteScript = Join-Path $PSScriptRoot 'mute-leak.ps1'
    if (Test-Path $muteScript) {
        Start-Process powershell -WindowStyle Hidden -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$muteScript`"",'-Loop'
        ) | Out-Null
        Write-Host '[up] leak-mute iniciado (mstsc silenciado enquanto a sessao durar).'
    }
}

$s = Get-UserSession $User
if ($s -and $s.State -eq 'Active') {
    Write-Host "[up] $User already Active in session $($s.Id)."
    Start-LeakMute
    exit 0
}

# Credential: store it once if provided, then require one to exist.
$target = "TERMSRV/$RdpHost"
if ($Password) {
    cmdkey /generic:$target /user:$User /pass:$Password | Out-Null
    Write-Host "[up] stored credential for $target in the vault."
}
$hasCred = cmdkey /list:$target 2>$null | Select-String -SimpleMatch $User
if (-not $hasCred) {
    throw "no stored credential for $target -- run once with -Password '<pw>'."
}

# Minimal loopback .rdp (administrative session, no NLA prompt).
$rdp = Join-Path $env:TEMP 'sd-loopback.rdp'
# authentication level 0 = connect without warning if server auth "fails";
# disabling CredSSP (NLA is already off) avoids the self-signed cert prompt for
# the loopback so the connect is unattended. If a one-time trust dialog still
# appears, tick "Don't ask me again for connections to this computer".
$rdpText = @"
full address:s:$RdpHost
username:s:$User
administrative session:i:1
prompt for credentials:i:0
screen mode id:i:1
desktopwidth:i:$Width
desktopheight:i:$Height
authentication level:i:0
redirectclipboard:i:0
redirectprinters:i:0
redirectsmartcards:i:0
redirectcomports:i:0
redirectposdevices:i:0
redirectwebauthn:i:0
devicestoredirect:s:
drivestoredirect:s:
audiomode:i:0
"@
if ($Shell) { $rdpText += "`r`nalternate shell:s:$Shell" }
$rdpText | Set-Content -Path $rdp -Encoding ASCII

# If a signing cert was set up (scripts/sign-rdp.ps1), sign the .rdp so mstsc
# trusts it and skips the "unknown publisher" warning.
$thumbFile = Join-Path $SD_InstanceDir 'rdp-sign.thumb'
if (Test-Path $thumbFile) {
    $thumb = (Get-Content $thumbFile -Raw).Trim()
    if ($thumb) {
        & "$env:SystemRoot\System32\rdpsign.exe" /sha256 $thumb "$rdp" 2>&1 | Out-Null
    }
}

Write-Host "[up] connecting $User over $RdpHost ..."
Start-Process mstsc -ArgumentList "`"$rdp`"" | Out-Null

$deadline = (Get-Date).AddSeconds($TimeoutSec)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 1500
    $s = Get-UserSession $User
    if ($s -and $s.State -eq 'Active') {
        Write-Host "[up] $User Active in session $($s.Id)."
        Start-LeakMute
        if ($Hide) {
            # Move the mstsc window OFF-SCREEN (not minimized). Minimizing makes
            # the RDP session drop its display surface, which breaks Apollo's
            # capture ("No displays found"). Keeping the window "shown" but at
            # off-screen coordinates keeps the session rendering while hiding it
            # from the console user. Experimental: if the display still drops,
            # run without -Hide (the window stays visible, which always works).
            try {
                Add-Type -Namespace SD -Name Win -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetWindowPos(System.IntPtr h, System.IntPtr after, int x, int y, int cx, int cy, uint flags);' -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 800
                $w = Get-Process mstsc -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
                # SWP_NOSIZE(0x1)|SWP_NOZORDER(0x4)|SWP_NOACTIVATE(0x10) = 0x15
                if ($w) { [SD.Win]::SetWindowPos($w.MainWindowHandle, [IntPtr]::Zero, -32000, -32000, 0, 0, 0x15) | Out-Null; Write-Host '[up] mstsc window moved off-screen.' }
            } catch { }
        }
        exit 0
    }
}
throw "timeout: $User session did not become Active within $TimeoutSec s."
