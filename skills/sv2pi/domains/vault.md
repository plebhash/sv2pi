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
├── ppq-readings/              # hourly PPQ credit balance readings (time-series CSV)
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
