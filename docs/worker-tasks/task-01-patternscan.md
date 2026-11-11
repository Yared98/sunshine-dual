# Task 01 — Pattern-scan core (sd::scan)

## Objetivo único
Implementar o scanner de assinaturas de bytes declarado em
`include/sunshinedual/signature.h`. Código puro C++20, **sem Win32, sem
dependências externas**.

## Arquivos que você PODE editar (e somente estes)
- `src/signature.cpp`  — a implementação
- `tests/scan_tests.cpp` — os testes (substitua o placeholder)

NÃO altere nenhum header em `include/`, o `CMakeLists.txt`, nem qualquer outro
arquivo. Não mude as assinaturas públicas das funções.

## Especificação (contrato em signature.h)
- `parse_ida("48 8B ?? C3")` → `Signature{ bytes={0x48,0x8B,0x00,0xC3}, mask="xx?x" }`.
  - Aceita `?` e `??` como wildcard. Hex sem case sensitivity. Espaços múltiplos ok.
  - Entrada malformada (nibble ímpar, token inválido, string vazia/sem bytes) →
    lança `std::invalid_argument`.
- `from_bytes(raw, mask, name)` → monta Signature; se `raw.size() != mask.size()`
  lança `std::invalid_argument`. Em `mask`, qualquer char diferente de `'x'`/`'X'`
  conta como wildcard? NÃO: aceite apenas `'x'` (exato) e `'?'` (wildcard); outro
  char → `std::invalid_argument`.
- `find_first(data, size, sig)` → offset do primeiro match, ou `std::nullopt`.
  Um match em `off` exige `off + sig.size() <= size`. Em cada i, casa se
  `mask[i]=='?'` OU `data[off+i]==bytes[i]`. Se `!sig.valid()` → `std::nullopt`.
- `find_all(...)` → todos os offsets, da esquerda p/ direita, **permitindo
  sobreposição** (avança de 1 em 1).

## Verificação (rode e cole a saída no relatório)
Toolchain da máquina: **MinGW-w64 g++ 16 + Ninja** (não há MSVC). Use:
```powershell
cmake -S . -B build-core -G Ninja -DCMAKE_CXX_COMPILER=g++ -DSD_BUILD_WIN32=OFF
cmake --build build-core
ctest --test-dir build-core --output-on-failure
```
Os testes em `tests/scan_tests.cpp` devem cobrir, no mínimo:
match no início, no fim e no meio; wildcard casando; no-match; tamanho de sig
maior que o buffer; matches sobrepostos; `parse_ida` com entrada válida e
inválida (checar que lança). Use o harness em `tests/test_harness.h`
(`SD_CHECK`, `SD_CHECK_EQ`, `SD_TEST_SUMMARY`). `ctest` deve passar 100%.

## Regras
- Ao final: `git add src/signature.cpp tests/scan_tests.cpp` e **um único**
  `git commit -m "task-01: implement sd::scan pattern scanner"`. Não use `git add -A`.
- NÃO rode `git reset`, `git rebase`, `git checkout <branch>`, `git merge`, `git push`.
- NÃO saia da pasta do worktree. NÃO instale nada global.
- Relatório curto: hash do commit + saída do `ctest`.
