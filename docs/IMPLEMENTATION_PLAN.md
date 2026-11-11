# sunshine-dual — Plano de implementação

## Objetivo
Permitir que um segundo usuário (ex.: filho via Moonlight em um portátil) jogue
com stream do host **enquanto o host segue em uso na tela física**, com foco de
teclado/mouse/gamepad desacoplado. Apollo cobre display virtual, captura, NVENC
e isolamento de gamepad. Este repo entrega as duas peças que faltam:

1. **Multi-session enabler** — patch em memória (pattern-scan) do `termsrv.dll`
   no processo vivo do `TermService`.
2. **Orquestrador de sessão** — provisiona usuário, abre sessão headless, sobe
   o Apollo nela, derruba tudo no fim.

Alvo: Windows 11 25H2, build 26200.9711, `termsrv.dll` 10.0.26100.8875,
RTX 4070 (NVENC AV1/HEVC/H264).

## Arquitetura em camadas

```
           ┌───────────────────────────────────────────────┐
           │ sunshine_dual (CLI / serviço)  — src/main.cpp  │
           └───────────────┬───────────────────────────────┘
                           │
        ┌──────────────────┴───────────────────┐
        │                                       │
   sd_patch (patcher.h)                  sd_session (session.h)
   enable_multisession()                 enumerate / ensure_user /
        │           │                    launch_in_session / logoff
        │           │
   sd_scan      sd_proc
 (signature.h) (procmem.h)
  byte scan    find_service_pid / find_module /
  (portável)   read_mem / apply_patch / restore_patch
```

- **sd_scan** — puro, portável, sem Win32, 100% testável por unidade.  → Task 01
- **sd_proc** — memória de processo remoto + resolução de módulo (Win32). → Task 02
- **sd_session** — ciclo de vida WTS/CreateProcessAsUser (Win32). → Task 03
- **sd_patch** — assinaturas reais do termsrv + política de segurança.
  **Escrito pelo mantenedor**, não delegado (área crítica; exige disassembly
  do termsrv.dll real e decisão de segurança).

## Ciclo de vida (orquestrador)
Start (patch em memória) → Attach (usuário + display virtual + sessão headless)
→ Stream (Apollo na sessão 2, portas 48984–48990, ViGEm dentro da sessão 2)
→ Teardown (para Apollo → remove display → logoff → opcional: revert patch).

## Regras para integração
- Cada task em seu próprio worktree/branch, **um commit**, sem merge/push.
- `sd_scan` deve compilar e passar `ctest` com `-DSD_BUILD_WIN32=OFF`.
- Componentes Win32: verificação mínima = **compila** no build completo; a
  correção lógica é revisada pelo mantenedor (não há CI com host real).
- Contratos (headers em `include/`) são fixos: workers implementam os `.cpp`,
  não alteram as assinaturas públicas.
