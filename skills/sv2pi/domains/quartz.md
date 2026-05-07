### 🧠 Quartz 4 Web Publishing 🖥️

**🚨 THIS IS THE ONLY PATH FOR SERVING THE VAULT.** When a user says "serve the vault," "publish the vault," "show the brain," or anything about making the vault web-accessible, this section IS the answer. There is no other server, no Python `http.server` workaround, no markdown renderer, no alternative. If you are loading this subskill because you saw "wiki" in the user prompt, you are in the RIGHT place. Do NOT load the llm-wiki skill for serving — llm-wiki is for editing content, not publishing it.

The vault is sv2pi's **long-term brain** 🧠 — a living, evolving knowledge-base that persists across agent sessions and serves both the agent and human operators. **Quartz 4** publishes this brain as a web-browsable, hyperlinked vault so humans can explore the full operational picture with their own eyes.

Quartz 4 is an open-source static site generator for Obsidian-flavored markdown vaults. It converts `$HOME/vault/` into a navigable website with backlinks, graph view, full-text search, and dark mode.

**Repair, don't replace:** If the Quartz directory (`~/quartz/`) is missing or broken, RESTORE it by cloning and reinstalling (`git clone` + `npm ci`). Never substitute a different server (Python, Caddy raw serving, nginx directory listing, etc.). The ONLY valid output is a Quartz-generated HTML static site served bound to the WireGuard IP on port 4028.

#### Terminology: serve vs publish

| Term | Meaning | Agent behavior |
|---|---|---|
| **serve raw vault** | Browse markdown files/directories as plain text | This is **never** the right answer — skip it |
| **publish vault** 🧠💻 | Build with Quartz and serve the generated HTML (Obsidian Publish style) | Build with `npx quartz build`, serve `quartz/public/` — this is the **only** correct answer |

When a user says "serve vault," "publish vault," or "show the brain," they mean **publish vault** — Quartz-generated HTML, not raw markdown. The raw vault is never the intended UX.

#### Pre-flight: read vault intent before serving

Before deciding how to serve, read these files in order to determine if Quartz/Obsidian Publish is expected:

1. `$HOME/vault/README.md` — top-level directives; may specify "quartz4 self-hosted obsidian publish-compatible server" and the target URL
2. `$HOME/vault/.wiki/config.json` — extension config; may list target port/interface
3. `$HOME/vault/WIKI_SCHEMA.md` — vault layout schema; may reference Quartz

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

**After pre-flight, stop probing.** Do NOT investigate unrelated system state (docker, process trees, npm scripts, `jq` on `package.json`). You have what you need — proceed directly to Q1.

#### Deployment modes (network interface)

| Mode | Interface | Visibility | When to use |
|---|---|---|---|
| `wg0` | WireGuard VPN | Restricted to VPN peers | Day-to-day operations — keep the brain within the trusted VPN 🧠🔒 |
| `eth0` | Public NIC | Exposed to the WWW | Public transparency or remote access without VPN 🧠🌐 |

The default port is **4028**. The agent binds Caddy to the interface IP (not `0.0.0.0`) so the vault is only reachable via that interface.

#### Firewall policy: probe without escalation, never tweak

**The agent must NEVER modify firewall rules.** The agent cannot read firewall rules directly (that requires escalated privileges which are forbidden). Before deploying Quartz, verify the listener is bound through the pre-flight `ss -ltnp` check — this confirms the service is reachable from localhost on the target interface.

If the port is blocked by an external firewall and the user needs it open:
- 🧠 Tell the operator: `"port 4028 may be firewalled on <iface> — operator should verify and open if needed"`
- 🧠 Do NOT output the command to open it — the operator knows their firewall tool
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
| `pageTitle` | `"sv2bot vault 🧠"` 🧠 | Shows in browser tab and site header |
| `baseUrl` | `"WIREGUARD_IP:4028"` | Must match the WireGuard IP from pre-flight (e.g. `10.0.0.1`) |
| `ignorePatterns` | `["private", "templates", ".obsidian", ".wiki", "raw", "outputs"]` | Skip extension-owned dirs and internal content; only publish `deployment/`, `interventions/`, `incidents/`, `wiki/`, and `index.md` |
| `Plugin.CustomOgImages()` | Comment it out | Speeds up builds; OG images are expensive and unnecessary for internal ops |

Update `baseUrl` dynamically from the detected WireGuard IP. Update `ignorePatterns` to exclude pi-llm-wiki internal directories.

##### Step Q3 — Ensure root index.md

Quartz requires a root `index.md` as the homepage. If missing, create one:

```bash
cat > $HOME/vault/index.md <<'EOF'
---
title: 🤖 sv2bot ⛏️  deployment vault 🧠
---

hi. I'm `sv2bot`.

I serve the [Sv2 Reference Implementation (SRI)](https://stratumprotocol.org) community of human FOSS-driven Bitcoin Miners.

---

you're reading my deployment vault (aka knowledge base 🧠), which consists of:

- [`quartz4`](https://quartz.jzhao.xyz/) self-hosted [`obsidian`]([`obsidian`](https://obsidian.md/))-compatible server
- a set of `.md` files compatible with:
  - [`obsidian`](https://obsidian.md/)
  - [Andrej Karpathy's LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)

this vault is served over SRI Community Wireguard VPN: http://10.0.0.1:4028 

---

most of the time, this knowledge base is actually meant for `sv2bot`'s own introspection. in other words, this is how `sv2bot` achieves long-term memory, and is able to serve the humans in SRI community (instead of causing them PITA).

humans are welcome to read this too, and that's why this vault is being served. especially for maintenance of `sv2bot`, in case it starts behaving in a weird way (which is cause either by buggy [`sv2pi`](https://github.com/plebhash/sv2pi) skills or corrupted vault). `sv2bot` tries to heal itself by letting plebhash know what kind of adjustments need to be made.

but humans beware: it might get pretty boring (and confusing!) to read `sv2bot's` internal notetaking system. you're much better off firing off prompts, which is the reason why `sv2bot` exists afterall!

only on doomsday scenarios, humans are encouraged to deep dive into this vault (which is also one of the reasons the vault exists).
```

##### Step Q4 — Build the static site

```bash
cd ~/quartz
rm -rf public
npx quartz build -d $HOME/vault -o public
```

This reads the vault at `$HOME/vault`, applies Quartz transformations, and emits static HTML/JS/CSS to `~/quartz/public/`. The build takes ~2–10s depending on vault size.

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

**System vs user Caddy:** The pre-flight may find both a system-level `caddy.service` and user-level Caddy services. Always prefer the user-level one — it runs as `sv2bot` and has the correct permissions. A failed system-level `caddy.service` is irrelevant if a user-level Caddy is running successfully. Only the Caddy instance that binds to the WireGuard IP matters.

If an existing Caddy user service is already running and bound to the WireGuard IP, add this site block to the existing Caddyfile. If no Caddy service exists, create one:

```bash
mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/sv2bot-quartz-caddy.service <<'EOF'
[Unit]
Description=Caddy reverse proxy for sv2bot Quartz vault
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

##### Step Q6 — Auto-rebuild on vault changes 🧠🔄

The published site must stay in sync with the vault. Add a systemd user path watcher that rebuilds Quartz whenever vault files change:

```bash
cat > ~/.config/systemd/user/sv2bot-quartz-build.service <<'EOF'
[Unit]
Description=Build sv2bot vault Quartz static site

[Service]
Type=oneshot
WorkingDirectory=%h/quartz
Environment=PATH=%h/.local/share/pi-node/node-v22.22.2-linux-x64/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=%h/.local/bin/build-sv2bot-quartz
EOF

cat > ~/.local/bin/build-sv2bot-quartz <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  --check)
    # Fast validation: verify Quartz is installed, no build
    if [ -d ~/quartz/node_modules ]; then echo "Quartz: OK"; exit 0; else echo "Quartz: missing node_modules"; exit 1; fi
    ;;
  "")
    cd ~/quartz
    exec npx quartz build -d ~/vault -o ~/quartz/public
    ;;
  *)
    echo "Usage: build-sv2bot-quartz [--check]" >&2
    exit 1
    ;;
esac
EOF
chmod +x ~/.local/bin/build-sv2bot-quartz

cat > ~/.config/systemd/user/sv2bot-quartz-build.path <<'EOF'
[Unit]
Description=Watch sv2bot vault markdown files and rebuild Quartz site

[Path]
PathModified=%h/vault
PathModified=%h/vault/deployment
PathModified=%h/vault/interventions
PathModified=%h/vault/incidents
PathModified=%h/vault/wiki
PathModified=%h/vault/meta
Unit=sv2bot-quartz-build.service

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now sv2bot-quartz-build.path
```

Now any vault edit triggers a rebuild within seconds. The build output goes to `~/quartz/public/` which Caddy is already serving.

**Note:** adapt `Environment=PATH` to the actual `pi-node` install path. Use `which node` to find it.

**Verify the rebuild works** before moving on:

```bash
# Trigger a manual rebuild and check it succeeded
systemctl --user start sv2bot-quartz-build.service
sleep 3
journalctl --user -u sv2bot-quartz-build.service -n 10 --no-pager | grep -o 'Done processing [0-9]* files'
# Expected: "Done processing N files" (N > 0)
```

**Do NOT probe the build script directly.** Calling `build-sv2bot-quartz --help` or similar will trigger a slow `npx quartz build --help` that times out. To check the script exists: `test -x ~/.local/bin/build-sv2bot-quartz && echo OK`. To check status: `systemctl --user status sv2bot-quartz-build.service`.

##### Step Q7 — Validate: MUST RUN BEFORE REPORTING DONE 🧠🚨

**This step is non-negotiable.** After deploy, you must run ALL 6 checks below with the actual WireGuard IP (exported as `$WG_IP` from pre-flight). Set the variable first:

```bash
WG_IP=$(ip -br addr show wg0 | awk '{print $3}' | cut -d/ -f1)
echo "WG_IP=$WG_IP"
```

Then run every check. All must pass:

```bash
# 1. Listener is WireGuard-bound ONLY (not 0.0.0.0)
ss -ltnp | grep ':4028'
# Expected: $WG_IP:4028 ... users:(("caddy",...))
# Reject:   0.0.0.0:4028  → over-exposed, fix the bind directive

# 2. Root returns text/html (not text/markdown or text/plain)
curl -s -o /dev/null -w '%{content_type}' http://$WG_IP:4028/
# Expected: text/html (or text/html; charset=utf-8)

# 3. HTML contains the Quartz site title
curl -s http://$WG_IP:4028/ | grep -o '<title>[^<]*</title>'
# Expected: <title>sv2bot vault</title>

# 4. Pretty routes work (no .html extension)
curl -s -o /dev/null -w '%{http_code}' http://$WG_IP:4028/deployment/overview
# Expected: 200 (redirect to /deployment/overview.html is acceptable)

# 5. Static assets exist (Quartz JS/CSS)
curl -s -o /dev/null -w '%{http_code}' http://$WG_IP:4028/static/contentIndex.json
# Expected: 200

# 6. Raw vault is NOT served directly
curl -s -o /dev/null -w '%{http_code}' http://$WG_IP:4028/README.md
# Expected: 404 (raw markdown should not be browsable)
```

**Do NOT report "done" or "serving" until ALL 6 checks pass.** If any check fails, diagnose and fix inline before declaring success. A deployment with 0 or partial validation is incomplete.

##### Step Q8 — Manual rebuild

After any manual vault edit that you want to publish immediately (without waiting for the path watcher):

```bash
systemctl --user start sv2bot-quartz-build.service
```

Or directly:

```bash
cd ~/quartz && npx quartz build -d ~/vault -o ~/quartz/public
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
