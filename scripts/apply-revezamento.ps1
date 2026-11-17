<#
    apply-revezamento.ps1 -- aplica o esquema "1 host revezando" (porta unica
    47989 + identidade/pareamento compartilhados). Autoeleva (um UAC).

    Faz:
      1. Backup e edita a config do Apollo principal (ApolloService) pra usar a
         MESMA identidade do Apollo-2 (cert/pkey/estado em C:\Users\Public\apollo-s2).
         Assim as duas instancias viram "o mesmo host" pro Moonlight.
      2. Reinicia o ApolloService pra carregar a config nova.
      3. Instala o launcher novo de streaming (que espera a porta 47989 liberar) na
         pasta Inicializar do SwitchGamer.
      4. (Re)registra o vigia apollo-priority (SYSTEM, no boot) com a logica nova.

    Reverter: ver reverter-revezamento.ps1 (restaura o backup e volta portas).
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
$svc      = $SD_Service

# ---- 1. identidade compartilhada na config do Apollo principal ----
if (Test-Path $mainConf) {
    $bk = "$mainConf.bak-revez-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item $mainConf $bk -Force
    Write-Host "[apply] backup da config principal: $bk"

    $lines = Get-Content $mainConf | Where-Object { $_ -notmatch '^\s*(pkey|cert|file_state|sunshine_name|credentials_file)\s*=' }
    $lines += "sunshine_name = $SD_HostName"
    $lines += "pkey = $s2dir\pkey.pem"
    $lines += "cert = $s2dir\cert.pem"
    $lines += "file_state = $s2dir\sunshine_state.json"
    $lines += "credentials_file = $s2dir\credentials.json"
    $lines | Set-Content -Path $mainConf -Encoding ASCII
    Write-Host "[apply] config principal agora usa a identidade compartilhada (apollo-s2)."
} else {
    Write-Host "[apply] AVISO: nao achei $mainConf"
}

# ---- 2. reinicia o ApolloService pra carregar ----
try { Restart-Service $svc -Force -ErrorAction Stop; Write-Host "[apply] ApolloService reiniciado." }
catch { Write-Host "[apply] restart service: $($_.Exception.Message)" }

# ---- 3. instala o launcher novo de streaming na pasta Inicializar do SwitchGamer ----
$startup = "C:\Users\$SD_User\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
if (Test-Path "$s2dir\start-apollo.cmd") {
    New-Item -ItemType Directory -Force -Path $startup | Out-Null
    Copy-Item "$s2dir\start-apollo.cmd" (Join-Path $startup 'start-apollo.cmd') -Force
    Write-Host "[apply] launcher novo (espera-porta) instalado no Startup do SwitchGamer."
} else {
    Write-Host "[apply] AVISO: nao achei $s2dir\start-apollo.cmd"
}

# ---- 4. (re)registra o vigia com a logica nova ----
$watcher = Join-Path $PSScriptRoot 'apollo-priority.ps1'
if (Test-Path $watcher) {
    Stop-ScheduledTask       -TaskName 'apollo-priority' -ErrorAction SilentlyContinue | Out-Null
    Unregister-ScheduledTask -TaskName 'apollo-priority' -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    Start-Sleep -Seconds 1
    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$watcher`""
    $trigger   = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName 'apollo-priority' -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName 'apollo-priority'
    Write-Host "[apply] vigia 'apollo-priority' (1-host 47989) registrado e iniciado."
} else {
    Write-Host "[apply] AVISO: nao achei $watcher"
}

Write-Host ""
Write-Host "=== PRONTO. Esquema 1-host revezando aplicado. ==="
Write-Host "No Switch Lite: um host so -> o IP deste PC (porta padrao)."
Write-Host "Se pedir pareamento, abra https://localhost:47990 e confirme o PIN uma vez."
Write-Host ""
Write-Host "Pressione Enter para fechar..."
[void][System.Console]::ReadLine()
