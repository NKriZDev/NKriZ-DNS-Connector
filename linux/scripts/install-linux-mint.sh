#!/bin/bash
set -euo pipefail

APP_NAME="nkriz-dns-connector"
LAUNCH_NAME="${APP_NAME}-launch"
DESKTOP_NAME="nkriz-dns-connector.desktop"
AUTOSTART_NAME="nkriz-dns-connector-autostart.desktop"
INSTALL_BIN="/usr/local/bin/${APP_NAME}"
INSTALL_LAUNCH="/usr/local/bin/${LAUNCH_NAME}"
INSTALL_DESKTOP="/usr/share/applications/${DESKTOP_NAME}"
INSTALL_AUTOSTART="/etc/xdg/autostart/${AUTOSTART_NAME}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$SCRIPT_DIR"
LINUX_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$LINUX_ROOT/scripts/common.sh" ]]; then
  # shellcheck source=common.sh
  source "$LINUX_ROOT/scripts/common.sh"
else
  run_root() {
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then "$@"; return; fi
    if command -v sudo >/dev/null 2>&1 && sudo "$@"; then return; fi
    su -c "$(printf '%q ' "$@")"
  }
  ensure_apt_packages() {
    local missing=()
    for pkg in network-manager policykit-1 libayatana-appindicator3-1; do
      dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
    done
    if ((${#missing[@]} > 0)); then
      run_root apt-get update
      run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
    fi
  }
fi

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "Error: this package is built for Linux Mint x64 (x86_64)." >&2
  exit 1
fi

if [[ ! -f "$DIST_DIR/$APP_NAME" ]]; then
  echo "Error: binary not found at $DIST_DIR/$APP_NAME" >&2
  exit 1
fi

ensure_apt_packages "runtime" network-manager policykit-1 libayatana-appindicator3-1

launch_src="$DIST_DIR/launch.sh"
if [[ ! -f "$launch_src" ]]; then
  launch_src="$LINUX_ROOT/scripts/launch.sh"
fi

echo "Installing $APP_NAME..."
run_root install -m 755 "$DIST_DIR/$APP_NAME" "$INSTALL_BIN"
run_root install -m 755 "$launch_src" "$INSTALL_LAUNCH"
run_root install -m 644 "$DIST_DIR/$DESKTOP_NAME" "$INSTALL_DESKTOP"

if [[ -f "$DIST_DIR/$AUTOSTART_NAME" ]]; then
  run_root install -m 644 "$DIST_DIR/$AUTOSTART_NAME" "$INSTALL_AUTOSTART"
fi

echo ""
echo "Installed:"
echo "  $INSTALL_BIN"
echo "  $INSTALL_LAUNCH"
echo "  $INSTALL_DESKTOP"
if [[ -f "$INSTALL_AUTOSTART" ]]; then
  echo "  $INSTALL_AUTOSTART"
fi
echo ""
echo "Launch: nkriz-dns-connector-launch"
echo "The app lives in the system tray (panel notification area)."
