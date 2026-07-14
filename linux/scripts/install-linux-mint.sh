#!/bin/bash
set -euo pipefail

APP_NAME="nkriz-dns-connector"
DESKTOP_NAME="nkriz-dns-connector.desktop"
AUTOSTART_NAME="nkriz-dns-connector-autostart.desktop"
INSTALL_BIN="/usr/local/bin/${APP_NAME}"
INSTALL_DESKTOP="/usr/share/applications/${DESKTOP_NAME}"
INSTALL_AUTOSTART="/etc/xdg/autostart/${AUTOSTART_NAME}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$SCRIPT_DIR"

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "Error: this package is built for Linux Mint x64 (x86_64)." >&2
  exit 1
fi

if [[ ! -f "$DIST_DIR/$APP_NAME" ]]; then
  echo "Error: binary not found at $DIST_DIR/$APP_NAME" >&2
  exit 1
fi

missing=()
for cmd in nmcli pkexec; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    missing+=("$cmd")
  fi
done

if ((${#missing[@]} > 0)); then
  echo "Installing required packages..."
  sudo apt-get update
  sudo apt-get install -y network-manager policykit-1 libayatana-appindicator3-1
fi

echo "Installing $APP_NAME..."
sudo install -m 755 "$DIST_DIR/$APP_NAME" "$INSTALL_BIN"
sudo install -m 644 "$DIST_DIR/$DESKTOP_NAME" "$INSTALL_DESKTOP"

if [[ -f "$DIST_DIR/$AUTOSTART_NAME" ]]; then
  sudo install -m 644 "$DIST_DIR/$AUTOSTART_NAME" "$INSTALL_AUTOSTART"
fi

echo ""
echo "Installed:"
echo "  $INSTALL_BIN"
echo "  $INSTALL_DESKTOP"
if [[ -f "$INSTALL_AUTOSTART" ]]; then
  echo "  $INSTALL_AUTOSTART"
fi
echo ""
echo "Launch from the application menu or run: $APP_NAME"
echo "The app lives in the system tray (panel notification area), not as a dock window."
