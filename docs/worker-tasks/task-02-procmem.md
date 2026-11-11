# Task 02 — Remote process memory (sd::proc)

## Objetivo único
Implementar as funções Win32 declaradas em `include/sunshinedual/procmem.h`.

## Arquivos que você PODE editar (e somente estes)
- `src/procmem.cpp`

NÃO altere headers, `CMakeLists.txt`, nem outros arquivos. NÃO mude assinaturas.

## Especificação
- `find_service_pid(service_name)`: abra o SCM (`OpenSCManagerW`), abra o serviço
  (`OpenServiceW`), consulte `QueryServiceStatusEx` com `SC_STATUS_PROCESS_INFO`
  para obter o `dwProcessId`. Retorne 0 em qualquer falha. (Para `TermService`
  isso devolve o PID do svchost hospedeiro.)
- `find_module(pid, module_name)`: snapshot de módulos do processo com
  `CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid)`,
  itere `Module32FirstW/Module32NextW`, compare `szModule` case-insensitive com
  `module_name`; devolva `{ (uintptr_t)modBaseAddr, modBaseSize }`. `std::nullopt`
  se não achar.
- `read_mem(process, addr, out, n)`: `ReadProcessMemory`; retorne bytes lidos
  (`SIZE_T` de saída), 0 em falha.
- `apply_patch(process, addr, patch, n)`:
  1. leia os `n` bytes atuais (snapshot) — se não conseguir ler, aborte (nullopt);
  2. `VirtualProtectEx(..., PAGE_EXECUTE_READWRITE, &old)`;
  3. `WriteProcessMemory`; se falhar, restaure a proteção e aborte (nullopt);
  4. `FlushInstructionCache`;
  5. `VirtualProtectEx(..., old, &tmp)` (restaure a proteção original);
  6. devolva `PatchRecord{ addr, original }`.
  Em qualquer falha, **não deixe memória alterada** e devolva nullopt.
- `restore_patch(process, rec)`: reaplique `rec.original` em `rec.addr` com a
  mesma dança de VirtualProtectEx; true em sucesso.

Trate handles com cuidado (feche SCM/serviço/snapshot). Não faça `OpenProcess`
aqui — o chamador passa o `HANDLE process` já aberto (exceto onde a função só
recebe `pid`, aí use o snapshot do Toolhelp que não precisa de handle).

## Verificação
Toolchain da máquina: **MinGW-w64 g++ 16 + Ninja** (não há MSVC/vcpkg). O alvo
`sd_proc` não depende de Zydis. Use:
```powershell
cmake -S . -B build-win -G Ninja -DCMAKE_CXX_COMPILER=g++ -DSD_BUILD_WIN32=ON
cmake --build build-win --target sd_proc
```
Deve **compilar sem erros** o alvo `sd_proc`. Não há teste de runtime (exige
host real); a correção lógica será revisada pelo mantenedor. Atenção a
diferenças de headers do MinGW (ex.: alguns símbolos exigem `#include <tlhelp32.h>`
e `#include <winsvc.h>` explícitos além de `<windows.h>`).

## Regras
- Ao final: `git add src/procmem.cpp` e **um único**
  `git commit -m "task-02: implement sd::proc remote memory"`. Não use `git add -A`.
- NÃO rode git destrutivo (reset/rebase/checkout de branch/merge/push). NÃO saia da pasta.
- Relatório: hash do commit + saída da compilação.
