#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-main}"
UPSTREAM_HOST="${2:-localhost}"
UPSTREAM_PORT="${3:-34265}"
CONFIG_DIR="${4:-$HOME/.sv2pi/translator/config}"
MONITORING_BIND_MODE="${5:-localhost}"
MONITORING_BIND_IP="${6:-}"

err() { printf 'ERROR: %s\n' "$*" >&2; }

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
            echo '  Pass it as the 6th argument or set SV2PI_WIREGUARD_IP.'
            exit 1
            ;;
        *)
            err "invalid monitoring bind mode: $1 (use localhost or wireguard)"
            exit 1
            ;;
    esac
}

MONITORING_HOST_BIND="$(resolve_bind_ip "$MONITORING_BIND_MODE" "$MONITORING_BIND_IP")"
MONITORING_HEALTH_HOST="$MONITORING_HOST_BIND"
if [ "$MONITORING_BIND_MODE" = "localhost" ]; then
    MONITORING_HEALTH_HOST="localhost"
fi

mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_DIR/tproxy-config.toml" <<TOML
downstream_address = "0.0.0.0"
downstream_port = 34255
downstream_extranonce2_size = 4
user_identity = "mainnet_miner"
aggregate_channels = true
monitoring_address = "0.0.0.0:9092"
monitoring_cache_refresh_secs = 15
job_keepalive_interval_secs = 60

[downstream_difficulty_config]
min_individual_miner_hashrate = 100_000_000_000_000.0
shares_per_minute = 6.0
enable_vardiff = true

[[upstreams]]
address = "$UPSTREAM_HOST"
port = $UPSTREAM_PORT
authority_pubkey = "3diFFYHQpAZJ5Mk6oFwqyqDdHXLmB2Q2DxAtx4Z4v2q3S2x9C"
TOML

docker rm -f translator_sv2 2>/dev/null || true

docker run -d \
    --name translator_sv2 \
    --restart unless-stopped \
    -p "0.0.0.0:34255:34255" \
    -p "${MONITORING_HOST_BIND}:9092:9092" \
    -v "$CONFIG_DIR:/app/config:ro" \
    "stratumv2/translator_sv2:$TAG"

echo ""
echo "=== Translator Proxy deployed ==="
echo "  Image:            stratumv2/translator_sv2:$TAG"
echo "  SV1 Downstream:   localhost:34255"
echo "  SV2 Upstream:     $UPSTREAM_HOST:$UPSTREAM_PORT"
echo "  Monitoring:       http://${MONITORING_HEALTH_HOST}:9092"
echo "  Monitoring bind:  ${MONITORING_HOST_BIND} (${MONITORING_BIND_MODE})"
echo ""
echo "Verify: curl -s http://${MONITORING_HEALTH_HOST}:9092/api/v1/health"
echo "Logs:   docker logs translator_sv2 --tail 50"
