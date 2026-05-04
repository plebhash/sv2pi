#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-latest}"
DATA_DIR="${2:-$HOME/.sv2pi/bitcoin/data}"
NETWORK="${3:-mainnet}"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

err() { printf '%bERROR:%b %s\n' "${RED}" "${NC}" "$*" >&2; }
ok()  { printf '%bOK:%b %s\n' "${GREEN}" "${NC}" "$*"; }

# Check Docker access
if ! docker ps >/dev/null 2>&1; then
    if groups 2>/dev/null | grep -q docker || id -Gn 2>/dev/null | grep -q docker; then
        err 'Docker is not accessible despite docker group membership. Try: newgrp docker'
    else
        err 'Docker is not accessible.'
        echo ''
        echo '  Fix: sudo usermod -aG docker $USER && newgrp docker'
        echo ''
    fi
    exit 1
fi

mkdir -p "$DATA_DIR"

case "$NETWORK" in
    mainnet) RPC_PORT=8332; P2P_PORT=8333; NET_FLAG="" ;;
    testnet4) RPC_PORT=48332; P2P_PORT=48333; NET_FLAG="-testnet4" ;;
    signet) RPC_PORT=38332; P2P_PORT=38333; NET_FLAG="-signet" ;;
    *) err "unknown network: $NETWORK (use mainnet, testnet4, or signet)"; exit 1 ;;
esac

printf '\n%bBitcoin Core (Docker)%b\n' "${CYAN}" "${NC}"
printf '  Image:   bitcoin/bitcoin:%s\n' "$TAG"
printf '  Network: %s\n' "$NETWORK"
printf '  Data:    %s\n' "$DATA_DIR"

docker rm -f bitcoin_core 2>/dev/null || true
echo ''

printf 'Pulling image... '
docker pull "bitcoin/bitcoin:$TAG" >/dev/null 2>&1 && ok 'done' || err 'pull failed'

docker run -d \
    --name bitcoin_core \
    --restart unless-stopped \
    -p ${RPC_PORT}:${RPC_PORT} \
    -p ${P2P_PORT}:${P2P_PORT} \
    -v "${DATA_DIR}:/home/bitcoin/.bitcoin" \
    --entrypoint bitcoin \
    "bitcoin/bitcoin:${TAG}" \
    -m node \
    -datadir=/home/bitcoin/.bitcoin \
    -printtoconsole \
    -ipcbind=unix:/home/bitcoin/.bitcoin/node.sock \
    ${NET_FLAG}

echo ''
echo '=== Bitcoin Core deployed ==='
printf '  Image:      bitcoin/bitcoin:%s\n' "$TAG"
printf '  Network:    %s\n' "$NETWORK"
printf '  IPC socket: %s/node.sock\n' "$DATA_DIR"
printf '  RPC port:   %s\n' "$RPC_PORT"
printf '  P2P port:   %s\n' "$P2P_PORT"
echo ''
printf 'BITCOIN_IPC_PATH=%s/node.sock\n' "$DATA_DIR"
