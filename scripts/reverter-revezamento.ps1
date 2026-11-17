<#
    reverter-revezamento.ps1 -- desfaz o esquema "1 host revezando" e volta ao
    estado de duas portas (console 47989 / streaming 48989) que funcionava. Autoeleva.

    Faz:
      1. Restaura a config do Apollo principal do backup mais recente (.bak-revez-*).
      2. Volta a porta do Apollo-2 para 48989 e o launcher original (sem espera).
      3. Reinstala o launcher original no Startup do SwitchGamer.
      4. Para/desregistra o vigia apollo-priority (pra nao interferir).
      5. Reinicia o ApolloService.
    Depois: rode start-stream-session para subir a sessao de streaming de novo.
#>
param([switch]$Elevated)
$ErrorActionPreference = 'Continue'

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",'-Elevated'
    )
    return
}

. (Join-Path $PSScriptRoot 'config.ps1')
$mainConf = Join-Path $SD_ApolloDir 'config\sunshine.conf'
$s2dir    = $SD_InstanceDir
$s2conf   = "$s2dir\sunshine.conf"
$startup  = "C:\Users\$SD_User\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"

# 1. restaura config do principal
$bk = Get-ChildItem 'C:\Program Files\Apollo\config' -Filter 'sunshine.conf.bak-revez-*' -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($bk) { Copy-Item $bk.FullName $mainConf -Force; Write-Host "[rev] config principal restaurada de $($bk.Name)." }
else { Write-Host "[rev] AVISO: sem backup .bak-revez-* da config principal." }

# 2. Apollo-2 volta a porta 48989 e nome original
if (Test-Path $s2conf) {
    $lines = Get-Content $s2conf
    $lines = $lines | ForEach-Object {
        if ($_ -match '^\s*port\s*=')          { 'port = 48989' }
        elseif ($_ -match '^\s*sunshine_name\s*=') { 'sunshine_name = Apollo-SwitchGamer' }
        else { $_ }
    }
    $lines | Set-Content -Path $s2conf -Encoding ASCII
    Write-Host "[rev] Apollo-2 voltou para a porta 48989."
}

# 3. launcher original (sem espera de porta)
$orig = @"
@echo off
rem Launch the streaming-user-session Apollo instance.
cd /d "$SD_ApolloDir"
start "" "sunshine.exe" "$SD_InstanceConf"
"@
$orig | Set-Content -Path "$s2dir\start-apollo.cmd" -Encoding ASCII
if (Test-Path $startup) { Copy-Item "$s2dir\start-apollo.cmd" (Join-Path $startup 'start-apollo.cmd') -Force }
Write-Host "[rev] launcher original restaurado."

# 4. para/desregistra o vigia
Stop-ScheduledTask       -TaskName 'apollo-priority' -ErrorAction SilentlyContinue | Out-Null
Unregister-ScheduledTask -TaskName 'apollo-priority' -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
Write-Host "[rev] vigia apollo-priority desregistrado."

# 5. reinicia o ApolloService
try { Restart-Service $SD_Service -Force -ErrorAction Stop; Write-Host "[rev] $SD_Service reiniciado." } catch {}

Write-Host "`nRevertido. Rode start-stream-session para subir a sessao de streaming (porta 48989)."
Write-Host "Pressione Enter para fechar..."
[void][System.Console]::ReadLine()
