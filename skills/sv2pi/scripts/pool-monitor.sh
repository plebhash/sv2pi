#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT="${SV2PI_VAULT:-$HOME/vault}"
MONITOR_DIR="$VAULT/pool-monitor"
SNAPSHOT_DIR="$MONITOR_DIR/snapshots"
PLOTS_DIR="$MONITOR_DIR/plots"
HASHLOG_FILE="$MONITOR_DIR/hashrate.jsonl"

mkdir -p "$SNAPSHOT_DIR" "$PLOTS_DIR"

MAINNET_API="http://127.0.0.1:9090/api/v1"

TIMESTAMP_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TIMESTAMP_FILE=$(date -u +"%Y%m%d_%H%M%S")

POOL_GLOBAL=$(curl -s "${MAINNET_API}/global" 2>/dev/null || echo '{}')
CLIENTS_COUNT=$(echo "$POOL_GLOBAL" | jq -r '.sv2_clients.total_clients // 0')
CLIENTS_HR=$(echo "$POOL_GLOBAL" | jq -r '.sv2_clients.total_hashrate // 0')
CHANNELS_TOTAL=$(echo "$POOL_GLOBAL" | jq -r '.sv2_clients.total_channels // 0')
UPTIME=$(echo "$POOL_GLOBAL" | jq -r '.uptime_secs // 0')
CLIENTS_LIMIT=$((CLIENTS_COUNT > 0 ? CLIENTS_COUNT : 1))

POOL_CLIENTS=$(curl -s "${MAINNET_API}/clients?limit=${CLIENTS_LIMIT}" 2>/dev/null || echo '{}')

echo "$POOL_GLOBAL" > "$SNAPSHOT_DIR/${TIMESTAMP_FILE}_pool-global.json"
echo "$POOL_CLIENTS" > "$SNAPSHOT_DIR/${TIMESTAMP_FILE}_pool-clients.json"

ENTRY=$(jq -nc '{
    timestamp: $ts,
    hashrate: $hr,
    clients: $cc,
    channels: $ch,
    uptime: $up
}' --arg ts "$TIMESTAMP_UTC" --argjson hr "$CLIENTS_HR" --argjson cc "$CLIENTS_COUNT" --argjson ch "$CHANNELS_TOTAL" --argjson up "$UPTIME")
echo "$ENTRY" >> "$HASHLOG_FILE"

python3 "${SCRIPT_DIR}/plot-pool-hashrate.py" "$HASHLOG_FILE" "$PLOTS_DIR/pool-hashrate.png"
