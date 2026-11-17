# sunshine-dual

Headless multiseat game streaming enabler for Windows 11, built around
[Apollo](https://github.com/ClassicOldSong/Apollo) / Sunshine + Moonlight.

It lets a second person stream a game to another device (e.g. Moonlight on a
handheld) **while the host keeps working on the physical display**, with fully
decoupled keyboard/mouse/controller focus. The virtual display, capture, NVENC
encoding and gamepad isolation are handled by Apollo; this project supplies the
two pieces Apollo does not:

1. **Multi-session enabler** — a runtime, in-memory pattern-scan patch of
   `termsrv.dll` (inside the live `TermService` svchost) that allows concurrent
   interactive sessions on Windows client SKUs. Nothing is written to disk, so
   SFC/DISM and the file signature are untouched. The patch is re-applied on
   each boot, so Windows updates that replace `termsrv.dll` are absorbed
   automatically as long as the code signature still matches.
2. **Session orchestrator** — provisions a dedicated local user, starts a
   headless interactive session for it, launches Apollo bound to that session,
   and tears everything down on disconnect.

## Why pattern-scan instead of RDPWrap

RDPWrap stores fixed byte offsets per `termsrv.dll` build in an `.ini`; every
cumulative update that touches the DLL breaks it until new offsets are
published. A pattern-scanner searches for the *shape* of the session-check
function at runtime, so it survives most updates and fails safe (it writes
nothing unless a signature matches with high confidence).

## Status

Early scaffold. See [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md).

## Build

```powershell
# Portable pattern-scan core + unit tests only (no vcpkg/Zydis needed):
cmake -S . -B build-core -DSD_BUILD_WIN32=OFF
cmake --build build-core
ctest --test-dir build-core --output-on-failure

# Full Windows build (needs vcpkg with Zydis):
cmake -S . -B build --preset ... -DCMAKE_TOOLCHAIN_FILE=<vcpkg>/scripts/buildsystems/vcpkg.cmake
cmake --build build
```

## Scripts & configuration

The one-click `.cmd` / `.ps1` helpers in [`scripts/`](scripts/) drive the setup:
create the dedicated user, swap Sunshine for Apollo, bring the headless second
session up/down, enforce single-port session priority, enable the virtual
display, and so on. They self-elevate (one UAC) where they need admin.

All machine-specific values (the streaming user name, your console user, the
host name shown to Moonlight, the Apollo install dir and service, the
second-instance config dir, ports) live in one place —
[`scripts/config.ps1`](scripts/config.ps1) — so nothing is hard-coded inside the
scripts. Sensible defaults are baked in (the streaming user defaults to
`SwitchGamer`, the console user and host name default to the current machine's),
so it works out of the box.

To override any value for your machine, copy the example and edit it:

```powershell
copy scripts\config.local.ps1.example scripts\config.local.ps1
# then edit scripts\config.local.ps1 — e.g. $SD_User = 'MyStreamUser'
```

`config.local.ps1` is git-ignored, so your personal paths/user/host never get
committed. You can also set the values through `SD_*` environment variables
(see `config.ps1` for the names).

## Legal

Enabling concurrent RDP sessions on a Windows client SKU is a licensing
restriction (not a technical crack of protected content); run it only on
hardware you own. This repository is interoperability tooling, in the same
category as the Apache-2.0 RDPWrap project. No Microsoft binaries or signatures
are redistributed here.
