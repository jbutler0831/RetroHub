# RetroHub — J-Star Shift 01 Audit

Date: 2026-10-21 · Machine: 2019 MacBook Pro, Intel i9-9980HK (8C/16T), 64 GB, macOS 14.4.1 (23E224)
Repository: an independent local copy, unpacked from a downloaded ZIP of `main`

| Area | Result | Evidence |
|---|---|---|
| Build (debug, x86_64) | **PASS** | `swift build`: 0 compiler warnings, also 0 under `-strict-concurrency=complete` |
| Build (release, universal) | **PASS** | `INSTALL=0 mac/build.sh` → `x86_64 arm64` fat binary, ad-hoc + hardened runtime, `codesign --verify --strict` OK |
| Automated tests | **PASS** (new) | No tests existed. Added `RetroHub --self-test` (debug only): 91 checks pass |
| Application launch | **PASS** | Dev app starts, main window 900×532 on screen, no crash. Since the UI fix shift, `scripts/dev-ui-check.sh` checks the sidebar and saves pictures the app draws of its own window (no Screen Recording permission needed) |
| Game launch | **UNVERIFIED** | No emulators installed on this Mac |
| Controller | **UNVERIFIED** | Needs a physical controller and you |
| Ready for manual test | **YES** | `mac/scripts/dev-run.sh` |

---

## 1. Phase 0: environment and isolation

**Independent copy confirmed.** There was no `.git` and no remote. The only other RetroHub copy on disk is the source ZIP. Jor-el's repository has never been referenced, pushed to or fetched from.

- Local Git baseline: `818c1ab` (the ZIP exactly as downloaded) and `c87543f` (this shift's fixes). Name and email are set only in this repo's own git config; no remote is configured.
- App identity: bundle ID `io.github.jbutler0831.retrohub`, version 1.6 (7), minimum macOS 14.0. Prefs live in UserDefaults under that ID. The legacy domain `local.retrohub` is migrated once if present (it isn't on this Mac).
- Paths the app uses at runtime:

  | What | Path | State on this Mac before the shift |
  |---|---|---|
  | Installed app | `~/Applications/RetroHub.app` (written by `build.sh`) | absent |
  | Prefs | `defaults read io.github.jbutler0831.retrohub` | domain absent |
  | Games folder | `~/Games` + 28 system folders, **created on first launch** | absent |
  | Cover cache | `~/Library/Caches/RetroHub/Covers` | absent |
  | RetroArch side files | `~/Library/Application Support/RetroArch/config/RetroHub/*.cfg, *.opt` (only when graphics options are on) | RetroArch absent |
  | Vita3K games (read only) | `~/Library/Application Support/Vita3K/Vita3K/ux0/app` | absent |
  | Emulators | `/Applications/<Name>.app`, `~/Applications/<Name>.app`, `…/shadPS4/shadps4` | **none installed** |

- Toolchain: Command Line Tools 15.3, Swift 5.10, macOS SDK 14.4. There is **no Xcode**, so there's **no XCTest** and `swift test` can't run. Node 24.5 and npm 11.5 are present; CI pins Node 22. No swiftlint, swift-format or shellcheck; I didn't install any.
- Disk: 166 GiB free. Memory pressure stayed at about 88% free throughout.
- **`mac/build.sh` is unsafe for development:** its last step is `rm -rf ~/Applications/RetroHub.app` followed by a copy. I didn't run it in that form. It now accepts `INSTALL=0` (the default behavior is unchanged).
- **License:** there is no LICENSE file, and `desktop/package.json` says `"license": "UNLICENSED", "private": true`, author `jbutler0831`. Legally that means all rights are reserved by the author. Fine for our private development with his blessing, but **don't publish builds or forks without Jor-el's OK**.
  - Mac app: no third-party Swift packages.
  - Electron app: dev dependencies `electron` 33.4.11, `electron-builder` 25.1.8 and `@electron/fuses` 1.8.0, all MIT. A packaged Electron app also ships Chromium's bundled licenses.
  - Runtime content: cover art is downloaded from `thumbnails.libretro.com`. The box art is publishers' artwork, so don't redistribute it.

## 2. Architecture (what the code actually does)

There are three front ends that share one design.

**Native Mac app** (`mac/`, SwiftUI, 2.1k lines, no dependencies):

| File | Responsibility |
|---|---|
| `RetroHubApp.swift` | Entry point. `WindowGroup` scene; the app quits when its last window closes. Debug `--self-test` hook (new) |
| `Systems.swift` | 29 `GameSystem`s (folder, extensions, preferred backends), 12 `Emulator`s (lookup in `/Applications` and `~/Applications`), `Launcher` (first installed backend wins; RetroArch needs a core dylib in `~/Library/Application Support/RetroArch/cores`) |
| `Library.swift` | Games-folder scan: recursive by extension, PS3/PS4 folder layouts, Vita3K installs, PARAM.SFO titles. Favorites and last-played kept in UserDefaults, keyed by **absolute path** |
| `ControllerInput.swift` | GameController framework, `extendedGamepad` only. D-pad/left stick move, A play, B back, Y favorite, LB/RB switch system, Menu toggles couch mode. Press edges only, no repeat |
| `ContentView.swift` | Sidebar, game grid (LazyVGrid), keyboard (arrows, Return, F), context menu, launch-error alert. Rescans on every app activation |
| `CouchView.swift` | Full-screen carousel with a blurred backdrop. Arrows, Return, Esc, F |
| `SetupView.swift` | Emulator install status and download links, games-folder chooser, graphics options, controller pairing hints, BIOS notes |
| `CoverArt.swift` | Local `<game>.png/jpg` first, then libretro-thumbnails over HTTPS with region-name guesses. Disk cache with `.none` miss markers |
| `Graphics.swift` | Per-launch RetroArch shader and core-option overrides via `--appendconfig` and `config_save_on_exit=false`, so `retroarch.cfg` isn't modified |

**Launch path:** `Library.play` → `Launcher.launch` → `Process().run()` with an argument array (no shell, so no injection). OpenEmu is opened through `NSWorkspace.open(_:withApplicationAt:)`. The `Process` is discarded immediately: there's no termination handler, no exit status, and no activation of the emulator.

**Electron app** (`desktop/`, about 1.6k lines): the same feature set for Windows, Linux and Raspberry Pi. It adds Xbox 360/Xenia, a "Locate…" button for emulators, and `--console` boot mode. It uses `contextIsolation` and `sandbox` correctly, launches through `spawn(..., {detached, stdio: 'ignore'})`, and reads the controller with the W3C Gamepad API (it only acts while `document.hasFocus()`). I didn't build or run it this shift because it isn't the Mac target.

**Pi** (`pi/`): an install script for a kiosk console. Out of scope.

**CI** (`.github/workflows/release.yml`): builds on release publish and attaches the zip, exe and AppImage files. It **runs no tests**, and none existed.

### README claims vs. implementation

| README says | Code (Mac) | Verdict |
|---|---|---|
| Universal Mac app | `build.sh` lipos arm64 + x86_64 | ✅ verified this shift |
| Emulator table / "first installed is used" | `GameSystem.backends` order + `Launcher.plan` | ✅ matches (Xenia is Win/Linux only, as stated) |
| Cover art, favorites, recently played, couch mode | All present | ✅ code present; UI not yet verified by you |
| Games folder "change it from the toolbar" | On Mac it's **Setup › Games Folder › Change…**; the toolbar only has Couch Mode and Rescan | ⚠️ README wording is wrong for Mac |
| Emulators found "in their usual install locations" | Mac checks only `/Applications` and `~/Applications` by exact app name; there's no Locate… button on Mac | ⚠️ apps in subfolders or renamed apps aren't found |
| PS Vita games listed from Vita3K | Default Vita3K storage path only | ⚠️ a custom Vita3K pref path isn't honored |

## 3. Build, run and test commands (all verified this shift)

```bash
cd mac

# Debug build + automated checks (no XCTest needed; touches only a temp folder)
swift build
"$(swift build --show-bin-path)/RetroHub" --self-test        # → PASS: 91 checks, exit 0

# Isolated development app: build/dev/RetroHub Dev.app, bundle ID io.github.jbutler0831.retrohub.dev
scripts/dev-build.sh                  # never installs anything
scripts/dev-run.sh                    # opens it with the test library; log in build/dev/logs/
scripts/dev-ui-check.sh               # opens it for ~6 s, checks the sidebar → PASS: 5 checks;
                                      # pictures of each step in build/dev/ui-check/

# Release / universal build WITHOUT touching ~/Applications
cd .. && INSTALL=0 mac/build.sh       # → mac/build/RetroHub.app + RetroHub.zip
```

Isolation guarantees of the dev app, verified on this Mac after launch:
- Prefs go only to `io.github.jbutler0831.retrohub.dev`. The production domain still doesn't exist.
- The games folder is `.devdata/Games` in the repository (gitignored). `~/Games` is still absent.
- The cover cache is `~/Library/Caches/RetroHub Dev/Covers`. The production app still uses `RetroHub/Covers`.
- `dev-run.sh` won't start a second copy.
- Remaining shared state: the RetroArch side-file folder `config/RetroHub/` (written only if you install RetroArch and turn on a graphics option; each launch overwrites it anyway) and LaunchServices registration of "RetroHub Dev".

**Don't open `mac/build/RetroHub.app`**, the release build. It has the production bundle ID and would create `~/Games` and the real prefs domain.

> **Update 2026-10-22:** `~/Games` (28 empty folders, no files) and the production prefs domain (window size only) were created at 23:52 on 2026-10-21. No session command was running then. The only app on this Mac with the production bundle ID is `mac/build/RetroHub.app`, so it was most likely opened. Both are left in place for you to decide.

Test library (`swift scripts/make-test-library.swift <dir>`, created automatically by `dev-run.sh`):
- `NES/RetroHub Test Pattern.nes`: a 104-byte NES program I wrote for this purpose (no copyrighted code). It cycles the screen through 8 colors about once a second. It's the only bootable file, and it's unverified until an NES emulator runs it.
- Zero-byte placeholders that exercise the scanner:
  - title cleanup ("Legend of Placeholder, The (USA) [!]" → "The Legend of Placeholder")
  - an uppercase `.SFC` extension
  - a nested `Genesis/Subfolder` game
  - `.hidden.nes` and `notes.txt`, which must be ignored
  - a PS1 `.cue` + `.bin` pair, where only the `.cue` is listed
  - a PS3 disc folder with a PARAM.SFO title, and a PS3 folder that isn't a game
  - a PS4 folder with a title

What `--self-test` covers:
- title cleanup
- PARAM.SFO parsing, including damaged files
- scanning rules for files, PS1, PS3 and PS4
- unique system folders (case-insensitively, because APFS is)
- every system having a backend
- RetroArch core-option values
- cover-art response classification

`dev-ui-check.sh` (`UIChecks.swift`, debug only) covers the sidebar in the real window: every row must span the sidebar at launch, after the down arrow moves to the next item, after scrolling to the end, and after hiding and showing the sidebar. The rest of the UI, launching and the controller are the manual tests.

## 4. Defects

### Fixed this shift (commit `c87543f`)

| # | Severity | Defect | Evidence | Fix + regression test |
|---|---|---|---|---|
| F1 | **Critical** | **Startup crash on a damaged PARAM.SFO.** `Library.sfoTitle` read each index entry before checking it was inside the file. The scan runs during `Library.init`, so one truncated PS3/PS4/Vita dump crashed RetroHub on **every** launch until the file was removed. | Reproduced: the unfixed dev app exited with code 132 (SIGILL, `Data.subscript` trap at `Library.swift:239`, per the crash report) against a 20-byte `param.sfo` claiming 40 entries. After the fix it runs normally against the same library. | Bounds check moved before the read. Self-tests: "truncated index", "index shorter than its count", "damaged PARAM.SFO falls back to folder name" |
| F2 | Medium | **Covers lost for good after a server hiccup.** `CoverArt.fetch` treated any non-200 response (429, 500, 503) as "no art" and wrote a permanent `.none` marker. | Code: `statusCode == 200 ? .found : .missing` | Only 404 is remembered; other statuses retry later. Self-test "cover art" (7 checks) |
| F3 | Process | `build.sh` always replaces `~/Applications/RetroHub.app` | Script inspection | `INSTALL=0` opt-out; default unchanged |
| F4 | Process | There was no way to run a second, isolated copy | — | `dev-build.sh`, `dev-run.sh`, cache folder follows `CFBundleName` |

### Fixed in the UI fix shift (2026-10-22)

| # | Severity | Defect | Evidence | Fix + regression test |
|---|---|---|---|---|
| F5 | **High** | **Sidebar showed only icons, with no names or counts.** The sidebar `List` was wrapped in `.safeAreaInset(edge: .bottom)` for the controller status. On macOS 14.4.1, a sidebar `List` inside `.safeAreaInset` or a `VStack` keeps its AppKit `NSOutlineView` column at 38 pt in a 240 pt sidebar, and resizing, navigating or hiding and showing the sidebar never fixes it. Each row's 22 pt icon fits; the name and count badge are squeezed to nothing. The row view, label styling, text color and sidebar width were not the cause. | Pictures the app drew of its own window, plus the AppKit view tree. In a scratch copy: a plain `Text` row, no `Spacer`, no activation rescan, no search, no toolbar, other selections: still 38 pt. Removing the inset: 208 pt. `.padding`/`.overlay` on the `List`: 208 pt. `VStack`, inset before or after the column-width modifier, inset around a `VStack`: 38–39 pt. Probably a SwiftUI bug on macOS 14 (Jor-el may not see it on a newer macOS); not checked on another OS | The `List` stays the sidebar's root view. The controller status now floats in an `.overlay` over 56 pt of `.padding` left below the list, so it looks the same and the last row ends above it (`.contentMargins` was tried and doesn't apply to a macOS 14 `List`). `dev-ui-check.sh`: **FAIL 4 of 5** on the old code (rows 38 pt), **PASS 5 of 5** with the fix (rows 208 pt) |
| F6 | Low | Strict-concurrency builds warned about `CommandLine.arguments` in the `--self-test` hook, so the "0 under strict concurrency" line above wasn't true for the final Shift 01 code | `swift build -Xswiftc -strict-concurrency=complete` | `ProcessInfo.processInfo.arguments`; strict build now 0 warnings |

### Open, prioritized for the Mac app (not fixed: these need your manual confirmation or a design decision)

| # | Severity | Finding | Where | Proposed fix |
|---|---|---|---|---|
| O1 | **High** | **A controller press can launch a game more than once.** `WindowGroup` allows File › New Window (⌘N). Each window's grid subscribes to `controller.commands`, so one A press calls `play` once per open window. | `RetroHubApp.swift:30`, `ContentView.swift:196` | Use a single `Window` scene. Confirm in manual test 7 first |
| O2 | **High** | **Nothing stops a second launch while a game is starting or running.** `Process` doesn't bring the emulator to the front. If it opens behind RetroHub, or in another Space because couch mode is full screen, the controller still drives RetroHub, and another A starts a second emulator. | `Systems.swift:384-389` | Track the running game; use `NSWorkspace.openApplication` with `arguments`/`activates` (or activate the child's `NSRunningApplication`); ignore Play while a game runs. Confirm in manual tests 6 and 8 |
| O3 | Medium | **No subprocess lifecycle.** No termination handler or exit status. Emulators that quit immediately (missing BIOS or core) fail silently, yet the game is still added to Recently Played. | `Systems.swift:384`, `Library.swift:157` | `Process.terminationHandler` + a `runningGame` state. This is also the hook for music pause/resume (§6) |
| O4 | Medium | **Full rescan on the main thread at launch and on every app activation**, i.e. every return from a game. Recursive enumeration, so big or network libraries will stall the UI. | `ContentView.swift:25-27`, `Library.swift:119` | Scan off the main actor; publish the results |
| O5 | Medium | **Couch-mode carousel isn't lazy.** Every cover in the list loads at once; unmatched titles try up to 11 URLs each against libretro's server. | `CouchView.swift:107` | `LazyHStack` |
| O6 | Low | AppKit warns "reentrant operation in its NSTableView delegate. This warning will become an assert in the future" on every launch | `build/dev/logs/*.log` (sidebar `List`) | Narrowed during F5: it goes away when the sidebar has no `Section`s, and stays with or without the activation rescan, whatever is selected, and with the F5 fix. Not related to the missing labels. Look at the header-less first `Section` |
| O7 | Low | Controller UX: no auto-repeat on held directions; B in the grid only dismisses errors; only the first controller's name is shown; Home and Options are unused | `ControllerInput.swift` | Part of the Phase 4 design |
| O8 | Low | Favorites and recents are keyed by absolute path, so changing the games folder or moving files loses them | `Library.swift:12` | Key on a path relative to the root (with migration) |
| O9 | Low | No `.m3u` multi-disc support, so each disc is listed separately (PS1, Sega CD, Saturn) | `Systems.swift` extensions | Add `m3u`; hide the discs it lists |
| O10 | Info | First launch creates `~/Games` + 28 folders without asking (the README documents this) | `Library.swift:84` | Fine; just be aware |
| O11 | Info | Cover lookups send game titles to `thumbnails.libretro.com`; there's no offline or opt-out setting | `CoverArt.swift:11` | Optional setting |
| O12 | Info | RetroArch core-option changes made in-game during a RetroHub launch go to RetroHub's copy, which the next launch overwrites | `Graphics.swift:137-151` | Document, or merge back |

## 5. Unverified behavior (needs you, a controller, or an emulator)

- **Everything visual except the sidebar:** grid, couch mode, Setup page, alerts. (The sidebar and the Setup and NES pages are in the `dev-ui-check.sh` pictures, but you haven't confirmed them yet.)
- **Emulator detection** with a real install. Note that `Emulator.isInstalled` only checks for an app with the exact expected name in the two Applications folders.
- **Any game launch**, including whether the emulator comes to the front, Spaces behavior in full-screen couch mode, and returning to RetroHub.
- **Controller connection and every binding.** GameController maps buttons by position. So on Nintendo controllers, the button macOS reports as `buttonA` may be the physical B; that needs checking on hardware.
- **Electron app** (not built).
- **The NES test ROM.** It's hand-assembled with a byte-layout check, but no emulator has run it yet.

## 6. Phase 3 manual test plan

Launch with `mac/scripts/dev-run.sh`. Each item stays **PENDING** until you confirm it.

| # | Test | What you should see | Status |
|---|---|---|---|
| 1 | Startup / shutdown | The menu bar says **RetroHub Dev**. With no emulators the window opens on **Setup**: "Welcome! Install an emulator below to get started." All 12 emulators show **Download**. ⌘Q quits; the log has no crash | PENDING |
| 2 | Library appearance / navigation | Sidebar: Favorites, Recently Played, Setup, then systems grouped by maker. Counts: NES 2, SNES 1, Genesis 1, PS1 1, PS3 1, PS4 1 | PENDING |
| 3 | Keyboard and mouse | In NES: arrows move the highlight, F toggles favorite (star), Return tries to play, right-click shows Play / Add to Favorites / Show in Finder, hover shows a play button | PENDING |
| 4 | Game discovery | Titles: "RetroHub Test Pattern", "The Legend of Placeholder", "UPPERCASE EXTENSION", "Nested Game", "Disc Placeholder", "PS3 Folder Placeholder", "PS4 Folder Placeholder". There should be **no** notes.txt, .hidden or Track 1 .bin entries, and no "Not A Game". Covers are colored placeholders | PENDING |
| 5 | Emulator detection | Each system header shows an orange **Setup needed** pill + a "Get RetroArch" (etc.) button. After you install one emulator (your choice; see below) the pill turns green, "Plays with …" | PENDING |
| 6 | Launch test game | NES › RetroHub Test Pattern › Return: the emulator opens and the screen cycles colors. Watch whether the emulator comes to the front (O2) | PENDING (needs an emulator) |
| 7 | Controller | Sidebar footer shows the controller's name; A/B/Y/LB/RB/Menu as in §2. Also try ⌘N for a second window, then A once: does the game start twice? (O1) | PENDING |
| 8 | Return from gameplay | "RetroHub Test Pattern" is under Recently Played as soon as it launches. Quit the emulator: RetroHub comes back with the library intact. Repeat from couch mode and note what Spaces do | PENDING |
| 9 | Persistence | Favorite a game, change the games folder in Setup, quit, relaunch with `dev-run.sh`: the favorite and the folder are kept | PENDING |
| 10 | Missing game / emulator | With no emulator, Return or A shows "Couldn't start the game" + install advice; A or B dismisses it. Deleting a game file and switching back to the app removes it from the list | PENDING |

**Emulator to install, your decision.** For the NES test, either works:
- **OpenEmu** (one app, NES works out of the box), or
- **RetroArch** plus one core (Online Updater › Core Downloader › "Nintendo - NES / Famicom (Mesen)").

I haven't installed either.

## 7. Phase 4: universal controller research

**What the platform gives us**
- **GameController framework:** Xbox Wireless, DualShock 4, DualSense, MFi, and since macOS 13 Switch Pro and Joy-Con. Buttons are mapped by position, and `GCController.current` / `physicalInputProfile` expose per-model glyphs and labels. Generic HID pads not on Apple's list aren't guaranteed to appear. Supporting them needs IOKit HID + an SDL GameControllerDB-style mapping file, which is a dependency decision.
- **Background input:** `GCController.shouldMonitorBackgroundEvents` (macOS 11.3+, default **off**) lets an app receive controller input while another app is in front, **without** Accessibility permission. Caveats:
  - The game sees the same presses, because it's monitoring, not interception.
  - SDL found it must be enabled only after the first connect notification.
  - Apple's forums report it broken on macOS 15.4. That doesn't affect Sonoma, but it's a fragility for later macOS versions.
- **The Home button** opens Launchpad's Games folder at system level, and users can remap per app in System Settings › Game Controllers (macOS 13+). Don't build RetroHub's actions on Home.

**Classification**

| | Actions | How |
|---|---|---|
| **A. RetroHub handles while focused** | up/down/left/right, confirm, back, launch selected, previous/next category, open/close RetroHub menu, favorite | Already implemented except a real "back" and a menu. Needs: held-direction repeat (about 400 ms delay, then 100 ms), a configurable logical-action map, and glyphs per controller family |
| **B. Needs a per-emulator adapter** | pause, save state, load state, "quit game and return" | **RetroArch:** UDP network commands on port 55355 (`PAUSE_TOGGLE`, `SAVE_STATE`, `LOAD_STATE`, `QUIT`, `CLOSE_CONTENT`, `MENU_TOGGLE`, `GET_STATUS`). RetroHub can turn these on **per launch** through the `--appendconfig` file it already writes (`network_cmd_enable = "true"`), leaving `retroarch.cfg` alone, and the same file can set `input_quit_gamepad_combo`. **PCSX2:** PINE IPC (save/load state opcodes, status). RPCS3 reportedly mirrors PINE; verify. **Dolphin, Cemu, melonDS, PPSSPP, xemu, Azahar:** no documented control channel found, so only their own hotkey settings or process termination are left. **OpenEmu:** opened through LaunchServices; no adapter |
| **C. Not reliably unifiable without extra permissions** | A universal "return to RetroHub" chord inside any emulator; suppressing the game's reaction to that chord; global keyboard hotkeys | Background monitoring (above) lets RetroHub *see* a chord, but the emulator sees it too. Intercepting it needs an event tap (Accessibility/Input Monitoring) or a virtual HID driver. **Off by default; opt-in only** |

**Proposed design (not implemented; waiting on the baseline test)**
1. `enum LogicalAction` (navigate×4, confirm, back, launch, prevCategory, nextCategory, menu, favorite, pause, saveState, loadState, returnToHub). A per-controller-family default map is stored in prefs and is user-editable. This replaces the hard-coded `bind` calls.
2. `protocol EmulatorAdapter { func pause(); func saveState(); func loadState(); func quit() }` with `RetroArchAdapter` (UDP), `PINEAdapter` (PCSX2/RPCS3), and `ProcessOnlyAdapter` (activate or terminate). Capabilities are shown in the UI per system.
3. A `GameSession` object owns the running process: its PID, a termination handler, and the adapter. It fixes O2/O3 and drives the music (§8).
4. Optional "Return to RetroHub": **hold** Menu + View (Options + Share) for 1.5 s while a session is active. It **brings RetroHub to the front with a Resume / Save & Quit / Quit overlay, and never kills the game directly**. Off by default, behind a Setup toggle that explains the background monitoring.

## 8. Phase 5: background music research

There's no audio code in RetroHub today. AVFoundation alone covers the feature, with no new dependencies.

- **Playback:** `AVAudioPlayer` (or `AVQueuePlayer` for a playlist). `setVolume(_:fadeDuration:)` gives the fade-out and fade-in.
- **Formats on this Mac** (`afconvert -hf`): mp3, m4a/aac/alac, flac, wav, aiff, caf. **No `.ogg` container.**
- **Where tracks come from:** your own licensed files in `<games folder>/Music/` (all systems) and `<games folder>/Music/<SystemFolder>/` (per-system playlists). Nothing is bundled or downloaded.
- **Controls:** a volume slider, a mute toggle (toolbar + Setup), and a "play in couch mode only" option, all in UserDefaults.
- **Lifecycle:** fade out over about 0.6 s in `Library.play` *before* the emulator starts; pause while a `GameSession` is active; resume with a fade-in when the session's process ends. Pausing on `NSApplication.didResignActive` is the fallback for OpenEmu, which has no PID to track. macOS never pauses one app's audio because another app starts, so RetroHub has to do it itself. This depends on O3.
- **Edge cases:** no Music folder means silent (the default); unreadable files are skipped; music should never start while the emulator is in front.

## 9. Prioritized next steps

1. **You:** run the manual tests in §6; pick an emulator for tests 5–8.
2. Confirm and fix **O1** (single `Window`) and **O2/O3** (`GameSession`: activation, a running-game guard, a termination handler). These are prerequisites for safe controller and music work.
3. **O5** (lazy couch carousel) and **O4** (background scan): small, low-risk changes.
4. Phase 4 step 1 (logical-action map + held-direction repeat) and the RetroArch adapter.
5. Phase 5 music, built on `GameSession`.
6. Optional: run `--self-test` in CI before the release builds; fix the README's "toolbar" wording; decide with Jor-el which fixes go back upstream (F1 in particular affects his users).

## Sources

- [GCController.shouldMonitorBackgroundEvents (Apple)](https://developer.apple.com/tutorials/data/documentation/gamecontroller/gccontroller/shouldmonitorbackgroundevents.md), [macOS 15.4 regression thread](https://developer.apple.com/forums/thread/782461), [SDL background-events crash fix](https://discourse.libsdl.org/t/sdl-fix-crash-when-reading-background-events-for-mfi-controllers-on-macos/35559)
- [RetroArch network control interface](https://docs.libretro.com/development/retroarch/network-control-interface/)
- [PCSX2 IPC (PINE) protocol](https://wiki.pcsx2.net/IPC_Protocol), [PINE opcodes (mirror)](https://repo.retrodeck.net/Xargon/Duckstation/src/commit/14f69b7b7827568b71dacb8dc674bf443ba8799a/src/core/pine_server.cpp)
- [Apple: connect a wireless game controller / per-app customization](https://support.apple.com/en-in/HT210414), [PopSci: Home button opens Launchpad Games](https://www.popsci.com/diy/how-to-connect-controller-to-mac/)
- [Switch Pro / Joy-Con support in iOS 16 / macOS 13](https://lowyat.net/2022/275774/apple-adds-nintendo-switch-pro-joy-con-controller-support-to-ios-16), [WWDC19 session 616](https://developer.apple.com/videos/play/wwdc2019/616/), [Apple forums: GameController ignores virtual HID devices](https://developer.apple.com/forums/thread/812774)
- [NSWorkspace.OpenConfiguration](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration.md), [Apple DTS: createsNewApplicationInstance](https://developer.apple.com/forums/thread/719474)
