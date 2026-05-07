#!/usr/bin/env bash
set -euo pipefail

MINERD_VERSION="2.5.1"
MINERD_DIR="$HOME/.sv2pi/minerd/v${MINERD_VERSION}"
MINERD_BINARY="$MINERD_DIR/minerd"
RELEASE_URL="https://github.com/stratum-mining/cpuminer/releases/download/v${MINERD_VERSION}"

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Linux)  PLATFORM="linux" ;;
    Darwin) PLATFORM="apple-darwin" ;;
    *)
        echo "ERROR: Unsupported OS: $OS"
        echo "  minerd v${MINERD_VERSION} supports Linux and macOS."
        exit 1
        ;;
esac

case "$ARCH" in
    x86_64|amd64)   ARCH="x86_64" ;;
    arm64|aarch64)  ARCH="arm64" ;;
    *)
        echo "ERROR: Unsupported architecture: $ARCH"
        echo "  minerd v${MINERD_VERSION} supports x86_64 and arm64."
        exit 1
        ;;
esac

if [ "$PLATFORM" = "apple-darwin" ]; then
    TARBALL="pooler-cpuminer-${MINERD_VERSION}-${ARCH}-${PLATFORM}.tar.gz"
else
    TARBALL="pooler-cpuminer-${MINERD_VERSION}-${PLATFORM}-${ARCH}.tar.gz"
fi

if [ -x "$MINERD_BINARY" ]; then
    if "$MINERD_BINARY" --version >/dev/null 2>&1; then
        echo "export MINERD_BINARY=\"$MINERD_BINARY\""
        echo "export MINERD_VERSION=\"$MINERD_VERSION\""
        echo "# minerd v${MINERD_VERSION} already installed at $MINERD_BINARY" >&2
        exit 0
    fi
    echo "  Existing binary at $MINERD_BINARY is not executable or corrupt — re-fetching..." >&2
fi

DOWNLOAD_URL="${RELEASE_URL}/${TARBALL}"
TMP_TARBALL="/tmp/${TARBALL}"

echo "=== Fetching minerd v${MINERD_VERSION} ===" >&2
echo "  Platform: ${OS}-${ARCH}" >&2
echo "  URL:      ${DOWNLOAD_URL}" >&2
echo "  Target:   ${MINERD_DIR}" >&2
echo "" >&2

if command -v curl >/dev/null 2>&1; then
    curl -fSL --progress-bar -o "$TMP_TARBALL" "$DOWNLOAD_URL"
elif command -v wget >/dev/null 2>&1; then
    wget -q --show-progress -O "$TMP_TARBALL" "$DOWNLOAD_URL"
else
    echo "ERROR: Neither curl nor wget found. Install one of them."
    exit 1
fi

echo "" >&2
echo "=== Extracting ===" >&2
mkdir -p "$MINERD_DIR"
tar -xzf "$TMP_TARBALL" -C "$MINERD_DIR" --strip-components=1
rm -f "$TMP_TARBALL"

if ! [ -x "$MINERD_BINARY" ]; then
    if [ -f "$MINERD_BINARY" ]; then
        chmod +x "$MINERD_BINARY"
    else
        echo "ERROR: Extracted tarball but minerd binary not found at $MINERD_BINARY" >&2
        echo "  Archive contents:" >&2
        ls -la "$MINERD_DIR/" >&2
        exit 1
    fi
fi

echo "  Binary:  $MINERD_BINARY" >&2
echo "  Version: $("$MINERD_BINARY" --version 2>&1 | head -1)" >&2
echo "" >&2

echo "export MINERD_BINARY=\"$MINERD_BINARY\""
echo "export MINERD_VERSION=\"$MINERD_VERSION\""
