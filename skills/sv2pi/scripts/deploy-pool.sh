#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-main}"
BITCOIN_IPC_PATH="${2:-${BITCOIN_IPC_PATH:-}}"
CONFIG_DIR="${3:-$HOME/.sv2pi/pool/config}"
DATA_DIR="${4:-$HOME/.sv2pi/pool/data}"

if [ -z "$BITCOIN_IPC_PATH" ]; then
    echo "ERROR: Bitcoin IPC path required."
    echo "Usage: $0 <tag> <bitcoin-ipc-path> [config-dir] [data-dir]"
    echo "  Run check-bitcoin.sh first to detect the IPC socket."
    exit 1
fi

if [ ! -S "$BITCOIN_IPC_PATH" ]; then
    echo "ERROR: Bitcoin IPC socket not found at: $BITCOIN_IPC_PATH"
    echo "  Verify Bitcoin Core is running with -ipcbind=unix"
    exit 1
fi

BITCOIN_DIR=$(dirname "$BITCOIN_IPC_PATH")
SOCK_NAME=$(basename "$BITCOIN_IPC_PATH")

mkdir -p "$CONFIG_DIR" "$DATA_DIR"

cat > "$CONFIG_DIR/pool-config.toml" <<TOML
authority_public_key = "9auqWEzQDVyd2oe1JVGFLMLHZtCo2FFqZwtKA5gd9xbuEu7PH72"
authority_secret_key = "mkDLTBBRxdBv998612qipDYoTK3YUrqLe8uWw7gu3iXbSrn2n"
cert_validity_sec = 3600
listen_address = "0.0.0.0:3333"
coinbase_reward_script = "P2WPKH"
server_id = 1
pool_signature = "SRI Mainnet Pool"
shares_per_minute = 6.0
share_batch_size = 10
monitoring_address = "0.0.0.0:9090"
monitoring_cache_refresh_secs = 15

[template_provider_type.BitcoinCoreIpc]
network = "mainnet"
data_dir = "/bitcoin"
fee_threshold = 100
min_interval = 5

[jds]
listen_address = "0.0.0.0:3334"
TOML

docker rm -f pool_sv2 2>/dev/null || true

docker run -d \
    --name pool_sv2 \
    --restart unless-stopped \
    -p 3333:3333 \
    -p 3334:3334 \
    -p 9090:9090 \
    -v "$CONFIG_DIR:/app/config:ro" \
    -v "$BITCOIN_DIR:/bitcoin:ro" \
    -v "$DATA_DIR:/app/data" \
    "stratumv2/pool_sv2:$TAG"

echo ""
echo "=== Pool deployed ==="
echo "  Image:            stratumv2/pool_sv2:$TAG"
echo "  Stratum endpoint: localhost:3333"
echo "  JDS endpoint:     localhost:3334"
echo "  Monitoring:       http://localhost:9090"
echo "  Bitcoin IPC:      mounted $BITCOIN_IPC_PATH -> /bitcoin/$SOCK_NAME"
echo ""
echo "Verify: curl -s http://localhost:9090/api/v1/health"
echo "Logs:   docker logs pool_sv2 --tail 50"
