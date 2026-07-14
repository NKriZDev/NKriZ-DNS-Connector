#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/../dist/linux"
TARGET="x86_64-unknown-linux-gnu"
APP_NAME="nkriz-dns-connector"
VERSION="1.0.0"

cd "$ROOT_DIR"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT_DIR/target}"

USE_CROSS=0
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  USE_CROSS=1
fi

if [[ "$USE_CROSS" -eq 1 ]]; then
  if ! command -v cross >/dev/null 2>&1; then
    echo "==> Installing cross..."
    cargo install cross --git https://github.com/cross-rs/cross
  fi

  if ! rustup target list --installed | grep -q "$TARGET"; then
    rustup target add "$TARGET"
  fi

  echo "==> Building Linux Mint x64 release via cross ($TARGET)..."
  cross build --release --target "$TARGET"
else
  echo "==> Docker unavailable; building with downloaded Linux sysroot..."
  echo "    Tip: start Docker Desktop for a simpler cross build, or run"
  echo "    linux/scripts/build-linux-native.sh directly on Linux Mint x64."
  echo "    This path needs ~3GB free disk for the cross sysroot."
  "$ROOT_DIR/scripts/bootstrap-sysroot.sh"

  if ! rustup target list --installed | grep -q "$TARGET"; then
    rustup target add "$TARGET"
  fi

  export PKG_CONFIG_ALLOW_CROSS=1
  CROSS_ROOTFS="$ROOT_DIR/.toolchain/cross-rootfs"
  SYSROOT="$CROSS_ROOTFS/usr/x86_64-linux-gnu"
  export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
  export PKG_CONFIG_PATH="$SYSROOT/usr/lib/x86_64-linux-gnu/pkgconfig:$SYSROOT/usr/lib64/x86_64-linux-gnu/pkgconfig:$SYSROOT/usr/share/pkgconfig"
  GCC="$ROOT_DIR/.toolchain/$TARGET/bin/x86_64-linux-gnu-gcc"
  GXX="$ROOT_DIR/.toolchain/$TARGET/bin/x86_64-linux-gnu-g++"
  export CC_x86_64_unknown_linux_gnu="$GCC"
  export CXX_x86_64_unknown_linux_gnu="$GXX"
  export CFLAGS_x86_64_unknown_linux_gnu="--sysroot=$SYSROOT"
  export CXXFLAGS_x86_64_unknown_linux_gnu="--sysroot=$SYSROOT"
  export BINDGEN_EXTRA_CLANG_ARGS="--sysroot=$SYSROOT"

  if ! command -v pkg-config >/dev/null 2>&1; then
    echo "Error: host pkg-config is required (brew install pkgconf)." >&2
    exit 1
  fi

  echo "==> Building Linux Mint x64 release ($TARGET)..."
  cargo build --release --target "$TARGET"
fi

BIN_PATH="$CARGO_TARGET_DIR/$TARGET/release/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "Build failed: binary not found at $BIN_PATH" >&2
  exit 1
fi

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
echo "  Binary:   $DIST_DIR/$APP_NAME"
echo "  Desktop:  $DIST_DIR/nkriz-dns-connector.desktop"
echo "  Package:  $TARBALL"
echo ""
echo "Install on Linux Mint x64:"
echo "  tar -xzf $(basename "$TARBALL")"
echo "  ./install-linux-mint.sh"
