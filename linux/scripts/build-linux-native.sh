#!/bin/bash
set -euo pipefail

# Wrapper kept for compatibility. Prefer: ./native build
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT_DIR/native" build
