# Task 03 — Session lifecycle (sd::session)

## Objetivo único
Implementar as funções Win32 declaradas em `include/sunshinedual/session.h`.

## Arquivos que você PODE editar (e somente estes)
- `src/session.cpp`

NÃO altere headers, `CMakeLists.txt`, nem outros arquivos. NÃO mude assinaturas.

## Especificação
- `enumerate()`: `WTSEnumerateSessionsW(WTS_CURRENT_SERVER_HANDLE, ...)`; para
  cada sessão preencha `SessionInfo{ id=SessionId, station=pWinStationName,
  state=State }` e, via `WTSQuerySessionInformationW(..., WTSUserName, ...)`,
  o campo `user`. Libere tudo com `WTSFreeMemory`.
- `ensure_local_user(name, password)`: `NetUserGetInfo` para checar existência;
  se `NERR_UserNotFound`, crie com `NetUserAdd` (nível 1, `USER_PRIV_USER`,
  `UF_DONT_EXPIRE_PASSWD | UF_SCRIPT`). Retorne true se existe ao final
  (criado ou já existente). Idempotente.
- `launch_in_session(session_id, command_line)`:
  1. `WTSQueryUserToken(session_id, &token)` (exige SYSTEM/SeTcbPrivilege);
  2. `DuplicateTokenEx(..., SecurityImpersonation, TokenPrimary, &primary)`;
  3. `CreateEnvironmentBlock(&env, primary, FALSE)`;
  4. `CreateProcessAsUserW` com `CREATE_UNICODE_ENVIRONMENT`, `lpDesktop=L"winsta0\\default"`,
     a `command_line` em buffer mutável (`std::vector<wchar_t>`);
  5. devolva `pi.dwProcessId` (feche handles, `DestroyEnvironmentBlock`).
  0 em qualquer falha.
- `logoff(session_id, wait)`: `WTSLogoffSession(WTS_CURRENT_SERVER_HANDLE,
  session_id, wait ? TRUE : FALSE)`.

Cuidado: `command_line` para `CreateProcessAsUserW` não pode ser string literal
const (a API pode escrever no buffer) — copie para `std::vector<wchar_t>`
terminado em nul.

## Verificação
Toolchain da máquina: **MinGW-w64 g++ 16 + Ninja** (não há MSVC/vcpkg). Use:
```powershell
cmake -S . -B build-win -G Ninja -DCMAKE_CXX_COMPILER=g++ -DSD_BUILD_WIN32=ON
cmake --build build-win --target sd_session
```
Deve **compilar sem erros** o alvo `sd_session`. Sem teste de runtime (exige
SYSTEM + host real); correção revisada pelo mantenedor. Atenção a headers do
MinGW: inclua explicitamente `<wtsapi32.h>`, `<lm.h>` (NetUserAdd/NetUserGetInfo),
`<userenv.h>` além de `<windows.h>`.

## Regras
- Ao final: `git add src/session.cpp` e **um único**
  `git commit -m "task-03: implement sd::session lifecycle"`. Não use `git add -A`.
- NÃO rode git destrutivo (reset/rebase/checkout de branch/merge/push). NÃO saia da pasta.
- Relatório: hash do commit + saída da compilação.
