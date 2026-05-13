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
DISCORD_CHANNEL_ID="${SV2PI_POOL_MONITOR_DISCORD_CHANNEL_ID:-1501133804058710116}"
PICORD_ENV_FILE="${SV2PI_PICORD_ENV:-/home/sv2bot/.picord/.env}"
DISCORD_POST_ENABLED="${SV2PI_POOL_MONITOR_DISCORD:-1}"
POOL_CONFIG_FILE="${SV2PI_POOL_CONFIG_FILE:-$HOME/.sv2pi/pool/config/pool-config.toml}"

if [ "${SV2PI_POOL_MONITOR_API_HOST:-}" = "0.0.0.0" ]; then
    echo "pool-monitor: SV2PI_POOL_MONITOR_API_HOST must not be 0.0.0.0; use localhost, 127.0.0.1, or a WireGuard IP" >&2
    exit 1
fi

parse_monitoring_host() {
    local cfg="$1"
    [ -s "$cfg" ] || return 1
    python3 - "$cfg" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text()
match = re.search(r'(?m)^\s*monitoring_address\s*=\s*"([^"]+)"\s*$', text)
if not match:
    raise SystemExit(1)

address = match.group(1).strip()
host = address
if address.startswith("["):
    end = address.find("]")
    if end != -1:
        host = address[1:end]
elif ":" in address:
    host = address.rsplit(":", 1)[0]

if host in ("", "0.0.0.0", "::"):
    raise SystemExit(1)

print(host)
PY
}

latest_hotpath_pool_config() {
    python3 - <<'PY'
from pathlib import Path

root = Path('/tmp')
candidates = []
for cfg in root.glob('sv2pi-hotpath-config-v*/pool/pool-config.toml'):
    try:
        if cfg.is_file():
            candidates.append((cfg.stat().st_mtime, cfg))
    except OSError:
        pass

if candidates:
    candidates.sort(reverse=True)
    print(candidates[0][1])
PY
}

detect_pool_api_host() {
    local host
    if [ -n "${SV2PI_POOL_MONITOR_API_HOST:-}" ]; then
        printf '%s\n' "$SV2PI_POOL_MONITOR_API_HOST"
        return 0
    fi

    if host=$(parse_monitoring_host "$POOL_CONFIG_FILE" 2>/dev/null); then
        printf '%s\n' "$host"
        return 0
    fi

    local hotpath_cfg
    hotpath_cfg=$(latest_hotpath_pool_config)
    if [ -n "$hotpath_cfg" ] && host=$(parse_monitoring_host "$hotpath_cfg" 2>/dev/null); then
        printf '%s\n' "$host"
        return 0
    fi

    printf '127.0.0.1\n'
}

POOL_API_HOST="$(detect_pool_api_host)"

format_hashrate() {
    local rate="$1"
    python3 - "$rate" <<'PY'
import sys
rate = float(sys.argv[1] or 0)
for scale, unit in [(10**18, "EH/s"), (10**15, "PH/s"), (10**12, "TH/s"), (10**9, "GH/s"), (10**6, "MH/s"), (10**3, "kH/s")]:
    if rate >= scale:
        print(f"{rate / scale:.3g} {unit}")
        break
else:
    print(f"{rate:.0f} H/s")
PY
}

format_duration() {
    local seconds="${1:-0}"
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))
    if [ "$days" -gt 0 ]; then
        printf '%sd %sh %sm' "$days" "$hours" "$minutes"
    elif [ "$hours" -gt 0 ]; then
        printf '%sh %sm' "$hours" "$minutes"
    else
        printf '%sm' "$minutes"
    fi
}

build_discord_client_summary() {
    local client_lines=""
    local idle_count=0
    local active_count=0
    local max_active="${SV2PI_POOL_MONITOR_MAX_ACTIVE_CLIENTS:-8}"
    local max_channels_per_client="${SV2PI_POOL_MONITOR_MAX_CHANNELS_PER_CLIENT:-6}"

    while IFS='|' read -r client_id ext_count std_count client_hr; do
        [ -n "$client_id" ] || continue
        local total_ch=$((ext_count + std_count))
        if [ "$total_ch" -eq 0 ]; then
            idle_count=$((idle_count + 1))
            continue
        fi
        active_count=$((active_count + 1))
        if [ "$active_count" -gt "$max_active" ]; then
            continue
        fi

        local client_hr_fmt channels channel_lines channel_count displayed_count
        client_hr_fmt=$(format_hashrate "$client_hr")
        client_lines="${client_lines}
• Client \`${client_id}\`: \`${total_ch}\` ch (\`${ext_count}\` ext, \`${std_count}\` std) | \`${client_hr_fmt%% *}\` ${client_hr_fmt#* }"

        channels=$(curl -s "${MAINNET_API}/clients/${client_id}/channels" 2>/dev/null || echo '{}')
        channel_count=$(echo "$channels" | jq -r '((.total_extended // 0) + (.total_standard // 0))')
        displayed_count=$channel_count
        if [ "$displayed_count" -gt "$max_channels_per_client" ]; then
            displayed_count=$max_channels_per_client
        fi
        channel_lines=$(echo "$channels" | jq -r --argjson max "$max_channels_per_client" '
            ([.extended_channels[]? | {kind:"ext", id:.channel_id, hr:(.nominal_hashrate // 0), shares:(.shares_accepted // null), best:(.best_diff // null), user:(.user_identity // "")}] +
             [.standard_channels[]? | {kind:"std", id:.channel_id, hr:(.nominal_hashrate // 0), shares:(.shares_accepted // null), best:(.best_diff // null), user:(.user_identity // "")}])[:$max] |
            to_entries[] |
            [.key, .value.id, .value.kind, .value.hr, (.value.shares // ""), (.value.best // ""), .value.user] | @tsv
        ' | while IFS=$'\t' read -r ch_idx ch_id ch_kind ch_hr ch_shares ch_best ch_user; do
            ch_hr_fmt=$(format_hashrate "$ch_hr")
            connector="├─"
            if [ "$displayed_count" -gt 0 ] && [ "$ch_idx" -eq $((displayed_count - 1)) ] && [ "$channel_count" -le "$max_channels_per_client" ]; then
                connector="└─"
            fi
            line="      ${connector} Ch \`${ch_id}\` (${ch_kind}): \`${ch_hr_fmt%% *}\` ${ch_hr_fmt#* }"
            if [ -n "$ch_shares" ]; then
                line="${line} | shares \`${ch_shares}\`"
            fi
            if [ -n "$ch_best" ]; then
                ch_best_int=$(printf '%.0f' "$ch_best")
                line="${line} | best diff \`${ch_best_int}\`"
            fi
            if [ -n "$ch_user" ]; then
                line="${line} | \`${ch_user}\`"
            fi
            printf '%s\n' "$line"
        done)
        if [ -n "$channel_lines" ]; then
            client_lines="${client_lines}
${channel_lines}"
        fi
        if [ "$channel_count" -gt "$max_channels_per_client" ]; then
            client_lines="${client_lines}
      └─ … $((channel_count - max_channels_per_client)) more channels"
        fi
    done < <(echo "$POOL_CLIENTS" | jq -r '.items[]? | "\(.client_id)|\(.extended_channels_count // 0)|\(.standard_channels_count // 0)|\(.total_hashrate // 0)"')

    if [ "$active_count" -gt "$max_active" ]; then
        client_lines="${client_lines}
• … $((active_count - max_active)) more active clients"
    fi
    if [ "$idle_count" -gt 0 ]; then
        client_lines="${client_lines}
• (\`${idle_count}\` idle clients with \`0\` channels)"
    fi

    printf '%s' "$client_lines"
}

post_discord_summary() {
    [ "$DISCORD_POST_ENABLED" = "1" ] || return 0
    [ -s "$PICORD_ENV_FILE" ] || return 0
    [ -s "$VAULT/pool-hashrate.png" ] || return 0
    command -v curl >/dev/null 2>&1 || return 0
    command -v jq >/dev/null 2>&1 || return 0

    local token=""
    token=$(python3 - "$PICORD_ENV_FILE" <<'PY'
import sys
from pathlib import Path
for line in Path(sys.argv[1]).read_text().splitlines():
    line = line.strip()
    if not line or line.startswith('#') or '=' not in line:
        continue
    key, value = line.split('=', 1)
    if key == 'PICORD_DISCORD_TOKEN':
        print(value.strip().strip('"').strip("'"))
        break
PY
)
    [ -n "$token" ] || return 0

    local pretty_hashrate uptime_pretty client_summary content payload tmp_response http_code
    pretty_hashrate=$(format_hashrate "$CLIENTS_HR")
    uptime_pretty=$(format_duration "$UPTIME")
    client_summary=$(build_discord_client_summary)
    content=$(cat <<MSGEOF
**📊 SRI Pool Stats 🤖⛏️**

**Uptime:** \`$uptime_pretty\`
**Clients:** \`$CLIENTS_COUNT\`
**Channels:** \`$CHANNELS_TOTAL\` (\`$CHANNELS_EXT\` ext, \`$CHANNELS_STD\` std)
**Hashrate:** \`${pretty_hashrate%% *}\` ${pretty_hashrate#* }${client_summary}

MSGEOF
)
    if [ "${#content}" -gt 1900 ]; then
        content=$(printf '%s\n\n%s' "$(echo "$content" | head -c 1850)" "… truncated; see vault dashboard for full snapshots.")
    fi
    payload=$(jq -nc --arg content "$content" '{content:$content, allowed_mentions:{parse:[]}}')
    tmp_response=$(mktemp)
    http_code=$(curl -sS -o "$tmp_response" -w '%{http_code}' \
        -H "Authorization: Bot ${token}" \
        -F "payload_json=${payload}" \
        -F "files[0]=@${VAULT}/pool-hashrate.png;type=image/png" \
        "https://discord.com/api/v10/channels/${DISCORD_CHANNEL_ID}/messages" 2>/tmp/sv2pi-discord-post.err || true)
    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        printf 'Discord post failed with HTTP %s\n' "$http_code" > /tmp/sv2pi-discord-post.log
        cat "$tmp_response" >> /tmp/sv2pi-discord-post.log 2>/dev/null || true
    fi
    rm -f "$tmp_response"
}

mkdir -p "$SNAPSHOT_DIR" "$PLOTS_DIR"

MAINNET_API="http://${POOL_API_HOST}:9090/api/v1"

TIMESTAMP_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
TIMESTAMP_FILE=$(date -u +"%Y%m%d_%H%M%S")

POOL_GLOBAL=$(curl -s "${MAINNET_API}/global" 2>/dev/null || echo '{}')
if [ "$POOL_GLOBAL" = "{}" ]; then
    echo "pool-monitor: failed to query ${MAINNET_API}/global" >&2
    exit 1
fi
CLIENTS_COUNT=$(echo "$POOL_GLOBAL" | jq -r '.sv2_clients.total_clients // 0')
CLIENTS_HR=$(echo "$POOL_GLOBAL" | jq -r '.sv2_clients.total_hashrate // 0')
CHANNELS_TOTAL=$(echo "$POOL_GLOBAL" | jq -r '.sv2_clients.total_channels // 0')
CHANNELS_EXT=$(echo "$POOL_GLOBAL" | jq -r '.sv2_clients.extended_channels // 0')
CHANNELS_STD=$(echo "$POOL_GLOBAL" | jq -r '.sv2_clients.standard_channels // 0')
UPTIME=$(echo "$POOL_GLOBAL" | jq -r '.uptime_secs // 0')
CLIENTS_LIMIT=$((CLIENTS_COUNT > 0 ? CLIENTS_COUNT : 1))

POOL_CLIENTS=$(curl -s "${MAINNET_API}/clients?limit=${CLIENTS_LIMIT}" 2>/dev/null || echo '{}')
if [ "$POOL_CLIENTS" = "{}" ]; then
    echo "pool-monitor: failed to query ${MAINNET_API}/clients?limit=${CLIENTS_LIMIT}" >&2
    exit 1
fi

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

post_discord_summary

printf '%s\n' "$ENTRY"
