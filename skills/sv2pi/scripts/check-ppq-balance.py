#!/usr/bin/env python3
import json
import sys
import urllib.error
import urllib.request

CONFIG_PATH = sys.argv[1] if len(sys.argv) > 1 else "/home/sv2bot/.pi/agent/models.json"

try:
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        models = json.load(f)

    cfg = models["providers"]["ppq"]
    api_key = cfg["apiKey"]
    base_url = cfg.get("baseUrl", "https://api.ppq.ai/v1").removesuffix("/")

    if base_url.endswith("/v1"):
        base_url = base_url[:-3]

    req = urllib.request.Request(
        base_url + "/credits/balance",
        data=b"{}",
        headers={
            "Content-Type": "application/json",
            "Authorization": "Bearer " + api_key,
        },
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=20) as resp:
        body = resp.read().decode("utf-8")
        data = json.loads(body)
        print(json.dumps({"ok": True, "balance": data.get("balance"), "raw": data}))

except KeyError as e:
    print(json.dumps({"ok": False, "error": "missing_config_key", "detail": str(e)}))
    sys.exit(1)
except FileNotFoundError:
    print(json.dumps({"ok": False, "error": "models_config_not_found", "path": CONFIG_PATH}))
    sys.exit(1)
except urllib.error.HTTPError as e:
    body = e.read().decode("utf-8", errors="replace")
    print(json.dumps({"ok": False, "error": "http_error", "status": e.code, "body": body}))
    sys.exit(1)
except Exception as e:
    print(json.dumps({"ok": False, "error": type(e).__name__, "detail": str(e)}))
    sys.exit(1)
