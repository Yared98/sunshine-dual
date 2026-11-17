<#
    ligar-monitor-virtual.ps1 -- liga o monitor virtual (headless_mode) SO no
    Apollo principal (sua sessao de console). Assim, ao transmitir, o Apollo cria
    um display virtual na resolucao que o cliente (Switch) pedir e captura nativo,
    em vez de capturar e escalar seu desktop ultrawide 4480x1080.

    NAO mexe na instancia de streaming (Apollo-2/RDP), que ja usa framebuffer 720p.
    So edita a config e reinicia o servico (sem tarefa agendada nem Startup).
    Autoeleva (um UAC). Reverter: tire a linha 'headless_mode = enabled' do
    arquivo e reinicie o ApolloService (ou restaure o .bak-mv-*).
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
$conf = Join-Path $SD_ApolloDir 'config\sunshine.conf'
if (-not (Test-Path $conf)) { Write-Host "nao achei $conf"; Write-Host "Enter p/ fechar"; [void][System.Console]::ReadLine(); return }

$bk = "$conf.bak-mv-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item $conf $bk -Force
Write-Host "[mv] backup: $bk"

$lines = Get-Content $conf | Where-Object { $_ -notmatch '^\s*(headless_mode|dd_configuration_option)\s*=' }
$lines += 'headless_mode = enabled'
$lines += 'dd_configuration_option = ensure_only_display'
$lines | Set-Content -Path $conf -Encoding ASCII
Write-Host "[mv] headless_mode = enabled + dd_configuration_option = ensure_only_display."
Write-Host "[mv] (durante a transmissao, so o display virtual fica ativo; os monitores"
Write-Host "[mv]  fisicos voltam quando o cliente desconecta)."

try { Restart-Service $SD_Service -Force -ErrorAction Stop; Write-Host "[mv] $SD_Service reiniciado." }
catch { Write-Host "[mv] restart: $($_.Exception.Message)" }

Write-Host "`n--- config atual ---"
Get-Content $conf
Write-Host "`nPronto. Conecte o Switch na SUA sessao: deve criar um display virtual"
Write-Host "na resolucao do Switch (720p) e sair nitido, sem escalar o ultrawide."
Write-Host "Pressione Enter para fechar..."
[void][System.Console]::ReadLine()
