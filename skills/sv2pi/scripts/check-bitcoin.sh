#!/usr/bin/env bash
set -euo pipefail

check_socket() {
    local path="$1"
    if [ -S "$path" ]; then
        echo "Found Bitcoin Core IPC at: $path"
        echo "BITCOIN_IPC_PATH=$path"
        export BITCOIN_IPC_PATH="$path"
        return 0
    fi
    return 1
}

# Docker-deployed Bitcoin Core (sv2pi managed)
check_socket "$HOME/.sv2pi/bitcoin/data/node.sock" && exit 0

# Custom data dir from env
if [ -n "${BITCOIN_DATA_DIR:-}" ]; then
    if check_socket "$BITCOIN_DATA_DIR/node.sock"; then
        exit 0
    fi
    if check_socket "$BITCOIN_DATA_DIR/mainnet/node.sock"; then
        exit 0
    fi
fi

# macOS
if [ "$(uname)" = "Darwin" ]; then
    check_socket "$HOME/Library/Application Support/Bitcoin/node.sock" && exit 0
    check_socket "$HOME/Library/Application Support/Bitcoin/mainnet/node.sock" && exit 0
fi

# Linux mainnet defaults
check_socket "$HOME/.bitcoin/node.sock" && exit 0
check_socket "$HOME/.bitcoin/mainnet/node.sock" && exit 0

echo "ERROR: Bitcoin Core IPC socket (node.sock) not found."
echo ""
echo "Locations checked:"
echo "  ~/.sv2pi/bitcoin/data/node.sock    (Docker-deployed via sv2pi)"
echo "  ~/.bitcoin/node.sock                (native Linux mainnet)"
echo "  ~/.bitcoin/mainnet/node.sock        (native Linux mainnet)"
echo ""
echo "If Bitcoin Core is not installed, the agent can deploy it via Docker:"
echo "  bash \$(dirname \$0)/deploy-bitcoin.sh <tag>"
echo ""
echo "To specify a custom datadir:"
echo "  BITCOIN_DATA_DIR=/path/to/.bitcoin bash \$0"
exit 1