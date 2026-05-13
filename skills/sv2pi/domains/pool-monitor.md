## 👁️ Pool Monitor 📊

Automated hashrate monitoring via the pool's HTTP API (port 9090). Two scripts work together to collect pool state and generate charts, with all output stored in the vault.

### Scripts

- **`{baseDir}/scripts/pool-monitor.sh`** — probes `http://<monitoring-host>:9090/api/v1/global` and `api/v1/clients` to collect pool state: uptime, client count, channel count, and aggregate hashrate. `monitoring-host` can be set explicitly with `SV2PI_POOL_MONITOR_API_HOST` (recommended). Without an explicit override, it auto-detects from `SV2PI_POOL_CONFIG_FILE`/`~/.sv2pi/pool/config/pool-config.toml` and, when needed, from the most recent hotpath rendered config under `/tmp/sv2pi-hotpath-config-v*/pool/pool-config.toml` (`monitoring_address`), then falls back to `127.0.0.1`. `0.0.0.0` is invalid for probes and is rejected. On API probe failure, the script exits non-zero instead of writing a false zero sample. Saves raw JSON snapshots, appends a structured hashrate log, and generates a human-readable dashboard page (`index.md`) for Quartz publishing.
- **`{baseDir}/scripts/plot-pool-hashrate.py`** — reads the vault's hashrate log and renders a log-scale hashrate-over-time PNG chart (dark theme, UTC-labeled x-axis). Requires `matplotlib` and `numpy`.

### Vault layout

All output lives under `$SV2PI_VAULT/pool-monitor/` (defaults to `$HOME/vault/pool-monitor/`):

```
$VAULT/pool-monitor/
├── index.md                         # primary dashboard (served at /pool-monitor/)
├── latest.md                        # latest-sample detail page
├── hashrate.jsonl                   # append-only time-series
│   # {"timestamp":"...", "hashrate":N, "clients":N, "channels":N, "uptime":N}
├── snapshots/                       # timestamped raw API responses
│   ├── YYYYMMDD_HHMMSS_pool-global.json
│   └── YYYYMMDD_HHMMSS_pool-clients.json
└── plots/
    └── pool-hashrate.png            # latest chart (overwritten each run)

$VAULT/pool-hashrate.png             # root-level chart alias for reliable Quartz embedding
```

The root-level `pool-hashrate.png` alias is the recommended URL for embedding the chart in Quartz pages — Quartz's path rewriting causes ambiguous relative paths for markdown image embeds. Use a raw HTML `<img>` tag with an absolute path:

```html
<img src="/pool-hashrate.png" alt="Pool hashrate" style="width: 100%; max-width: 1000px;" />
```

### Dashboard contents

The generated `index.md` is the primary operator-facing page and should include:
- Latest sample timestamp and pool hashrate
- Current SV2 client/channel counts
- Pool uptime
- Total sample and snapshot counts
- Embedded latest chart (raw HTML img tag)
- Recent readings table (newest N entries first)

### Discord report style

When `pool-monitor.sh` posts automated Discord reports, keep the message compact, readable, and Discord-native. Operator feedback established this report-template style:

- Header: `📊 SRI Pool Stats 🤖⛏️`
- Do not include decorative environment separator lines such as `Mainnet (port 3333)`.
- Do not include implementation/status footer text such as `Auto-report • no AI tokens`.
- Do not include a visible attachment-label line such as `pool-hashrate.png attached`; attach the PNG silently.
- Use bold labels for top-level fields and inline-code formatting for values:
  - `**🤑 Blocks Found:** \`0\``
  - `**🏆 Uptime:** \`2d 16h 38m\``
  - `**🧑‍🤝‍🧑 Clients:** \`3\``
  - `**🔀 Channels:** \`1\` (\`1\` ext, \`0\` std)`
  - `**❤️‍🔥 Hashrate:** \`6.75\` TH/s`
- For client/channel detail rows, wrap IDs, counts, numeric values, and identities in inline code while leaving units and labels readable:
  - `• 👤 Client \`109\`: \`1\` ch (\`1\` ext, \`0\` std) | \`6.75\` TH/s`
  - `      └─ Ch \`2\` (ext): \`6.75\` TH/s | \`BadAssBassDad.translator-proxy\``
  - `• 👻 (\`2\` idle clients with \`0\` channels)`
- Keep markdown simple for Discord rendering: bold labels, bullets, indentation, inline code; avoid tables.
- The visual pattern is: labels and units are plain text, data values are inline-code. This makes live metrics scan like structured data without turning the report into a table.

### Operator deployment

The scripts are designed to be invoked periodically via a systemd timer. Recommended timer config:

```ini
[Unit]
Description=Run SRI pool monitor every 15 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=15min
AccuracySec=5min
Persistent=true
Unit=sv2pi-pool-monitor.service

[Install]
WantedBy=timers.target
```

**Note:** manual samples triggered during setup may produce close-together readings. This is normal — the steady-state sampling interval is every 15 minutes, while Discord posts stay at 2 hours (script-side throttle).

Set the probe host explicitly in the user service environment when monitoring is not localhost-bound:

```bash
systemctl --user edit sv2pi-pool-monitor.service
```

```ini
[Service]
Environment=SV2PI_POOL_MONITOR_API_HOST=127.0.0.1
# or: Environment=SV2PI_POOL_MONITOR_API_HOST=10.x.y.z   # WireGuard IP
```

Then reload and run once:

```bash
systemctl --user daemon-reload
systemctl --user restart sv2pi-pool-monitor.service
```

### Verification checklist

After deploying, verify:

```bash
systemctl --user is-enabled sv2pi-pool-monitor.timer
systemctl --user is-active sv2pi-pool-monitor.timer
systemctl --user show sv2pi-pool-monitor.service -p Environment

test -s ~/vault/pool-monitor/hashrate.jsonl
test -s ~/vault/pool-monitor/index.md
test -s ~/vault/pool-monitor/latest.md
test -s ~/vault/pool-hashrate.png

curl -sf http://<monitoring-host>:9090/api/v1/health
```

If published via Quartz, also verify:

```bash
curl -sw '%{http_code} %{content_type}\n' -o /dev/null http://10.0.0.1:4028/pool-monitor/
# Expected: 200 text/html
curl -sw '%{http_code} %{content_type}\n' -o /dev/null http://10.0.0.1:4028/pool-hashrate.png
# Expected: 200 image/png
```

### Diagnostics

If API probing fails, the script exits non-zero and does not append a sample. Treat this as a probe failure and investigate host/bind mismatch.

Operational failures are logged in the systemd journal:

```bash
journalctl --user -u sv2pi-pool-monitor.service -n 30
```

Keep the dashboard clean — never surface Python import failures, stack traces, or implementation details in the operator-facing pages. The dashboard status field should be concise (e.g. `PNG updated`) rather than exposing internal error messages.

The scripts consume zero AI tokens — pure data collection and rendering.

---
