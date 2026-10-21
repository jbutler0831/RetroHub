# RetroHub

One library for NES, SNES, N64, Xbox and PS3 games on macOS. RetroHub does not
emulate anything itself; it finds your games and launches them in:

| System | Emulator |
|---|---|
| NES / SNES / N64 | RetroArch (Mesen, Snes9x, Mupen64Plus-Next cores) or OpenEmu |
| Xbox (original) | xemu |
| PS3 | RPCS3 |

## Build

Requires the Xcode Command Line Tools (`xcode-select --install`).

    ./build.sh

## Games folder

Defaults to `~/Games` (change it from the toolbar). RetroHub creates:

    ~/Games/NES    .nes
    ~/Games/SNES   .sfc .smc
    ~/Games/N64    .z64 .n64 .v64
    ~/Games/Xbox   XISO .iso
    ~/Games/PS3    one folder per game, containing PS3_GAME/ or USRDIR/

Use dumps of games you own. xemu also needs BIOS, MCPX boot ROM and HDD image
files set in its settings; RPCS3 needs the PS3 firmware from Sony's site
(File › Install Firmware).
