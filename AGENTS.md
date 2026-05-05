# AGENTS.md

## Worktree-based feature workflow

Every new feature or contribution is developed in a dedicated git worktree with
a matching feature branch. This keeps the main worktree clean and avoids stashing
or dirty-state accidents.

If the user does not specify a worktree, assume the main/root worktree (`./sv2pi`).

### Creating a feature worktree

```bash
# From the repo root (main worktree, on main branch):
FEATURE="oneshot-ci"

git worktree add -b "$FEATURE" "worktrees/sv2pi-$FEATURE" main
```

This creates `worktrees/sv2pi-$FEATURE/` as a new checkout on branch `$FEATURE`, branched
from `main`. Work there and commit freely.

### Rebasing before resuming work

Always rebase the feature branch against `origin/main` before resuming work.
This prevents drift and catches upstream changes early:

```bash
cd "worktrees/sv2pi-$FEATURE"
git fetch origin
git rebase origin/main
```

If conflicts arise, **abort and alert the user** — do not attempt resolution:

```bash
git rebase --abort
# Then tell the user: "Rebase of $FEATURE onto origin/main hit conflicts."
```

If the rebase fails due to a divergent history (e.g. local amend vs pushed ancestor),
use cherry-pick as a fallback:

```bash
git log --oneline main..$FEATURE          # review feature-only commits
git reset --hard origin/main
git cherry-pick <commit1> <commit2> ...   # re-apply feature commits
```

### Returning to main

```bash
cd ../sv2pi              # back to the main worktree
git fetch origin
git merge "$FEATURE"     # or open a PR on GitHub
```

### Cleaning up

After the feature branch is merged (or abandoned):

```bash
git worktree remove "worktrees/sv2pi-$FEATURE"
git branch -d "$FEATURE"   # local
```

## Commit rules

- **Commit title template:** every commit title must carry the `🤖 sv2pi ⛏️` signature:

```
🤖 sv2pi ⛏️ feat: add oneshot CI workflow
🤖 sv2pi ⛏️ fix: correct -ipcbind flag in deploy-bitcoin.sh
🤖 sv2pi ⛏️ docs: document Bitcoin Core compatibility matrix
🤖 sv2pi ⛏️ refactor: restructure references/ directory layout
```

- **NEVER sign commits.** Do not use `-S`, `-s`, `--gpg-sign`, or any commit signing mechanism. Commits must remain unsigned.

- **NEVER push to GitHub.** Do not run `git push` or any equivalent. The user handles all remote operations.

- **Sign commits when possible.** Use `-S` or `--gpg-sign`. If signing fails (e.g. hardware key unavailable, passphrase prompt), alert the user for human intervention rather than retrying indefinitely.

## Conventional commits

Follow [Conventional Commits](https://www.conventionalcommits.org/) for the type prefix after the signature. Common types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`.

## Skill development

When modifying the sv2pi skill under `skills/sv2pi/`:

- `SKILL.md` — the main workflow document the agent follows
- `scripts/` — deployment scripts called by the agent via `bash`
- `references/` — reference documents the agent loads on demand
- `references/sv2-apps/docker-templates/` — frozen config templates per SRI release (update when new SRI tags are released)

After changing the skill, test by installing locally:

```bash
cp -r skills/sv2pi ~/.pi/agent/skills/
```
