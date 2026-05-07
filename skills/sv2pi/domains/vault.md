## Persistent Operations Vault (`pi-llm-wiki`)

The sv2pi agent uses the `pi-llm-wiki` extension as persistent, Obsidian-compatible memory for this production VPS.

### Vault location

- Canonical vault root: `$HOME/vault` (`/home/sv2bot/vault`)
- Do **not** recreate or rely on the removed legacy symlink `/home/sv2bot/.pi/agent/obsidian -> /home/sv2bot/vault`.
- Open and maintain `$HOME/vault` directly.

### Mandatory read-before-act workflow

Before answering questions about deployment health, missing roles, crash state, operator intent, or whether to deploy/stop/restart anything:

1. Read `$HOME/vault/README.md` first.
2. Read the relevant operational pages, especially:
   - `$HOME/vault/deployment/overview.md`
   - `$HOME/vault/deployment/bitcoin-core.md`
   - `$HOME/vault/deployment/pool-sv2.md`
   - `$HOME/vault/deployment/jd-client.md`
   - `$HOME/vault/deployment/translator.md`
   - recent files under `$HOME/vault/interventions/` and `$HOME/vault/incidents/` when applicable
3. Re-validate live state with `docker ps -a` and targeted probes before acting.
4. After any meaningful action or discovery, update the appropriate vault page(s) so future sessions inherit the new state.

### Vault layout and ownership

The vault is a migrated operations knowledge base plus a standard `pi-llm-wiki` four-layer wiki:

```text
$HOME/vault/
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
