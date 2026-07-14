#!/bin/bash
set -euo pipefail

# Native build for Linux Mint / Ubuntu x86_64 (run on the target machine).
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/../dist/linux"
APP_NAME="nkriz-dns-connector"
VERSION="1.0.0"

if [[ "$(uname -s)" != "Linux" ]] || [[ "$(uname -m)" != "x86_64" ]]; then
  echo "Error: run this script on Linux Mint / Ubuntu x86_64." >&2
  exit 1
fi

missing=()
for cmd in cargo pkg-config nmcli; do
  command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done

if ((${#missing[@]} > 0)); then
  echo "Installing build dependencies..."
  sudo apt-get update
  sudo apt-get install -y \
    build-essential curl pkg-config \
    libgtk-3-dev libayatana-appindicator3-dev libxdo-dev \
    network-manager policykit-1
fi

cd "$ROOT_DIR"
cargo build --release

BIN_PATH="$ROOT_DIR/target/release/$APP_NAME"
mkdir -p "$DIST_DIR"
cp "$BIN_PATH" "$DIST_DIR/$APP_NAME"
cp "$ROOT_DIR/nkriz-dns-connector.desktop" "$DIST_DIR/nkriz-dns-connector.desktop"
cp "$ROOT_DIR/nkriz-dns-connector-autostart.desktop" "$DIST_DIR/nkriz-dns-connector-autostart.desktop"
cp "$ROOT_DIR/scripts/install-linux-mint.sh" "$DIST_DIR/install-linux-mint.sh"
chmod +x "$DIST_DIR/install-linux-mint.sh"

TARBALL="$DIST_DIR/NKriZ-DNS-Connector-linux-x64-${VERSION}.tar.gz"
rm -f "$TARBALL"
tar -czf "$TARBALL" -C "$DIST_DIR" \
  "$APP_NAME" \
  nkriz-dns-connector.desktop \
  nkriz-dns-connector-autostart.desktop \
  install-linux-mint.sh

echo ""
echo "Build complete."
echo "  Binary:  $DIST_DIR/$APP_NAME"
echo "  Package: $TARBALL"
echo ""
echo "Install:"
echo "  tar -xzf $(basename "$TARBALL")"
echo "  ./install-linux-mint.sh"
