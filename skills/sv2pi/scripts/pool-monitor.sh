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

python3 "${SCRIPT_DIR}/plot-pool-hashrate.py" "$HASHLOG_FILE" "$PLOTS_DIR/pool-hashrate.png" >/tmp/sv2pi-plot.log 2>&1 && PLOT_STATUS="PNG updated" || true

python3 - "$HASHLOG_FILE" "$PLOTS_DIR/pool-hashrate.svg" <<'PY'
import json
import math
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

entries = []
for line in Path(sys.argv[1]).read_text().splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        e = json.loads(line)
    except json.JSONDecodeError:
        continue
    ts = datetime.fromisoformat(e["timestamp"].replace("Z", "+00:00"))
    entries.append((ts, e.get("hashrate", 0)))

if not entries:
    print("No data", file=sys.stderr)
    sys.exit(1)

W, H = 1000, 400
PAD_L, PAD_R, PAD_T, PAD_B = 80, 20, 30, 60

t_min = entries[0][0].timestamp()
t_max = entries[-1][0].timestamp()
r_min = 0
r_max = max(r for _, r in entries)
if r_max == 0:
    r_max = 1

def fmt_rate(r):
    for scale, unit in [(10**18, "EH/s"), (10**15, "PH/s"), (10**12, "TH/s"),
                         (10**9, "GH/s"), (10**6, "MH/s"), (10**3, "kH/s")]:
        if r >= scale:
            return f"{r / scale:.3g} {unit}"
    return f"{r} H/s"

def log_tick_range(rmax):
    ticks = []
    steps = [1, 10, 100]
    prefixes = [(1, "H/s"), (10**3, "kH/s"), (10**6, "MH/s"), (10**9, "GH/s"),
                (10**12, "TH/s"), (10**15, "PH/s"), (10**18, "EH/s")]
    for scale, unit in prefixes:
        for step in steps:
            v = step * scale
            if 1 <= v <= rmax * 10:
                ticks.append((math.log10(max(v, 1)), f"{step} {unit}"))
    return sorted(ticks)

def x_pos(ts_val):
    if t_max == t_min:
        return PAD_L
    return PAD_L + (ts_val - t_min) / (t_max - t_min) * (W - PAD_L - PAD_R)

use_log = r_max >= 10000

if use_log:
    log_min = 0
    log_max = math.log10(r_max) if r_max >= 1 else 0
    yticks = log_tick_range(r_max)
    def y_pos(r):
        return PAD_T + (1 - (math.log10(max(r, 1)) - log_min) / max(log_max - log_min, 1)) * (H - PAD_T - PAD_B)
else:
    def y_pos(r):
        return PAD_T + (1 - r / max(r_max, 1)) * (H - PAD_T - PAD_B)

svg_ns = "http://www.w3.org/2000/svg"
svg = ET.Element("svg", {
    "xmlns": svg_ns,
    "viewBox": f"0 0 {W} {H}",
    "width": str(W), "height": str(H),
})

style = ET.SubElement(svg, "style")
style.text = """
.bg { fill: #0b1d3a; }
.axis { stroke: #8ecbff; stroke-width: 1; }
.axis-label { fill: #ffffff; font-family: monospace; font-size: 11px; }
.grid { stroke: #8ecbff; stroke-width: 0.5; stroke-dasharray: 4 4; opacity: 0.3; }
.line { stroke: #ffffff; stroke-width: 1.5; fill: none; }
.title { fill: #8dff9a; font-family: monospace; font-size: 14px; font-weight: bold; }
.tick-text { fill: #8ecbff; font-family: monospace; font-size: 9px; }
"""

ET.SubElement(svg, "rect", {"width": str(W), "height": str(H), "class": "bg"})

ET.SubElement(svg, "line", {
    "x1": str(PAD_L), "y1": str(PAD_T),
    "x2": str(PAD_L), "y2": str(H - PAD_B), "class": "axis",
})
ET.SubElement(svg, "line", {
    "x1": str(PAD_L), "y1": str(H - PAD_B),
    "x2": str(W - PAD_R), "y2": str(H - PAD_B), "class": "axis",
})

if use_log:
    for val, label in yticks:
        y = PAD_T + (1 - (val - log_min) / max(log_max - log_min, 1)) * (H - PAD_T - PAD_B)
        ET.SubElement(svg, "line", {
            "x1": str(PAD_L), "y1": str(round(y, 1)),
            "x2": str(W - PAD_R), "y2": str(round(y, 1)), "class": "grid",
        })
        ET.SubElement(svg, "text", {
            "x": str(PAD_L - 6), "y": str(round(y + 3, 1)),
            "text-anchor": "end", "class": "tick-text",
        }).text = label
else:
    for i in range(5):
        r = (r_max / 4.0) * i
        y = y_pos(r)
        ET.SubElement(svg, "line", {
            "x1": str(PAD_L), "y1": str(round(y, 1)),
            "x2": str(W - PAD_R), "y2": str(round(y, 1)), "class": "grid",
        })
        ET.SubElement(svg, "text", {
            "x": str(PAD_L - 6), "y": str(round(y + 3, 1)),
            "text-anchor": "end", "class": "tick-text",
        }).text = fmt_rate(r)

for i, (ts, r) in enumerate(entries):
    x = x_pos(ts.timestamp())
    if i % max(1, len(entries) // 12) == 0:
        label = ts.strftime("%H:%M") if ts.hour != 0 else ts.strftime("%d/%m\n%H:%M")
        ET.SubElement(svg, "text", {
            "x": str(round(x, 1)), "y": str(H - PAD_B + 16),
            "text-anchor": "middle", "class": "tick-text",
        }).text = label

points = " ".join(f"{x_pos(ts.timestamp()):.1f},{y_pos(r):.1f}" for ts, r in entries)
ET.SubElement(svg, "polyline", {"points": points, "class": "line"})

last_r = entries[-1][1]
ET.SubElement(svg, "text", {
    "x": str(W / 2), "y": str(PAD_T - 10),
    "text-anchor": "middle", "class": "title",
}).text = f"SRI Pool mainnet — {fmt_rate(last_r)}"

tree = ET.ElementTree(svg)
tree.write(sys.argv[2], encoding="unicode", xml_declaration=True)
print(f"Saved SVG to {sys.argv[2]}")
PY

SVG_OK=$?
if [ "$SVG_OK" -eq 0 ]; then
    cp "$PLOTS_DIR/pool-hashrate.svg" "$MONITOR_DIR/pool-hashrate.svg"
    cp "$PLOTS_DIR/pool-hashrate.svg" "$VAULT/pool-hashrate.svg"
    if [ "$PLOT_STATUS" = "PNG updated" ]; then
        PLOT_STATUS="SVG + PNG updated"
    else
        PLOT_STATUS="SVG updated"
    fi
else
    PLOT_STATUS="${PLOT_STATUS} (SVG failed)"
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

<img src="/pool-hashrate.svg" alt="Pool hashrate" style="width: 100%; max-width: 1000px;" />

## Recent readings

Showing newest 20 of $TOTAL_SAMPLES samples.

| Timestamp UTC | Hashrate H/s | Clients | Channels | Uptime seconds |
|---|---:|---:|---:|---:|
$RECENT_ROWS

## Links

- [[pool-monitor/index|👁️ Pool Monitor 📊 dashboard]]
- Latest chart: \`/pool-hashrate.svg\`
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

<img src="/pool-hashrate.svg" alt="Pool hashrate" style="width: 100%; max-width: 1000px;" />

## Recent readings

Showing newest 20 of $TOTAL_SAMPLES samples.

| Timestamp UTC | Hashrate H/s | Clients | Channels | Uptime seconds |
|---|---:|---:|---:|---:|
$RECENT_ROWS

## Links

- [[pool-monitor/latest|Latest status page]]
- Latest chart: \`/pool-hashrate.svg\`
- JSONL history in vault: \`pool-monitor/hashrate.jsonl\`
- Raw snapshots in vault: \`pool-monitor/snapshots/\` ($SNAPSHOT_COUNT JSON files)
INDEXEOF

printf '%s\n' "$ENTRY"
