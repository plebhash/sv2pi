#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT="${SV2PI_VAULT:-$HOME/vault}"
MONITOR_DIR="$VAULT/pool-monitor"
SNAPSHOT_DIR="$MONITOR_DIR/snapshots"
PLOTS_DIR="$MONITOR_DIR/plots"
HASHLOG_FILE="$MONITOR_DIR/hashrate.jsonl"
STATUS_FILE="$MONITOR_DIR/latest.md"
INDEX_FILE="$MONITOR_DIR/index.md"

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

PLOT_STATUS="skipped"

PLOT_PYTHON="${SV2PI_PLOT_PYTHON:-python3}"
if ! "$PLOT_PYTHON" - <<'PY' >/dev/null 2>&1
import matplotlib, numpy
PY
then
    if command -v python3.8 >/dev/null 2>&1 && python3.8 - <<'PY' >/dev/null 2>&1
import matplotlib, numpy
PY
    then
        PLOT_PYTHON="python3.8"
    fi
fi

if "$PLOT_PYTHON" "${SCRIPT_DIR}/plot-pool-hashrate.py" "$HASHLOG_FILE" "$PLOTS_DIR/pool-hashrate.png" >/tmp/sv2pi-plot.log 2>&1; then
    cp "$PLOTS_DIR/pool-hashrate.png" "$MONITOR_DIR/pool-hashrate.png"
    cp "$PLOTS_DIR/pool-hashrate.png" "$VAULT/pool-hashrate.png"
    PLOT_STATUS="PNG updated"
elif [ -s "$PLOTS_DIR/pool-hashrate.png" ]; then
    cp "$PLOTS_DIR/pool-hashrate.png" "$MONITOR_DIR/pool-hashrate.png"
    cp "$PLOTS_DIR/pool-hashrate.png" "$VAULT/pool-hashrate.png"
    PLOT_STATUS="PNG stale"
else
    PLOT_STATUS="PNG unavailable"
fi

RECENT_ROWS=$(tail -20 "$HASHLOG_FILE" | tac | jq -r '"| " + .timestamp + " | " + (.hashrate|tostring) + " | " + (.clients|tostring) + " | " + (.channels|tostring) + " | " + (.uptime|tostring) + " |"')
TOTAL_SAMPLES=$(wc -l < "$HASHLOG_FILE" | tr -d ' ')
SNAPSHOT_COUNT=$(find "$SNAPSHOT_DIR" -type f -name '*.json' | wc -l | tr -d ' ')

cat > "$STATUS_FILE" <<STATUSEOF
---
title: 👁️ Pool Monitor 📊
---

# 👁️ Pool Monitor 📊

| Field | Value |
|---|---:|
| Last sample UTC | $TIMESTAMP_UTC |
| Pool hashrate H/s | $CLIENTS_HR |
| SV2 clients | $CLIENTS_COUNT |
| SV2 channels | $CHANNELS_TOTAL |
| Pool uptime seconds | $UPTIME |
| Plot status | $PLOT_STATUS |

## Hashrate Plot

<img src="/pool-hashrate.png" alt="Pool hashrate" style="width: 100%; max-width: 1000px;" />

## Recent readings

Showing newest 20 of $TOTAL_SAMPLES samples.

| Timestamp UTC | Hashrate H/s | Clients | Channels | Uptime seconds |
|---|---:|---:|---:|---:|
$RECENT_ROWS

## Links

- [[pool-monitor/index|👁️ Pool Monitor 📊 dashboard]]
- Latest chart: \`/pool-hashrate.png\`
- JSONL history in vault: \`pool-monitor/hashrate.jsonl\`
- Raw snapshots in vault: \`pool-monitor/snapshots/\` ($SNAPSHOT_COUNT JSON files)
STATUSEOF

cat > "$INDEX_FILE" <<INDEXEOF
---
title: 👁️ Pool Monitor 📊
---

# 👁️ Pool Monitor 📊

Latest sample: **$TIMESTAMP_UTC**
Latest hashrate: **$CLIENTS_HR H/s**
SV2 clients / channels: **$CLIENTS_COUNT** / **$CHANNELS_TOTAL**
Pool uptime: **$UPTIME** seconds
Total samples: **$TOTAL_SAMPLES**
Raw snapshots: **$SNAPSHOT_COUNT JSON files**

## Hashrate Plot

<img src="/pool-hashrate.png" alt="Pool hashrate" style="width: 100%; max-width: 1000px;" />

## Recent readings

Showing newest 20 of $TOTAL_SAMPLES samples.

| Timestamp UTC | Hashrate H/s | Clients | Channels | Uptime seconds |
|---|---:|---:|---:|---:|
$RECENT_ROWS

## Links

- [[pool-monitor/latest|Latest status page]]
- Latest chart: \`/pool-hashrate.png\`
- JSONL history in vault: \`pool-monitor/hashrate.jsonl\`
- Raw snapshots in vault: \`pool-monitor/snapshots/\` ($SNAPSHOT_COUNT JSON files)
INDEXEOF

printf '%s\n' "$ENTRY"
