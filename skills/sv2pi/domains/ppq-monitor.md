## PPQ Credit Balance Monitor

The sv2bot agent uses PPQ (PayPerQ) as its LLM provider. Checking the PPQ credit balance is part of operational maintenance — low or zero balance can cause model calls to fail.

Use this when the user asks about:
- "PPQ credit" or "PayPerQ balance"
- "credits remaining" or "LLM provider balance"
- "why model calls are failing due to insufficient credit"

**Model routing:** PPQ balance monitoring is a **DEFAULT_MODEL** operation. It is a routine operational report, not an admin/policy/safety change. The daily Discord report and on-demand balance checks both route through DEFAULT_MODEL.

### Security Rules

1. **Never** print, echo, summarize, log, or persist the PPQ API key.
2. **Never** paste the full contents of `models.json` into user-facing output.
3. **Never** write the API key into the vault, skill docs, incident notes, or command transcripts.
4. Use the placeholder `<PPQ_API_KEY>` when discussing the key.
5. If showing commands, prefer commands that read the key locally and do not display it.
6. Do not run shell tracing (`set -x`) around these commands.
7. If an error occurs, report HTTP status and error body only after confirming it does not include secrets.

### Config Location

Pi stores model provider configuration at:

```text
/home/sv2bot/.pi/agent/models.json
```

The relevant provider entry is `providers.ppq` with expected fields:

```json
{
  "apiKey": "<PPQ_API_KEY>",
  "baseUrl": "https://api.ppq.ai/v1",
  "type": "openai-completions"
}
```

The PPQ credits endpoint lives outside `/v1`; the probe script strips `/v1` from `baseUrl` before calling the credit endpoint.

### Balance Endpoint

```http
POST https://api.ppq.ai/credits/balance
Authorization: Bearer <PPQ_API_KEY>
Content-Type: application/json

{}
```

A `credit_id` is not required — bearer authentication alone is sufficient.

Expected successful response shape:

```json
{ "balance": 18.83440603170697 }
```

Treat any remembered balance as stale. Always probe live before answering.

### Live Balance Probe

```bash
python3 {baseDir}/scripts/check-ppq-balance.py [/path/to/models.json]
```

Defaults to `/home/sv2bot/.pi/agent/models.json`. Accepts an optional config path argument.

The script reads the API key locally from Pi config but never prints it. Output is always JSON:

- `{"ok": true, "balance": 18.83, "raw": {...}}`
- `{"ok": false, "error": "missing_config_key", ...}`
- `{"ok": false, "error": "models_config_not_found", ...}`
- `{"ok": false, "error": "http_error", "status": 402, "body": "..."}`

### Agent Behavior

When the user asks for PPQ credit balance:

1. Run the live balance probe.
2. Parse the returned JSON.
3. If `ok: true`, answer with the current balance (e.g. "PPQ credit balance is currently $18.83.").
4. Do not mention or expose the API key.
5. If the endpoint fails, report:
   - whether config was missing,
   - whether the HTTP request failed,
   - HTTP status if available,
   - sanitized error body if available.

### Hourly Balance Probe

The agent probes PPQ credit balance every hour and logs the reading to the vault. This is a **zero-token, fire-and-forget operation** — probe the API, dump the result to CSV, exit. No LLM reasoning, no summarization, no agent response generation. This builds a time series for analyzing credit consumption patterns and detecting impending depletion.

**Scheduling:** Probe at the top of every hour. If precise scheduling is not feasible, probe at the next opportunity and record the actual timestamp.

**Logging:** After each probe, append a line to the vault's PPQ readings CSV:

```bash
python3 {baseDir}/scripts/log-ppq-reading.py
```

This script runs the balance probe and appends to `$HOME/vault/ppq-readings/readings.csv`:

```csv
2026-05-07T14:00:00Z,18.834
```

Format: ISO-8601 UTC timestamp, balance as a decimal float. The script never prints the API key.

**Analysis:** The accumulated CSV provides a complete credit consumption ledger. The agent or operator can:

- Plot balance over time to visualize burn rate.
- Forecast depletion date from recent consumption slope.
- Correlate consumption spikes with specific tasks or model usage.

The full vault tracking convention is documented in `{baseDir}/domains/vault.md`.

### Daily Discord Balance Report

Once per day, a scripted report probes the current PPQ balance, reads the hourly readings CSV to compute burn rate and depletion forecast, posts a formatted summary to Discord, and logs a daily entry to the vault. This is a **scripted, non-LLM operation** — shell script, no token consumption. Model routing is **DEFAULT_MODEL** because this is routine operational reporting.

**What it produces:**

1. A Discord message in `⛏️sv2bot🤖` with current balance, 24h burn rate, and estimated days remaining.
2. A daily summary line appended to `$HOME/vault/ppq-readings/daily-report.md`.
3. If balance is critically low (below a configured threshold), a prominent ⚠️ warning in the Discord message.

**Script:**

```text
{baseDir}/scripts/ppq-daily-report.sh
```

Environment variables:

```text
SV2PI_PPQ_DAILY_DISCORD=0              # disable Discord posting
SV2PI_PPQ_DAILY_DISCORD_CHANNEL_ID=<id> # override target channel (default: 1501133804058710116)
SV2PI_PPQ_LOW_BALANCE_THRESHOLD=5.00    # $ balance below which to emit ⚠️ warning (default: 5.00)
SV2PI_PICORD_ENV=<path>                 # override Picord env file (default: /home/sv2bot/.picord/.env)
```

**Discord message format:**

```
💰 PPQ Balance Report — 2026-05-08

Balance: $18.79
24h burn: $0.17
7d avg burn: $0.15/day
Est. days remaining: ~125 days

⚠️ Balance below $5.00 threshold — top up soon.
```

The ⚠️ line only appears when balance is below the threshold. The message uses `allowed_mentions: {parse: []}` to avoid spurious pings. If posting fails, errors go to `/tmp/sv2pi-ppq-discord-post.log` and the script exits non-zero but does not abort the vault logging step.

**Vault daily log:**

```text
$HOME/vault/ppq-readings/daily-report.md
```

Each run appends a markdown list entry:

```markdown
- **2026-05-08:** $18.79 | 24h burn: $0.17 | ~125 days remaining
```

The script creates the file with a `# PPQ Daily Balance Log` header on first write if it doesn't exist.

**Timer/service:**

```ini
# ~/.config/systemd/user/sv2pi-ppq-daily-report.service
[Unit]
Description=Daily PPQ balance report (DEFAULT_MODEL)
After=network.target

[Service]
Type=oneshot
ExecStart=%h/.pi/agent/git/github.com/plebhash/sv2pi/skills/sv2pi/scripts/ppq-daily-report.sh
StandardOutput=journal
StandardError=journal
```

```ini
# ~/.config/systemd/user/sv2pi-ppq-daily-report.timer
[Unit]
Description=Daily PPQ balance Discord report

[Timer]
OnCalendar=daily
RandomizedDelaySec=180
Persistent=true
Unit=sv2pi-ppq-daily-report.service

[Install]
WantedBy=timers.target
```

**Commands:**

```bash
# Enable and start the timer
systemctl --user enable --now sv2pi-ppq-daily-report.timer

# Check timer status
systemctl --user list-timers sv2pi-ppq-daily-report.timer --no-pager

# Manual trigger (immediate run)
systemctl --user start sv2pi-ppq-daily-report.service

# Check logs
journalctl --user -u sv2pi-ppq-daily-report.service -n 20 --no-pager

# Disable
systemctl --user disable --now sv2pi-ppq-daily-report.timer
```

### Error Semantics

- **HTTP 402** may indicate insufficient credit for model requests.
- If model calls are failing and PPQ balance is low or zero, suggest topping up PPQ credits.
- If `models.json` is missing or `providers.ppq.apiKey` is absent, report that PPQ is not configured locally.
