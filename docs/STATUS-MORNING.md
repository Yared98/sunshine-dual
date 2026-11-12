# Bom dia — resumo da noite (2026-11-12)

## TL;DR
O código e a automação estão prontos e commitados. **Os passos que exigem admin
não rodaram** porque o UAC precisa de clique e você estava dormindo — e o próprio
harness bloqueou criar tarefa SYSTEM sozinho (persistência). Então deixei tudo
atrás de **um clique**: rode `scripts\00-finish-setup.ps1`, aceite **1 UAC**,
conclua o instalador do Apollo, e pareie o Moonlight. Nada destrutivo foi feito.

## O que eu fiz sozinho (tudo commitado na `main`)
- **Patcher idempotente** (`5035750`): a assinatura agora casa antes e depois do
  patch, então a re-aplicação no boot reconhece "já aplicado" em vez de falhar.
  Reconferido: continua **match único** no `termsrv.dll` (offset `0xA68A7`).
- **Fix do SeDebugPrivilege** (`c28701a`): sem habilitar o privilégio, o
  `OpenProcess` no TermService dava GLE=5 mesmo elevado.
- **Orquestrador** (`f268280`): `sunshine_dual sessions|up|down`. O `sessions`
  foi testado (lista Yared/Console e SwitchGamer/sessão 2). `up`/`down` compilam
  e estão fiados, mas precisam de SYSTEM + Apollo para rodar de verdade.
- **Apollo v0.4.6 baixado** e verificado (17.529.901 bytes, SHA256
  `42B2AEFAACB3474511517A56B96EE9F0517F30AC38B5DD2FDA9FD5B478F5021A`) em
  `.staging-apollo\` (fora do git). **Atenção: o instalador não é assinado** —
  o SmartScreen vai avisar ("Mais informações" → "Executar assim mesmo").
- **Scripts 1-clique** em `scripts\` (todos parse-checados e reversíveis).

## O estado AGORA (neste boot, antes de reiniciar)
- O patch do TermService **ainda está aplicado** da sessão anterior → o gate de
  multisessão está aberto neste boot. Um reboot zera isso (por isso a tarefa de
  boot). Não reiniciei nada.
- Seu **Sunshine continua rodando normalmente** — eu **não** mexi nele ainda.
  A troca para o Apollo só acontece quando você rodar o `00-finish-setup`.
- Usuário `SwitchGamer` existe (criado ontem, grupos Users + Remote Desktop
  Users). A sessão de teste dele foi deslogada.

## O que fazer de manhã (≈5 min)
1. Abrir um PowerShell e rodar:
   ```
   powershell -ExecutionPolicy Bypass -File D:\Projetos\sunshine-dual\scripts\00-finish-setup.ps1
   ```
2. Aceitar **1 UAC**. O script então: coloca o Sunshine em Manual → abre o
   instalador do Apollo (conclua o wizard; "Run anyway" no SmartScreen) →
   registra a tarefa de boot e valida → aplica o patch agora.
3. Abrir **https://localhost:47990** (Apollo): ligar **display virtual**
   (headless), encoder **NVENC**, e **parear o Moonlight** do portátil do seu
   filho.

## Decisões que deixei para você (não dava para fazer sozinho com segurança)
- **Trocar Sunshine→Apollo** mexe na sua stack de streaming atual. É reversível
  (`scripts\rollback.ps1` volta o Sunshine), mas é sua chamada confirmar a troca.
- **Instalador não assinado** do Apollo — você decide confiar e executar.
- **Tarefa SYSTEM no boot** (persistência que injeta no TermService todo boot):
  é o que você pediu, mas é uma mudança sensível que deve ser você a autorizar
  rodando o script elevado.

## Ainda em aberto (precisa de teste com o aparelho do seu filho)
- **Login headless do SwitchGamer**: a prova de ontem usou `mstsc` loopback
  interativo. Falta automatizar o logon headless (RDP/WTS programático + display
  virtual) para o `up` conseguir subir o Apollo na sessão 2 sem você logar à mão.
- **Isolamento de gamepad** (ViGEmBus é global): conferir com as duas sessões
  transmitindo ao mesmo tempo.
- Teste fim-a-fim real (Moonlight conectando e jogando) só com um cliente.

## Reverter tudo
```
powershell -ExecutionPolicy Bypass -File D:\Projetos\sunshine-dual\scripts\rollback.ps1
```
Remove a tarefa de boot e devolve o Sunshine para Automatic. Apollo fica
instalado (desinstale por Apps & Recursos se quiser). O patch vivo some no reboot.
