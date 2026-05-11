#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-latest}"
DATA_DIR="${2:-$HOME/.sv2pi/bitcoin/data}"
NETWORK="${3:-mainnet}"
RPC_BIND_MODE="${4:-localhost}"
RPC_BIND_IP="${5:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

err() { printf '%bERROR:%b %s\n' "${RED}" "${NC}" "$*" >&2; }
ok()  { printf '%bOK:%b %s\n' "${GREEN}" "${NC}" "$*"; }

resolve_bind_ip() {
    case "$1" in
        localhost)
            printf '127.0.0.1'
            ;;
        wireguard)
            if [ -n "$2" ]; then
                printf '%s' "$2"
                return
            fi
            if [ -n "${SV2PI_WIREGUARD_IP:-}" ]; then
                printf '%s' "$SV2PI_WIREGUARD_IP"
                return
            fi
            err 'wireguard bind mode requires an explicit WireGuard IP.'
            echo '  Pass it as the 5th argument or set SV2PI_WIREGUARD_IP.'
            exit 1
            ;;
        *)
            err "invalid RPC bind mode: $1 (use localhost or wireguard)"
            exit 1
            ;;
    esac
}

# Check Docker access — agent must not invoke sudo/newgrp/sg.
# Docker group membership is the operator's responsibility.
if ! docker ps >/dev/null 2>&1; then
    err 'Docker is not accessible. Ensure your user is in the docker group and the daemon is running.'
    exit 1
fi

mkdir -p "$DATA_DIR"

case "$NETWORK" in
    mainnet) RPC_PORT=8332; P2P_PORT=8333; NET_FLAG="" ;;
    testnet4) RPC_PORT=48332; P2P_PORT=48333; NET_FLAG="-testnet4" ;;
    signet) RPC_PORT=38332; P2P_PORT=38333; NET_FLAG="-signet" ;;
    *) err "unknown network: $NETWORK (use mainnet, testnet4, or signet)"; exit 1 ;;
esac

RPC_HOST_BIND="$(resolve_bind_ip "$RPC_BIND_MODE" "$RPC_BIND_IP")"

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
    -p "${RPC_HOST_BIND}:${RPC_PORT}:${RPC_PORT}" \
    -p "0.0.0.0:${P2P_PORT}:${P2P_PORT}" \
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
printf '  RPC endpoint: %s:%s\n' "$RPC_HOST_BIND" "$RPC_PORT"
printf '  P2P port:   %s\n' "$P2P_PORT"
printf '  RPC bind:   %s (%s)\n' "$RPC_HOST_BIND" "$RPC_BIND_MODE"
echo ''
printf 'BITCOIN_IPC_PATH=%s/node.sock\n' "$DATA_DIR"
