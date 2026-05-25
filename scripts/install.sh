#!/usr/bin/env sh
set -eu

REPO="${CONTROLKEEL_GITHUB_REPO:-aryaminus/controlkeel}"
VERSION="${CONTROLKEEL_VERSION:-latest}"
INSTALL_DIR="${CONTROLKEEL_INSTALL_DIR:-}"

detect_os() {
  case "$(uname -s)" in
    Darwin) printf "macos" ;;
    Linux) printf "linux" ;;
    *)
      echo "unsupported operating system: $(uname -s)" >&2
      exit 1
      ;;
  esac
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf "x86_64" ;;
    arm64|aarch64) printf "arm64" ;;
    *)
      echo "unsupported architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
}

binary_asset_name() {
  os="$1"
  arch="$2"

  case "${os}:${arch}" in
    linux:x86_64) printf "controlkeel-linux-x86_64" ;;
    linux:arm64) printf "controlkeel-linux-arm64" ;;
    macos:x86_64) printf "controlkeel-macos-x86_64" ;;
    macos:arm64) printf "controlkeel-macos-arm64" ;;
    *)
      echo "unsupported platform: ${os}/${arch}" >&2
      exit 1
      ;;
  esac
}

release_base_url() {
  if [ "$VERSION" = "latest" ]; then
    printf "https://github.com/%s/releases/latest/download" "$REPO"
  else
    printf "https://github.com/%s/releases/download/v%s" "$REPO" "$VERSION"
  fi
}

default_install_dir() {
  if [ -n "$INSTALL_DIR" ]; then
    printf "%s" "$INSTALL_DIR"
  elif [ -w "/usr/local/bin" ]; then
    printf "/usr/local/bin"
  else
    printf "%s/.local/bin" "${HOME:-$PWD}"
  fi
}

OS="$(detect_os)"
ARCH="$(detect_arch)"
ASSET="$(binary_asset_name "$OS" "$ARCH")"
BASE_URL="$(release_base_url)"
DEST_DIR="$(default_install_dir)"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT INT TERM

mkdir -p "$DEST_DIR"

curl -fsSL "${BASE_URL}/${ASSET}" -o "${TMP_DIR}/controlkeel"
chmod +x "${TMP_DIR}/controlkeel"
mv "${TMP_DIR}/controlkeel" "${DEST_DIR}/controlkeel"

echo "Installed ControlKeel to ${DEST_DIR}/controlkeel"
echo ""

case ":$PATH:" in
  *":${DEST_DIR}:"*) ;;
  *)
    echo "Add ${DEST_DIR} to your PATH first:" >&2
    echo "  export PATH=\"${DEST_DIR}:\$PATH\"" >&2
    echo "" >&2
    ;;
esac

cat <<'EOF'
Next steps — wire ControlKeel into your agent host:

  1. Attach to the agent you use (one or more):
       controlkeel attach claude-code
       controlkeel attach cursor
       controlkeel attach codex-cli
       controlkeel attach opencode
       controlkeel attach copilot

  2. Optional — sync governance evidence to a control plane:
       controlkeel cloud connect --enroll https://controlkeel.com
     (or your self-host URL, e.g. https://govern.acme.com)

  3. Verify everything is healthy:
       controlkeel cloud doctor

Run `controlkeel --help` for the full surface. See docs/self-hosting.md
to run your own controlkeel.com on fly.io.
EOF
