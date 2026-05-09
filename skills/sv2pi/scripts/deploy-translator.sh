#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-main}"
if [[ "$TAG" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    TAG="v$TAG"
fi
UPSTREAM_HOST="${2:-localhost}"
UPSTREAM_PORT="${3:-34265}"
CONFIG_DIR="${4:-$HOME/.sv2pi/translator/config}"

mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_DIR/translator-config.toml" <<TOML
downstream_address = "0.0.0.0"
downstream_port = 34255
max_supported_version = 2
min_supported_version = 2
downstream_extranonce2_size = 4
user_identity = "mainnet_miner"
aggregate_channels = true
monitoring_address = "0.0.0.0:9092"
monitoring_cache_refresh_secs = 15

[downstream_difficulty_config]
min_individual_miner_hashrate = 100_000_000_000_000.0
shares_per_minute = 6.0
enable_vardiff = true
job_keepalive_interval_secs = 60

[[upstreams]]
address = "$UPSTREAM_HOST"
port = $UPSTREAM_PORT
authority_pubkey = "9auqWEzQDVyd2oe1JVGFLMLHZtCo2FFqZwtKA5gd9xbuEu7PH72"
TOML

docker rm -f translator_sv2 2>/dev/null || true

docker run -d \
    --name translator_sv2 \
    --restart unless-stopped \
    -p 34255:34255 \
    -p 9092:9092 \
    -v "$CONFIG_DIR:/app/config:ro" \
    "stratumv2/translator_sv2:$TAG"

echo ""
echo "=== Translator Proxy deployed ==="
echo "  Image:            stratumv2/translator_sv2:$TAG"
echo "  SV1 Downstream:   localhost:34255"
echo "  SV2 Upstream:     $UPSTREAM_HOST:$UPSTREAM_PORT"
echo "  Monitoring:       http://localhost:9092"
echo ""
echo "Verify: curl -s http://localhost:9092/api/v1/health"
echo "Logs:   docker logs translator_sv2 --tail 50"
