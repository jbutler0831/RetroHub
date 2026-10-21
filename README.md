# RetroHub

One library for NES, SNES, N64, Xbox and PS3 games on macOS. RetroHub does not
emulate anything itself; it finds your games and launches them in:

| System | Emulator (first one installed is used) |
|---|---|
| NES, SNES, N64, Game Boy, GBC, GBA, Genesis, PS1 | RetroArch or OpenEmu |
| GameCube, Wii | Dolphin |
| Nintendo DS | melonDS, RetroArch or OpenEmu |
| PS2 | PCSX2 |
| PS3 | RPCS3 |
| PSP | PPSSPP, RetroArch or OpenEmu |
| Xbox (original) | xemu |

Also: cover art, favorites, recently played, and a full-screen couch mode
for controllers (press Menu/Options, or the TV button in the toolbar).

## Downloads

Get the latest version from the Releases page:

- **Mac** (Apple silicon and Intel): `RetroHub.zip`
- **Windows**: `RetroHub-Setup-<version>.exe` (installer) or `RetroHub-Portable-<version>.exe`
- **Linux**: `RetroHub-<version>-x86_64.AppImage` (`chmod +x` it, then run)

On Windows and Linux, RetroHub looks for emulators in their usual install
locations (including Scoop on Windows and Flatpak on Linux). If one isn't found,
open Setup and click **Locate…** to pick its program file. OpenEmu is Mac-only;
use RetroArch on Windows and Linux.

## Build

**Mac app** (native Swift, in `Sources/`): requires the Xcode Command Line Tools
(`xcode-select --install`).

    ./build.sh

This builds `build/RetroHub.app` and `build/RetroHub.zip` (the file to upload to a
release) and installs the app to `~/Applications`. By default the app is signed
ad hoc: it runs on your Mac, but on other Macs Gatekeeper blocks it until the user
right-clicks it and chooses **Open**. To build one that opens normally anywhere,
sign it with a Developer ID certificate and notarize it:

    xcrun notarytool store-credentials retrohub --apple-id <you@example.com> --team-id <TEAMID>
    SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=retrohub ./build.sh

**Windows/Linux app** (Electron, in `desktop/`): requires Node.js 22.

    cd desktop
    npm install
    npm start          # run it
    npm run dist       # build installers for the current OS

Publishing a GitHub release triggers `.github/workflows/desktop.yml`, which builds
the Windows and Linux versions and attaches them to the release; upload the Mac
`build/RetroHub.zip` yourself. The Windows build is unsigned, so Windows SmartScreen
shows "Windows protected your PC" on first run (click **More info** → **Run anyway**).

## Games folder

Defaults to `~/Games` (change it from the toolbar). RetroHub creates one folder
per system (NES, SNES, N64, GameCube, Wii, GB, GBC, GBA, DS, Genesis, PS1, PS2,
PS3, PSP, Xbox); each empty system shows which file types it expects. PS3 games
go in one folder per game, containing PS3_GAME/ or USRDIR/.

Use dumps of games you own. xemu also needs BIOS, MCPX boot ROM and HDD image
files set in its settings; PS1 and PCSX2 need a console BIOS; RPCS3 needs the PS3 firmware from Sony's site
(File › Install Firmware).
