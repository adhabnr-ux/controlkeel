#!/usr/bin/env sh
set -eu

# build_local.sh — Build a Burrito-wrapped controlkeel binary from source
# and install it to ~/.local/bin (or BINARY_DEST).
#
# Usage:
#   scripts/build_local.sh              # build for current platform, install
#   scripts/build_local.sh --no-install  # build only, skip install
#
# Requirements:
#   - Elixir/OTP (via asdf, brew, etc.)
#   - xz (brew install xz)
#   - zig 0.15.2 (auto-downloaded to a temp dir if missing or wrong version)
#
# This script ensures the installed binary always matches the source version
# in mix.exs, preventing the stale-binary drift that occurs when the version
# is bumped before CI cuts a release.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REQUIRED_ZIG="0.15.2"
NO_INSTALL=false

for arg in "$@"; do
  case "$arg" in
    --no-install) NO_INSTALL=true ;;
    *) echo "unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# --- Detect current platform ---
os="$(uname -s)"
arch="$(uname -m)"

case "$os" in
  Darwin)
    case "$arch" in
      arm64|aarch64) BURRITO_TARGET="macos_silicon"; BINARY_NAME="controlkeel_macos_silicon" ;;
      x86_64|amd64)  BURRITO_TARGET="macos";          BINARY_NAME="controlkeel_macos" ;;
      *) echo "unsupported macOS architecture: $arch" >&2; exit 1 ;;
    esac
    ;;
  Linux)
    case "$arch" in
      x86_64|amd64)  BURRITO_TARGET="linux";     BINARY_NAME="controlkeel_linux" ;;
      aarch64|arm64) BURRITO_TARGET="linux_arm64"; BINARY_NAME="controlkeel_linux_arm64" ;;
      *) echo "unsupported Linux architecture: $arch" >&2; exit 1 ;;
    esac
    ;;
  *) echo "unsupported OS: $os" >&2; exit 1 ;;
esac

echo "==> Platform: ${os}/${arch} -> Burrito target: ${BURRITO_TARGET}"

# --- Check / download correct zig ---
ZIG_BIN=""
if command -v zig >/dev/null 2>&1; then
  INSTALLED_VSN="$(zig version 2>/dev/null || true)"
  if [ "$INSTALLED_VSN" = "$REQUIRED_ZIG" ]; then
    ZIG_BIN="$(command -v zig)"
  fi
fi

if [ -z "$ZIG_BIN" ]; then
  echo "==> zig ${REQUIRED_ZIG} not found on PATH; downloading to temp dir..."
  ZIG_TMP="$(mktemp -d)"
  trap 'rm -rf "$ZIG_TMP"' EXIT INT TERM

  case "$os" in
    Darwin)
      case "$arch" in
        arm64|aarch64) ZIG_TARGET="aarch64-macos" ;;
        x86_64|amd64)  ZIG_TARGET="x86_64-macos" ;;
      esac
      ;;
    Linux)
      case "$arch" in
        x86_64|amd64)  ZIG_TARGET="x86_64-linux" ;;
        aarch64|arm64) ZIG_TARGET="aarch64-linux" ;;
      esac
      ;;
  esac

  ZIG_ARCHIVE="zig-${ZIG_TARGET}-${REQUIRED_ZIG}.tar.xz"
  ZIG_URL="https://ziglang.org/download/${REQUIRED_ZIG}/${ZIG_ARCHIVE}"

  curl -fLsS "$ZIG_URL" -o "$ZIG_TMP/zig.tar.xz"
  tar -xJf "$ZIG_TMP/zig.tar.xz" -C "$ZIG_TMP"
  ZIG_BIN="$ZIG_TMP/zig-${ZIG_TARGET}-${REQUIRED_ZIG}/zig"
  echo "    downloaded zig ${REQUIRED_ZIG} -> ${ZIG_BIN}"
fi

# --- Read version from mix.exs ---
VSN="$(grep -oE 'version: "[^"]*"' "$ROOT/mix.exs" | head -1 | grep -oE '"[^"]*"' | tr -d '"')"
if [ -z "$VSN" ]; then
  echo "ERROR: could not read version from mix.exs" >&2
  exit 1
fi
echo "==> Building ControlKeel ${VSN} (${BURRITO_TARGET})..."

# --- Build ---
(
  cd "$ROOT"
  PATH="$(dirname "$ZIG_BIN"):${PATH}"
  export PATH
  export CK_RELEASE_BURRITO=1
  export BURRITO_TARGET="$BURRITO_TARGET"

  mix deps.get
  mix release --overwrite
)

BUILT_BINARY="$ROOT/burrito_out/${BINARY_NAME}"
if [ ! -f "$BUILT_BINARY" ]; then
  echo "ERROR: expected binary not found at ${BUILT_BINARY}" >&2
  exit 1
fi

BUILT_VSN="$("$BUILT_BINARY" version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
echo "==> Built binary version: ${BUILT_VSN:-unknown}"

if [ "$BUILT_VSN" != "$VSN" ]; then
  echo "WARNING: built version (${BUILT_VSN:-unknown}) != mix.exs version (${VSN})" >&2
fi

# --- Install ---
if [ "$NO_INSTALL" = true ]; then
  echo "==> Skipping install (--no-install). Binary at: ${BUILT_BINARY}"
  exit 0
fi

DEST="${BINARY_DEST:-${HOME}/.local/bin/controlkeel}"
cp "$BUILT_BINARY" "$DEST"
chmod +x "$DEST"
echo "==> Installed to ${DEST}"

# Verify
INSTALLED_VSN="$("$DEST" version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
echo "==> Installed version: ${INSTALLED_VSN:-unknown}"
echo "==> Done!"
