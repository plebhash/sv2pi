# minerd — SV1 CPU Miner

minerd (cpuminer v2.5.1) is an SV1-compatible CPU miner used in sv2pi as an SV1 load generator. It connects to the Translator Proxy's SV1 downstream (port 34255), producing real share flow through the full SV2 pipeline.

**Scope:** `-a sha256d` only — other hashing algorithms are out of scope for sv2pi.

SV1 protocol reference: `{baseDir}/references/sv1-overview.md`

## Prerequisites

The Translator Proxy must be running and accepting SV1 connections on port 34255. See `{baseDir}/domains/translator.md` for deployment. Verify:

```bash
curl -sf http://localhost:9092/api/v1/sv1/clients | python3 -m json.tool
```

## Fetch Binary

```bash
eval "$(bash {baseDir}/scripts/fetch-minerd.sh)"
```

Downloads v2.5.1 from [GitHub releases](https://github.com/stratum-mining/cpuminer/releases/tag/v2.5.1) to `~/.sv2pi/minerd/v2.5.1/`. Auto-detects host platform (Linux/macOS) and architecture (x86_64/arm64). Sets `MINERD_BINARY` and `MINERD_VERSION`. Idempotent — skips download if binary is already installed and valid.

## CLI Quick Reference

| Flag | Meaning |
|---|---|
| `-a sha256d` | SHA-256d algorithm (Bitcoin) |
| `-o stratum+tcp://HOST:PORT` | Upstream Stratum endpoint |
| `-u USER` | Worker username |
| `-p PASS` | Worker password |
| `-O USER:PASS` | Combined credentials |
| `-t N` | Miner threads (default: auto-detect cores) |
| `-q` | Suppress per-thread hashmeter |
| `-P` | Dump protocol-level JSON-RPC messages |

Full man page: `minerd --help`

## Deployment Modes

### Adhoc — One-shot connections

```bash
bash {baseDir}/scripts/run-minerd-adhoc.sh <url> <user> <pass> <mode>
```

**Modes:**

| Mode | Behavior | Expected duration | Match string |
|---|---|---|---|
| `handshake` | Connects, completes SV1 handshake, exits | ~3s | `Stratum difficulty set to` |
| `oneshot` | Connects, completes handshake, submits one share, exits | 5–30s | `accepted:` |

Both modes timeout after 60s (configurable via `TIMEOUT_SECS`). Returns exit code 0 on success.

**Usage with multiple workers (N instances):** Run the script N times in a loop or background jobs with different usernames:

```bash
for i in $(seq 1 5); do
    bash {baseDir}/scripts/run-minerd-adhoc.sh stratum+tcp://127.0.0.1:34255 worker.${i} x handshake &
done
wait
```

### Sustained — Systemd-controlled background mining

```bash
bash {baseDir}/scripts/deploy-minerd-sustained.sh <url> <user_prefix> <pass> <mode> <instances> [--yes-overcommit]
```

**Parameter resolution:**

| Mode | Threads per instance | `-t` flag |
|---|---|---|
| `minimal` | 1 | `-t 1` |
| `full` | Auto-detect cores | (none — minerd auto-detects) |
| `1.5`, `2.5`, etc. | `ceil(mult × cores)` | `-t N` |

**User prefix:** workers are named `<user_prefix>.<N>` (e.g. `worker.1`, `worker.2`, …). All instances share the same password.

Each instance gets a systemd user unit at `~/.config/systemd/user/minerd-{N}.service` with `Restart=on-failure` and 10s restart delay.

**CRITICAL — Multi-instance resource warning:**

When `instances > 1`, the script calculates total allocated threads and **refuses to proceed** unless `--yes-overcommit` is passed. The agent must:

1. **Calculate the oversubscription ratio**: `instances × threads_per_instance ÷ CPU_cores`
2. **Print a prominent warning** describing total threads vs available cores, the oversubscription ratio, and potential consequences (system slowdown, OOM kills, degraded translator/pool performance, share loss)
3. **Ask for explicit confirmation**: *"This will allocate X threads across Y CPU cores — are you sure?"*
4. **Only pass `--yes-overcommit`** after the user confirms they understand the risks

For full-load (`mode=full`) with instances > 1, the oversubscription ratio is exactly `instances` — every core is already saturated with one instance. Adding more instances creates pure context switch overhead with no additional hashing throughput.

## Verification

### Adhoc

```bash
# Handshake: expect exit 0 in ~3s
bash {baseDir}/scripts/run-minerd-adhoc.sh stratum+tcp://127.0.0.1:34255 worker.1 x handshake

# Oneshot: expect exit 0 in 5-30s
bash {baseDir}/scripts/run-minerd-adhoc.sh stratum+tcp://127.0.0.1:34255 worker.1 x oneshot
```

### Sustained

```bash
systemctl --user status minerd-1
journalctl --user -u minerd-1 -f
```

### Cross-reference with Translator

```bash
# SV1 clients should appear when minerd connects
curl -s http://localhost:9092/api/v1/sv1/clients | python3 -m json.tool

# Shares flowing through the pipeline
curl -s http://localhost:9092/api/v1/server/channels | python3 -m json.tool
```

## Crash Diagnostics

| Symptom | Likely cause |
|---|---|
| `Connection refused` | Translator Proxy not running or wrong port |
| `JSON-RPC error` / `"error":null,"result":false` | Auth failure (wrong username/password) or protocol mismatch |
| `Stratum connection interrupted` | Network drop or server-side disconnect |
| `No suitable long-poll found` | Wrong scheme (http instead of stratum+tcp) |
| `Timed out after 60s` (oneshot) | Vardiff is too high — miner hasn't found a share within timeout |

```bash
# Systemd logs for sustained instances
journalctl --user -u minerd-1 --tail 50

# Check if translator is reachable
docker exec translator_sv2 sh -c 'echo | nc -w2 localhost 34255 2>/dev/null && echo "OK" || echo "UNREACHABLE"'
```
