---
name: sv2pi
description: Agentic deployment of the Stratum V2 Reference Implementation (SRI) for Bitcoin mainnet. Use when deploying or managing Docker-based SRI apps (pool_sv2, jd_client_sv2, translator_sv2, sv2_tp) alongside Bitcoin Core with IPC. Also use for crash diagnostics and health monitoring of already-deployed SRI instances. Scope is strictly production mainnet — not for development, testing, or devnet work.
---

# sv2pi — SRI Agentic Deployment

Agentic deployment skill for the [Stratum V2 Reference Implementation](https://github.com/stratum-mining) on Bitcoin mainnet.

This skill deploys Bitcoin Core and four SRI-related Docker roles:
| Role | Docker Image |
|---|---|
| Bitcoin Core | `bitcoin/bitcoin:latest` |
| Sv2 Template Provider | `stratumv2/sv2-tp` |
| Pool (with embedded JDS) | `stratumv2/pool_sv2` |
| Job Declarator Client (JDC) | `stratumv2/jd_client_sv2` |
| Translator Proxy (SV1→SV2 bridge) | `stratumv2/translator_sv2` |

**sv2-ui** (`stratumv2/sv2-ui`) is planned for a follow-up release and is currently out of scope. If a user asks about sv2-ui, acknowledge it is on the roadmap but not yet available in this skill.

Helper scripts at `{baseDir}/scripts/`. Reference docs at `{baseDir}/references/`.

---

## Stateful Context Model

You build a stateful mental model of deployed SRI instances from four sources:

1. **SV2 Operations Wiki** — Persistent operator memory lives at `$HOME/wiki` (`/home/sv2bot/wiki` on this VPS). It is an LLM Wiki vault managed by `pi-llm-wiki`; read it before making deployment-health claims or operational recommendations.
2. **SV2 Protocol Spec** — Understand what each app does and how they connect. See `{baseDir}/references/sv2-spec-overview.md`.
3. **Log Observation** — Analyze the source code first to understand log format and error patterns, then grep logs for those patterns. NEVER load entire log files into context — they are too large and will burn tokens. Always use `--tail N` or pipe through `grep`.
4. **HTTP API Probing** — Probe monitoring endpoints described in `{baseDir}/references/sv2-apps/monitoring-api.md`. This provides real-time hashrate, channel count, connected clients, shares accepted, and block data.

Use all four sources together. The wiki gives durable cross-session context and operator directives. Logs give operational detail. APIs give quantitative state. Source code gives authoritative semantics.

**Concurrent human operators:** The stateful model is not authoritative. Human operators may concurrently interact with containers (stop, restart, reconfigure them). Always re-validate container state with `docker ps` before running any operation that depends on a running container. Never assume a previously-running container is still up.

---

## Persistent Operations Wiki (`pi-llm-wiki`)

The sv2pi agent uses the `pi-llm-wiki` extension as persistent, Obsidian-compatible memory for this production VPS.

### Vault location

- Canonical vault root: `$HOME/wiki` (`/home/sv2bot/wiki`)
- Do **not** recreate or rely on the removed legacy symlink `/home/sv2bot/.pi/agent/obsidian -> /home/sv2bot/wiki`.
- Open and maintain `$HOME/wiki` directly.

### Mandatory read-before-act workflow

Before answering questions about deployment health, missing roles, crash state, operator intent, or whether to deploy/stop/restart anything:

1. Read `$HOME/wiki/README.md` first.
2. Read the relevant operational pages, especially:
   - `$HOME/wiki/deployment/overview.md`
   - `$HOME/wiki/deployment/bitcoin-core.md`
   - `$HOME/wiki/deployment/pool-sv2.md`
   - `$HOME/wiki/deployment/jd-client.md`
   - `$HOME/wiki/deployment/translator.md`
   - recent files under `$HOME/wiki/interventions/` and `$HOME/wiki/incidents/` when applicable
3. Re-validate live state with `docker ps -a` and targeted probes before acting.
4. After any meaningful action or discovery, update the appropriate wiki page(s) so future sessions inherit the new state.

### Wiki layout and ownership

The vault is a migrated operations knowledge base plus a standard `pi-llm-wiki` four-layer wiki:

```text
$HOME/wiki/
├── README.md                  # top-level operator directives and usage instructions
├── deployment/                # migrated sv2pi operational state pages
├── interventions/             # operator/agent intervention records
├── incidents/                 # crash reports and incident analyses
├── raw/sources/               # immutable source packets; extension-owned
├── wiki/                      # editable LLM Wiki pages: sources/entities/concepts/syntheses/analyses
├── meta/                      # auto-generated registry/backlinks/log; extension-owned
└── .wiki/                     # extension config/templates
```

Respect the `pi-llm-wiki` rules:

- Never edit `$HOME/wiki/raw/`; capture new sources with `wiki_capture_source`.
- Never edit `$HOME/wiki/meta/`; metadata is extension-generated.
- Editable knowledge lives in `$HOME/wiki/wiki/` and the migrated sv2pi operations directories (`deployment/`, `interventions/`, `incidents/`).
- Cross-reference durable notes with Obsidian `[[wikilinks]]` where useful.

### Using wiki tools

Use the `pi-llm-wiki` tools when maintaining structured knowledge:

- `wiki_search` before creating new canonical pages, to avoid duplicates.
- `wiki_capture_source` for URLs, local files, or pasted text that should become immutable evidence.
- `wiki_ingest` after capture, then read `raw/sources/SRC-*/extracted.md` and synthesize into editable pages.
- `wiki_ensure_page` for canonical entity/concept/synthesis/analysis pages.
- `wiki_lint` for health checks and `wiki_rebuild_meta` only if metadata appears out of sync.
- `wiki_log_event` for significant operational decisions when a structured event is useful.

For direct operational pages in migrated directories, use normal file tools (`read`, `edit`, `write`) and keep entries concise, dated, and factual.

### Operator directives in the wiki are binding

If `$HOME/wiki/README.md` or a deployment/intervention page contains a permanent operator directive, treat it as higher-priority operational context for this deployment. Example currently recorded in the vault: `jd_client_sv2` must not be deployed on this VPS, and its absence is expected rather than a fault. Always re-read the wiki to confirm current directives before discussing role topology.

### 🧠 Quartz 4 Web Publishing 🖥️

The wiki is sv2pi's **long-term brain** 🧠 — a living, evolving knowledge-base that persists across agent sessions and serves both the agent and human operators. **Quartz 4** publishes this brain as a web-browsable, hyperlinked wiki so humans can explore the full operational picture with their own eyes.

Quartz 4 is an open-source static site generator for Obsidian-flavored markdown vaults. It converts `$HOME/wiki/` into a navigable website with backlinks, graph view, full-text search, and dark mode.

#### Terminology: serve vs publish

| Term | Meaning | Agent behavior |
|---|---|---|
| **serve raw vault** | Browse markdown files/directories as plain text | Use Caddy `file_server browse` on the wiki vault root — this is the **wrong** default |
| **publish wiki** 🧠💻 | Build with Quartz and serve the generated HTML (Obsidian Publish style) | Build with `npx quartz build`, serve `quartz/public/` via Caddy — this is the **correct** default |

When a user says "serve wiki," "publish wiki," or "show the brain," they mean **publish wiki** — Quartz-generated HTML, not raw markdown. The raw vault is never the intended UX.

#### Pre-flight: read vault intent before serving

Before deciding how to serve, read these files in order to determine if Quartz/Obsidian Publish is expected:

1. `$HOME/wiki/README.md` — top-level directives; may specify "quartz4 self-hosted obsidian publish-compatible server" and the target URL
2. `$HOME/wiki/.wiki/config.json` — extension config; may list target port/interface
3. `$HOME/wiki/WIKI_SCHEMA.md` — vault layout schema; may reference Quartz

If any of these reference Quartz, Obsidian Publish, or port 4028 → **build and serve with Quartz**, never serve the raw vault.

#### Pre-flight: discover existing serving infrastructure

Before creating a new listener, check what's already running:

```bash
# Existing listeners (look for Caddy, nginx, http-server)
ss -ltnp | grep -E ':4028|:80|:443|:8080|:3000|caddy|nginx'

# Existing user systemd services
systemctl --user list-units --type=service --all | grep -Ei 'caddy|nginx|proxy|serve|web|quartz|wiki'

# Existing Caddy configs (common patterns)
find /home/sv2bot/.config -maxdepth 4 -iname 'Caddyfile' -type f 2>/dev/null
find /etc/caddy -maxdepth 2 -iname 'Caddyfile' -type f 2>/dev/null

# WireGuard interface and IP
ip -br addr show | grep wg
wg show 2>/dev/null || true
```

**Prefer extending an existing WireGuard-bound Caddy service** over creating a competing server. If a Caddyfile already binds to the WireGuard IP (e.g. `10.0.0.1`), add the Quartz site block to that same config and reload.

#### Deployment modes (network interface)

| Mode | Interface | Visibility | When to use |
|---|---|---|---|
| `wg0` | WireGuard VPN | Restricted to VPN peers | Day-to-day operations — keep the brain within the trusted VPN 🧠🔒 |
| `eth0` | Public NIC | Exposed to the WWW | Public transparency or remote access without VPN 🧠🌐 |

The default port is **4028**. The agent binds Caddy to the interface IP (not `0.0.0.0`) so the wiki is only reachable via that interface.

#### Firewall policy: probe, never tweak

**The agent must NEVER modify firewall rules.** Before deploying Quartz, probe the target interface to detect whether port 4028 is reachable:

```bash
sudo iptables -L INPUT -n --line-numbers | grep -E '4028|dpt:4028'
sudo ufw status | grep 4028
```

If port 4028 is blocked and the user wants that interface:
- 🧠 Tell the operator: `"port 4028 is blocked on <iface> — human operator must open it"`
- 🧠 Suggest the exact ufw/iptables command (e.g. `sudo ufw allow in on wg0 to any port 4028`)
- 🧠 Wait for operator confirmation before proceeding

#### One-shot deploy recipe: Quartz build → Caddy serve

This is the full end-to-end recipe. Follow sequentially — no steps skipped.

##### Step Q1 — Install or locate Quartz 4

```bash
# Clone Quartz 4 if not already present
if [ ! -d ~/quartz ]; then
  git clone --depth 1 https://github.com/jackyzha0/quartz.git ~/quartz
fi
cd ~/quartz && npm ci
```

##### Step Q2 — Configure quartz.config.ts

Read the existing config, then edit these key fields:

```bash
cd ~/quartz
```

| Setting | Value | Why |
|---|---|---|
| `pageTitle` | `"sv2bot wiki"` 🧠 | Shows in browser tab and site header |
| `baseUrl` | `"WIREGUARD_IP:4028"` | Must match the WireGuard IP from pre-flight (e.g. `10.0.0.1`) |
| `ignorePatterns` | `["private", "templates", ".obsidian", ".wiki", "raw", "outputs"]` | Skip extension-owned dirs and internal content; only publish `deployment/`, `interventions/`, `incidents/`, `wiki/`, and `index.md` |
| `Plugin.CustomOgImages()` | Comment it out | Speeds up builds; OG images are expensive and unnecessary for internal ops |

Update `baseUrl` dynamically from the detected WireGuard IP. Update `ignorePatterns` to exclude pi-llm-wiki internal directories.

##### Step Q3 — Ensure root index.md

Quartz requires a root `index.md` as the homepage. If missing, create one:

```bash
cat > $HOME/wiki/index.md <<'EOF'
---
title: sv2bot wiki
---

# sv2bot wiki 🧠

Welcome to the sv2bot knowledge base, published with Quartz.

Start here:

- [[deployment/overview|Deployment Overview]]
- [[wiki/index|LLM Wiki]]
- [[interventions/index|Interventions]]
- [[incidents/index|Incidents]]
EOF
```

##### Step Q4 — Build the static site

```bash
cd ~/quartz
rm -rf public
npx quartz build -d $HOME/wiki -o public
```

This reads the vault at `$HOME/wiki`, applies Quartz transformations, and emits static HTML/JS/CSS to `~/quartz/public/`. The build takes ~2–10s depending on vault size.

##### Step Q5 — Serve with Caddy bound to WireGuard IP only

Add (or extend) a Caddy site block. **Never** bind `0.0.0.0` — bind to the specific WireGuard IP:

```caddy
http://10.0.0.1:4028 {
    bind 10.0.0.1
    root * /home/sv2bot/quartz/public
    try_files {path} {path}.html {path}/ =404
    file_server
}
```

- `root * /home/sv2bot/quartz/public` — serve the **built Quartz output**, not the raw vault
- `try_files {path} {path}.html {path}/ =404` — enable pretty URLs like `/deployment/overview` (without `.html`)
- `bind 10.0.0.1` — restrict to WireGuard IP only 🧠🔒
- `file_server` (without `browse`) — directory listing disabled for security

If an existing Caddy user service is already running and bound to the WireGuard IP, add this site block to the existing Caddyfile. If no Caddy service exists, create one:

```bash
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/sv2bot-quartz-caddy.service <<'EOF'
[Unit]
Description=Caddy reverse proxy for sv2bot Quartz wiki
After=network.target

[Service]
Type=notify
ExecStart=/usr/bin/caddy run --config %h/.config/sv2bot-quartz-caddy/Caddyfile --adapter caddyfile
ExecReload=/usr/bin/caddy reload --config %h/.config/sv2bot-quartz-caddy/Caddyfile --adapter caddyfile
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

mkdir -p ~/.config/sv2bot-quartz-caddy
# Write the Caddyfile (with the site block above) to ~/.config/sv2bot-quartz-caddy/Caddyfile
systemctl --user daemon-reload
systemctl --user enable --now sv2bot-quartz-caddy.service
```

Validate and reload:

```bash
caddy validate --config ~/.config/sv2bot-quartz-caddy/Caddyfile --adapter caddyfile
systemctl --user reload sv2bot-quartz-caddy.service
```

##### Step Q6 — Auto-rebuild on wiki changes 🧠🔄

The published site must stay in sync with the vault. Add a systemd user path watcher that rebuilds Quartz whenever wiki files change:

```bash
cat > ~/.config/systemd/user/sv2bot-quartz-build.service <<'EOF'
[Unit]
Description=Build sv2bot wiki Quartz static site

[Service]
Type=oneshot
WorkingDirectory=%h/quartz
Environment=PATH=%h/.local/share/pi-node/node-v22.22.2-linux-x64/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=%h/.local/bin/build-sv2bot-quartz
EOF

cat > ~/.local/bin/build-sv2bot-quartz <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd ~/quartz
exec npx quartz build -d ~/wiki -o ~/quartz/public
EOF
chmod +x ~/.local/bin/build-sv2bot-quartz

cat > ~/.config/systemd/user/sv2bot-quartz-build.path <<'EOF'
[Unit]
Description=Watch sv2bot wiki markdown files and rebuild Quartz site

[Path]
PathModified=%h/wiki
PathModified=%h/wiki/deployment
PathModified=%h/wiki/interventions
PathModified=%h/wiki/incidents
PathModified=%h/wiki/wiki
PathModified=%h/wiki/meta
Unit=sv2bot-quartz-build.service

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now sv2bot-quartz-build.path
```

Now any wiki edit triggers a rebuild within seconds. The build output goes to `~/quartz/public/` which Caddy is already serving.

**Note:** adapt `Environment=PATH` to the actual `pi-node` install path. Use `which node` to find it.

##### Step Q7 — Validate: Quartz UI, not raw markdown

After deploy, run ALL of these checks. Success requires every check to pass:

```bash
# 1. Listener is WireGuard-bound ONLY (not 0.0.0.0)
ss -ltnp | grep ':4028'
# Expected: 10.0.0.1:4028 ... users:(("caddy",...))
# Reject:   0.0.0.0:4028  → over-exposed, fix the bind directive

# 2. Root returns text/html (not text/markdown or text/plain)
curl -s -o /dev/null -w '%{content_type}' http://10.0.0.1:4028/
# Expected: text/html (or text/html; charset=utf-8)

# 3. HTML contains the Quartz site title
curl -s http://10.0.0.1:4028/ | grep -o '<title>[^<]*</title>'
# Expected: <title>sv2bot wiki</title>

# 4. Pretty routes work (no .html extension)
curl -s -o /dev/null -w '%{http_code}' http://10.0.0.1:4028/deployment/overview
# Expected: 200 (redirect to /deployment/overview.html is acceptable)

# 5. Static assets exist (Quartz JS/CSS)
curl -s -o /dev/null -w '%{http_code}' http://10.0.0.1:4028/static/contentIndex.json
# Expected: 200

# 6. Raw vault is NOT served directly
curl -s -o /dev/null -w '%{http_code}' http://10.0.0.1:4028/README.md
# Expected: 404 (raw markdown should not be browsable)
```

**If any check fails:** the deployment is incomplete. Diagnose and fix before reporting "done."

##### Step Q8 — Manual rebuild

After any manual wiki edit that you want to publish immediately (without waiting for the path watcher):

```bash
systemctl --user start sv2bot-quartz-build.service
```

Or directly:

```bash
cd ~/quartz && npx quartz build -d ~/wiki -o ~/quartz/public
```

##### Summary checklist 🧠✅

| # | Step | Must not skip |
|---|---|---|
| Q0 | Pre-flight: read vault README + detect existing infra | ✅ |
| Q1 | Install/locate Quartz 4 | |
| Q2 | Configure quartz.config.ts | ✅ |
| Q3 | Ensure root index.md | ✅ |
| Q4 | Build static site | |
| Q5 | Serve with Caddy, WireGuard-bound only | |
| Q6 | Auto-rebuild path watcher | |
| Q7 | **Validate** Quartz UI (all 6 checks) | ✅ |
| Q8 | (Ongoing) manual rebuild on demand | |

Human operators can bookmark the Quartz URL and browse the brain alongside the agent's real-time probes. Think of it as a split-screen console: the agent works the terminal while the human watches the evolving knowledge graph 🧠💻.

---

## Architecture Quick Reference

### Mode A: Direct IPC (no sv2-tp)

```
bitcoin_core (docker) ──(IPC)──► pool_sv2 (with embedded JDS)
  ~/.sv2pi/bitcoin/data           ├── Stratum: 0.0.0.0:3333
                                  └── JDS:     0.0.0.0:3334
                                          ▲
                                          │ (JD protocol)
bitcoin_core (same volume) ──(IPC)──► jd_client_sv2
                                          ├── Downstream: 0.0.0.0:34265
                                          └── Upstream:   pool:3333 + pool:3334 (JDS)
                                                  ▲
                                                  │ (SV2 Mining Protocol)
                                        translator_sv2
                                          ├── Downstream (SV1): 0.0.0.0:34255  ← SV1 miners connect here
                                          └── Upstream (SV2):   jdc:34265
```

### Mode B: With sv2-tp (Template Distribution Protocol)

```
bitcoin_core (docker) ──(IPC)──► sv2_tp
  ~/.sv2pi/bitcoin/data           └── Template Distribution: 0.0.0.0:8442
                                                ▲
                        ┌───────────────────────┴───────────────────────┐
                        │                                               │
              pool_sv2 (embedded JDS)                         jd_client_sv2
              ├── Stratum: 0.0.0.0:3333                      ├── Downstream: 0.0.0.0:34265
              └── JDS:     0.0.0.0:3334                      └── Upstream:   pool:3333 + pool:3334
                        ▲                                               ▲
                        │ (JD protocol)                                 │
                        └───────────────────────────────────────────────┘
                                                ▲
                                                │ (SV2 Mining Protocol)
                                      translator_sv2
                                      ├── Downstream (SV1): 0.0.0.0:34255  ← SV1 miners connect here
                                      └── Upstream (SV2):   jdc:34265
```

In Mode B, Pool and JDC use `[template_provider_type.Sv2Tp]` with `address = "127.0.0.1:8442"` instead of `BitcoinCoreIpc`.

See `{baseDir}/references/architecture.md` for full detail.

---

## Workflow

### Step 1 — Select Deployment Tag

Ask the user: **"Which SRI Docker Hub tag? (`main` or a version like `v0.3.5`)"**

Store as `DEPLOY_TAG`. If the user doesn't specify, default to `main`.

**Compatibility constraint:** The SRI tag and Bitcoin Core version must be compatible. `{baseDir}/references/sv2-apps/bitcoin-core-version.md` contains a reverse-lookup table. After deploying Bitcoin Core, when the user selects an SRI tag, check this table. If the pair is incompatible, tell the user which SRI tags are supported for that Bitcoin Core version and ask them to choose again.

### Step 2 — Load Source and Config Context

**Docker config templates for past releases are frozen in this skill** at `{baseDir}/references/sv2-apps/docker-templates/{tag}/`. No clone needed for known tags — read them directly:

```
{baseDir}/references/
├── sv2-apps/
│   ├── config-reference.md              ← semantic explanations of every parameter
│   ├── monitoring-api.md                ← HTTP monitoring API for all roles
│   ├── bitcoin-core-version.md          ← BTC Core version compatibility matrix
│   └── docker-templates/
│       ├── v1.1.0/                      ← frozen sv2-tp v1.1.0
│       ├── v0.3.5/                      ← frozen at v0.3.5
│       ├── v0.3.4/
│       ├── v0.3.3/
│       ├── v0.3.2/
│       ├── v0.3.1/
│       ├── v0.3.0/
│       ├── v0.2.0/
│       └── v0.1.0/
├── architecture.md                      ← SRI app architecture
└── sv2-spec-overview.md                 ← SV2 protocol overview
```

**If the user selected a tagged release (e.g. `v0.3.5`):**

Read the frozen Docker config templates directly:

```bash
cat {baseDir}/references/sv2-apps/docker-templates/$DEPLOY_TAG/docker_env.example
cat {baseDir}/references/sv2-apps/docker-templates/$DEPLOY_TAG/pool-jds-config.toml.template
cat {baseDir}/references/sv2-apps/docker-templates/$DEPLOY_TAG/jdc-config.toml.template
cat {baseDir}/references/sv2-apps/docker-templates/$DEPLOY_TAG/translator-proxy-config.toml.template
```

If the selected tag does not exist in the frozen references (future release), clone `sv2-apps` at that tag:

```bash
git clone --branch $DEPLOY_TAG --depth 1 https://github.com/stratum-mining/sv2-apps /tmp/sv2-apps-$DEPLOY_TAG
cat /tmp/sv2-apps-$DEPLOY_TAG/docker/docker_env.example
cat /tmp/sv2-apps-$DEPLOY_TAG/docker/config/*.toml.template
```

**If the user selected `main`:**

`main` is a **rolling branch** — it changes continuously. There is no frozen snapshot for it. You must fetch the live `docker/config` templates at runtime:

```bash
git clone --depth 1 https://github.com/stratum-mining/sv2-apps /tmp/sv2-apps-main
cat /tmp/sv2-apps-main/docker/docker_env.example
cat /tmp/sv2-apps-main/docker/config/pool-jds-config.toml.template
cat /tmp/sv2-apps-main/docker/config/jdc-config.toml.template
cat /tmp/sv2-apps-main/docker/config/translator-proxy-config.toml.template
```

File layout inside `/tmp/sv2-apps-main/docker/config/` mirrors the frozen release directories — the agent applies the same reading logic, just from a live source.

Also clone `sv2-spec` for protocol context and `sv2-apps` source for log comparison:

```bash
git clone --depth 1 https://github.com/stratum-mining/sv2-spec ~/.cache/sv2pi/sv2-spec 2>/dev/null || true
git clone --branch $DEPLOY_TAG --depth 1 https://github.com/stratum-mining/sv2-apps ~/.cache/sv2pi/sv2-apps-$DEPLOY_TAG 2>/dev/null || \
git clone --depth 1 https://github.com/stratum-mining/sv2-apps ~/.cache/sv2pi/sv2-apps-$DEPLOY_TAG
```

**CRITICAL: Understand every parameter.** For semantic explanations of each parameter — what it controls in the SV2 protocol, valid values, tradeoffs, and which keys must be replaced for production — load `{baseDir}/references/sv2-apps/config-reference.md`.

### Step 3 — Verify Bitcoin Core Version Compatibility

Before deploying, determine the minimum Bitcoin Core version for this SRI release:

```bash
cat {baseDir}/references/sv2-apps/bitcoin-core-version.md
```

The agent must know the required version before running `deploy-bitcoin.sh`:
- **`main`** → Bitcoin Core v31.0 (bitcoin_core_sv2 v0.2.0)
- **v0.3.5 through v0.1.0** → Bitcoin Core v30.2
- **sv2-tp v1.1.0** → Bitcoin Core v31.0 (uses `stratumv2/sv2-tp:v1.1.0`)

If using a tag not in the frozen references, clone `sv2-apps` and check `bitcoin-core-sv2/README.md` for the exact version requirement.

### Step 4 — Deploy Bitcoin Core

If the user explicitly says "deploy Bitcoin Core", run the deploy script. Do NOT run `check-bitcoin.sh` first — it's only for the "already running" case below. The user asked to deploy; deploy.

If the user didn't specify a tag, ask: *"Which tag? (`latest`, `31.0`, `30.2`)"* The compatibility matrix at `{baseDir}/references/sv2-apps/bitcoin-core-version.md` maps SRI releases to minimum BTC Core versions.

**Deploy:**

```bash
bash {baseDir}/scripts/deploy-bitcoin.sh $BTC_TAG
export BITCOIN_IPC_PATH="$HOME/.sv2pi/bitcoin/data/node.sock"
```

After running the script, export the IPC path and move immediately to Step 5. Do NOT probe the deployment (no curl health checks, no `ls -la node.sock`, no `bitcoin-cli`). The script succeeds = deployment succeeded. The host data dir is root-owned (Docker volumes), so `ls` from the host user will fail — this is normal and irrelevant; SRI containers run as root.

**After deployment:** look up the BTC Core → SRI mapping in `{baseDir}/references/sv2-apps/bitcoin-core-version.md`. When the user later picks an SRI tag, only suggest compatible ones. If the user requests an incompatible pair, refuse and show the valid mappings.

If the script fails with a Docker permission error:
```bash
sudo usermod -aG docker $USER && newgrp docker
```
Or prefix with `sg docker -c "..."` if already in the group but the current shell lacks it.

**Existing Bitcoin Core** (only if the user says they already have it running):

```bash
bash {baseDir}/scripts/check-bitcoin.sh
export BITCOIN_IPC_PATH   # use the path it outputs
```

### Step 5 — Deploy SV2 Template Provider (sv2-tp)

**sv2-tp is optional but recommended** for production deployments. It decouples the SRI apps from direct Bitcoin Core IPC by serving the Template Distribution Protocol over TCP. This provides better fault isolation — sv2-tp handles IPC reconnection so Pool and JDC don't need direct IPC socket access.

**Compatibility check before deploying:** sv2-tp v1.1.0 requires Bitcoin Core v31.0+. If deploying against v30.2, use sv2-tp v1.0.6. Check `{baseDir}/references/sv2-apps/bitcoin-core-version.md` for the full matrix.

Deploy:

```bash
bash {baseDir}/scripts/deploy-tp.sh v1.1.0 $HOME/.sv2pi/bitcoin/data mainnet
```

This:
- Pulls `stratumv2/sv2-tp:v1.1.0`
- Connects to Bitcoin Core via IPC (`-ipcconnect=unix`) through the shared datadir volume
- Listens for Template Distribution Protocol connections on port 8442 (mainnet default)
- Binds `0.0.0.0:8442` by default (access from other containers)

**The script outputs the address for Pool/JDC configuration.** After deploying sv2-tp, Pool and JDC must use `Sv2Tp` instead of `BitcoinCoreIpc`:

```toml
# In pool-config.toml or jdc-config.toml:
[template_provider_type.Sv2Tp]
address = "127.0.0.1:8442"
```

Do NOT probe the deployment after the script succeeds.

### Step 6 — Deploy Pool (with embedded JDS)

**CRITICAL:** Never deploy to production with the default keypairs from the Docker config templates. The pool's `authority_public_key`/`authority_secret_key` and the JDC's keypair must be unique per deployment. Generate fresh keys:

```bash
bash {baseDir}/scripts/generate-keypair.sh
```

This uses `key-utils` (the official SRI key generation crate) inside a Dockerized Rust environment — no local Rust toolchain needed. The output is a base58-encoded secp256k1 keypair in TOML-ready format.

**Security tradeoff:** The generated private keys are exposed to the LLM context and potentially exposed to LLM providers. This is a deliberate tradeoff of agentic deployments in sv2pi — the user accepts this. Encourage the user to ask the agent to rotate keys across deployments.

Generate **two** secp256k1 keypairs: one for the pool app, one for the JDC app. Copy the pool's `authority_public_key` into the JDC's `[[upstreams]].authority_pubkey`. The JDC's own authority keypair is separate and used for downstream Translator connections.

If the user has already reviewed the config templates (Step 2) and agrees to use defaults, deploy directly:

```bash
bash {baseDir}/scripts/deploy-pool.sh $DEPLOY_TAG $BITCOIN_IPC_PATH
```

If the user's request is vague (e.g. "deploy a pool"), walk them through each configuration choice from the frozen Docker config template, offering the default value each time. Key parameters:

| Parameter | Default | Ask |
|---|---|---|
| `coinbase_reward_script` | `addr(...)` (SRI community wallet) | "What payout address? (default: SRI community wallet)" |
| `listen_address` | `0.0.0.0:3333` | "Stratum port? (default 3333)" |
| `JDS listen_address` | `0.0.0.0:3334` | "JDS port? (default 3334)" |
| `shares_per_minute` | `6.0` | "Target shares/minute? (default 6)" |
| `pool_signature` | `SRI Mainnet Pool` | "Pool signature string?" |
| Authority keypair | hardcoded example | Warn: "Replace with your own keypair for production" |

Never ask about ports/values the user already specified. If the user says "use defaults", deploy immediately.

After the script succeeds, move to Step 7. Do NOT probe the deployment.

### Step 7 — Deploy JD Client

```bash
bash {baseDir}/scripts/deploy-jd.sh $DEPLOY_TAG $BITCOIN_IPC_PATH
```

This:
- Creates `~/.sv2pi/jdc/config/` and writes `jdc-config.toml`
- Configures upstream to pool on localhost:3333 and JDS on localhost:3334
- Exposes port 34265 (downstream), 9091 (monitoring)

**If sv2-tp is deployed**, the JDC's template provider must be changed from `BitcoinCoreIpc` to `Sv2Tp`. The generated config uses IPC by default — the agent must update `[template_provider_type]` accordingly.

After deployment, verify:
```bash
docker logs jd_client_sv2 --tail 20
curl -s http://localhost:9091/api/v1/health
```

### Step 8 — Deploy Translator Proxy

```bash
bash {baseDir}/scripts/deploy-translator.sh $DEPLOY_TAG
```

This:
- Creates `~/.sv2pi/translator/config/` and writes `tproxy-config.toml`
- Upstream points to JDC on localhost:34265
- Exposes port 34255 (SV1 downstream), 9092 (monitoring)

After deployment, verify:
```bash
docker logs translator_sv2 --tail 20
curl -s http://localhost:9092/api/v1/health
curl -s http://localhost:9092/api/v1/sv1/clients
```

### Step 9 — Verify Full Deployment

Run a comprehensive health check across all roles:

```bash
# All monitoring endpoints
for endpoint in 9090 9091 9092; do
  echo "--- Port $endpoint ---"
  curl -sf http://localhost:$endpoint/api/v1/health | python3 -m json.tool 2>/dev/null || echo "UNREACHABLE"
done

# Container status (including sv2-tp)
docker ps --filter "name=pool_sv2" --filter "name=jd_client_sv2" --filter "name=translator_sv2" --filter "name=sv2_tp" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# SV2 Template Provider status
docker logs sv2_tp --tail 10
```

### Step 10 — Build Stateful Representation

Probe detailed monitoring endpoints and build a mental model:

```bash
# Pool state
curl -s http://localhost:9090/api/v1/server/channels | python3 -m json.tool
curl -s http://localhost:9090/api/v1/clients | python3 -m json.tool

# JDC state
curl -s http://localhost:9091/api/v1/server/channels | python3 -m json.tool
curl -s http://localhost:9091/api/v1/clients | python3 -m json.tool

# Translator state (includes SV1 clients)
curl -s http://localhost:9092/api/v1/sv1/clients | python3 -m json.tool
curl -s http://localhost:9092/api/v1/server/channels | python3 -m json.tool
```

Track these metrics over time:
| Metric | What it means |
|---|---|
| `server.channels` count | Active mining connections at each hop |
| `server.hashrate_total` | Aggregate hashrate |
| `clients[].hashrate_total` | Per-client hashrate |
| `shares_accepted_total` | Cumulative accepted shares |
| `sv1.clients` count | Legacy SV1 miners connected |

---

## Crash Diagnostics

When something fails:

### 1. Check Container Status
```bash
docker ps -a --filter "name=pool_sv2" --filter "name=jd_client_sv2" --filter "name=translator_sv2" --filter "name=sv2_tp"
```

### 2. Inspect Logs Against Source

**NEVER load entire log files into context.** Logs can be hundreds of MB. Always use source-code-informed grepping.

1. **Analyze source first.** Read the relevant source files at `~/.cache/sv2pi/sv2-apps-$DEPLOY_TAG/` to identify log message formats, error strings, and diagnostic patterns:

| App | Key source paths |
|---|---|---|
| sv2-tp | `src/sv2/` (template_provider, connman, messages, noise, transport) |
| Pool | `pool-apps/pool/src/` |
| JDC | `miner-apps/jd-client/src/` |
| Translator | `miner-apps/translator/src/` |
| Monitoring | `stratum-apps/src/monitoring/` |

2. **Grep with source-derived patterns.** Use the error strings and log patterns found in source code to filter logs:

```bash
# Example: grep pool logs for connection errors
docker logs pool_sv2 --tail 200 | grep -E 'error|Error|ERR|fail|timeout|rejected'

# Example: grep for IPC-related errors
docker logs pool_sv2 --tail 200 | grep -i 'ipc\|template\|socket'
```

Adjust the `--tail` count based on recency (100 for recent crashes, 500 for broader context). Always pipe through `grep` — never `cat` the raw log output.

### 3. Check Connectivity
```bash
# Can JDC reach pool?
docker exec jd_client_sv2 sh -c 'echo | nc -w2 pool_host 3333 && echo "POOL REACHABLE" || echo "POOL UNREACHABLE"'

# Can translator reach JDC?
docker exec translator_sv2 sh -c 'echo | nc -w2 jdc_host 34265 && echo "JDC REACHABLE" || echo "JDC UNREACHABLE"'

# Is Bitcoin IPC mounted?
docker exec pool_sv2 ls -la /bitcoin/node.sock
```

### 4. Check Bitcoin Core and sv2-tp
```bash
# Verify container is running
docker ps --filter name=bitcoin_core
docker ps --filter name=sv2_tp

# Check IPC socket inside SRI containers
docker exec pool_sv2 ls -la /bitcoin/node.sock 2>/dev/null || echo "IPC socket not visible to pool"
docker exec sv2_tp ls -la /home/bitcoin/.bitcoin/node.sock 2>/dev/null || echo "IPC socket not visible to sv2-tp"

# Check sv2-tp IPC connection status
docker logs sv2_tp --tail 20 | grep -i 'connect\|ipc\|error'

# Check sync status
docker exec bitcoin_core bitcoin-cli getblockchaininfo 2>/dev/null | grep -E 'blocks|verificationprogress'

# Check logs
docker logs bitcoin_core --tail 50
docker logs sv2_tp --tail 50
```

### 5. Config Validation
Compare running configs against example configs from the source:

```bash
diff ~/.sv2pi/pool/config/pool-config.toml ~/.cache/sv2pi/sv2-apps-$DEPLOY_TAG/config-examples/mainnet/pool-config-bitcoin-core-ipc-example.toml || true
```

---

## Keypair Management

Deployment scripts use example/test keypairs by default. For production mainnet:

1. Generate unique Noise authority keypairs (ed25519-based, base58-encoded, 44 chars each)
2. Pool and JDC each need their own keypair
3. The `[[upstreams]]` section in JDC and translator configs must reference the correct `authority_pubkey` of their upstream

If `sv2-apps` includes a keygen utility, use it. Otherwise, generate with `openssl`:
```bash
openssl genpkey -algorithm ed25519 -outform DER | base64 | tr -d '/+=\n'
```

Then update `authority_public_key` and `authority_secret_key` in each app's config before deploying.

---

## Reference Files

### Static references (bundled with the skill)
- `{baseDir}/references/architecture.md` — SRI app architecture and connection flow
- `{baseDir}/references/sv2-spec-overview.md` — SV2 protocol roles and sub-protocols
- `{baseDir}/references/sv2-apps/monitoring-api.md` — HTTP monitoring API reference for each app
- `{baseDir}/references/sv2-apps/config-reference.md` — every config parameter with SV2-spec context and production guidance
- `{baseDir}/references/sv2-apps/bitcoin-core-version.md` — Bitcoin Core version compatibility per SRI release

### Frozen Docker config templates (bundled per release tag)
These ship with the skill — no clone needed for known tags:
- `{baseDir}/references/sv2-apps/docker-templates/v1.1.0/` — sv2-tp v1.1.0 frozen template
- `{baseDir}/references/sv2-apps/docker-templates/v0.3.5/` through `{baseDir}/references/sv2-apps/docker-templates/v0.1.0/` — SRI release templates

There is **no frozen snapshot for `main`**. `main` is a rolling branch; its Docker config templates must be fetched live at runtime from `https://github.com/stratum-mining/sv2-apps`.

Each frozen SRI directory contains:
- `docker_env.example` — environment variables and defaults
- `pool-jds-config.toml.template` — pool + embedded JDS
- `jdc-config.toml.template` — Job Declarator Client
- `translator-proxy-config.toml.template` — SV1→SV2 Translator Proxy

The sv2-tp frozen directory contains:
- `docker_env.example` — sv2-tp CLI flags and defaults (no TOML config needed)

### Live sources (fetched at runtime)
- `https://github.com/stratum-mining/sv2-apps` — for `main` branch Docker config templates, unknown future tags, and source code for log comparison
- `https://github.com/stratum-mining/sv2-spec` — protocol specification
