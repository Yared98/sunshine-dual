<#
    config.ps1 -- shared configuration for the sunshine-dual scripts.

    Every other script dot-sources this file and reads the $SD_* variables below,
    so there are no hard-coded machine/user specifics in the scripts themselves.

    Resolution order for each value (first that is set wins):
      1. a value you set in  config.local.ps1  (same folder, git-ignored)
      2. an environment variable (SD_USER, SD_CONSOLE_USER, ...)
      3. the default shown here

    To customize: copy  config.local.ps1.example  to  config.local.ps1  and edit.
    Do NOT put secrets here; this file is committed.
#>

# 1. Load local overrides first (git-ignored, optional).
$__sdLocal = Join-Path $PSScriptRoot 'config.local.ps1'
if (Test-Path $__sdLocal) { . $__sdLocal }

# Helper: use existing value, else env var, else default.
function Get-SDValue($current, $envName, $default) {
    if ($current)                         { return $current }
    $ev = [Environment]::GetEnvironmentVariable($envName)
    if ($ev)                              { return $ev }
    return $default
}

# 2/3. Defaults (env + fallback) for anything not set by config.local.ps1.

# Dedicated streaming user (the second, isolated session).
$SD_User        = Get-SDValue $SD_User        'SD_USER'         'SwitchGamer'
# The main/console user (defaults to whoever runs the scripts).
$SD_ConsoleUser = Get-SDValue $SD_ConsoleUser 'SD_CONSOLE_USER' $env:USERNAME
# Display name advertised to Moonlight (defaults to this PC's name).
$SD_HostName    = Get-SDValue $SD_HostName    'SD_HOST_NAME'    $env:COMPUTERNAME

# Apollo install directory and its Windows service name.
$SD_ApolloDir   = Get-SDValue $SD_ApolloDir   'SD_APOLLO_DIR'   'C:\Program Files\Apollo'
$SD_Service     = Get-SDValue $SD_Service     'SD_SERVICE'      'ApolloService'

# Second-instance (streaming-user) config/state directory.
$SD_InstanceDir = Get-SDValue $SD_InstanceDir 'SD_INSTANCE_DIR' 'C:\Users\Public\apollo-s2'

# RDP loopback host used to spin up the headless second session.
$SD_LoopbackHost = Get-SDValue $SD_LoopbackHost 'SD_LOOPBACK_HOST' '127.0.0.2'

# Streaming resolution of the headless RDP framebuffer.
$SD_Width       = [int](Get-SDValue $SD_Width  'SD_WIDTH'  '1280')
$SD_Height      = [int](Get-SDValue $SD_Height 'SD_HEIGHT' '720')

# Apollo base port (web UI is base+1). Used by the shared-port priority scheme.
$SD_Port        = [int](Get-SDValue $SD_Port   'SD_PORT'   '47989')

# Convenience (derived).
$SD_InstanceConf    = Join-Path $SD_InstanceDir 'sunshine.conf'
$SD_StartLauncher   = Join-Path $SD_InstanceDir 'start-apollo.cmd'
$SD_LanIp = try {
    (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.|172\.(1[6-9]|2[0-9]|3[01])\.)' -and $_.PrefixOrigin -eq 'Dhcp' } |
        Select-Object -First 1 -ExpandProperty IPAddress)
} catch { $null }
if (-not $SD_LanIp) { $SD_LanIp = 'this-PC-IP' }
