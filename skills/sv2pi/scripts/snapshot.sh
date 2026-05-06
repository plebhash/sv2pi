#!/usr/bin/env bash
set -euo pipefail

BLOCKS_DIR="${1:-}"
CHAINSTATE_DIR="${2:-}"
PRUNE="${3:-}"
DATA_DIR="${BITCOIN_DATA_DIR:-$HOME/.sv2pi/bitcoin/data}"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

err() { printf '%bERROR:%b %s\n' "${RED}" "${NC}" "$*" >&2; }
ok()  { printf '%bOK:%b %s\n' "${GREEN}" "${NC}" "$*"; }

if [ -z "$BLOCKS_DIR" ] || [ -z "$CHAINSTATE_DIR" ]; then
    err 'usage: snapshot.sh <blocks_dir> <chainstate_dir> [prune]'
    echo '  blocks_dir     path to an existing blocks/ directory'
    echo '  chainstate_dir path to an existing chainstate/ directory'
    echo '  prune          optional prune target in MiB (e.g. 555)'
    exit 1
fi

if [ ! -d "$BLOCKS_DIR" ]; then
    err "blocks directory not found: $BLOCKS_DIR"
    exit 1
fi

if [ ! -d "$CHAINSTATE_DIR" ]; then
    err "chainstate directory not found: $CHAINSTATE_DIR"
    exit 1
fi

if [ -n "$PRUNE" ]; then
    if ! [[ "$PRUNE" =~ ^[0-9]+$ ]]; then
        err "prune must be a positive integer (MiB), got: $PRUNE"
        exit 1
    fi
    if [ "$PRUNE" -lt 550 ]; then
        err "minimum prune is 550 MiB (Bitcoin Core enforces >= 550)"
        exit 1
    fi
fi

printf '\n%bSnapshot Injection%b\n' "${CYAN}" "${NC}"
printf '  Blocks:     %s\n' "$BLOCKS_DIR"
printf '  Chainstate: %s\n' "$CHAINSTATE_DIR"
printf '  Data dir:   %s\n' "$DATA_DIR"
[ -n "$PRUNE" ] && printf '  Prune:      %s MiB\n' "$PRUNE" || true
echo ''

if docker ps --filter name=bitcoin_core --format '{{.Names}}' | grep -q bitcoin_core; then
    printf 'Stopping bitcoin_core container... '
    docker stop bitcoin_core >/dev/null 2>&1
    ok 'stopped'
fi

printf 'Clearing existing blocks/chainstate from data dir... '
rm -rf "$DATA_DIR/blocks" "$DATA_DIR/chainstate" 2>/dev/null || true
ok 'cleared'

printf 'Copying blocks... '
cp -r "$BLOCKS_DIR" "$DATA_DIR/blocks"
ok 'done'

printf 'Copying chainstate... '
cp -r "$CHAINSTATE_DIR" "$DATA_DIR/chainstate"
ok 'done'

if [ -n "$PRUNE" ]; then
    printf 'Writing prune=%s to bitcoin.conf... ' "$PRUNE"
    if grep -q '^prune=' "$DATA_DIR/bitcoin.conf" 2>/dev/null; then
        sed -i '' "s/^prune=.*/prune=$PRUNE/" "$DATA_DIR/bitcoin.conf" 2>/dev/null || \
            sed -i "s/^prune=.*/prune=$PRUNE/" "$DATA_DIR/bitcoin.conf"
    else
        echo "prune=$PRUNE" >> "$DATA_DIR/bitcoin.conf"
    fi
    ok 'done'
fi

printf 'Starting bitcoin_core... '
docker start bitcoin_core >/dev/null 2>&1
ok 'started'

echo ''
echo 'Snapshot injected. Bitcoin Core will resume from the snapshot state.'
echo '  docker logs bitcoin_core --tail 5'
echo '  docker exec bitcoin_core bitcoin-cli getblockchaininfo'
