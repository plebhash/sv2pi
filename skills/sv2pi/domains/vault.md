## Persistent Operations Vault (`pi-llm-wiki`)

The sv2pi agent uses the `pi-llm-wiki` extension as persistent, Obsidian-compatible memory for this production VPS.

### Vault location

- Canonical vault root: `$HOME/vault` (`/home/sv2bot/vault`)
- Do **not** recreate or rely on the removed legacy symlink `/home/sv2bot/.pi/agent/obsidian -> /home/sv2bot/vault`.
- Open and maintain `$HOME/vault` directly.

### Vault existence check (single probe)

Read `$HOME/vault/README.md` **once**. If it returns ENOENT, the vault is uninitialized — stop probing. Do not iterate over individual pages that can't exist without it. Note the absence, proceed with the task, and optionally initialize the vault afterward (see [Initializing a new vault](#initializing-a-new-vault)).

### Tiered read model

**Quick check** — before any deploy, stop, restart, or config change:
- Read only `$HOME/vault/README.md` to check for permanent operator directives.
- If absent (no vault), proceed immediately.
- Do not cascade into full reads for deployment actions.

**Full read** — only for health diagnosis, crash investigation, topology questions, or explicit vault queries:
- `$HOME/vault/deployment/overview.md`
- `$HOME/vault/deployment/<relevant-role>.md` (bitcoin-core, pool-sv2, jd-client, translator)
- Recent files under `$HOME/vault/interventions/` and `$HOME/vault/incidents/` when investigating a crash

After any read, re-validate live state with `docker ps -a` and targeted probes before acting — the vault is memory, not live truth.

### Concrete update triggers

| Event | What to write/update |
|---|---|
| First deployment on this VPS | Initialize the vault (see below), then proceed |
| PPQ balance reading (hourly) | `$HOME/vault/ppq-readings/readings.csv` — append timestamp,balance line |
| Role deployed successfully | `$HOME/vault/deployment/<role>.md` — tag, config summary, upstream/downstream addresses |
| Role stopped or removed | `$HOME/vault/deployment/<role>.md` — note decommissioned state |
| Crash or abnormal exit | `$HOME/vault/incidents/<YYYY-MM-DD>-<role>.md` — exit code, tail of logs, suspected cause |
| Operator gives a permanent directive | `$HOME/vault/README.md` — verbatim quote, dated |
| Intervention (fix, restart, config change) | `$HOME/vault/interventions/<YYYY-MM-DD>-<description>.md` |

Entries must be concise, dated, and factual. Use normal file tools (`read`, `edit`, `write`).

### Initializing a new vault

When deploying the first role on a VPS with no vault:

1. Create `$HOME/vault/` and the required `pi-llm-wiki` directories:
   ```bash
   mkdir -p $HOME/vault/{deployment,interventions,incidents,raw/sources,wiki,meta,.wiki}
   ```
2. Write a minimal `$HOME/vault/README.md`:
   ```markdown
   # sv2pi Operations Vault

   This vault records the persistent operational state of the sv2pi SRI deployment.

   Initiated: <YYYY-MM-DD>
   ```
3. Without a `README.md`, `pi-llm-wiki` tools may not bind to the vault. The agent should create it, then proceed with the deployment.

If the vault exists but `README.md` is missing (partial/migrated vault), create it by inspecting what `deployment/` pages exist. Never remove existing vault artifacts.

### Vault layout and ownership

The vault is a migrated operations knowledge base plus a standard `pi-llm-wiki` four-layer wiki:

```text
$HOME/vault/
├── README.md                  # top-level operator directives and usage instructions
├── deployment/                # migrated sv2pi operational state pages
├── interventions/             # operator/agent intervention records
├── incidents/                 # crash reports and incident analyses
├── ppq-readings/              # hourly PPQ credit balance readings and consolidation costs (time-series CSV)
├── raw/sources/               # immutable source packets; extension-owned
├── wiki/                      # editable LLM Wiki pages: sources/entities/concepts/syntheses/analyses
├── meta/                      # auto-generated registry/backlinks/log; extension-owned
└── .wiki/                     # extension config/templates
```

### PPQ Credit Balance Readings

The `ppq-readings/` directory stores a time series of PPQ credit balance probes taken hourly by the agent.

**Directory:**

```text
$HOME/vault/ppq-readings/
└── readings.csv
```

**Format:** CSV with two columns — ISO-8601 UTC timestamp and balance as a decimal float:

```csv
2026-05-07T14:00:00Z,18.834
2026-05-07T15:00:00Z,18.791
```

**Writing:** The trigger fires hourly, invokes `{baseDir}/scripts/log-ppq-reading.py`, and appends one line to the CSV. This is a **zero-token operation** — probe the API, dump to disk, exit. No LLM involvement. Never edit this CSV manually.

**Reading:** To analyze credit consumption over time, read `readings.csv` directly. Compute burn rate as the slope of balance over a recent window. Forecast depletion by extrapolating the current burn rate to zero.

**Initialization:** If the directory or CSV does not exist, the logging script creates it on first write. No manual vault initialization is needed for PPQ readings.

Detailed probe behavior is documented in `{baseDir}/domains/ppq-monitor.md`.

#### Consolidation Costs

The `consolidation-costs.csv` file records the PPQ credit cost of each daily vault consolidation run:

```text
$HOME/vault/ppq-readings/
├── readings.csv
└── consolidation-costs.csv
```

**Format:** CSV with four columns — ISO-8601 UTC timestamp, balance before consolidation, balance after, and cost delta:

```csv
timestamp,before,after,cost
2026-05-08T01:00:00Z,18.791,18.745,0.046
```

**Writing:** Written by the agent at the end of each consolidation run as part of the post-consolidation phase (see [Post-consolidation](#post-consolidation)). Never edit this CSV manually.

**Reading:** To analyze long-term consolidation costs, read `consolidation-costs.csv` directly. Compute average daily cost, detect cost trends (is ADMIN_MODEL getting cheaper or more expensive over time?), and forecast monthly consolidation budget.

Respect the `pi-llm-wiki` rules:

- Never edit `$HOME/vault/raw/`; capture new sources with `wiki_capture_source`.
- Never edit `$HOME/vault/meta/`; metadata is extension-generated.
- Editable knowledge lives in `$HOME/vault/wiki/` and the migrated sv2pi operations directories (`deployment/`, `interventions/`, `incidents/`).
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

### Operator directives in the vault are binding

If `$HOME/vault/README.md` or a deployment/intervention page contains a permanent operator directive, treat it as higher-priority operational context for this deployment. Example currently recorded in the vault: `jd_client_sv2` must not be deployed on this VPS, and its absence is expected rather than a fault. Always re-read the vault to confirm current directives before discussing role topology.

### Quartz homepage template

The vault may contain a root `index.md` for Quartz publishing. The canonical creation template lives in `{baseDir}/domains/quartz.md` under `Step Q3 — Ensure root index.md` and must remain verbatim.

---

## Daily Vault Consolidation

Once per day, the agent performs a comprehensive vault analysis and consolidation using the **ADMIN_MODEL**. This is a high-impact persistent-memory operation — the consolidation runs with the strongest available model because it modifies the vault's durable knowledge. The concrete model backing `ADMIN_MODEL` is deployment configuration (see the vault's model-routing policy), not a hardcoded skill constant.

### Why consolidation exists

Different agent sessions (CLI, Discord/Picord, automated timers) may introduce competing or fragmented documentation patterns. Over time, this produces:

- **Redundant intervention notes** — multiple notes documenting the same event from different sessions.
- **Drifted deployment pages** — deployment pages that no longer match live container state.
- **Stale cross-references** — wikilinks pointing to renamed or archived pages.
- **Implicit knowledge fragmentation** — related information scattered across interventions, deployments, and wiki pages without synthesis.

Consolidation is the deliberate, safety-guarded process of detecting and resolving these issues without losing the audit trail.

### Trigger

Consolidation runs once every 24 hours. Two trigger paths:

1. **Scheduled trigger (primary):** A daily systemd timer at a low-activity hour.
2. **Session-start check (secondary):** On any new agent session, check whether >24h has elapsed since the last recorded consolidation. If so, ask the operator whether to run consolidation now or defer to the scheduled trigger.

### Pre-flight checklist

Before any consolidation work, the agent MUST:

1. **Read binding directives:** `$HOME/vault/README.md` — these are immutable guardrails.
2. **Read current topology:** `$HOME/vault/deployments/overview.md`.
3. **Validate live state:** `docker ps -a` for all sv2pi containers; note any drift between vault and live state.
4. **Inventory recent pages:** List all files under `$HOME/vault/interventions/` and `$HOME/vault/incidents/` modified in the last 7 days.
5. **Run health scan:** `wiki_lint` to detect orphans, missing pages, contradictions, and gaps.
6. **Read the last consolidation report:** `$HOME/vault/analyses/consolidation-*.md` (most recent) to understand what was done last time and what was flagged for follow-up.
7. **Probe PPQ balance (before):** Run `python3 {baseDir}/scripts/check-ppq-balance.py` and record the balance. This is the starting credit before consolidation consumes tokens.

### Analysis phase

Read every intervention note from the past 7 days. For each note, classify it:

| Classification | Definition | Action |
|---|---|---|
| **Standalone event** | A single, non-overlapping incident or intervention | Keep as-is; add cross-references |
| **Duplicate** | Same event documented in multiple notes from different sessions | Merge into one consolidated note; move originals to `archive/` |
| **Fragment** | Partial documentation of a multi-step event, completed across multiple notes | Merge fragments into one coherent narrative; move originals to `archive/` |
| **Stale** | Documents a transient state that has since changed (e.g., "restarted X" when X was later rebuilt) | Annotate with dated note linking to the newer state; do NOT delete |
| **Policy/Operational** | Contains a binding directive, access rule, or permanent policy change | ALWAYS preserve verbatim; ensure it's reflected in README.md if global |

Identify cross-cutting themes across interventions:
- Are there recurring diagnostic patterns? (e.g., "IPC socket not found" appearing in multiple incidents)
- Are there undocumented deployment changes? (e.g., interventions that describe config changes not reflected in deployment pages)
- Are there gaps? (e.g., deployment page for a running container is missing)

### Consolidation phase — SAFETY-CRITICAL RULES

#### NEVER

- **Delete or alter binding operator directives** from `README.md` or any page marked as a permanent directive.
- **Delete or alter permanent deployment policies** (e.g., the no-JDC directive, translator topology, model-routing policy, access-policy boundaries).
- **Collapse distinct incidents** into a single page. Different dates and root causes must remain separate.
- **Remove dated records.** Dates are the audit trail. Even merged originals go to `archive/`, never to `/dev/null`.
- **Invent facts** not sourced from vault pages, live probes, or container logs.
- **Change** model-routing policy, access policy, authority boundaries, or skill conventions during consolidation.
- **Compress away** security-sensitive information (API key locations, token paths, config paths) — these are operational references, not duplication.
- **Introduce hallucinations.** Every claim in a consolidation note must cite a source page or live probe result.

#### ALWAYS

- **Merge duplicates and fragments:** When multiple intervention notes document the same event:
  1. Create a single consolidated note with filename `YYYY-MM-DD-<topic>-CONSOLIDATED.md` in `$HOME/vault/interventions/`.
  2. The consolidated note must cite all original notes it subsumes.
  3. Create `$HOME/vault/interventions/archive/` if it doesn't exist.
  4. Move originals into `archive/` — **never delete them.**
  
- **Update deployment pages for drift:** When live state (`docker ps -a`) differs from a deployment page:
  1. Append a dated update section at the bottom of the deployment page.
  2. Format: `### Update YYYY-MM-DD` followed by the observed drift and any context.
  3. Never overwrite the page's history — the full deployment timeline must be preserved.

- **Add cross-references:** Every related page should link to its neighbors via `[[wikilinks]]`.

- **Create synthesis pages for cross-cutting themes:** If a pattern appears across 3+ interventions/incidents, create a synthesis page at `$HOME/vault/wiki/syntheses/<topic>.md` via `wiki_ensure_page`.

- **Flag anything uncertain:** If two pages contradict each other, or a claim can't be verified, add a visible `⚠️ HUMAN REVIEW NEEDED` marker and describe exactly what's uncertain.

### Post-consolidation

1. **Probe PPQ balance (after):** Run `python3 {baseDir}/scripts/check-ppq-balance.py` again after all consolidation work is complete. Compute the delta: `before − after = cost`.

2. **Write consolidation report:** Create `$HOME/vault/analyses/consolidation-YYYY-MM-DD.md` (use `wiki_ensure_page(type="analysis", title="consolidation-YYYY-MM-DD")`). The report must include:
   - Timestamp and model used.
   - PPQ credit balance: before, after, and delta (cost of this consolidation run).
   - Pre-flight state summary (vault vs. live state).
   - Pages merged (with before/after filenames).
   - Deployment pages updated (with drift details).
   - New synthesis pages created.
   - Issues flagged for human review.
   - Open follow-up items for next consolidation.

3. **Append cost to time-series CSV:** Write the before/after/delta to `$HOME/vault/ppq-readings/consolidation-costs.csv`:
   ```csv
   2026-05-08T01:00:00Z,18.791,18.745,0.046
   ```
   Format: `timestamp,before,after,cost`. If the file doesn't exist, create it with a header row: `timestamp,before,after,cost`.

4. **Rebuild metadata:** `wiki_rebuild_meta`.

5. **Verify health:** `wiki_lint` and confirm zero new orphans. If orphans remain, resolve them.

6. **Log the event:** `wiki_log_event(kind="consolidation", details={...})` with summary counts including the credit delta.

### Scheduling mechanism

The daily timer invokes the consolidation via the ADMIN_MODEL path. The service file:

```ini
# ~/.config/systemd/user/sv2pi-vault-consolidation.service
[Unit]
Description=Daily sv2pi vault consolidation (ADMIN_MODEL)
After=network-online.target

[Service]
Type=oneshot
ExecStart=%h/.pi/agent/git/github.com/plebhash/sv2pi/skills/sv2pi/scripts/trigger-vault-consolidation.sh
StandardOutput=journal
StandardError=journal
```

```ini
# ~/.config/systemd/user/sv2pi-vault-consolidation.timer
[Unit]
Description=Daily sv2pi vault consolidation trigger

[Timer]
OnCalendar=daily
RandomizedDelaySec=1800
Persistent=true

[Install]
WantedBy=timers.target
```

The trigger script writes a structured prompt file for the next agent session to pick up, or invokes `pi` directly with the consolidation prompt. The agent should detect this trigger on next session start and run the consolidation workflow.
