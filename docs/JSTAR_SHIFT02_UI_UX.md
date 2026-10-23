# RetroHub — J-Star Shift 02: Navigation, Sidebar and Controller-Ready UI

Date: 2026-10-22 · Mac: 2019 MacBook Pro (Intel i9), macOS 14.4.1 · Copy: independent local copy (nothing pushed)

| Area | Result | Evidence |
|---|---|---|
| Sidebar labels | **PASS** (automated) | Every row spans the sidebar (208 pt in 240 pt) at launch, after navigating, scrolling, hiding/showing, resizing, in dark mode and at all three sidebar icon sizes |
| Navigation | **PASS** (automated) | Sidebar, menu bar, keyboard and simulated controller all change the same selection; no duplicate actions |
| Keyboard | **PASS** (automated, synthesized key events in the real window) | ↑/↓, click then ↓, Return/→ into games, Esc back, F, ⌘, ⌘[ ⌘] ⌘F, Return from search |
| Controller | **UNVERIFIED on hardware** | LB/RB/Y/B/Menu behave correctly when simulated; needs a real pad |
| Resizing | **PASS** (automated) | Minimum window 760 pt, sidebar 220 pt minimum, 420 pt wide, 1500 × 900 |
| Build | **PASS** | Debug, universal release (x86_64 + arm64) and strict-concurrency builds: 0 warnings |
| Automated tests | **PASS** | `--self-test` 112 checks (91 before) · `dev-ui-check.sh` 47 + 2 checks |
| Ready for manual review | **YES** | `mac/scripts/dev-run.sh` |

"Automated" means the checks below, run against the real app window. None of it counts as passed until you've looked at it yourself.

---

## 1. Phase 1 verified

The Phase 1 sidebar fix was intact. On the Phase 1 code, the new check suite found every row 208 pt wide in the 240 pt sidebar (it was 38 pt before the fix), with all labels and counts drawn. That stays true through every step of the suite.

## 2. What the UI was (before this shift)

- **Layout:**
  - One `WindowGroup` scene. `NavigationSplitView` with two columns: the sidebar `List` and the detail pane (`SetupView`, the game grid, or an empty state).
  - Couch mode replaces the whole split view with a full-screen carousel.
  - Sidebar width: 220 pt minimum, 240 pt ideal, no maximum. The window's minimum is 760 × 480 pt.
- **State:**
  - `ContentView` held the selection, the search text and couch mode as `@State`.
  - Each game grid kept its own selected game, and its `.id(item)` meant that selection was lost every time the list changed.
- **Input:**
  - Controller presses go through a `PassthroughSubject<ControllerCommand>`. `ContentView` handled LB/RB/Menu; every live grid or couch view handled move/A/Y/B.
  - Keyboard in the grid: arrows, Return and F via `onKeyPress`.
  - The grid grabbed keyboard focus whenever it appeared.
- **Native conventions already used:** sidebar `List` with maker sections, standard selection highlight, toolbar search, toolbar buttons, the sidebar toggle button, and dark mode via system colors.

## 3. Problems found

Measured by running the new check suite against an unmodified copy of the Phase 1 code (`--self-test` 91 PASS, build PASS):

| # | Problem | Evidence |
|---|---|---|
| P1 | **↓ in the sidebar only worked once.** Picking a list made the game grid take keyboard focus, so the next ↓ moved through the games instead of the lists. | Baseline: after ↓, focus was in the grid; the second ↓ left the selection on NES. |
| P2 | **The selected system could be off-screen and unmarked.** LB/RB (and anything else that selected by code) changed the list without scrolling the sidebar. | Baseline picture: after LB from Setup the detail pane showed Arcade, but no sidebar row was highlighted, and Arcade was scrolled out of view. |
| P3 | **Duplicate actions.** File › New Window (⌘N) opened more windows, and every window's grid acted on each controller press. | Baseline: with two windows on NES, one simulated Y left favorites unchanged (toggled on and straight back off). |
| P4 | **No keyboard way back to the sidebar or into the games.** Esc did nothing; Return/→ in the sidebar did nothing. | Baseline checks; exploration of the focus chain. |
| P5 | **Each list forgot its selected game.** Leaving NES and coming back reset the selection to the first game. | Baseline: F acted on the first game instead of the one picked before. |
| P6 | **No menu equivalents.** No Settings (⌘,), no Find (⌘F); the View menu was empty. LB/RB had no keyboard counterpart. | Baseline menu dump. |
| P7 | **Systems with games but no emulator looked the same as ready ones.** The "Setup needed" state was only shown after opening the system. | Code and pictures. |
| P8 | Search showed the total count ("2 games") while filtering to one. | Picture. |
| P9 | Sidebar icons stayed 22 pt when System Settings › Appearance › Sidebar icon size changed; text scaled, icons didn't. | Code. |
| P10 | The first-launch window was 900 × 532 pt: about 11 sidebar rows. | Window frame. |

Not caused by this shift, noted for later:
- AppKit's "reentrant operation in its NSTableView delegate" warning on launch (audit O6).
- A one-time "-layoutSubtreeIfNeeded … already being laid out" message when the split view divider is moved by code. Running the same steps on the Phase 1 code logs it too.

## 4. What changed

### Priority A
- **One window** (`Window` scene instead of `WindowGroup`). There's no New Window command, so each controller press acts once (P3, audit O1).
- **One navigation model.** The new `Navigator` (`Navigator.swift`) owns the selected list and couch mode. The sidebar, the menu bar, the keyboard and the controller's LB/RB/Menu all change them through it.
  - The sidebar order and the LB/RB order now come from one definition, `SidebarItem.sections`, so they can't drift apart.
  - Menu commands no longer depend on window focus. An earlier version used SwiftUI's focused-scene values, which never reached the menu commands on this Mac.
- **Keyboard focus model** (P1, P4):

  | Where | Key | Result |
  |---|---|---|
  | Sidebar | ↑ ↓ | Move through the lists; focus stays in the sidebar (click and keyboard alike) |
  | Sidebar | Return or → | Move focus into the games |
  | Games | arrows, Return, F | Move, play, favorite (unchanged) |
  | Games | Esc | Back to the sidebar |
  | Search field | Return | Move to the results, so a second Return plays the match |
  | Anywhere | ⌘, | Setup |
  | Anywhere | ⌘[ / ⌘] | Previous / next system (same as LB / RB) |
  | Anywhere | ⌘F | Search |
  | Anywhere | ⌘R | Rescan games |
  | Anywhere | ⌃⌘S | Show/hide sidebar (View menu; standard `SidebarCommands`) |

  A click on a game, or any controller input, also moves focus to the games.
- **The selection stays visible** (P2). The sidebar scrolls to whatever got selected; it doesn't move for a row already in view.
- **Each list remembers its game** (P5), in the browser and couch mode alike.

### Priority B
- **Focus is visible.**
  - The sidebar highlight is blue while the sidebar has focus and grey while the games have it (standard macOS).
  - The selected game is outlined in blue while the games have focus and in grey otherwise. Before, the outline was blue no matter where keyboard focus was.
- **Status in the sidebar** (P7).
  - A system with games but no emulator shows an orange ⚠ count. It's an icon plus a number, not color alone, so it doesn't rely on color vision.
  - Hovering any row shows a tooltip: the game count, plus "Plays with RetroArch (Mesen)" or the setup step that's needed.
  - Empty systems show no badge.
  - Setup's tooltip lists what it covers.
- **Labels never wrap.** Names are one line and truncate with "…" if they ever had to; the tooltip has the full name.
- **Icons follow the sidebar size setting** (P9): 18, 22 or 26 pt for Small, Medium and Large. Checked at all three: "Game Boy Advance" plus its badge fits at Large.
- **Search** (P8): the header shows "1 of 2 games" while filtering.
- **First launch** (P10): the default window is 1100 × 720 pt. A saved window size still wins.
- **Accessibility names** (see §7): each row reads as its visible name, with the game count and any setup warning as its value. The decorative icon tile is hidden from VoiceOver.

### Not changed on purpose
- **No hover highlight on sidebar rows.** macOS sidebars don't have one; the tooltips are the hover feedback. Game cards keep their existing hover effect.
- **The Setup row stays with Favorites and Recently Played,** as your brief listed. It's also on ⌘,.
- **Controller mappings are unchanged:** d-pad/stick move, A play, B back, Y favorite, LB/RB switch, Menu couch mode.

## 5. Files changed

| File | Why |
|---|---|
| `mac/Sources/RetroHub/Navigator.swift` (new) | Selected list, couch mode, next/previous, Setup, Find: one place for the sidebar, menus, keyboard and controller |
| `mac/Sources/RetroHub/ContentView.swift` | Sidebar built from `SidebarItem.sections`; focus model (Return/→, Esc, search submit); scroll-to-selection; rows with status badge, tooltip, accessibility, icon size; grid keeps the picked game, takes focus only when the sidebar doesn't have it, and shows focus on the outline; "x of y games" |
| `mac/Sources/RetroHub/RetroHubApp.swift` | `Window` scene, default size, menu commands (Setup…, Find Games, Previous/Next System, Couch Mode, Rescan Games), `SidebarCommands` |
| `mac/Sources/RetroHub/Library.swift` | `SidebarItem.sections`, `all` derived from it, `stepping(from:by:in:)` |
| `mac/Sources/RetroHub/CouchView.swift` | Shares the remembered game per list with the browser |
| `mac/Sources/RetroHub/ControllerInput.swift` | Debug-only hook so the checks can simulate controller presses |
| `mac/Sources/RetroHub/SelfTests.swift` | New "sidebar" section: 21 checks on order, sections, names and LB/RB wrapping |
| `mac/Sources/RetroHub/UIChecks.swift` | Rewritten window check suite (below) |
| `mac/scripts/dev-ui-check.sh` | Runs the suite in a separate "RetroHub Dev Check" app with fresh settings every run, plus Small/Large sidebar runs; timeout |
| `mac/scripts/dev-build.sh` | `NAME` and `BUNDLE_ID` overrides (used by the check app) |
| `mac/scripts/dev-run.sh` | Now rebuilds every time (it used to reuse a stale build); still refuses to start a second copy |
| `docs/JSTAR_SHIFT01_AUDIT.md` | O1 marked fixed; pointers to this document |

## 6. Builds and tests

| | Before (Phase 1 code) | After |
|---|---|---|
| Debug build | PASS | PASS, 0 warnings |
| Strict concurrency build | — | PASS, 0 warnings |
| Universal release build (`INSTALL=0`) | PASS | PASS, 0 warnings, `x86_64 arm64`, signature valid, no test code in the binary, `~/Applications` untouched |
| `--self-test` | 91 PASS | **112 PASS** |
| `dev-ui-check.sh` full suite | 25 of 43 passed (earlier version of the suite) | **47 of 47 PASS** |
| Sidebar at Small / Large icon size | — | PASS / PASS |

How the window checks work (`scripts/dev-ui-check.sh`):
- **Isolation:**
  - They run in "RetroHub Dev Check", a separate debug app with its own bundle ID, settings and cover cache. Its settings are wiped before each run, so every run starts like a first launch.
  - Your RetroHub Dev settings, favorites and window are never touched, and the games folder is the test library.
- **What they do:** the real window is driven the way a person would: key presses, a mouse click, menu shortcuts and simulated controller presses. Each result is checked, and a picture of every step goes to `mac/build/dev/ui-check/`.
- **Keyboard checks need the window in front.** macOS 14 won't let a background program take focus while you're using another app, so the run waits up to 90 seconds: click its Dock icon when it appears and leave the Mac alone for about a minute. Without that, the keyboard and menu checks fail and say why.
- **Fix-ups to the suite itself:**
  - It originally waited with Swift's `Task.sleep`. Here a step sometimes never resumed even though the main thread was idle, so it now uses main-queue timers. Cause not identified.
  - The "selected row is in view" check first subtracted the toolbar height twice; I fixed it and re-ran both the old and new code with the corrected version.

## 7. Limitations (performance and accessibility)

- **VoiceOver names are set but not verified.** SwiftUI only builds its accessibility tree while an assistive app is running, and the app can't read it from inside. To check by hand:
  1. Turn on VoiceOver (⌘F5) and move through the sidebar with VO-arrows.
  2. Each row should read like "NES, 2 games, setup needed".
  3. Turn VoiceOver off again with ⌘F5.
- **Not tested:** Increase Contrast, Reduce Transparency, Full Keyboard Access and the Tab-key order. Synthetic Tab presses didn't move focus out of the grid in exploration, but that may be the synthetic event rather than the app, so test Tab and Shift-Tab by hand.
- **Contrast:** checked in pictures for light and dark mode. The orange badge also has an icon and a number; the selected row's badge turns white on the blue highlight.
- **Performance:** a row only checks whether an emulator is installed when its system has games (a few file checks each). The sidebar list is unchanged otherwise. The full rescan on every app activation still runs on the main thread (audit O4).
- **Window size:** RetroHub Dev keeps its saved window size, so the new 1100 × 720 default shows only where there's no saved size, as in the check app.

## 8. Check it yourself

```
mac/scripts/dev-run.sh
```

It rebuilds RetroHub Dev from the current source and opens it on the test library. (If RetroHub Dev is already open, it only brings it forward; quit it first with ⌘Q.)

1. **Labels:** every sidebar row shows an icon and a name. NES ⚠2, Super Nintendo ⚠1, Sega Genesis ⚠1 and the PlayStation, PlayStation 3 and PlayStation 4 rows ⚠1 show orange badges (no emulator yet). Hover NES: the tooltip explains what's needed.
2. **Keyboard in the sidebar:** click Setup, then press ↓ several times. Each press moves one row, and the highlight stays blue.
3. **Into the games and back:** on NES press Return (or →). The sidebar row turns grey and the first game gets a blue outline. ← → move between games, Esc goes back to the sidebar, and ↓ keeps moving through the systems.
4. **Remembered game:** in NES pick the second game, press ↓ to Super Nintendo, ↑ back to NES, Return. The second game is still selected.
5. **Menus:** ⌘, opens Setup. ⌘] and ⌘[ step through the lists. View shows Previous/Next System, Couch Mode, Rescan Games and Hide Sidebar. File has no New Window.
6. **Search:** press ⌘F, type "pattern" and press Return. The header says "1 of 2 games", the match is outlined in blue, and Return would play it.
7. **Resizing:** drag the window as small as it goes, and drag the divider in and out. Names never clip or overlap; the sidebar stops at 220 pt.
8. **Appearance:** switch to Dark in System Settings › Appearance, and try Sidebar icon size Small/Large. Everything stays readable and aligned.
9. **Controller (needs a pad):** LB/RB step through all lists and the sidebar scrolls to keep the highlighted one visible. Y favorites once. Menu enters couch mode, and B leaves it with the sidebar intact.
10. **Tab key and VoiceOver:** the two things I couldn't verify (§7).

## 9. Deferred

- **Compact (icon-only) sidebar.** There's no compact mode now, and this shift didn't add one. The labeled sidebar comes first, and on this macOS the sidebar column is fragile (the Phase 1 bug). Design for later:
  - A View menu toggle that's off by default.
  - In compact mode, rows show only the icon tile, and the name stays as the tooltip and VoiceOver label.
  - Section headers become dividers.
  - The column width becomes about 64 pt.
  - The controller panel shrinks to its icon.
  - The `List` must stay unwrapped by layout containers, and `dev-ui-check.sh` should run in both modes.
  - Risk to check first: whether `NavigationSplitView` honors a changed `navigationSplitViewColumnWidth` without a relaunch.
- **Controller focus zones:** let the d-pad move between the sidebar and the games (for example ← at the grid's left edge into the sidebar), with the focus outline following. This needs hardware testing.
- Remembering the last list between launches; keyboard navigation inside Setup's emulator cards.
- Audit items still open: O2/O3 (no guard against a second launch, no emulator process tracking), O4 (main-thread rescan), O6 (table reentrancy warning).

## 10. Recommended next steps

1. Your manual review (§8), especially Tab, VoiceOver and a real controller.
2. Install one emulator (OpenEmu, or RetroArch with the Mesen core) and run the game-launch tests from the Shift 01 plan.
3. Fix O2/O3 (running-game tracking and a single launch per press). They are the remaining reliability gap before the controller hotkey work.
4. Then the Phase 4 controller design (logical actions to per-emulator adapters) and the Phase 5 music, both of which build on `Navigator` and the game lifecycle.
