#!/usr/bin/env python3
"""Append current PPQ balance to vault readings CSV. Zero-token, no LLM.

Reads the API key from Pi models.json, probes PPQ /credits/balance,
and appends a line to $HOME/vault/ppq-readings/readings.csv.
Never prints the API key.
"""
import csv
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

MODELS_CONFIG = "/home/sv2bot/.pi/agent/models.json"
VAULT = os.environ.get("SV2PI_VAULT", os.path.expanduser("~/vault"))

READINGS_DIR = Path(VAULT) / "ppq-readings"
READINGS_CSV = READINGS_DIR / "readings.csv"


def probe_balance(config_path: str) -> dict:
    try:
        with open(config_path, "r", encoding="utf-8") as f:
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
            return {"ok": True, "balance": data.get("balance")}
    except KeyError as e:
        return {"ok": False, "error": "missing_config_key", "detail": str(e)}
    except FileNotFoundError:
        return {"ok": False, "error": "models_config_not_found", "path": config_path}
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        return {"ok": False, "error": "http_error", "status": e.code, "body": body}
    except Exception as e:
        return {"ok": False, "error": type(e).__name__, "detail": str(e)}


def main():
    result = probe_balance(MODELS_CONFIG)

    if not result["ok"]:
        print(f"ppq-log-reading: probe failed: {result.get('error','unknown')}", file=sys.stderr)
        sys.exit(1)

    balance = result["balance"]
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    READINGS_DIR.mkdir(parents=True, exist_ok=True)

    write_header = not READINGS_CSV.exists()
    with open(READINGS_CSV, "a", newline="") as f:
        writer = csv.writer(f)
        if write_header:
            writer.writerow(["timestamp", "balance"])
        writer.writerow([timestamp, balance])

    # Silent success — this is a fire-and-forget operation
    sys.exit(0)


if __name__ == "__main__":
    main()
