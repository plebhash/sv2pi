# Deployment Context

### Step 1 — Select Deployment Tag

Ask the user: **"Which SRI Docker Hub tag? (`main` or a version like `v0.4.0`)"**

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
│       ├── v0.4.0/                      ← frozen at v0.4.0
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

**If the user selected a tagged release (e.g. `v0.4.0`):**

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
- **v0.4.0** → Bitcoin Core v31.0 (first tagged release with bitcoin_core_sv2 v0.2.0)
- **v0.3.5 through v0.1.0** → Bitcoin Core v30.2
- **sv2-tp v1.1.0** → Bitcoin Core v31.0 (uses `stratumv2/sv2-tp:v1.1.0`)

If using a tag not in the frozen references, clone `sv2-apps` and check `bitcoin-core-sv2/README.md` for the exact version requirement.

---

### Deploying Applications

The sections below describe how to deploy each application. **Deploy only what the user needs** — not every component is required. The agent must:

1. Understand what the user wants to accomplish
2. Check the dependency graph to determine prerequisites
3. Deploy only the necessary components, in dependency order
4. Adapt template provider configuration (IPC vs Sv2Tp) based on what's deployed

