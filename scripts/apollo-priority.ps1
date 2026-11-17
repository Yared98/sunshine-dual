<#
    apollo-priority.ps1 -- esquema "1 host revezando" na porta compartilhada 47989.

    Roda como SYSTEM (tarefa agendada no boot). Garante que SO UMA instancia
    Apollo use a porta 47989 por vez:

      - RDP de streaming ABERTO (sessao SwitchGamer = Active): para o ApolloService
        (sua sessao de console). O Apollo-2 de streaming, lancado no logon dele,
        espera a porta liberar e assume a 47989.
      - RDP de streaming FECHADO (sessao = Disc): apos um curto grace, ENCERRA
        (logoff) a sessao do SwitchGamer. Isso mata o Apollo-2 e libera a 47989.
      - Porta 47989 livre e sem o usuario de streaming Active: sobe o ApolloService (a vez do console).

    Como as duas compartilham identidade/pareamento (mesmo cert/estado), o Switch
    Lite pareia uma vez no IP deste PC e cai sempre na sessao ativa do momento.

    OBS importante: a sessao RDP (mstsc loopback no console) so vira 'Disc'
    quando VOCE fecha a janela do Remote Desktop -- o Moonlight de streaming
    conectar/desconectar NAO mexe nela. Entao o auto-logoff so dispara quando
    voce encerra de proposito. O grace evita flap em desconexao rapida.
#>
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'config.ps1')
$svc      = $SD_Service
$port     = $SD_Port
$graceSec = 8
$log      = Join-Path $SD_InstanceDir 'apollo-priority.log'
$discSince = $null
$lastState = $null

function Write-Log([string]$m) {
    try { "$([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))  $m" | Add-Content -Path $log -Encoding ASCII } catch {}
}
function Test-PortFree {
    -not (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
}
function Get-SonSession {
    $o = qwinsta 2>$null | Select-String $SD_User
    if (-not $o) { return @{ State = 'none'; Id = $null } }
    $line = $o.ToString()
    if ($line -match '\s(\d+)\s+Active')             { return @{ State = 'Active'; Id = $Matches[1] } }
    if ($line -match '\s(\d+)\s+(Disc|Disconnected)'){ return @{ State = 'Disc';   Id = $Matches[1] } }
    if ($line -match '\s(\d+)\s+')                   { return @{ State = 'other';  Id = $Matches[1] } }
    return @{ State = 'none'; Id = $null }
}

Write-Log "apollo-priority (1-host 47989) iniciado (SYSTEM)."
while ($true) {
    try {
        $s = Get-SonSession
        $svcObj = Get-Service $svc -ErrorAction SilentlyContinue

        if ($s.State -eq 'Active') {
            # Vez do usuario de streaming: o Apollo de console precisa sair da 47989.
            $discSince = $null
            if ($svcObj -and $svcObj.Status -ne 'Stopped') {
                Stop-Service $svc -Force -ErrorAction SilentlyContinue
                Write-Log "RDP aberto (vez do usuario de streaming) -> ApolloService PARADO."
            }
        }
        else {
            # Usuario de streaming nao esta Active.
            if ($s.State -eq 'Disc') {
                if (-not $discSince) { $discSince = Get-Date }
                elseif (((Get-Date) - $discSince).TotalSeconds -ge $graceSec -and $s.Id) {
                    logoff $s.Id 2>$null
                    Write-Log "RDP fechado -> encerrando sessao de streaming (libera a 47989)."
                    $discSince = Get-Date   # evita logoff repetido enquanto encerra
                }
            } else {
                $discSince = $null
            }
            # Sua vez: porta livre e Apollo de console parado -> sobe.
            if ((Test-PortFree) -and $svcObj -and $svcObj.Status -ne 'Running') {
                Start-Service $svc -ErrorAction SilentlyContinue
                Write-Log "Porta 47989 livre (a vez do console) -> ApolloService INICIADO."
            }
        }

        if ($s.State -ne $lastState) { Write-Log "estado de streaming: $($s.State)"; $lastState = $s.State }
    } catch { Write-Log "erro: $($_.Exception.Message)" }
    Start-Sleep -Seconds 2
}
