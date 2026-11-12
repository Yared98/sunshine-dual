# sunshine-dual — setup scripts

These scripts finish the headless multiseat setup on this machine. They perform
**elevated, non-destructive, reversible** changes. Nothing is deleted; no disk
or data is destroyed. Each needs admin — `00-finish-setup.ps1` self-elevates so a
single UAC covers everything.

## One-click

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\00-finish-setup.ps1
```

Runs, in order:

1. **`01-swap-sunshine-to-apollo.ps1`** — stops `SunshineService` and sets it to
   *Manual* so Apollo can bind the host ports (47984/47989/48010/47990).
   Reversible; Sunshine stays installed with its config and pairings intact.
2. **`02-install-apollo.ps1`** — runs the Apollo v0.4.6 installer
   (ClassicOldSong/Apollo). Apollo is used instead of stock Sunshine because it
   bundles the **IddCx virtual display driver** + ViGEmBus, which the headless
   second session needs. The installer is **unsigned** — SmartScreen may warn
   ("More info" → "Run anyway"). Complete its wizard.
3. **`03-register-boot-patch.ps1`** — copies `sunshine_dual.exe` +
   `boot-apply-patch.ps1` to `C:\Program Files\sunshine-dual\`, registers the
   **"sunshine-dual multiseat patch"** scheduled task (SYSTEM, at startup), and
   validates it once. The in-memory termsrv patch does not survive a reboot, so
   this re-applies it on every boot.
4. Applies the termsrv patch to the **running** TermService immediately.

## Undo

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\rollback.ps1
```

Removes the boot task and restores `SunshineService` to Automatic (started).
Leaves Apollo installed (uninstall via *Apps & features* if you want). The live
patch clears on the next reboot.

## Apollo configuration (manual, needs your son's device)

After install, open Apollo's web UI at **https://localhost:47990** and:

- **Audio/Video → Display**: enable the **virtual display** (headless). Set the
  resolution/refresh you want to stream (e.g. 1920×1080 @ 120). This creates a
  per-session virtual monitor so the SwitchGamer session has a framebuffer to
  capture without a physical screen.
- **Audio/Video → Encoder**: NVENC (the RTX 4070 does AV1/HEVC/H264).
- **Pair** Moonlight from the handheld (enter the PIN Apollo shows).

## Wiring the SwitchGamer second session

The gate (concurrent Windows sessions) is handled by the termsrv patch. The
`sunshine_dual` orchestrator drives the second session's lifecycle:

```
sunshine_dual sessions            # list Terminal Services sessions (no admin)
sunshine_dual up <apollo.exe>     # launch Apollo in the SwitchGamer session (SYSTEM)
sunshine_dual down                # log the SwitchGamer session off (SYSTEM)
```

`up`/`down` use `CreateProcessAsUser` into the target session and require
SYSTEM/SeTcbPrivilege, so run them from the SYSTEM context (e.g. a scheduled
task) — the same way the boot patch task runs.

**Still open / needs a live test with the handheld:**

- The `SwitchGamer` session must be *logged in headless* before `up` can launch
  Apollo into it. Tonight's proof used an interactive `mstsc /v:127.0.0.2`
  loopback; the headless-login automation (programmatic RDP/WTS logon with the
  virtual display) is the next piece to build and must be tested against a real
  Moonlight client.
- Gamepad isolation (ViGEmBus pads are system-global) should be verified once
  two sessions stream at once.

## Credentials

The `SwitchGamer` password generated during setup is stored in the session
scratchpad (`switchgamer.cred`), not in the repo. Rotate it with
`Set-LocalUser` if you like.
