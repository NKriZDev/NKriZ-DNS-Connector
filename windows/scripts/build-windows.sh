#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/../dist/windows"
TARGET="x86_64-pc-windows-gnu"
APP_NAME="NKriZ-DNS-Connector.exe"
TOOLCHAIN_DIR="$ROOT_DIR/.toolchain/llvm-mingw"
ARCHIVE="$ROOT_DIR/.toolchain/llvm-mingw.tar.xz"
TOOLCHAIN_URL="https://github.com/mstorsjo/llvm-mingw/releases/download/20260616/llvm-mingw-20260616-ucrt-macos-universal.tar.xz"

cd "$ROOT_DIR"

export PATH="$TOOLCHAIN_DIR/bin:$PATH"

if [ ! -x "$TOOLCHAIN_DIR/bin/x86_64-w64-mingw32-gcc" ]; then
  echo "==> Downloading llvm-mingw toolchain..."
  mkdir -p "$ROOT_DIR/.toolchain"
  curl -fL "$TOOLCHAIN_URL" -o "$ARCHIVE"
  rm -rf "$TOOLCHAIN_DIR"
  mkdir -p "$TOOLCHAIN_DIR"
  tar -xJf "$ARCHIVE" -C "$TOOLCHAIN_DIR" --strip-components=1
fi

if ! rustup target list --installed | grep -q "$TARGET"; then
  rustup target add "$TARGET"
fi

echo "==> Building Windows release ($TARGET)..."
cargo build --release --target "$TARGET"

mkdir -p "$DIST_DIR"
cp "$ROOT_DIR/target/$TARGET/release/nkriz-dns-connector.exe" "$DIST_DIR/$APP_NAME"

if command -v zip >/dev/null 2>&1; then
  (cd "$DIST_DIR" && rm -f NKriZ-DNS-Connector-windows.zip && zip -q NKriZ-DNS-Connector-windows.zip "$APP_NAME")
  echo "==> Zip: $DIST_DIR/NKriZ-DNS-Connector-windows.zip"
fi

echo "==> Done: $DIST_DIR/$APP_NAME"
