#!/bin/bash
# Shared helpers for native Linux Mint build/run scripts.

set -euo pipefail

LINUX_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="nkriz-dns-connector"
LAUNCH_NAME="${APP_NAME}-launch"
VERSION="1.0.0"
DIST_DIR="$LINUX_ROOT/../dist/linux"
BIN_PATH="$LINUX_ROOT/target/release/$APP_NAME"

APT_BUILD_PACKAGES=(
  build-essential
  curl
  pkg-config
  libgtk-3-dev
  libayatana-appindicator3-dev
  libxdo-dev
)

APT_RUNTIME_PACKAGES=(
  network-manager
  policykit-1
  libayatana-appindicator3-1
)

log() {
  printf '\n==> %s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_linux_x64() {
  [[ "$(uname -s)" == "Linux" ]] || die "Run this on Linux."
  [[ "$(uname -m)" == "x86_64" ]] || die "Run this on x86_64 (64-bit)."
}

run_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    log "Using sudo (enter your user password if prompted)..."
    if sudo "$@"; then
      return
    fi
    warn "sudo failed; falling back to su (enter root password)..."
  fi

  if [[ ! -t 0 ]]; then
    die "Root access required. Open a terminal on mint-dev and run this again."
  fi

  log "Using su (enter root password)..."
  local cmd
  cmd="$(printf '%q ' "$@")"
  su -c "$cmd"
}

pkg_installed() {
  dpkg -s "$1" >/dev/null 2>&1
}

ensure_apt_packages() {
  local label="$1"
  shift
  local packages=("$@")
  local missing=()

  for pkg in "${packages[@]}"; do
    pkg_installed "$pkg" || missing+=("$pkg")
  done

  if ((${#missing[@]} == 0)); then
    return
  fi

  log "Installing ${label} packages: ${missing[*]}"
  run_root apt-get update
  run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

ensure_native_cargo_config() {
  local config="$LINUX_ROOT/.cargo/config.toml"
  mkdir -p "$LINUX_ROOT/.cargo"

  if [[ -f "$config" ]] && grep -q '/Users/' "$config" 2>/dev/null; then
    warn "Removing Mac cross-compile settings from .cargo/config.toml"
  fi

  cat > "$config" <<'EOF'
[source.crates-io]
replace-with = "rsproxy-sparse"

[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"

[net]
git-fetch-with-cli = true
EOF
}

cargo_ready() {
  command -v cargo >/dev/null 2>&1 && cargo --version >/dev/null 2>&1
}

ensure_rust() {
  if cargo_ready; then
    log "Rust already installed: $(rustc --version 2>/dev/null || cargo --version)"
    return
  fi

  log "Installing Rust..."
  if command -v apt-get >/dev/null 2>&1; then
    ensure_apt_packages "Rust (apt)" curl
    if run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y rustc cargo; then
      if cargo_ready; then
        log "Rust installed via apt: $(cargo --version)"
        return
      fi
    fi
  fi

  if [[ ! -x "$HOME/.cargo/bin/rustup" ]]; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable \
      || die "Rust install failed. Check network access to sh.rustup.rs / static.rust-lang.org."
  fi

  # shellcheck disable=SC1091
  source "$HOME/.cargo/env"

  if ! cargo_ready; then
    export RUSTUP_DIST_SERVER="${RUSTUP_DIST_SERVER:-https://mirrors.tuna.tsinghua.edu.cn/rustup}"
    export RUSTUP_UPDATE_ROOT="${RUSTUP_UPDATE_ROOT:-https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup}"
    "$HOME/.cargo/bin/rustup" toolchain install stable
    # shellcheck disable=SC1091
    source "$HOME/.cargo/env"
  fi

  cargo_ready || die "Rust is still unavailable after install."
  log "Rust ready: $(cargo --version)"
}

load_rust_env() {
  if [[ -f "$HOME/.cargo/env" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/.cargo/env"
  fi
}

detect_graphical_env() {
  local uid session_id session_type display

  uid="$(id -u)"

  if command -v loginctl >/dev/null 2>&1; then
    while read -r session_id _ _ _; do
      [[ -n "$session_id" ]] || continue
      session_type="$(loginctl show-session "$session_id" -p Type --value 2>/dev/null || true)"
      display="$(loginctl show-session "$session_id" -p Display --value 2>/dev/null || true)"
      if [[ "$session_type" == "x11" || "$session_type" == "wayland" ]]; then
        [[ -n "$display" && -z "${DISPLAY:-}" ]] && export DISPLAY="$display"
        break
      fi
    done < <(loginctl list-sessions --no-legend 2>/dev/null | awk -v uid="$uid" '$3 == uid {print $1}')
  fi

  if [[ -z "${DISPLAY:-}" && -S /tmp/.X11-unix/X0 ]]; then
    export DISPLAY=:0
  fi

  if [[ -z "${XAUTHORITY:-}" && -f "$HOME/.Xauthority" ]]; then
    export XAUTHORITY="$HOME/.Xauthority"
  fi

  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
}

resolve_binary() {
  if [[ -x "$BIN_PATH" ]]; then
    printf '%s\n' "$BIN_PATH"
    return
  fi
  if [[ -x "/usr/local/bin/$APP_NAME" ]]; then
    printf '/usr/local/bin/%s\n' "$APP_NAME"
    return
  fi
  die "Binary not found. Run: ./native build"
}

# Linux truncates /proc/comm to 15 chars, so pgrep -x on the full binary name fails.
app_is_running() {
  pgrep -f '[n]kriz-dns-connector' >/dev/null 2>&1
}

app_pids() {
  pgrep -f '[n]kriz-dns-connector' 2>/dev/null || true
}

app_stop() {
  if app_is_running; then
    pkill -f '[n]kriz-dns-connector' || true
  fi
}

RUN_LOG="/tmp/nkriz-dns-connector.log"
