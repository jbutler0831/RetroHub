#!/bin/bash
# Sets up a Raspberry Pi 5 (64-bit Raspberry Pi OS with desktop) to boot straight into RetroHub,
# with an optional safe-shutdown button and power LED.
#
#   ./install.sh [path/to/RetroHub-arm64.AppImage]
#
# Without a path it downloads the latest arm64 AppImage from GitHub. Settings:
#   SHUTDOWN_GPIO  GPIO for a shutdown button to ground (default 3, header pin 5). "none" to skip.
#   LED_GPIO       GPIO for a power LED (default 17, header pin 11). "none" to skip.
set -euo pipefail

SHUTDOWN_GPIO="${SHUTDOWN_GPIO:-3}"
LED_GPIO="${LED_GPIO:-17}"
REPO=jbutler0831/RetroHub
APP_DIR="$HOME/RetroHub"
APP="$APP_DIR/RetroHub.AppImage"

if [ "$(uname -m)" != "aarch64" ]; then
    echo "This needs 64-bit Raspberry Pi OS (aarch64); this system is $(uname -m)." >&2
    exit 1
fi
if [ "$(id -u)" = 0 ]; then
    echo "Run this as your normal user, not with sudo; it asks for sudo when it needs it." >&2
    exit 1
fi

echo "== Installing RetroArch (Flatpak) and AppImage support"
sudo apt-get update
# The Flatpak build keeps RetroArch's core and shader downloader, which Debian's package turns off.
sudo apt-get install -y flatpak
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
sudo flatpak install -y flathub org.libretro.RetroArch
# AppImages need FUSE 2 (libfuse2t64 on newer releases, libfuse2 on Bookworm).
sudo apt-get install -y libfuse2t64 || sudo apt-get install -y libfuse2

echo "== Installing RetroHub"
mkdir -p "$APP_DIR"
if [ $# -ge 1 ]; then
    cp "$1" "$APP"
else
    url=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | grep -o '"browser_download_url": *"[^"]*arm64\.AppImage"' | head -1 | cut -d'"' -f4)
    if [ -z "$url" ]; then
        echo "The latest release has no arm64 AppImage yet. Pass one as an argument." >&2
        exit 1
    fi
    curl -fL -o "$APP" "$url"
fi
chmod +x "$APP"

echo "== Starting RetroHub in console mode at login"
mkdir -p "$HOME/.config/autostart"
cat > "$HOME/.config/autostart/retrohub.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=RetroHub
Exec=$APP --console
X-GNOME-Autostart-enabled=true
EOF
# Boot to the desktop and log in automatically, so the Pi powers on into RetroHub.
sudo raspi-config nonint do_boot_behaviour B4

CONFIG=/boot/firmware/config.txt
[ -f "$CONFIG" ] || CONFIG=/boot/config.txt

if [ "$SHUTDOWN_GPIO" != none ]; then
    echo "== Shutdown button on GPIO $SHUTDOWN_GPIO"
    if ! grep -q '^dtoverlay=gpio-shutdown' "$CONFIG"; then
        printf '\n# RetroHub: shut down safely when this GPIO is connected to ground\ndtoverlay=gpio-shutdown,gpio_pin=%s\n' \
            "$SHUTDOWN_GPIO" | sudo tee -a "$CONFIG" >/dev/null
    fi
    # The overlay sends a power-key press; have it power off instead of asking first.
    sudo mkdir -p /etc/systemd/logind.conf.d
    printf '[Login]\nHandlePowerKey=poweroff\n' | sudo tee /etc/systemd/logind.conf.d/retrohub.conf >/dev/null
fi

if [ "$LED_GPIO" != none ]; then
    echo "== Power LED on GPIO $LED_GPIO"
    sudo tee /etc/systemd/system/retrohub-led.service >/dev/null <<EOF
[Unit]
Description=RetroHub power LED (GPIO $LED_GPIO)

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/pinctrl set $LED_GPIO op dh
ExecStop=/usr/bin/pinctrl set $LED_GPIO op dl

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable --now retrohub-led.service
fi

echo
echo "Done. Reboot to start RetroHub: sudo reboot"
echo "Then put your games in ~/Games (one folder per system). Open RetroArch once"
echo "(flatpak run org.libretro.RetroArch) to download cores and shaders from Main Menu > Online Updater."
