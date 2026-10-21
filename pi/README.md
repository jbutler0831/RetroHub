# RetroHub on a Raspberry Pi 5

Turn a Raspberry Pi 5 into a little console that powers on straight into your game library,
with a safe-shutdown button and a power LED. It suits a mini case modeled on a classic system
(a tiny Neo Geo or Saturn, a mini arcade cabinet) or a handheld build.

## What you need

- **Raspberry Pi 5** (4 GB or more) with **64-bit Raspberry Pi OS with desktop**. The Pi 4 and
  Compute Module 4/5 work too. The Pi Zero 2 W doesn't have enough memory for RetroHub; use a
  lightweight emulation OS such as RetroPie or Recalbox there.
- A screen. RetroHub's console mode fits anything from a 320×240 handheld LCD up to a TV.
- A USB or Bluetooth controller.
- Optional: a momentary push button, an LED and a 330 Ω resistor.

## Install

On the Pi, in a terminal:

    curl -fLO https://raw.githubusercontent.com/jbutler0831/RetroHub/main/pi/install.sh
    chmod +x install.sh
    ./install.sh
    sudo reboot

The script:

1. Installs RetroArch (the Flatpak version, which can download cores and shaders) and the FUSE
   library AppImages need.
2. Downloads the latest RetroHub for Raspberry Pi (`RetroHub-<version>-arm64.AppImage`) to `~/RetroHub`.
   To use a file you already have, pass it: `./install.sh RetroHub-1.5.0-arm64.AppImage`.
3. Starts RetroHub in **console mode** (`--console`: full screen, controller-first, games open
   full screen) when the Pi logs in, and sets the Pi to log in automatically.
4. Sets up the shutdown button and power LED below. Choose other pins with
   `SHUTDOWN_GPIO=… LED_GPIO=… ./install.sh`, or skip either with `none`.

After rebooting, open RetroArch once (`flatpak run org.libretro.RetroArch`) and use
**Main Menu › Online Updater** to download cores (Core Downloader) and shaders (Update Slang
Shaders). Then put your games in `~/Games`, one folder per system.

## Buttons and LED

Pin numbers are physical header pins; pin 1 is the one with the square solder pad.

| Part | Connect | Notes |
|---|---|---|
| **Power button** (on and off) | The two **J2** pads on the Pi 5 board | Built into the Pi 5, no setup needed. Press to turn on. Press while running for a clean shutdown; on the desktop the first press may show a menu, and a second press shuts down. |
| **Shutdown button** (optional extra) | **Pin 5** (GPIO 3) and **pin 6** (ground) | Connecting the two shuts the Pi down safely. On the Pi 5 it doesn't turn it back on; use J2 for that. |
| **Power LED** | **Pin 11** (GPIO 17) → 330 Ω resistor → LED long leg; LED short leg → **pin 9** (ground) | Lights once the Pi has started and goes out when it shuts down. |

Use momentary (push-to-make) buttons. Never connect a GPIO pin straight to 5 V.

## Cases

Search Printables or Thingiverse for "Raspberry Pi 5 mini console case" (or a specific system,
such as "Pi 5 Neo Geo", "Pi 5 Saturn" or "Pi mini arcade cabinet"). Most have a hole for a button
and a light pipe or LED. Leave room for the Pi 5's fan or a heatsink: emulating 3D systems at
higher resolutions makes it run hot.

## If something doesn't work

- **RetroHub doesn't start at boot:** check `~/.config/autostart/retrohub.desktop`, and run
  `~/RetroHub/RetroHub.AppImage --console` from a terminal to see any error.
- **"AppImages require FUSE":** run `sudo apt install libfuse2t64` (or `libfuse2` on older releases).
- **Games don't start:** RetroArch needs the core for that system (see Setup in RetroHub).
- **LED stays off:** check its direction (long leg towards the resistor), then `systemctl status retrohub-led`.
