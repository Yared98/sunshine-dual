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

### Option B — the son streams a truly separate Windows session (WORKING)

A single Apollo streams the service/console session, and its "Virtual Display"
only adds an isolated *screen* inside that session (keyboard/mouse still shared).
For full isolation the son needs his own Windows session, so a **second Apollo
instance runs inside the `SwitchGamer` session**:

- `C:\Users\Public\apollo-s2\sunshine.conf` — its own config: `port = 48989`
  (web UI 48990), own `file_apps` / `file_state` / `pkey` / `cert`.
- `C:\Users\Public\apollo-s2\start-apollo.cmd` — `cd /d "C:\Program Files\Apollo"`
  then starts `sunshine.exe` with that config. The working dir **must** be the
  Apollo install dir or it can't find `assets\shaders` and crashes (0xC0000005).
- **`setup-session2.ps1`** installs that launcher in the SwitchGamer **Startup
  folder** (and removes any old scheduled task). It must start from the normal
  login shell, not a scheduled task: a task-launched process gets a token that
  can't spawn games (`CreateProcess` error 5).

Flow: `setup-session2.ps1` (once) → `session-up.ps1` logs SwitchGamer in over the
RDP loopback → Startup launches Apollo-2 → the son pairs **Artemis** (the Apollo
client, not stock Moonlight) to `host:48989` and streams his own session while
you keep working on the console.

**Caveats learned the hard way:**

- **Do not minimize or close the mstsc window** while streaming — an RDP session
  drops its display surface when the client isn't shown, which breaks Apollo
  capture (`No displays found` / `DuplicateOutput 0x80070005`). `session-up -Hide`
  moves it off-screen instead (experimental); otherwise leave it visible.
- NVENC only appears when the display is properly attached (window connected);
  with the display dropped it falls back to software (libx264).
- `SwitchGamer` is a fresh user: Steam login, emulator configs and saves are
  per-user (the Steam login screen in his session is expected).
- Gamepad isolation (ViGEmBus pads are system-global) still to verify with two
  concurrent streams.

## Credentials

The `SwitchGamer` password generated during setup is stored in the session
scratchpad (`switchgamer.cred`), not in the repo. Rotate it with
`Set-LocalUser` if you like.
