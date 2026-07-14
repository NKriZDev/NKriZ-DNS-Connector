#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TOOLCHAIN_DIR="$ROOT_DIR/.toolchain"
TARGET="x86_64-unknown-linux-gnu"
TOOLCHAIN_ROOT="$TOOLCHAIN_DIR/$TARGET"
GCC_BIN="$TOOLCHAIN_ROOT/bin/x86_64-linux-gnu-gcc"
CROSS_IMAGE="ghcr.io/cross-rs/${TARGET}:0.2.5"
CROSS_ROOTFS="$TOOLCHAIN_DIR/cross-rootfs"
SYSROOT_DIR="$CROSS_ROOTFS/usr/x86_64-linux-gnu"
UBUNTU_SUITE="focal"
MARKER="$SYSROOT_DIR/.bootstrap-complete"

arch="$(uname -m)"
case "$arch" in
  arm64|aarch64) HOST_ARCH="aarch64-darwin"; CRANE_ARCH="Darwin_arm64" ;;
  x86_64) HOST_ARCH="x86_64-darwin"; CRANE_ARCH="Darwin_x86_64" ;;
  *)
    echo "Unsupported build host architecture: $arch" >&2
    exit 1
    ;;
esac

MESSENSE_VERSION="v15.2.0"
MESSENSE_URL="https://github.com/messense/homebrew-macos-cross-toolchains/releases/download/${MESSENSE_VERSION}/${TARGET}-${HOST_ARCH}.tar.gz"
CRANE_VERSION="v0.21.7"
CRANE_URL="https://github.com/google/go-containerregistry/releases/download/${CRANE_VERSION}/go-containerregistry_${CRANE_ARCH}.tar.gz"
CRANE_BIN="$TOOLCHAIN_DIR/bin/crane"
POOL_BASE="http://archive.ubuntu.com/ubuntu"

extract_deb() {
  local deb="$1"
  local dest="$2"
  local tmp
  tmp="$(mktemp -d)"
  (
    cd "$tmp"
    ar x "$deb"
    tar -xf data.tar.zst -C "$dest" 2>/dev/null \
      || tar -xf data.tar.xz -C "$dest" 2>/dev/null \
      || tar -xf data.tar.gz -C "$dest" 2>/dev/null
  )
  rm -rf "$tmp"
}

pool_filename() {
  local package="$1"
  local dist component file
  for dist in "${UBUNTU_SUITE}" "${UBUNTU_SUITE}-updates" "${UBUNTU_SUITE}-security"; do
    for component in main universe; do
      file="$(
        curl -fsSL "${POOL_BASE}/dists/${dist}/${component}/binary-amd64/Packages.gz" \
          | gunzip \
          | awk -v pkg="$package" '
              $1 == "Package:" && $2 == pkg { found = 1; next }
              found && $1 == "Filename:" { print $2; exit }
            ' \
          || true
      )"
      if [[ -n "$file" ]]; then
        echo "$file"
        return 0
      fi
    done
  done
  return 1
}

download_single_deb() {
  local package="$1"
  local cache="$TOOLCHAIN_DIR/debs"
  local deb="$cache/${package}.deb"
  mkdir -p "$cache"

  if [[ -f "$deb" ]]; then
    return 0
  fi

  local filename
  if ! filename="$(pool_filename "$package")"; then
    echo "  warning: package not found in Ubuntu pool: $package" >&2
    return 0
  fi

  echo "  downloading $package"
  if ! curl -fsSL -o "$deb" "${POOL_BASE}/${filename}"; then
    echo "  warning: failed to download $package" >&2
    rm -f "$deb"
  fi
}

resolve_dep_names() {
  local control="$1"
  awk '/^(Depends|Build-Depends):/ {
    line = $0
    sub(/^[^:]+: /, "", line)
    gsub(/[|]/, ",", line)
    n = split(line, chunks, ",")
    for (i = 1; i <= n; i++) {
      sub(/^[[:space:]]+/, "", chunks[i])
      if (match(chunks[i], /^[A-Za-z0-9.+~-][A-Za-z0-9.+~:-]*/)) {
        print substr(chunks[i], RSTART, RLENGTH)
      }
    }
  }' "$control" | sort -u
}

download_focal_packages() {
  local cache="$TOOLCHAIN_DIR/debs"
  mkdir -p "$cache"

  local -a queue=(
    libgtk-3-dev
    libappindicator3-dev
    libxdo-dev
  )
  local seen_file="$cache/.seen"
  : > "$seen_file"

  already_seen() {
    rg -Fxq "$1" "$seen_file"
  }

  mark_seen() {
    echo "$1" >> "$seen_file"
  }

  download_package() {
    local package="${1%%:*}"
    if already_seen "$package"; then
      return 0
    fi
    mark_seen "$package"

    download_single_deb "$package"

    local deb="$cache/${package}.deb"
    if [[ ! -f "$deb" ]]; then
      return 0
    fi

    local tmp deps_file
    tmp="$(mktemp -d)"
    deps_file="$tmp/deps.txt"
    (
      cd "$tmp"
      ar x "$deb"
      tar -xf control.tar.zst 2>/dev/null || tar -xf control.tar.xz 2>/dev/null || tar -xf control.tar.gz 2>/dev/null
      if [[ -f control ]]; then
        resolve_dep_names control > "$deps_file"
      fi
    )
    if [[ -f "$deps_file" ]]; then
      while IFS= read -r dep; do
        queue+=("$dep")
      done < "$deps_file"
    fi
    rm -rf "$tmp"
  }

  local package
  while ((${#queue[@]} > 0)); do
    package="${queue[0]}"
    queue=("${queue[@]:1}")
    download_package "$package"
  done

  shopt -s nullglob
  for deb in "$cache"/*.deb; do
    extract_deb "$deb" "$SYSROOT_DIR"
  done
}

ensure_libxdo_pc() {
  local pc="$SYSROOT_DIR/usr/lib/x86_64-linux-gnu/pkgconfig/libxdo.pc"
  if [[ -f "$pc" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$pc")"
  cat > "$pc" <<'EOF'
prefix=/usr
libdir=${prefix}/lib/x86_64-linux-gnu
includedir=${prefix}/include

Name: libxdo
Description: X11 automation library
Version: 1.0
Libs: -L${libdir} -lxdo
Cflags: -I${includedir}
EOF
}

is_sysroot_ready() {
  [[ -f "$SYSROOT_DIR/lib/libc.so.6" ]] \
    && [[ -f "$SYSROOT_DIR/usr/lib/x86_64-linux-gnu/pkgconfig/gtk+-3.0.pc" ]]
}

ensure_cross_rootfs() {
  if [[ -f "$SYSROOT_DIR/lib/libc.so.6" ]]; then
    return 0
  fi

  echo "==> Exporting cross-rs Linux sysroot (no Docker daemon required)..."
  mkdir -p "$TOOLCHAIN_DIR/bin" "$CROSS_ROOTFS"
  if [[ ! -x "$CRANE_BIN" ]]; then
    tmp="$(mktemp -t crane.XXXXXX.tar.gz)"
    curl -fsSL -o "$tmp" "$CRANE_URL"
    tar -xzf "$tmp" -C "$TOOLCHAIN_DIR/bin" crane
    rm -f "$tmp"
    chmod +x "$CRANE_BIN"
  fi

  rm -rf "$CROSS_ROOTFS"
  mkdir -p "$CROSS_ROOTFS"
  # macOS tar cannot create device nodes; skip dev/ entries.
  "$CRANE_BIN" export "$CROSS_IMAGE" | tar --no-same-owner --exclude='dev/*' -xf - -C "$CROSS_ROOTFS"
}

mkdir -p "$TOOLCHAIN_DIR"

if [[ ! -x "$GCC_BIN" ]]; then
  echo "==> Downloading macOS-hosted $TARGET toolchain..."
  tmp="$(mktemp -t nkriz-toolchain.XXXXXX.tar.gz)"
  curl -fsSL -o "$tmp" "$MESSENSE_URL"
  tar -xzf "$tmp" -C "$TOOLCHAIN_DIR"
  rm -f "$tmp"
fi

ensure_cross_rootfs

if ! is_sysroot_ready; then
  echo "==> Installing GTK/AppIndicator packages for Ubuntu ${UBUNTU_SUITE} into cross sysroot..."
  rm -f "$MARKER"
  download_focal_packages
  ensure_libxdo_pc
  if is_sysroot_ready; then
    touch "$MARKER"
  else
    echo "Error: sysroot is missing GTK development files after package install." >&2
    exit 1
  fi
fi

cat > "$ROOT_DIR/.cargo/config.toml" <<EOF
[source.crates-io]
replace-with = "rsproxy-sparse"

[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"

[net]
git-fetch-with-cli = true

[target.$TARGET]
linker = "$GCC_BIN"
rustflags = [
  "-C", "link-arg=--sysroot=$CROSS_ROOTFS",
  "-C", "link-arg=-Wl,-rpath-link,$SYSROOT_DIR/usr/lib/x86_64-linux-gnu",
  "-C", "link-arg=-Wl,-rpath-link,$CROSS_ROOTFS/lib/x86_64-linux-gnu",
]
EOF

echo "Sysroot bootstrap complete:"
echo "  Toolchain: $GCC_BIN"
echo "  Sysroot:   $SYSROOT_DIR"
