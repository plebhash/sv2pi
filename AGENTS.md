# AGENTS.md

## NO SUDO

**The agent must never invoke, output, suggest, or type `sudo`, `newgrp`, or `sg` in any context.** This is a hard constraint — the agent runs as a non-root user and has no authority to escalate and no business giving privilege-escalation advice to the operator. The word `sudo` must not appear in agent-authored text under any circumstances.

- **Docker access:** it is the human operator's responsibility to ensure that pi's userspace has access to the `docker` group before deploying. If a script fails with a Docker permission error, the agent reports the error to the user and stops. If the operator asks how to fix it, the agent deflects: Docker access configuration is the operator's domain and the agent has no knowledge of the host's privilege model. The agent may repeat the deploy command but must not offer any fix.
- **Root-owned volumes:** Bitcoin Core's Docker data directory (`~/.sv2pi/bitcoin/data/`) is owned by root inside the container and may be root-owned on the host. The agent never inspects or modifies these paths with escalated privileges. The operator must pre-configure directory permissions if needed.
- **Script hygiene:** every script under `skills/sv2pi/scripts/` must be audited to contain zero invocations of `sudo`, `newgrp`, or `sg`. If a script needs elevated access, it must fail with a clear message telling the operator what to configure — not attempt escalation itself.

## Worktree-based feature workflow

Every new feature or contribution is developed in a dedicated git worktree with
a matching feature branch. This keeps the main worktree clean and avoids stashing
or dirty-state accidents.

If the user does not specify a worktree, assume the main/root worktree (`./sv2pi`). New feature branches should normally branch from `staging` unless the user explicitly says otherwise.

### Creating a feature worktree

```bash
# From the repo root (main worktree):
FEATURE="oneshot-ci"

git worktree add -b "$FEATURE" "worktrees/$FEATURE" staging
```

This creates `worktrees/$FEATURE/` as a new checkout on branch `$FEATURE`, branched
from `staging`. Work there and commit freely.

### Rebasing before resuming work

Always rebase staging-targeted feature branches against `origin/staging` before resuming work.
This prevents drift and catches upstream changes early:

```bash
cd "worktrees/$FEATURE"
git fetch origin
git rebase origin/staging
```

If conflicts arise, **abort and alert the user** — do not attempt resolution:

```bash
git rebase --abort
# Then tell the user: "Rebase of $FEATURE onto origin/staging hit conflicts."
```

If the rebase fails due to a divergent history (e.g. local amend vs pushed ancestor),
use cherry-pick as a fallback:

```bash
git log --oneline staging..$FEATURE       # review feature-only commits
git reset --hard origin/staging
git cherry-pick <commit1> <commit2> ...   # re-apply feature commits
```

### Returning to main (via staging)

**CRITICAL: NEVER merge a feature branch directly into `main`.** Every feature must land in `staging` first for integration testing. Only `staging` is merged into `main`.

See [Staging workflow](#staging-workflow) for the full flow.

### Cleaning up

After the feature branch is merged (or abandoned):

```bash
git worktree remove "worktrees/$FEATURE"
git branch -d "$FEATURE"   # local
```

## Staging workflow

**CRITICAL: `main` is protected — never merge feature branches directly into `main`.** All features go through `staging` first. `staging` is the integration testing ground; only `staging` gets merged into `main`. If a user asks you to merge a feature into `main`, push back and remind them of this rule.

The `staging` worktree/branch is a persistent integration testing ground
where features are assembled and live-tested before landing on `main`.

`main` must remain stable and deployable at all times — no direct merges
from feature branches. Everything flows through staging first.

### Creating the staging worktree (one-time)

```bash
git worktree add -b staging worktrees/staging main
```

### Merging a feature into staging

After a feature branch is reviewed and ready:

```bash
cd worktrees/staging
git fetch origin
git merge "$FEATURE"
```

Run live-tests. If issues are found, fix them on the feature branch and re-merge.

### Rebasing staging onto main

Before merging staging back into main, rebase to get a clean linear history:

```bash
cd worktrees/staging
git fetch origin
git rebase origin/main
```

If conflicts arise, **abort and alert the user** — do not attempt resolution:

```bash
git rebase --abort
# Then tell the user: "Rebase of staging onto origin/main hit conflicts."
```

### Promoting staging to main

Once staging passes live-testing:

```bash
cd ../sv2pi              # back to the main worktree
git fetch origin
git merge staging
```

After the merge, staging can be reset to track main again:

```bash
cd worktrees/staging
git reset --hard origin/main
```

Do NOT clean up the staging worktree — it is persistent.

## Commit rules

- **Commit title template:** every commit authored by the agent must carry the `🤖 sv2pi ⛏️` signature. This rule applies only to agent-created commits — human commits are not obligated (nor encouraged) to follow this template.

```
🤖 sv2pi ⛏️ feat: add oneshot CI workflow
🤖 sv2pi ⛏️ fix: correct -ipcbind flag in deploy-bitcoin.sh
🤖 sv2pi ⛏️ docs: document Bitcoin Core compatibility matrix
🤖 sv2pi ⛏️ refactor: restructure references/ directory layout
```

- **Sign commits when possible.** Use `-S` or `--gpg-sign`. If signing fails (e.g. hardware key unavailable, passphrase prompt), alert the user for human intervention rather than retrying indefinitely. Ask if they want to sign, or proceed without signing.

- **NEVER push to GitHub.** Do not run `git push` or any equivalent. The user handles all remote operations.

## Conventional commits

Follow [Conventional Commits](https://www.conventionalcommits.org/) for the type prefix after the signature. Common types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`.

## Skill development

When modifying the sv2pi skill under `skills/sv2pi/`:

- `SKILL.md` — root orchestrator and dispatch table
- `domains/` — on-demand domain instructions loaded via `read {baseDir}/domains/...`
- `scripts/` — deployment scripts called by the agent via `bash`
- `references/` — passive reference documents and frozen templates
- `references/sv2-apps/docker-templates/` — frozen config templates per SRI release (update when new SRI tags are released)

After changing the skill, test by installing locally:

```bash
cp -r skills/sv2pi ~/.pi/agent/skills/
```
