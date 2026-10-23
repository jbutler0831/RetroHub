# RetroHub: what J-Star has done so far (for Jor-el)

Short version for our shared project. The details are in `docs/JSTAR_SHIFT01_AUDIT.md`, `docs/JSTAR_SHIFT02_UI_UX.md` and `docs/JSTAR_SHIFT03_HANDOFF.md`.

## Where the work is

- **Starting point:** J-Star started from a ZIP of `main`. It turned out to be **exactly v1.6** (`dd37423`), file for file.
- **The branch:** all the work is replayed onto a branch from `origin/main`, **`jstar/shift-01-03`**: 12 commits, one topic each, all building.
- **Nothing pushed yet.** J-Star's account has push access; the branch goes up as a pull request for you to review, never straight to `main`.
- **Rules for agents:** we added `AGENTS.md`. Agents never push to `main`, never merge, never force-push, and never change remotes; a person approves every push; and no games, BIOS, credentials or build output go into commits.

## Mac app changes (the Windows/Linux app is untouched)

**Fixes**
- **Startup crash:** one damaged PS3/PS4/Vita `PARAM.SFO` crashed RetroHub on every launch.
- **Cover art:** one server error hid a game's cover for good.
- **Sidebar on macOS 14:** it showed icons only. `.safeAreaInset` around the sidebar `List` squeezed its column to 38 pt.
- **Duplicate actions:** with two windows open, one controller press acted twice. It's a single window now.
- **Duplicate launches:** A pressed during a launch could start a second emulator. Now one game runs at a time; A brings the running one forward, and RetroHub comes back to the front when the game closes.

**New**
- **Sidebar:** grouped by maker, with Favorites, Recently Played and Setup on top. An orange ⚠ count means a system has games but no emulator.
- **Keyboard and menu:**
  - ↑/↓ move through the sidebar;
  - Return or → goes into the games, Esc comes back;
  - ⌘, opens Setup, ⌘F searches, ⌘[ / ⌘] switch systems (like LB/RB), ⌘R rescans.
  - Each list remembers its picked game.
- **Appearance:** Follow System / Light / Dark, in Setup and the View menu. It affects RetroHub only. Orange and green status text is now readable in Light mode: it measured 1.55:1, now 5.6:1.
- **Developer tools** (debug builds only):
  - `--self-test`: 188 checks;
  - `scripts/dev-ui-check.sh`: window checks;
  - Controller Diagnostics: shows each raw press, the action it made, and the result;
  - `scripts/dev-inventory.sh`: read-only. Gives READY / SETUP_REQUIRED / UNKNOWN / UNSUPPORTED for each system, from installed emulators, their CPU architecture, cores, and the firmware those cores list.
  - An isolated "RetroHub Dev" app that never touches real settings or `~/Games`.

## Not verified yet

- **Real DualSense controller:** next test session.
- **A real game in RetroArch:** RetroArch isn't installed yet.
- **VoiceOver.**

## Questions for you

1. Is `github.com/jbutler0831/RetroHub` the repo we should both use, with `main` as the base?
2. OK to protect `main` (pull request + one approval, no force pushes) and add a small CI check (Mac build + self-tests, desktop syntax check)?
3. Any plans of yours that touch the Mac sidebar, controller input or `Systems.swift`, so we don't collide?
4. Should both apps eventually read one shared systems/emulators catalog, instead of keeping `Systems.swift` and `systems.js` in step by hand?
