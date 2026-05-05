#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-v1.1.0}"
BITCOIN_DATA_DIR="${2:-$HOME/.sv2pi/bitcoin/data}"
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

# Verify Bitcoin data directory exists
if [ ! -d "$BITCOIN_DATA_DIR" ]; then
    err "Bitcoin data directory not found: $BITCOIN_DATA_DIR"
    echo "  Deploy Bitcoin Core first: bash deploy-bitcoin.sh"
    exit 1
fi

# Verify IPC socket exists (retry with sudo for root-owned volumes)
IPC_SOCK="$BITCOIN_DATA_DIR/node.sock"
if [ ! -S "$IPC_SOCK" ] && ! sudo test -S "$IPC_SOCK" 2>/dev/null; then
    err "Bitcoin IPC socket not found at: $IPC_SOCK"
    echo "  Verify Bitcoin Core is running with -ipcbind=unix"
    exit 1
fi

# Determine SV2 port per network
case "$NETWORK" in
    mainnet)  SV2_PORT=8442;  CHAIN="main" ;;
    testnet4) SV2_PORT=48442; CHAIN="testnet4" ;;
    signet)   SV2_PORT=38442; CHAIN="signet" ;;
    regtest)  SV2_PORT=18447; CHAIN="regtest" ;;
    *) err "unknown network: $NETWORK (use mainnet, testnet4, signet, or regtest)"; exit 1 ;;
esac

printf '\n%bSV2 Template Provider (Docker)%b\n' "${CYAN}" "${NC}"
printf '  Image:   stratumv2/sv2-tp:%s\n' "$TAG"
printf '  Network: %s\n' "$NETWORK"
printf '  SV2 Port: %s\n' "$SV2_PORT"
printf '  IPC:     %s\n' "$IPC_SOCK"

docker rm -f sv2_tp 2>/dev/null || true
echo ''

# Ensure the shared datadir is writable by the container.
# Bitcoin Core creates it root-owned; sv2-tp needs write access for its PID file and keys.
sudo chmod 777 "$BITCOIN_DATA_DIR" 2>/dev/null || true

printf 'Pulling image... '
docker pull "stratumv2/sv2-tp:$TAG" >/dev/null 2>&1 && ok 'done' || err 'pull failed'

docker run -d \
    --name sv2_tp \
    --restart unless-stopped \
    -p ${SV2_PORT}:${SV2_PORT} \
    -v "${BITCOIN_DATA_DIR}:/home/bitcoin/.bitcoin" \
    "stratumv2/sv2-tp:${TAG}" \
    -datadir=/home/bitcoin/.bitcoin \
    -ipcconnect=unix \
    -chain="$CHAIN" \
    -sv2bind="0.0.0.0:${SV2_PORT}" \
    -debug=sv2 \
    -printtoconsole \
    -debuglogfile=0 \
    -pid=/tmp/sv2-tp.pid

echo ''
echo '=== SV2 Template Provider deployed ==='
printf '  Image:       stratumv2/sv2-tp:%s\n' "$TAG"
printf '  Network:     %s\n' "$NETWORK"
printf '  SV2 endpoint:  localhost:%s\n' "$SV2_PORT"
printf '  Bitcoin IPC:   mounted %s -> /home/bitcoin/.bitcoin/node.sock\n' "$IPC_SOCK"
echo ''
echo "Verify: docker logs sv2_tp --tail 20"
echo "Logs:   docker logs sv2_tp -f"
echo ""
echo "Pool/JDC template_provider_type.Sv2Tp address: 127.0.0.1:$SV2_PORT"
