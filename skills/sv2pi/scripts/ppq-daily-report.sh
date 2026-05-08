#!/usr/bin/env bash
# ppq-daily-report.sh — Daily PPQ balance report (DISCORD + VAULT)
#
# DEFAULT_MODEL operation. Probes current PPQ balance, reads hourly CSV
# to compute burn rate and forecast, posts to Discord, logs to vault.
#
# Environment:
#   SV2PI_PPQ_DAILY_DISCORD=0              disable Discord posting
#   SV2PI_PPQ_DAILY_DISCORD_CHANNEL_ID=<id> override target channel
#   SV2PI_PPQ_LOW_BALANCE_THRESHOLD=5.00    warning threshold
#   SV2PI_PICORD_ENV=<path>                 Picord env file
#   SV2PI_VAULT=<path>                      vault root

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VAULT="${SV2PI_VAULT:-$HOME/vault}"
READINGS_DIR="$VAULT/ppq-readings"
READINGS_CSV="$READINGS_DIR/readings.csv"
DAILY_LOG="$READINGS_DIR/daily-report.md"
DISCORD_POST_ENABLED="${SV2PI_PPQ_DAILY_DISCORD:-1}"
DISCORD_CHANNEL_ID="${SV2PI_PPQ_DAILY_DISCORD_CHANNEL_ID:-1501133804058710116}"
LOW_BALANCE_THRESHOLD="${SV2PI_PPQ_LOW_BALANCE_THRESHOLD:-5.00}"
PICORD_ENV_FILE="${SV2PI_PICORD_ENV:-/home/sv2bot/.picord/.env}"

# ── Probe current balance ──────────────────────────────────────────────

balance_json=$("$SCRIPT_DIR/check-ppq-balance.py" 2>/dev/null || echo '{"ok":false}')
if ! echo "$balance_json" | python3 -c 'import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get("ok") else 1)' 2>/dev/null; then
    echo "ppq-daily-report: balance probe failed" >&2
    exit 1
fi

current_balance=$(echo "$balance_json" | python3 -c 'import sys,json; print(json.load(sys.stdin)["balance"])')
today=$(date -u +%Y-%m-%d)

# ── Compute burn rate from hourly CSV ───────────────────────────────────

burn_24h="N/A"
burn_7d="N/A"
est_days="unknown"

if [ -s "$READINGS_CSV" ]; then
    stats=$(python3 - "$READINGS_CSV" "$current_balance" <<'PY'
import csv, sys
from datetime import datetime, timezone
from io import StringIO

csv_path = sys.argv[1]
current = float(sys.argv[2])

with open(csv_path, newline='') as f:
    reader = csv.DictReader(f)
    rows = list(reader)

if len(rows) < 2:
    print("N/A N/A unknown")
    sys.exit(0)

# Parse timestamps and balances
for r in rows:
    r['_dt'] = datetime.fromisoformat(r['timestamp'].replace('Z', '+00:00'))
    r['_bal'] = float(r['balance'])

now = datetime.now(timezone.utc)

# 24h burn: oldest reading within 24h window vs current
recent_24h = [r for r in rows if (now - r['_dt']).total_seconds() <= 86400]
if recent_24h and len(recent_24h) >= 2:
    oldest_24h = min(recent_24h, key=lambda r: r['_bal'])
    burn_24h = round(max(0, oldest_24h['_bal'] - current), 4)
else:
    burn_24h = None

# 7d avg daily burn
recent_7d = [r for r in rows if (now - r['_dt']).total_seconds() <= 7 * 86400]
if recent_7d and len(recent_7d) >= 2:
    oldest_7d = min(recent_7d, key=lambda r: r['_dt'])
    newest_7d = max(recent_7d, key=lambda r: r['_dt'])
    days_span = (newest_7d['_dt'] - oldest_7d['_dt']).total_seconds() / 86400
    if days_span > 0.1:
        burn_7d = round(max(0, (oldest_7d['_bal'] - newest_7d['_bal']) / days_span), 4)
    else:
        burn_7d = None
else:
    burn_7d = None

# Est days remaining using 7d avg; fall back to 24h
daily_rate = burn_7d if burn_7d and burn_7d > 0 else (burn_24h if burn_24h and burn_24h > 0 else None)
if daily_rate and daily_rate > 0:
    est_days = round(current / daily_rate)
else:
    est_days = None

b24 = f"${burn_24h:.2f}" if burn_24h is not None else "N/A"
b7d = f"${burn_7d:.2f}/day" if burn_7d is not None else "N/A"
edays = f"~{est_days} days" if est_days is not None else "unknown"

print(f"{b24} {b7d} {edays}")
PY
)
    burn_24h=$(echo "$stats" | awk '{print $1}')
    burn_7d=$(echo "$stats" | awk '{print $2}')
    est_days=$(echo "$stats" | awk '{print $3}')
fi

# ── Warning line ────────────────────────────────────────────────────────

warning=""
if python3 -c "exit(0 if float('$current_balance') < float('$LOW_BALANCE_THRESHOLD') else 1)" 2>/dev/null; then
    warning=$(printf '\n⚠️ Balance below $%.2f threshold — top up soon.' "$LOW_BALANCE_THRESHOLD")
fi

# ── Discord post ────────────────────────────────────────────────────────

post_discord() {
    [ "$DISCORD_POST_ENABLED" = "1" ] || return 0
    [ -s "$PICORD_ENV_FILE" ] || return 0
    command -v curl >/dev/null 2>&1 || return 0

    local token
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

    local content
    content=$(cat <<MSGEOF
**💰 PPQ Balance Report — $today**

**Balance:** \`\$$current_balance\`
**24h burn:** \`$burn_24h\`
**7d avg burn:** \`$burn_7d\`
**Est. days remaining:** \`$est_days\`$warning
MSGEOF
)

    local payload tmp_response http_code
    payload=$(python3 -c 'import sys,json; print(json.dumps({"content":sys.argv[1],"allowed_mentions":{"parse":[]}}))' "$content")
    tmp_response=$(mktemp)
    http_code=$(curl -sS -o "$tmp_response" -w '%{http_code}' \
        -H "Authorization: Bot ${token}" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "https://discord.com/api/v10/channels/${DISCORD_CHANNEL_ID}/messages" 2>/tmp/sv2pi-ppq-discord-post.err || true)
    if [ "$http_code" != "200" ] && [ "$http_code" != "201" ]; then
        printf 'Discord post failed with HTTP %s\n' "$http_code" > /tmp/sv2pi-ppq-discord-post.log
        cat "$tmp_response" >> /tmp/sv2pi-ppq-discord-post.log 2>/dev/null || true
        rm -f "$tmp_response"
        return 1
    fi
    rm -f "$tmp_response"
    return 0
}

# ── Vault daily log ─────────────────────────────────────────────────────

mkdir -p "$READINGS_DIR"

if [ ! -f "$DAILY_LOG" ]; then
    cat > "$DAILY_LOG" <<'HEADER'
# PPQ Daily Balance Log

HEADER
fi

printf -- '- **%s:** $%.2f | 24h burn: %s | %s remaining\n' \
    "$today" "$current_balance" "$burn_24h" "$est_days" >> "$DAILY_LOG"

# ── Discord (non-fatal) ─────────────────────────────────────────────────

post_discord || true

exit 0
