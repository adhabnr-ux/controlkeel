#!/usr/bin/env sh
set -eu

VERSION="${1:-0.15.2}"
INSTALL_ROOT="${INSTALL_ROOT:-/usr/local/zig}"
CONNECT_TIMEOUT="${ZIG_CONNECT_TIMEOUT:-30}"
MAX_TIME="${ZIG_MAX_TIME:-120}"
RETRIES="${ZIG_RETRIES:-3}"

os="$(uname -s)"
arch="$(uname -m)"

case "$os" in
  Linux)
    case "$arch" in
      x86_64|amd64) zig_target="x86_64-linux" ;;
      aarch64|arm64) zig_target="aarch64-linux" ;;
      *) echo "unsupported Linux architecture: $arch" >&2; exit 1 ;;
    esac
    ;;
  Darwin)
    case "$arch" in
      x86_64|amd64) zig_target="x86_64-macos" ;;
      arm64|aarch64) zig_target="aarch64-macos" ;;
      *) echo "unsupported macOS architecture: $arch" >&2; exit 1 ;;
    esac
    ;;
  *)
    echo "unsupported host OS: $os" >&2
    exit 1
    ;;
esac

# Allow pre-installed Zig — skip download if already present
if [ -x "${INSTALL_ROOT}/zig" ]; then
  installed_version="$("${INSTALL_ROOT}/zig" version 2>/dev/null || true)"
  if [ "$installed_version" = "$VERSION" ]; then
    echo "Zig ${VERSION} already installed at ${INSTALL_ROOT}, skipping download."
    echo "$INSTALL_ROOT"
    exit 0
  fi
fi

archive="zig-${zig_target}-${VERSION}.tar.xz"
url="https://ziglang.org/download/${VERSION}/${archive}"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

downloaded=false
for attempt in $(seq 1 "$RETRIES"); do
  echo "Downloading Zig ${VERSION} (attempt ${attempt}/${RETRIES})..." >&2
  if curl -fLsS --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" --retry 0 "$url" -o "$tmp_dir/zig.tar.xz"; then
    downloaded=true
    break
  fi
  echo "Download attempt ${attempt} failed, retrying in 5s..." >&2
  sleep 5
done

if [ "$downloaded" = "false" ]; then
  echo "Failed to download Zig after ${RETRIES} attempts" >&2
  exit 1
fi

tar -xJf "$tmp_dir/zig.tar.xz" -C "$tmp_dir"

extracted_dir="$tmp_dir/zig-${zig_target}-${VERSION}"

if [ ! -d "$extracted_dir" ]; then
  echo "expected extracted Zig directory not found: $extracted_dir" >&2
  exit 1
fi

sudo rm -rf "$INSTALL_ROOT"
sudo mv "$extracted_dir" "$INSTALL_ROOT"
echo "$INSTALL_ROOT"
