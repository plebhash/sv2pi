## 👁️ Pool Monitor 📊

Automated hashrate monitoring via the pool's HTTP API (port 9090). Two scripts work together to collect pool state and generate charts, with all output stored in the vault.

### Scripts

- **`{baseDir}/scripts/pool-monitor.sh`** — probes `http://127.0.0.1:9090/api/v1/global` and `api/v1/clients` to collect pool state: uptime, client count, channel count, and aggregate hashrate. Saves raw JSON snapshots, appends a structured hashrate log, and generates a human-readable dashboard page (`index.md`) for Quartz publishing.
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

$VAULT/pool-hashrate.svg             # root-level chart alias for reliable Quartz embedding
```

The root-level `pool-hashrate.svg` alias is the recommended URL for embedding the chart in Quartz pages — Quartz's path rewriting causes ambiguous relative paths for markdown image embeds. Use a raw HTML `<img>` tag with an absolute path:

```html
<img src="/pool-hashrate.svg" alt="Pool hashrate" style="width: 100%; max-width: 1000px;" />
```

### Dashboard contents

The generated `index.md` is the primary operator-facing page and should include:
- Latest sample timestamp and pool hashrate
- Current SV2 client/channel counts
- Pool uptime
- Total sample and snapshot counts
- Embedded latest chart (raw HTML img tag)
- Recent readings table (newest N entries first)

### Operator deployment

The scripts are designed to be invoked periodically via a systemd timer. Recommended timer config:

```ini
[Unit]
Description=Run SRI pool monitor every 2 hours

[Timer]
OnBootSec=5min
OnUnitActiveSec=2h
AccuracySec=5min
Persistent=true
Unit=sv2pi-pool-monitor.service

[Install]
WantedBy=timers.target
```

**Note:** manual samples triggered during setup may produce close-together readings. This is normal — the steady-state interval is every 2 hours.

### Verification checklist

After deploying, verify:

```bash
systemctl --user is-enabled sv2pi-pool-monitor.timer
systemctl --user is-active sv2pi-pool-monitor.timer

test -s ~/vault/pool-monitor/hashrate.jsonl
test -s ~/vault/pool-monitor/index.md
test -s ~/vault/pool-monitor/latest.md
test -s ~/vault/pool-hashrate.svg

curl -sf http://127.0.0.1:9090/api/v1/health
```

If published via Quartz, also verify:

```bash
curl -sw '%{http_code} %{content_type}\n' -o /dev/null http://10.0.0.1:4028/pool-monitor/
# Expected: 200 text/html
curl -sw '%{http_code} %{content_type}\n' -o /dev/null http://10.0.0.1:4028/pool-hashrate.svg
# Expected: 200 image/svg+xml
```

### Diagnostics

Operational failures are logged in the systemd journal:

```bash
journalctl --user -u sv2pi-pool-monitor.service -n 30
```

Keep the dashboard clean — never surface Python import failures, stack traces, or implementation details in the operator-facing pages. The dashboard status field should be concise (e.g. `SVG updated`) rather than exposing internal error messages.

The scripts consume zero AI tokens — pure data collection and rendering.

---
