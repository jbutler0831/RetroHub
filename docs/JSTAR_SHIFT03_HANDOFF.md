# RetroHub — J-Star Shift 03: Appearance, Controller Testing, Compatibility and Safe Collaboration

Date: 2026-10-22 · Mac: MacBook Pro 2019 (MacBookPro16,1), Intel Core i9-9980HK 8-core, 64 GB, Radeon Pro 5500M 8 GB + Intel UHD 630, macOS 14.4.1 (23E224) · Working copy: the local ZIP copy · Migration clone: a fresh `git clone` · **Nothing pushed**

| Area | Result | Evidence |
|---|---|---|
| A. Existing work preserved | **PASS** | Phase 1 and Shift 02 split into two commits; each builds and passes its tests |
| B. Appearance | **PASS** (automated) · window checks **pending** | Follow System / Light / Dark in Setup and View › Appearance; badge text 1.55:1 → 5.62:1 as drawn in Light |
| C. DualSense | **UNVERIFIED — needs you** | Diagnostics tool built; test procedure in §4.4 |
| D. Compatibility inventory | **PASS** (read-only, automated) | `scripts/dev-inventory.sh`: all 29 systems SETUP_REQUIRED on this Mac (no emulators installed) |
| E. First NES game | **NOT STARTED — needs your approval** | Test ROM validated; RetroArch 1.22.2 Universal and an x86_64 Mesen core exist; steps in §6.4 |
| F. GitHub migration | **PASS** (local only) | ZIP = `origin/main` exactly; branch `jstar/shift-01-03` (9 commits) in the clone; same tree, 184 self-tests pass |
| Build | **PASS** | Debug, strict-concurrency and universal release: 0 warnings; release has no debug code |
| Self-tests | **PASS** | 184 (112 before this shift) |
| Window checks | **PENDING** | Need the Mac's screen: §9 |

---

## 1. Phase A — existing work preserved

### Repository state at the start

- The local ZIP copy, branch `main`, **no remotes**. History: the ZIP baseline (`818c1ab`), Shift 01 (`c87543f`, `2d4f1dd`), and the Phase 1 and Shift 02 work **uncommitted** (9 modified files, 4 new).
- Before committing anything, every uncommitted file was saved to a backup archive, and afterwards compared byte for byte: nothing was discarded or overwritten.
- The diff held no stray binaries, absolute paths, credentials or debug prints. The only tracked binaries are the app icons from the original ZIP.

### The two commits

The Phase 1 state was rebuilt from that session's record (the fix, its window check and its audit entries) on top of `2d4f1dd`, without touching the working files. Shift 02 went on top.

| Local | Migrated | Commit | Contents | Checked |
|---|---|---|---|---|
| `6293df3` | `d2cdca7` | Mac: show sidebar names and counts again; sidebar window checks | Sidebar fix (F5), strict-concurrency fix (F6), first `UIChecks.swift` (5 checks), audit entries | Builds with 0 warnings (strict too); 91 self-tests pass |
| `254259b` | `e76ad6a` | Mac: sidebar sections, keyboard and menu navigation, one window | All of Shift 02 | 0 warnings; 112 self-tests pass |

Author on both: Jay, with `Co-Authored-By: Claude Opus 5.5`, like the Shift 01 commits.

### .gitignore

The original ignored build folders, `.DS_Store` and the dev test library. This shift adds:
- any `mac/.build*` folder;
- editor and platform files;
- `.env` files and signing material;
- logs;
- game image formats that can't be anything else.

`.bin`, `.zip`, `.7z` and `.md` are left to review, because they're also ordinary files. No tracked file is affected.

---

## 2. Phase B — Appearance

### What was there

RetroHub already followed the macOS appearance. It uses system colors, sets no `NSAppearance` and no `preferredColorScheme`. The only override is couch mode, which forces Dark on a black background (a TV-style screen). There was no way to choose an appearance for RetroHub alone.

### What changed

- **Setup › Appearance** and **View › Appearance**: Follow System (default), Light, Dark.
- The choice sets `NSApp.appearance`:
  - **What changes:** RetroHub's own windows, menus and alerts, and **never the Mac's setting**. The checks confirm System Settings is untouched.
  - **When:** it's applied before the window first draws, so there's no flash of the wrong appearance.
  - **Where it's saved:** in the app's own settings, per bundle ID. RetroHub Dev, RetroHub Dev Check and the installed RetroHub each keep their own.
- **Couch mode keeps its dark TV look** in every setting. That's deliberate: it's a full-screen, controller-first screen, and a light version would be a design change.

### Contrast fix

In Light mode the orange and green status text was hard to read:

| Element | Light, before | Light, after | Dark, before | Dark, after |
|---|---|---|---|---|
| Sidebar "setup needed" count and ⚠ (as drawn, measured from the window) | **1.55:1** | **5.62:1** | about 4.4:1 (calculated) | **5.18:1** |
| "Setup needed" pill, shader warning, "Installed", controller icon | about 1.6–2.2:1 (calculated) | ≥ 4.5:1 (self-test) | ≥ 4.4:1 | ≥ 4.5:1 (self-test) |

Small text needs 4.5:1.
- **The fix:** `NSColor.readable` moves the same orange and green 60% toward black in Light mode and 35% toward white in Dark mode. The badge background tints are unchanged.
- **How it was checked:** one round of measuring the drawn window found the first values too weak in Light (4.29:1), because the sidebar is darker than the window background. The self-test now models the sidebar as drawn.

### Tests

- **Self-tests:** the three choices, and every status color on every background it's drawn on, in both appearances (14 checks).
- **Window checks:**
  - View › Appearance › Dark and Setup › Appearance › Light each check that the choice is saved, applied, ticked in the menu, and leaves the Mac's setting unchanged.
  - The badge's contrast is measured in the drawn window, in Light and Dark.
  - Couch mode stays dark while RetroHub is set to Light (average luminance below 0.2).
  - Follow System returns to the Mac's setting.
  - A **relaunch run** confirms Dark is still applied after quitting and reopening.
- The relaunch path was verified on its own with a throwaway bundle: Dark is applied at launch and the window draws dark.

---

## 3. Phase D — Emulator and hardware compatibility

### How RetroHub detects emulators today

**Detection:**
- **How it looks:** an emulator counts as installed when an app with the exact expected name is in `/Applications` or `~/Applications` (shadPS4: a `shadPS4/shadps4` program). The desktop app has its own lists of paths for Windows and Linux.
- **What it doesn't read:** no versions, and no CPU architectures. On this Intel Mac, an Apple silicon-only build would count as installed and then fail to start.
- **RetroArch cores:** a file named `<core>_libretro.dylib` in `~/Library/Application Support/RetroArch/cores`. That matches RetroArch's own default (`platform_darwin.m`, builds with the core updater), but RetroArch's `libretro_directory` setting isn't read.

**Errors:**
- **"Setup needed":** the readiness check names a missing emulator or core.
- **Firmware:** only described in static notes.
- **Launch failures:** they surface as an alert at launch.
- **Exits:** before this shift, an emulator that quit immediately went unnoticed.

**Duplicated catalog:** the systems and emulators catalog exists twice, in `mac/Sources/RetroHub/Systems.swift` and `desktop/src/systems.js`, kept in step by hand.

### Proposed architecture (Mac, Windows, Linux, Raspberry Pi)

1. **One catalog as data:** systems, backends, cores, and known requirements, each with its source. Both apps read it, or a CI check keeps the two copies equal until they do.
2. **A probe per platform, one snapshot format:** `Host` (OS, CPU and its features, RAM, GPUs and graphics APIs, disks) and `Installed` (emulators with path, version and architectures; cores with architectures and firmware lists; folders).
   - **macOS:** Mach-O headers, `Info.plist`, Metal, `sysctl`. Built this shift.
   - **Windows:** PE header machine type, known paths and registry, DXGI/Vulkan.
   - **Linux/Pi:** ELF `e_machine`, `/proc/cpuinfo`, Flatpak, optional `vulkaninfo`.
3. **One evaluator:** a pure function from catalog + snapshot to one status per system, tested with shared fixtures of made-up machines, so the Swift and JavaScript ports must agree.
4. **Optional benchmarks:**
   - **Never by default.** They need a person's opt-in.
   - **Limits:** time-boxed, ordinary load (no stress tests), and reported as measurements, not promises.
5. **Per-game sources:**
   - **Display only:** shown with attribution and a date, keyed by the identifiers each source uses (PS3 serials, PS4 title IDs).
   - **Never inferred:** RetroHub would show what a source says, nothing more.

### Built this shift (macOS, read-only)

`mac/scripts/dev-inventory.sh` (`RetroHub --inventory [--json] [--include-documents]`, debug builds).

What it does:
- **Changes and runs nothing:** no game is started, no benchmark runs.
- **Picks the emulator the way the launcher does.** A self-test checks the two agree on this Mac.

Statuses:

| Status | Meaning |
|---|---|
| READY | The emulator RetroHub would use is installed, built for this CPU, and nothing it's known to need is missing |
| SETUP_REQUIRED | Something nameable is missing: an emulator, a core, or required firmware (none of the required files present) |
| UNKNOWN | Installed, but what it needs can't be checked from outside (PCSX2's BIOS, RPCS3's firmware), some but not all required firmware is present (often one region is enough), the firmware folder is protected, or a core has no `.info` file |
| UNSUPPORTED | The installed emulator or core isn't built for this CPU, so macOS won't run it (from the Mach-O header, not guessed) |

How each part is checked:
- **Confidence:** each result gets a confidence (high, medium or low) and lists its evidence and limits.
- **Firmware:**
  - **The list:** comes from each core's own `.info` file (`firmwareN_path`, `firmwareN_opt`), not from a list written into RetroHub.
  - **Where it's looked for:** RetroArch's system folder. On macOS that defaults to `~/Documents/RetroArch/system` (RetroArch source, `platform_darwin.m`).
  - **Protected folder:** macOS protects `~/Documents`, so the inventory doesn't read it unless you pass `--include-documents`.

### This Mac

```
macOS 14.4.1 (23E224) · MacBookPro16,1
CPU    Intel Core i9-9980HK @ 2.40GHz · x86_64 · 8 cores, 16 threads · SSE4.2 · AVX · AVX2
RAM    64 GB
GPU    AMD Radeon Pro 5500M · Metal 3: yes · 8.0 GB usable
GPU    Intel UHD Graphics 630 · Metal 3: yes · low power · 1.5 GB usable
Emulators: none installed.  RetroArch settings: not found.  Cores: none.
All 29 systems: SETUP_REQUIRED (high), e.g. NES: "Install RetroArch (with the Mesen, FCEUmm, or Nestopia core) or OpenEmu."
```

Self-tests (54 checks):
- Mach-O parsing: Intel, Apple silicon, universal, scripts and truncated headers.
- `.info` parsing, using a real core's entries.
- Every status on made-up Macs: missing core, Intel core, an Apple silicon core picked first on Intel, BIOS missing, partial and complete, a protected folder, no `.info` file, standalone emulators, and Apple silicon with and without Rosetta.
- Agreement with the launcher on this Mac.

### Per-game compatibility sources (researched; nothing imported)

| Source | Keyed by | Notes |
|---|---|---|
| RPCS3 (rpcs3.net/compatibility) | PS3 serial (e.g. BLUS30279) | Statuses Playable / Ingame / Intro / Loadable / Nothing; an undocumented JSON export (`?api=v1&export`) is reported on its forum, with some titles missing |
| shadPS4 (`shadps4-emu/shadps4-game-compatibility` on GitHub) | PS4 title ID | Tiers such as Playable and In-Game; counts quoted by third parties disagree |
| Vita3K (vita3k.org/compatibility.html) | Vita title ID | Statuses by playability |
| Dolphin wiki, xemu, PPSSPP | — | Exist, but not verified this shift |
| RetroArch cores | — | No per-game lists; core `.info` files give firmware and supported extensions only |

---

## 4. Phase C — DualSense

### How input works today

- **Source and delivery:**
  - **Source:** GameController framework. Each control has a handler on the main queue that sends one command: move, play, back, favorite, previous/next system, couch mode.
  - **Frontmost only:** input arrives only while RetroHub is the frontmost app (`shouldMonitorBackgroundEvents` stays off). There's no system-wide interception.
- **Bindings:** GameController names buttons by position, as on an Xbox controller. **On a DualSense these are expected, not confirmed** (Apple's convention):
  - `buttonA` = Cross: play
  - `buttonB` = Circle: back
  - `buttonY` = Triangle: favorite
  - `buttonMenu` = Options: couch mode
  - `leftShoulder` / `rightShoulder` = L1 / R1: previous / next system
  - D-pad and left stick: move
- **Not used:** Square, L2/R2, Create, PS, the touchpad, L3/R3 and the right stick.
- **Connecting:** every connect or disconnect re-binds every controller. Handlers are replaced, not added, so reconnecting shouldn't double anything. Only the first controller's name is shown.
- **What to watch for on hardware:**
  - **Stick repeats:** a stick resting near its threshold could repeat moves.
  - **PS button:** macOS may react to it itself.
  - **Two connections:** a DualSense connected by cable and Bluetooth at once might appear twice.

### Changes this shift

- **One table of bindings:** `ControllerInput.bindings`, used by the handlers and the diagnostics. No behavior change.
- **Picked game per list:** moved into `Navigator`, so the diagnostics can see it. No behavior change, and the Shift 02 window checks cover it.

### Controller Diagnostics (debug builds only)

`scripts/dev-run.sh --controller-diagnostics` opens it next to RetroHub Dev, or use Window › Controller Diagnostics. It records lines in its window and in `mac/build/dev/logs/RetroHub-Dev-*.log`:

```
[controller] 14:02:11.204 device connected: DualSense Wireless Controller (DualSense)
[controller] 14:02:15.880 input  Cross Button (buttonA) pressed → play          ← example; real names come from macOS
[controller] 14:02:15.881 action play
[controller] 14:02:15.902 result launch error: Install RetroArch or OpenEmu to play NES games.
[controller] 14:02:16.131 result keyboard focus: games; RetroHub is the active app
```

What it records:
- **input:** what GameController reported, using macOS's own name for the control and the gamepad property. It includes controls RetroHub doesn't use ("→ no RetroHub action").
- **action:** the logical command RetroHub made of the press.
- **result:** what changed. That covers:
  - the list shown, the picked game, favorites, couch mode;
  - a game starting or closing, with its exit status;
  - the frontmost app, and where keyboard focus is.
- **check:** appears if a press made anything other than exactly one action.

What it doesn't record: about the device, only its name and category; no other identifiers, battery or motion. It only observes and never acts on input.

### Test procedure (please run; I'll read the log afterwards)

Start: `mac/scripts/dev-run.sh --controller-diagnostics`. Keep RetroHub Dev in front: macOS only sends controller input to the frontmost app.

| # | Do | Expected | Observed |
|---|---|---|---|
| 1 | Pair: hold **PS + Create** until the light bar flashes; System Settings › Bluetooth › DualSense Wireless Controller › Connect | Shows as Connected | |
| 2 | System Settings › Game Controllers | DualSense listed | |
| 3 | Look at the bottom of RetroHub's sidebar and the diagnostics window; then turn the controller off (hold PS about 10 s) and on (press PS) | Name instead of "No controller"; `device connected` / `disconnected` lines | |
| 4 | In NES: D-pad left/right/up/down, then the left stick | Selection moves one game per press; `input … → move …`, one `action` each, `result picked …` | |
| 5 | Press each button once: Cross, Circle, Triangle, Square, L1, R1, L2, R2, Options, Create, touchpad click, L3, R3. Don't press PS yet | Mapped ones: as listed in "Bindings" above. Others: `→ no RetroHub action`. Cross on a game: "Couldn't start the game" (no emulator), Cross again closes it | Write the name each line shows |
| 6 | L1/R1 several times; then Triangle on a game | Sidebar selection follows and stays in view; the selected game gets the blue outline; one favorite toggled per press | |
| 7 | Options (couch mode); D-pad left/right; L1/R1; Circle | Full-screen carousel; moves one cover per press; switches list; Circle leaves | |
| 8 | Turn off and on again; repeat 4–6 briefly. Then click another app and press buttons | No `check` lines; nothing recorded while another app is in front | |
| 9 | (Optional) Press PS once | Note what macOS does | |

Hardware results stay **UNVERIFIED** until you report them.

---

## 5. Phase E prep — one game at a time

- **The problem:** before this shift, nothing stopped a second launch while an emulator was starting or open behind RetroHub. RetroHub also never learned that a game had ended (Shift 01 findings O2 and O3).
- **What happens now:**
  - The launcher returns the emulator's process, with its exit handler attached before it starts.
  - While that process runs, **Play brings the running emulator forward** instead of starting another copy.
  - When it exits, RetroHub asks macOS to bring it back to the front. macOS declines if you've moved on to another app.
- **Not covered:** OpenEmu (macOS opens it, and it stays open after a game), which is unchanged.
- **Self-tests:** exits are reported with their status, including programs that fail at once, and a missing emulator is an error.
- **Not yet observed with a real emulator.**

---

## 6. Phase E — First NES game (needs your approval to install RetroArch)

### 6.1 The test ROM

`.devdata/Games/NES/RetroHub Test Pattern.nes` is written by `mac/scripts/make-test-library.swift`, so it contains no third-party code.
- **Format:** valid iNES, 24,592 bytes: NROM (mapper 0), 16 KB program, 8 KB blank tiles.
- **Vectors:** NMI `$C035`, reset `$C000`, IRQ `$C044`.
- **Behaviour:** run for 600 frames in a small 6502 interpreter written for this check, with a modelled PPU:
  - it hits no unknown instruction;
  - it enables NMI and the background;
  - it writes the backdrop color `$3F00` every 64 frames (about once a second), cycling through 8 colors (`$21`–`$28`).

On screen in an emulator this should be a full-screen color that changes about once a second, with no sound. That's a model, not an emulator: it's confirmed only when it runs in RetroArch.

A lawful alternative with more to look at: the NES port of the 240p Test Suite (`pinobatch/240p-test-mini`, GPL-2.0-or-later). It wasn't checked whether a prebuilt `.nes` is published. Downloading it needs your OK.

### 6.2 RetroArch on this Mac

- **Version and build:** retroarch.com offers **RetroArch 1.22.2, Universal** (`RetroArch_Metal.dmg`) "for macOS 10.13 (High Sierra) or later", for both Apple silicon and Intel.
- **NES cores for Intel:** libretro's build server has x86_64 builds of Mesen, FCEUmm and Nestopia, dated 2026-10-22.
- **Which core RetroHub uses:** RetroHub prefers Mesen ("Nintendo - NES / Famicom (Mesen)"). Its `.info` file lists only `disksys.rom`, which is optional (Famicom Disk System), so no firmware is needed for NES.
- **Controller driver:** RetroArch's macOS controller driver is `mfi` or `hid` (Settings › Drivers › Controller). Which one is the default wasn't confirmed, and users report either one working better on different setups.
- **What RetroHub writes:** with Setup's Graphics options at their defaults (filter Off, Native, widescreen off), RetroHub writes **nothing** into RetroArch's folders. With a filter or higher 3D resolution, it writes its own files under RetroArch's `config/RetroHub/`, never `retroarch.cfg`. Keep the defaults for the first test.

### 6.3 Approval points

1. **Installing RetroArch** (external software into `/Applications`). Needs your OK.
2. **Downloading the Mesen core** (RetroArch's Online Updater writes to `~/Library/Application Support/RetroArch/cores`). Needs your OK.
3. **Changing any RetroArch setting**, such as the controller driver. Note the old value first.

### 6.4 Steps (after approval)

1. **Install:** retroarch.com › Platforms › macOS › Universal (`RetroArch_Metal.dmg`). Drag RetroArch.app to **/Applications**, where RetroHub looks. Open it once. If macOS warns about the download, use right-click › Open; don't turn off Gatekeeper.
2. **Core:** in RetroArch, Main Menu › Online Updater:
   - Core Downloader › "Nintendo - NES / Famicom (Mesen)";
   - then Online Updater › Update Core Info Files.
   - Then run `mac/scripts/dev-inventory.sh`. Expected: NES **READY**, "RetroArch (Mesen)", Mesen built for x86_64.
3. **DualSense in RetroArch:** check Settings › Drivers › Controller (write the value down), then Settings › Input › Port 1 Controls. The D-pad should move RetroArch's menu. If it doesn't, stop and tell me before changing drivers.
4. **Direct launch:** Load Core › Mesen. Load Content › `.devdata/Games/NES/RetroHub Test Pattern.nes`. Expected: a full-screen color changing about once a second. Quit with Esc (press again if asked) or ⌘Q.
5. **Through RetroHub Dev:** `scripts/dev-run.sh --controller-diagnostics`. In NES, the header should say "Plays with RetroArch (Mesen)". Select RetroHub Test Pattern and press **Cross**. Expected: RetroArch opens with the pattern, and the log shows `game started …` and `frontmost app: RetroArch`.
6. **Exit:** Esc or ⌘Q in RetroArch. Expected: `game closed …, exit status 0` and `frontmost app: RetroHub Dev`.
7. **Verify:**
   - **Focus:** RetroHub is in front and the controller works without clicking.
   - **Cleanup:** `pgrep -lf RetroArch` prints nothing.
   - **No duplicates:** press Cross twice quickly, and only one `game started` appears.
   - **Bring forward:** with the game running, ⌘-Tab to RetroHub and press Cross; RetroArch comes forward and no second copy starts.
   - **Couch mode:** repeat steps 5–6 from couch mode.

Gameplay stays **unverified** until you've seen it.

---

## 7. Phase F — GitHub

### Findings

- **Local repository:**
  - **History:** the ZIP baseline commit (`818c1ab`) is a root commit, so it shares no history with GitHub.
  - **Remotes:** none. None were added this shift, either.
- **The repository:**
  - **Where:** `github.com/jbutler0831/RetroHub`. Identified from the bundle ID `io.github.jbutler0831.retrohub`, the author `jbutler0831` in `desktop/package.json`, and the ZIP name `RetroHub-main`.
  - **Access:** public; read without credentials (`git ls-remote`, `git clone`).
  - **Please confirm** it's the repository Jor-el means us to use.
- **Remote state:**
  - **Default branch:** `main` = tag `v1.6` = `dd37423`.
  - **Other refs:** `release-hardening`, already merged in PR #1 (`fc939a6`); tags v1.0–v1.6.
  - **History:** 14 commits by Jor-el (`jorelbutler`, `jbutler0831`).
- **The ZIP is exactly `origin/main`.** Our baseline commit's tree, `954b9ec4…`, is the same object as `dd37423`'s tree: every file and mode is identical. So the histories are unrelated, but the content is the same, and our commits apply to `origin/main` with no conflicts.

### Migration (done locally)

1. **Fresh clone:** a separate folder, made with `git clone`. Its only remote is `origin`, as cloned. The original working copy was left as it is.
2. **Branch:** `jstar/shift-01-03` from `origin/main` (`dd37423`).
3. **Commits:** the 9 local commits replayed with `git format-patch` / `git am`, so no remote was added to either repository. The clone was given a repository-level identity (Jay, with J-Star's GitHub noreply address), so no machine name appears as committer.
4. **Verified:**
   - The branch's tree, `c7f25f8e…`, is identical to the working copy's.
   - Debug build: 0 warnings.
   - `--self-test`: PASS, 184 checks.
   - The clone's working tree is clean (build output is ignored).
5. **Nothing pushed.** No pull request opened. No settings changed.

| Migrated | Local | Commit |
|---|---|---|
| `d15336a` | `c87543f` | Mac: fix startup crash on damaged PARAM.SFO; isolated dev build; self-tests |
| `68dd8f1` | `2d4f1dd` | docs: J-Star Shift 01 audit |
| `d2cdca7` | `6293df3` | Mac: show sidebar names and counts again; sidebar window checks |
| `e76ad6a` | `254259b` | Mac: sidebar sections, keyboard and menu navigation, one window |
| `f855b2e` | `730fdfc` | Mac: appearance setting (Follow System, Light, Dark); readable status colors |
| `e643ae2` | `74c707f` | Mac: one game at a time; back to RetroHub when the game closes |
| `240c481` | `a658b18` | Mac: controller diagnostics (debug builds); one table of controller bindings |
| `3ec84c1` | `82f69a7` | Mac: read-only compatibility inventory |
| `5dececf` | `eff6de4` | Rules for coding agents; ignore games, secrets and editor files |

This handoff document is committed last in both repositories. Each Shift 03 topic is its own commit, and each was built and self-tested at that point (126, 130, 130, 184, 184 checks).

**To push later, only with your OK:**
- Command, in the clone: `git push -u origin jstar/shift-01-03`.
- **Prerequisite:** it needs J-Star's GitHub account to have write access. `gh` isn't installed, and no credentials were used.

### Proposed GitHub setup (Jor-el decides; nothing changed)

**Branch protection on `main`** (a ruleset):
- require a pull request, with one approval from the other person;
- dismiss stale approvals when new commits are pushed;
- require the CI check below to pass;
- block force pushes and branch deletion;
- apply the rules to admins too.

**Collaborators:**
- **Jor-el:** stays owner.
- **J-Star:** Write access (branches and pull requests), not Admin.
- **Coding agents:** a fine-grained token for this repository only, with:
  - Contents and Pull requests: read/write;
  - no admin rights;
  - Workflows only if a change touches `.github/workflows`.

**Review process:**
- one topic per branch (`jstar/…`, `jorel/…`);
- the pull request lists what changed, the checks run, screenshots, and what's still unverified;
- the other person reviews and merges; agents never merge;
- branches are deleted after merging.

**CI** (proposed `.github/workflows/checks.yml`; not added, so nothing runs on the shared repository until you decide):

```yaml
name: Checks
on: [pull_request]
permissions:
  contents: read
jobs:
  mac:
    runs-on: macos-15-intel        # same runner as release.yml
    steps:
      - uses: actions/checkout@v4
      - name: Build (debug, warnings are errors)
        run: cd mac && swift build -Xswiftc -warnings-as-errors
      - name: Self-tests
        run: cd mac && "$(swift build --show-bin-path)/RetroHub" --self-test
  desktop:
    runs-on: ubuntu-latest
    defaults: { run: { working-directory: desktop } }
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22, cache: npm, cache-dependency-path: desktop/package-lock.json }
      - run: npm ci
      - run: for f in src/*.js src/renderer/*.js; do node --check "$f"; done
```

The window checks need a logged-in screen, so they stay manual for now. The runner's Swift may be newer than the Command Line Tools here (5.10), so `-warnings-as-errors` may need one adjustment on first run. `node --check` passes on every desktop source file locally.

### Rules for agents

`AGENTS.md` at the repository root (read by Codex and most agents), with `CLAUDE.md` pointing to it. It covers:
- no pushes to `main`;
- a person approves every push and merges every pull request;
- no force pushes, destructive operations or remote changes;
- start from the latest `origin/main`;
- stop on divergence or conflicts;
- nothing private, generated or game-related in commits;
- the checks to run first;
- keeping the developer's own setup safe.

### Draft pull request (not opened)

**Title:** Mac: sidebar fixes, keyboard/menu navigation, appearance setting, controller diagnostics, compatibility inventory

**Body:**

> Work from J-Star's shifts 01–03 on the Mac app, replayed onto `main` (v1.6). Each commit is one topic and builds on its own.
>
> **Fixes**
> - Startup crash on a damaged PS3/PS4/Vita PARAM.SFO.
> - Cover art hidden for good after a server error.
> - Sidebar showing icons only on macOS 14.
> - One controller press acting once per open window (single window now).
> - A second game starting while one runs.
>
> **New**
> - Sidebar sections by maker.
> - Keyboard navigation and menu commands: ⌘, ⌘F ⌘[ ⌘] ⌘R.
> - Remembered game per list.
> - Setup warnings in the sidebar.
> - Follow System / Light / Dark, with readable status colors.
> - Debug tools:
>   - `--self-test` (184 checks);
>   - window checks (`scripts/dev-ui-check.sh`);
>   - Controller Diagnostics;
>   - a read-only compatibility inventory;
>   - an isolated "RetroHub Dev" build.
> - `AGENTS.md`.
>
> **Verified**
> - Builds: debug, strict concurrency, and universal release, all with 0 warnings.
> - Self-tests: 184 pass.
> - Window checks: <result of the pending run>.
>
> **Not verified**
> - A physical DualSense.
> - A real emulator launch.
> - VoiceOver.
> - The Windows/Linux app (unchanged).
>
> **Screenshots:** `mac/build/dev/ui-check/` from the window checks (to attach).
>
> Co-authored with Claude Opus 5.5.
>
> 🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## 8. Builds and tests

| Check | Command (from `mac/`) | Result |
|---|---|---|
| Debug build | `swift build` | PASS, 0 warnings |
| Strict concurrency | `swift build --build-path <scratch> -Xswiftc -strict-concurrency=complete` | PASS, 0 warnings |
| Universal release | `INSTALL=0 ./build.sh` | PASS: `x86_64 arm64`, `codesign --verify --strict` OK, no debug-only symbols, `~/Applications` untouched |
| Self-tests | `"$(swift build --show-bin-path)/RetroHub" --self-test` | **PASS, 184 checks** (+14 appearance, +4 process, +54 compatibility) |
| Each Shift 03 commit | built and self-tested at each step | 126 → 130 → 130 → 184 → 184 |
| Migrated branch | the same, in the clone | PASS, 184 |
| Inventory | `scripts/dev-inventory.sh [--json]` | Runs; valid JSON (29 systems) |
| Window checks | `scripts/dev-ui-check.sh` | **Pending**: 77 checks expected (47 before), plus relaunch 4, Small 1, Large 1 |

Two oddities:
- **`build.sh` stalled twice:** each time it was started from a background shell, it sat idle before starting the compiler, without output. Run with `bash -x`, it completed normally. I couldn't reproduce or explain it.
- **A stray "RetroHub Dev Check" instance:** it has been running since 10:15 this morning, started without test arguments (not by a check run). `dev-ui-check.sh` refuses to start while it runs.

## 9. Unresolved

1. **Window checks not yet run:** they need the screen. Quit RetroHub Dev Check, run `scripts/dev-ui-check.sh`, click its Dock icon, and leave the Mac alone for about 1½ minutes.
2. **Hardware:** the DualSense test (§4).
3. **Gameplay:** Phase E (§6), after your approval.
4. **Still open from earlier shifts:** VoiceOver labels and Tab order (from Shift 02). From the Shift 01 list:
   - O4: rescan on the main thread
   - O5: couch carousel isn't lazy
   - O6: AppKit reentrancy warning
   - O7: controller auto-repeat, and B in the browser
   - O8: favorites keyed by absolute path
   - O9: no `.m3u`
5. **Housekeeping:**
   - **From Shift 01:** `~/Games` (28 empty folders) and the production settings domain, created by opening the release build. Left for you.
   - **Removed this shift:**
     - the throwaway "RetroHub Probe" app and its settings;
     - a `RetroHub` settings domain (window sizes only), left by running the raw debug binary as an app during the UI-fix shift.
6. **Repository confirmation:** confirm `jbutler0831/RetroHub` is the authorized repository, and whether J-Star has write access.

## 10. Recommended next shift

1. Go through the DualSense results:
   - fix any binding or double-action problem the log shows;
   - add auto-repeat for held directions;
   - decide what B, PS and the touchpad do in the browser.
2. Once RetroArch is approved and running: confirm the NES launch end to end, including focus, cleanup and no duplicates. Then add a clear message when an emulator quits straight away with an error.
3. Show the inventory in Setup ("This Mac": ready / setup needed / unknown, with the reason).
4. Move the systems catalog to one shared data file for the Mac and desktop apps, with fixtures that both evaluators must pass.
5. With Jor-el:
   - push `jstar/shift-01-03`;
   - open the pull request;
   - turn on branch protection;
   - add the CI workflow.
6. After that: music, which was deferred since Shift 01.
