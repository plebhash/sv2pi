#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-main}"
BITCOIN_IPC_PATH="${2:-${BITCOIN_IPC_PATH:-}}"
POOL_HOST="${3:-75.119.150.111}"
POOL_PORT="${4:-3333}"
JDS_PORT="${5:-3334}"
CONFIG_DIR="${6:-$HOME/.sv2pi/jdc/config}"

if [ -z "$BITCOIN_IPC_PATH" ]; then
    echo "ERROR: Bitcoin IPC path required."
    echo "Usage: $0 <tag> <bitcoin-ipc-path> [pool-host] [pool-port] [jds-port] [config-dir]"
    echo "  Run check-bitcoin.sh first to detect the IPC socket."
    exit 1
fi

# Socket check. Agent does not invoke sudo; operator must ensure socket is readable.
if [ ! -S "$BITCOIN_IPC_PATH" ]; then
    echo "ERROR: Bitcoin IPC socket not found at: $BITCOIN_IPC_PATH"
    echo "  Verify Bitcoin Core is running with -ipcbind=unix"
    exit 1
fi

mkdir -p "$CONFIG_DIR"

# REPLACE WITH YOUR MAINNET ADDRESS BELOW
cat > "$CONFIG_DIR/jdc-config.toml" <<TOML
listening_address = "0.0.0.0:34265"
max_supported_version = 2
min_supported_version = 2
authority_public_key = "9auqWEzQDVyd2oe1JVGFLMLHZtCo2FFqZwtKA5gd9xbuEu7PH72"
authority_secret_key = "mkDLTBBRxdBv998612qipDYoTK3YUrqLe8uWw7gu3iXbSrn2n"
cert_validity_sec = 3600
user_identity = "mainnet_miner"
shares_per_minute = 6.0
share_batch_size = 10
mode = "FULLTEMPLATE"
jdc_signature = "SRI JD Client"
coinbase_reward_script = "addr(1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa)"
monitoring_address = "0.0.0.0:9091"
monitoring_cache_refresh_secs = 15

[[upstreams]]
authority_pubkey = "9auqWEzQDVyd2oe1JVGFLMLHZtCo2FFqZwtKA5gd9xbuEu7PH72"
pool_address = "$POOL_HOST"
pool_port = $POOL_PORT
jds_address = "$POOL_HOST"
jds_port = $JDS_PORT

[template_provider_type.BitcoinCoreIpc]
network = "mainnet"
fee_threshold = 100
min_interval = 5
TOML

docker rm -f jd_client_sv2 2>/dev/null || true

docker run -d \
    --name jd_client_sv2 \
    --restart unless-stopped \
    -p 34265:34265 \
    -p 9091:9091 \
    -v "$CONFIG_DIR/jdc-config.toml:/app/jdc-config.toml:ro" \
    -v "$BITCOIN_IPC_PATH:/root/.bitcoin/node.sock:ro" \
    "stratumv2/jd_client_sv2:$TAG"

echo ""
echo "=== JD Client deployed ==="
echo "  Image:            stratumv2/jd_client_sv2:$TAG"
echo "  Downstream:       localhost:34265"
echo "  Upstream pool:    $POOL_HOST:$POOL_PORT"
echo "  Upstream JDS:     $POOL_HOST:$JDS_PORT"
echo "  Monitoring:       http://localhost:9091"
echo "  Bitcoin IPC:      mounted $BITCOIN_IPC_PATH -> /root/.bitcoin/node.sock"
echo ""
echo "Verify: curl -s http://localhost:9091/api/v1/health"
echo "Logs:   docker logs jd_client_sv2 --tail 50"
