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

## Build

Requires the Xcode Command Line Tools (`xcode-select --install`).

    ./build.sh

## Games folder

Defaults to `~/Games` (change it from the toolbar). RetroHub creates one folder
per system (NES, SNES, N64, GameCube, Wii, GB, GBC, GBA, DS, Genesis, PS1, PS2,
PS3, PSP, Xbox); each empty system shows which file types it expects. PS3 games
go in one folder per game, containing PS3_GAME/ or USRDIR/.

Use dumps of games you own. xemu also needs BIOS, MCPX boot ROM and HDD image
files set in its settings; PS1 and PCSX2 need a console BIOS; RPCS3 needs the PS3 firmware from Sony's site
(File › Install Firmware).
