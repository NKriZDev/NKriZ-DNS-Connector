#!/bin/bash
# Installed as /usr/local/bin/nkriz-dns-connector-launch
# Sets up the desktop session environment before starting the tray app.

set -euo pipefail

APP_NAME="nkriz-dns-connector"
INSTALL_BIN="/usr/local/bin/${APP_NAME}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
  # shellcheck source=common.sh
  source "$SCRIPT_DIR/common.sh"
else
  detect_graphical_env() {
    [[ -z "${DISPLAY:-}" && -S /tmp/.X11-unix/X0 ]] && export DISPLAY=:0
    [[ -z "${XAUTHORITY:-}" && -f "$HOME/.Xauthority" ]] && export XAUTHORITY="$HOME/.Xauthority"
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
  }
fi

detect_graphical_env

if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
  echo "error: no graphical session found (DISPLAY/WAYLAND_DISPLAY not set)." >&2
  echo "Open a terminal on the desktop (not plain SSH) and run: ./native run" >&2
  exit 1
fi

exec "$INSTALL_BIN"
