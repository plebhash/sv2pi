## PPQ Credit Balance Check

The sv2bot agent uses PPQ (PayPerQ) as its LLM provider. Checking the PPQ credit balance is part of operational maintenance — low or zero balance can cause model calls to fail.

Use this when the user asks about:
- "PPQ credit" or "PayPerQ balance"
- "credits remaining" or "LLM provider balance"
- "why model calls are failing due to insufficient credit"

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

### Error Semantics

- **HTTP 402** may indicate insufficient credit for model requests.
- If model calls are failing and PPQ balance is low or zero, suggest topping up PPQ credits.
- If `models.json` is missing or `providers.ppq.apiKey` is absent, report that PPQ is not configured locally.

