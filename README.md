# RetroHub

One library for your retro and console games, from NES to PS4, on Mac, Windows, Linux and Raspberry Pi. RetroHub does not
emulate anything itself; it finds your games and launches them in:

| System | Emulator (first one installed is used) |
|---|---|
| NES, SNES, N64, Game Boy, GBC, GBA, PS1 | RetroArch or OpenEmu |
| Master System, Genesis, Sega CD, 32X, Saturn, Game Gear | RetroArch or OpenEmu |
| Dreamcast | RetroArch (Flycast) |
| TurboGrafx-16, Atari 2600 | RetroArch or OpenEmu |
| Arcade, Neo Geo | RetroArch (FinalBurn Neo) |
| GameCube, Wii | Dolphin |
| Wii U | Cemu |
| Nintendo DS | melonDS, RetroArch or OpenEmu |
| Nintendo 3DS | Azahar or RetroArch |
| PS2 | PCSX2 |
| PS3 | RPCS3 |
| PS4 | shadPS4 (early: many games don't run yet) |
| PSP | PPSSPP, RetroArch or OpenEmu |
| PS Vita | Vita3K (games are installed in Vita3K and listed from there) |
| Xbox (original) | xemu |
| Xbox 360 | Xenia Canary (Windows and Linux only) |

Also: cover art, favorites, recently played, and a full-screen couch mode
for controllers (press Menu/Options, or the TV button in the toolbar).

## Downloads

Get the latest version from the Releases page:

- **Mac** (Apple silicon and Intel): `RetroHub.zip`
- **Windows**: `RetroHub-Setup-<version>.exe` (installer) or `RetroHub-Portable-<version>.exe`
- **Linux**: `RetroHub-<version>-x86_64.AppImage` (`chmod +x` it, then run)
- **Raspberry Pi 4/5** (64-bit Raspberry Pi OS): `RetroHub-<version>-arm64.AppImage`. To build a console that
  boots into RetroHub, with a shutdown button and power LED, see [pi/README.md](pi/README.md).

On Windows and Linux, RetroHub looks for emulators in their usual install
locations (including Scoop on Windows and Flatpak on Linux). If one isn't found,
open Setup and click **Locate…** to pick its program file. OpenEmu is Mac-only;
use RetroArch on Windows and Linux.

## Build

**Mac app** (native Swift, in `mac/`): requires the Xcode Command Line Tools
(`xcode-select --install`).

    mac/build.sh

This builds `mac/build/RetroHub.app` and `mac/build/RetroHub.zip` (the file to upload to a
release) and installs the app to `~/Applications`. By default the app is signed
ad hoc: it runs on your Mac, but on other Macs Gatekeeper blocks it until the user
right-clicks it and chooses **Open**. To build one that opens normally anywhere,
sign it with a Developer ID certificate and notarize it:

    xcrun notarytool store-credentials retrohub --apple-id <you@example.com> --team-id <TEAMID>
    SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=retrohub mac/build.sh

**Windows/Linux app** (Electron, in `desktop/`): requires Node.js 22.

    cd desktop
    npm install
    npm start          # run it
    npm run dev        # run a development copy: settings and games in .devdata/, never ~/Games
    npm test           # tests
    npm run dist       # build installers for the current OS

Publishing a GitHub release triggers `.github/workflows/release.yml`, which builds
the Mac, Windows and Linux (x86_64 and Raspberry Pi) versions and attaches them to the release. The Mac build
from CI is signed ad hoc, and the Windows build is unsigned, so Windows SmartScreen
shows "Windows protected your PC" on first run (click **More info** → **Run anyway**).

## Games folder

Defaults to `~/Games` (change it from the toolbar). RetroHub creates one folder
per system (for example NES, SNES, N64, Genesis, Dreamcast, Arcade, PS2); each empty
system shows which file types it expects. PS Vita is the exception: install games in
Vita3K and RetroHub lists them. PS3 games
go in one folder per game, containing PS3_GAME/ or USRDIR/; PS4 games go in one folder
per game, containing eboot.bin and sce_sys/.

Use dumps of games you own. xemu also needs BIOS, MCPX boot ROM and HDD image
files set in its settings; PS1 and PCSX2 need a console BIOS; RPCS3 needs the PS3 firmware from Sony's site
(File › Install Firmware); some PS4 games need firmware modules from your own PS4.

shadPS4 comes as a plain program rather than an installer. On a Mac, unzip it into
`Applications/shadPS4/`; on Windows, into `C:\shadPS4\`; on Linux, put the AppImage
on your PATH. Anywhere else works too: click **Locate…** in Setup (Windows and Linux).
