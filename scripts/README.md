# sunshine-dual — setup scripts

These helpers finish the headless multiseat setup on a Windows 11 host. They are
**elevated, non-destructive and reversible** — nothing on disk or data is
destroyed, and each self-elevates (one UAC) where it needs admin.

## Configuration

Every machine-specific value (the dedicated streaming user, your console user,
the host name shown to Moonlight, the Apollo install dir and service, the
second-instance config dir, ports) lives in **`config.ps1`**, which all the
scripts read — nothing is hard-coded. Sensible defaults are baked in, so it runs
as-is. To override for your machine:

```powershell
copy config.local.ps1.example config.local.ps1   # then edit it
```

`config.local.ps1` is git-ignored; you can also use `SD_*` environment variables.

## 1. Install (one-click)

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\00-finish-setup.ps1
```

Runs, in order:

1. **`01-swap-sunshine-to-apollo.ps1`** — stops `SunshineService` and sets it to
   *Manual* so Apollo can bind the host ports. Reversible; Sunshine stays
   installed with its config/pairings intact.
2. **`02-install-apollo.ps1`** — runs the Apollo installer (ClassicOldSong/Apollo).
   Apollo bundles the **virtual display driver (SudoVDA)** + ViGEmBus the headless
   second session needs. The installer is **unsigned** — SmartScreen may warn
   ("More info" → "Run anyway"). Complete its wizard.
3. **`03-register-boot-patch.ps1`** — installs `sunshine_dual.exe` +
   `boot-apply-patch.ps1` and registers the **boot scheduled task** (SYSTEM, at
   startup) that re-applies the in-memory termsrv patch on every boot.
4. Applies the termsrv patch to the **running** TermService immediately.

Undo with **`rollback.ps1`** (removes the boot task, restores `SunshineService`;
the live patch clears on the next reboot).

Optional: **`migrate-apps.ps1`** copies your existing Sunshine app list into Apollo.

## 2. The second (streaming-user) session

The concurrent-session gate is the termsrv patch. A **second Apollo instance**
runs inside the dedicated streaming user's session (its config lives in
`$SD_InstanceDir`, default `C:\Users\Public\apollo-s2`).

- **`setup-session2.ps1`** (once) installs the instance launcher in the streaming
  user's **Startup folder** (it must start from the login shell, not a scheduled
  task, or the token can't launch games — `CreateProcess` error 5).
- **`session-up.ps1`** logs the streaming user in over an RDP loopback so the
  session exists and has a framebuffer to capture. `start-stream-session.cmd` is a
  double-click wrapper. **`session-down.ps1`** logs it off.
- **`sign-rdp.ps1`** (optional) signs the loopback `.rdp` with a trusted cert so
  mstsc skips the "unknown publisher" warning.

> **Do not minimize the Remote Desktop window while streaming.** An RDP session
> suspends its display when the client window is minimized, which freezes Apollo's
> capture. Leave it visible, or use `session-up.ps1 -Hide` (moves it off-screen
> instead of minimizing, so it keeps rendering).

## 3. One host, taking turns (priority + shared port)

So a single Moonlight host entry reaches whichever session is active:

- **`instalar-revezamento.cmd`** → `apply-revezamento.ps1`: unifies the two Apollo
  instances onto one port + one identity/pairing, and registers the priority
  watcher **`apollo-priority.ps1`** (SYSTEM task). While the streaming user's RDP
  is open, the console Apollo is stopped; when it closes, the streaming session is
  logged off and the console Apollo comes back.
- **`reverter-revezamento.ps1`** reverts to the two-port layout.

## 4. Audio and display helpers

- **`mute-leak.ps1`** — the RDP session captures "Remote Audio", which also plays
  on the console; this mutes the mstsc audio per-app so the console user doesn't
  hear it. `session-up.ps1` starts it automatically.
- **`ligar-monitor-virtual.cmd`** → `ligar-monitor-virtual.ps1`: enables Apollo's
  headless virtual display on the console instance, so it streams at the client's
  resolution natively instead of scaling the physical desktop.
- **`silence-armoury.ps1`** (optional, ASUS only) — scopes ASUS/Armoury Crate
  logon tasks to the console user so they don't pop a UAC prompt in the streaming
  session.

## Credentials

The streaming user's password generated during setup is kept outside the repo
(session scratchpad), never committed. Rotate it with `Set-LocalUser` if you like.
