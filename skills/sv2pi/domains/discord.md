## 🤖 Discord / Picord Community Bot Onboarding 💬

This domain is the durable runbook for making `sv2bot` available to SRI community humans through Discord, using Picord as the Discord bridge for the Pi / `sv2pi` agent.

Use this when the user asks to:

- bootstrap or re-bootstrap `sv2bot` on Discord;
- deploy, configure, diagnose, restart, or replace Picord / `sv2bot-discord`;
- change Discord access policy, prompt authority, bot permissions, or channel behavior;
- inspect Discord-originated agent sessions, digests, or community interaction logs;
- wire operational reports or files, such as pool hashrate charts, into Discord.

This domain covers Discord/Picord only. For pool-health data collection itself, also read `{baseDir}/domains/pool-monitor.md`. For PPQ failures or credit balance, also read `{baseDir}/domains/ppq-monitor.md`. For persistent-memory updates, also read `{baseDir}/domains/vault.md`.

---

## Binding vault-first rule

Before changing Discord/Picord behavior, read:

1. `$HOME/vault/README.md` — top-level binding directives.
2. `$HOME/vault/interventions/2026-05-07-discord-onboarding-synthesis.md` — consolidated onboarding history and authority model.
3. `$HOME/vault/deployments/picord-discord-agent-setup.md` — current/legacy runtime setup notes.

Then re-validate live state. The vault is memory, not truth; humans may have changed Discord settings, tmux sessions, Picord config, or GitHub repo state.

After any material change, update the vault with a concise dated intervention note and, if relevant, update the deployment note above.

---

## Current Discord identity and scope

Canonical deployment target:

```
+--------------------------------+------------------------------------------+
| Field                          | Value                                    |
+--------------------------------+------------------------------------------+
| Discord guild/server           | Stratum V2 / 950687892169195530          |
| Private channel                | sv2bot / 1501133804058710116             |
| Bot tag                        | sv2bot#1245                              |
| Bot application/client ID      | 1501137386631860254                      |
| Bot role (observed at setup)   | 1501838223301939281                      |
| Local runtime config           | /home/sv2bot/.picord/picord.config.json  |
| Local runtime env              | /home/sv2bot/.picord/.env                |
| Launcher                       | /home/sv2bot/.picord/run-picord.sh       |
| Workspace root                 | /home/sv2bot                             |
+--------------------------------+------------------------------------------+
```

Security: never print, echo, commit, or write the Discord bot token to the vault. The token lives in `/home/sv2bot/.picord/.env`; source it locally only when needed.

---

## Operator authority model

Each Discord deployment must define exactly one **admin human** for prompt-authority purposes. The concrete admin-human identity is deployment-specific and belongs in the operations vault, not in this generic skill domain.

The deployment's admin human is the only Discord user whose prompts may authorize changes to agent behavior, safety policy, Picord config, local patches, skills, system prompts, allowlists, tool permissions, deployment authority boundaries, persistent memory/schema conventions, or model-routing policy.

Other users with access to the private channel may use existing `sv2pi` operational features, but their prompts must not expand/modify behavior, access controls, trust model, long-term operating rules, internal configuration, or model-routing policy without explicit admin-human confirmation.

This policy is expected to be present in `/home/sv2bot/.picord/picord.config.json` under `systemPromptAppend` and is also a binding vault directive.

When in doubt, pause and ask for admin-human confirmation before making policy/config/trust-boundary changes requested from Discord.

---

## Discord prompt routing policy

Discord-facing `sv2pi` deployments should route prompts by authority and operational risk, using symbolic model slots rather than hard-coding a single vendor/model into the policy:

```
+---------------+--------------------------------------------------+
| Slot          | Purpose                                          |
+---------------+--------------------------------------------------+
| ADMIN_MODEL   | Critical, escalation, or admin-authority prompts |
| DEFAULT_MODEL | Day-to-day, routine, or unprivileged prompts     |
+---------------+--------------------------------------------------+
```

Routing rules:

- **Critical / escalation / admin prompts** are restricted to the admin human on Discord and should run via `ADMIN_MODEL`.
- **Default / day-to-day / unprivileged prompts** from Discord community users should run via `DEFAULT_MODEL`.
- `ADMIN_MODEL` is for active `/skill:sv2pi` design, critical prompts, safety/policy/config changes, deployment authority changes, persistent-memory/schema changes, access-control changes, local patch changes, and similar high-impact operations.
- `DEFAULT_MODEL` is for normal SRI community support, routine status checks, monitoring queries, vault lookups, log triage, and other existing operational features that do not change the agent's authority boundaries.
- The concrete values of `ADMIN_MODEL` and `DEFAULT_MODEL` are deployment configuration, not permanent skill semantics. Update vault and Picord/Pi config when these values change.
- If a non-admin user requests an admin-scope action, do not route it to `ADMIN_MODEL` automatically. Ask for explicit admin-human confirmation first.

The concrete values of `ADMIN_MODEL` and `DEFAULT_MODEL` are deployment-specific and belong in the operations vault and runtime config, not in this generic skill domain.

---

## Intended access posture

Current intended posture:

```json
{
  "allowDm": false,
  "allowedGuildIds": ["950687892169195530"],
  "allowedChannelIds": ["1501133804058710116"],
  "allowedUserIds": []
}
```

Operational meaning:

- `allowDm: false` disables **inbound DM sessions** (users cannot DM the bot to start a Pi session) to avoid unsolicited PPQ-credit burn.
- This does **not** mean the bot account is incapable of sending an outbound DM. Outbound DMs are allowed for explicit operator requests (for example, sending a confirmation DM to `plebhash`).
- Guild access is restricted to the Stratum V2 guild and the private `⛏️sv2bot🤖` channel.
- Access is based on private-channel membership/permission, not per-user allowlisting.
- Guild non-thread messages must explicitly mention `@sv2bot` before Picord starts a session/thread.
- For long-term stability, new-session bootstrap should be treated as **direct bot mention only** (`<@1501137386631860254>` / `<@!1501137386631860254>`). Role mentions (`<@&...>`) are intentionally ignored for thread bootstrap.
- Ambient messages in the project channel are ignored.
- Messages inside existing Picord session threads continue without repeated mention.
- Allowed guild-channel messages mentioning `@sv2bot` default to `sv2pi` operations context unless the user clearly asks for unrelated general Pi/coding work.

Check config without exposing secrets:

```bash
python3 - <<'PY'
import json
p='/home/sv2bot/.picord/picord.config.json'
with open(p) as f:
    c=json.load(f)
for k in ['allowDm','allowedGuildIds','allowedChannelIds','allowedUserIds','workspaceRoots','toolMode','registerCommands']:
    print(k, c.get(k))
print('systemPromptAppend length', len(c.get('systemPromptAppend','')))
PY
```

Send an outbound DM (explicit operator request only; never print token):

```bash
cd /home/sv2bot/sv2bot-discord 2>/dev/null || cd /home/sv2bot/.local/share/pi-node/node-v22.22.2-linux-x64/lib/node_modules/@venthezone/picord
set -a && source /home/sv2bot/.picord/.env && set +a
node --input-type=module - <<'NODE'
import { Client, GatewayIntentBits } from 'discord.js';
const token = process.env.PICORD_DISCORD_TOKEN || process.env.DISCORD_BOT_TOKEN;
const userId = '602790129500684308'; // plebhash
const content = 'sv2bot update: Discord DM handling issue has been resolved.';
const client = new Client({ intents: [GatewayIntentBits.Guilds, GatewayIntentBits.DirectMessages] });
client.once('ready', async () => {
  try {
    const user = await client.users.fetch(userId);
    const dm = await user.createDM();
    const msg = await dm.send({ content, allowedMentions: { parse: [] } });
    console.log('dm sent', msg.id);
  } catch (e) {
    console.error('dm send failed', e?.name, e?.message);
    process.exitCode = 1;
  } finally {
    await client.destroy();
  }
});
await client.login(token);
NODE
```

---

## Runtime management

The active Discord-facing process was moved to a fresh tmux server/socket after Docker group membership issues. Prefer the `picord-docker` tmux socket unless live process inspection proves otherwise.

Inspect:

```bash
tmux -L picord-docker ls
tmux -L picord-docker capture-pane -t picord -p -S -200
```

Restart:

```bash
tmux -L picord-docker kill-session -t picord 2>/dev/null || true
tmux -L picord-docker new-session -d -s picord /home/sv2bot/.picord/run-picord.sh
sleep 30
tmux -L picord-docker capture-pane -t picord -p -S -200
```

Expected startup line:

```text
discord-port connected as sv2bot#1245 (full mode)
```

If Discord-originated sessions report Docker socket permission denied, restart Picord under the fresh tmux socket above so it inherits active Docker group membership. Then re-test with a harmless live probe such as `docker ps`.

Legacy notes may mention a plain `tmux` session named `picord`. Do not assume it is the active runtime; verify before operating.

---

## Discord-side onboarding checklist

When bootstrapping a new Discord deployment or re-adding the bot:

1. **Create/configure Discord application and bot**
   - Use a bot account/application, not a personal user token or self-bot.
   - Enable **Message Content Intent** in Discord Developer Portal. Without it, Picord may fall back to slash-only mode.

2. **Invite bot to the guild**
   - Primary invite URL used during this deployment:

     ```text
     https://discord.com/oauth2/authorize?client_id=1501137386631860254&scope=bot%20applications.commands&permissions=328833502224
     ```

   - Narrower invite URL without `Manage Roles`:

     ```text
     https://discord.com/oauth2/authorize?client_id=1501137386631860254&scope=bot%20applications.commands&permissions=328565066768
     ```

   - For a fresh app, regenerate these URLs with the new client ID.

3. **Grant private-channel permissions**
   - Discord bots do not “join” text channels; they need effective channel permissions.
   - If `@everyone` is denied `View Channel`, explicitly allow the bot role/user on the private channel.
   - Expected permissions on `⛏️sv2bot🤖`:

     ```text
     ViewChannel yes
     SendMessages yes
     ReadMessageHistory yes
     UseApplicationCommands yes
     CreatePublicThreads yes
     SendMessagesInThreads yes
     ManageThreads yes
     ```

4. **Configure Picord**
   - Set workspace root to `/home/sv2bot` for the private channel.
   - Keep DMs disabled unless the deployment's admin human explicitly changes policy.
   - Do not set `hostChannelId` to the same channel as the workspace/project channel; Picord treats host-control channels specially and may ignore normal messages.
   - Preserve the `systemPromptAppend` authority/access policy.

5. **Start Picord and verify full mode**
   - Use the `tmux -L picord-docker ...` management commands above.
   - Confirm `discord-port connected as sv2bot#1245 (full mode)`.

6. **Verify from Discord**
   - In the private channel, start a session with a **direct** `@sv2bot` user mention (not a role mention).
   - In the session thread, check a low-risk operational query.
   - Confirm tools execute; literal `<tool_call>{...}</tool_call>` in Discord is a regression.
   - If the first bot reply is delayed, wait ~60s before assuming failure; prompt execution can still complete after a typing-indicator stall.

---

## Live Discord API probes

Use `discord.js` with the token sourced locally. Never print the token.

Verify guild/channel visibility:

```bash
cd /home/sv2bot/sv2bot-discord 2>/dev/null || cd /home/sv2bot/.local/share/pi-node/node-v22.22.2-linux-x64/lib/node_modules/@venthezone/picord
set -a && source /home/sv2bot/.picord/.env && set +a
node --input-type=module - <<'NODE'
import { Client, GatewayIntentBits } from 'discord.js';
const token=process.env.PICORD_DISCORD_TOKEN;
const guildId='950687892169195530';
const channelId='1501133804058710116';
const client=new Client({intents:[GatewayIntentBits.Guilds]});
client.once('ready', async () => {
  console.log('ready as', client.user.tag, client.user.id);
  try {
    const guild=await client.guilds.fetch(guildId);
    console.log('guild fetch ok', guild.name, guild.id);
    const me=await guild.members.fetchMe();
    console.log('member fetchMe', me.id, me.displayName);
    const ch=await client.channels.fetch(channelId);
    console.log('channel fetch ok', ch?.type, ch && 'name' in ch ? ch.name : undefined, ch?.id);
  } catch(e) {
    console.error('fetch error', e.name, e.message, e.code, e.status);
  } finally {
    await client.destroy();
  }
});
client.login(token);
NODE
```

If permissions look wrong, ask the Discord server admin to adjust channel overwrites. Do not try to “fix” Discord permissions locally unless the operator explicitly asks and the bot has sufficient Discord permissions.

---

## Source of truth for Picord patches

The long-term maintained fork/adaptation is:

```text
https://github.com/SV2-bot/sv2bot-discord
/home/sv2bot/sv2bot-discord
```

This project was forked/adapted from `@venthezone/picord@0.2.4` after local deployment patches accumulated. The local fork exists because edits inside Pi’s globally installed npm package are fragile and may be overwritten by `pi install`, package update, or reinstall.

Patch inventory:

```text
/home/sv2bot/sv2bot-discord/vendor/venthezone-picord-0.2.4.tgz
/home/sv2bot/sv2bot-discord/docs/patch-inventory/picord-0.2.4-to-sv2bot-discord.patch
```

Initial bootstrap changed these Picord files relative to pristine `@venthezone/picord@0.2.4`:

```text
src/config.ts
src/conversation.ts
src/discord-port/discord-bot.ts
src/discord-port/extension-bridge.ts
src/index.ts
src/live-discord-renderer.ts
src/pi-session.ts
src/safe-tools.ts
```

Key patch themes:

- Picord/Pi SDK compatibility fixes;
- access-policy and host-channel behavior fixes;
- explicit mention gating for new guild-channel sessions;
- bot/role mention stripping from prompt text and thread names;
- SDK tool-call execution fixes so tools execute instead of leaking `<tool_call>` markup;
- Discord output noise reduction;
- reactive file attachment support via `send_file` and `ATTACH_FILE` directives;
- standalone channel file-sending CLI for operational artifacts.

Before patching Picord again:

1. Check `/home/sv2bot/sv2bot-discord` Git status.
2. Prefer editing the fork, committing, and pushing to GitHub.
3. Only patch the globally installed npm package directly for emergency runtime repair.
4. If local runtime package edits are made, immediately port them back to the fork and update the vault.

Useful checks:

```bash
cd /home/sv2bot/sv2bot-discord
git status --short
git log --oneline -5
npm run typecheck
```

For syntax-only checks on patched TypeScript files when no build is desired:

```bash
node --check src/index.ts
node --check src/pi-session.ts
node --check src/live-discord-renderer.ts
node --check src/safe-tools.ts
node --check src/config.ts
node --check src/conversation.ts
node --check src/discord-port/discord-bot.ts
node --check src/discord-port/extension-bridge.ts
```

---

## Sending files to Discord

For proactive/channel file sending, prefer the maintained `sv2bot-discord` CLI:

```bash
cd /home/sv2bot/sv2bot-discord
set -a && source /home/sv2bot/.picord/.env && set +a
npm run send:file -- \
  --config /home/sv2bot/.picord/picord.config.json \
  --channel-id 1501133804058710116 \
  --file /home/sv2bot/vault/pool-hashrate.png \
  --message "Latest pool hashrate chart"
```

Dry run first:

```bash
cd /home/sv2bot/sv2bot-discord
set -a && source /home/sv2bot/.picord/.env && set +a
npm run send:file -- \
  --config /home/sv2bot/.picord/picord.config.json \
  --file /home/sv2bot/vault/pool-hashrate.png \
  --dry-run
```

The CLI:

- reads `PICORD_DISCORD_TOKEN` or `DISCORD_BOT_TOKEN`;
- reads config from `--config`, `PICORD_CONFIG`, or local `picord.config.json`;
- defaults to `PICORD_SEND_FILE_CHANNEL_ID` or the first `allowedChannelIds` entry when `--channel-id` is omitted;
- sends attachments with `allowedMentions: { parse: [] }`.

Reactive/session attachment support also exists in Picord-derived source:

- `send_file` custom tool validates a workspace-readable path;
- final answers can include `ATTACH_FILE: /path/to/file`;
- the Discord renderer strips that directive from visible text and attaches the file.

Preferred pool chart path:

```text
/home/sv2bot/vault/pool-hashrate.png
```

---

## Pool monitor Discord reports

Automated pool-monitor Discord reports are implemented in:

```text
{baseDir}/scripts/pool-monitor.sh
```

The script posts to Discord after it updates the vault dashboard and `pool-hashrate.png`. It reads the bot token from `/home/sv2bot/.picord/.env` and must never print it.

Relevant environment variables:

```text
SV2PI_POOL_MONITOR_DISCORD=0                 # disable Discord posting
SV2PI_POOL_MONITOR_DISCORD_CHANNEL_ID=<id>   # override target channel
SV2PI_PICORD_ENV=<path>                      # override Picord env file
```

Canonical report style is documented in `{baseDir}/domains/pool-monitor.md`. Preserve that style: concise SRI-branded header, no tables, inline-code values, attached PNG silently, no implementation-status footer.

Timer/service:

```bash
systemctl --user is-enabled sv2pi-pool-monitor.timer
systemctl --user is-active sv2pi-pool-monitor.timer
journalctl --user -u sv2pi-pool-monitor.service -n 30 --no-pager
```

---

## Discord interaction digests

Discord-originated Pi sessions are summarized into daily vault digests. Raw sessions remain the source of truth.

Generator:

```text
/home/sv2bot/.local/bin/sv2bot-discord-digest
```

Inputs:

```text
/home/sv2bot/.pi/agent/sessions/--home-sv2bot--/*.jsonl
```

Outputs:

```text
/home/sv2bot/vault/discord-digests/YYYY-MM-DD.md
/home/sv2bot/vault/discord-digests/index.md
```

Systemd units:

```text
/home/sv2bot/.config/systemd/user/sv2bot-discord-digest.service
/home/sv2bot/.config/systemd/user/sv2bot-discord-digest.timer
```

Useful commands:

```bash
# Generate today's digest manually
/home/sv2bot/.local/bin/sv2bot-discord-digest --today

# Generate a specific date
/home/sv2bot/.local/bin/sv2bot-discord-digest --date 2026-05-07

# Check timer
systemctl --user list-timers --all 'sv2bot-discord-digest.timer' --no-pager
systemctl --user status sv2bot-discord-digest.timer --no-pager

# Check logs
journalctl --user -u sv2bot-discord-digest.service -n 100 --no-pager
```

Caveats:

- The digest is heuristic.
- It only captures Discord-originated Pi sessions that Picord wrapped as `[Discord message]` prompts.
- It does not capture ambient Discord messages ignored before session creation.
- If Picord’s prompt wrapper changes, update the parser.

---

## Discord response style

For Discord-facing answers:

- Be concise unless the user asks for detail.
- Prefer bullets or short paragraphs.
- Avoid Markdown tables in responses; Discord renders them poorly. When tabular data must be shown, use an ASCII box table inside a fenced code block instead:
  ````
  ```
  +----------+--------------------+
  | Column A | Column B           |
  +----------+--------------------+
  | value    | description        |
  +----------+--------------------+
  ```
  ````
- Avoid model/thinking/context metadata footers.
- Avoid noisy tool/progress timelines in the visible Discord response.
- Use operationally useful summaries with clear next steps.
- Do not expose secrets, raw tokens, large logs, or huge command outputs.

For SRI community users, the goal is productive collaboration, not a maintenance PITA.

---

## Known failure modes and fixes

### Bot not in guild / `Unknown Guild`

Cause: bot invitation not accepted or wrong app/client ID.

Fix: invite bot to the guild, then verify guild/member/channel fetch with the Discord API probe above.

### Slash-only mode / message content unavailable

Cause: Message Content Intent disabled in Discord Developer Portal.

Fix: enable Message Content Intent, restart Picord, verify `full mode`.

### Bot can send but not read/view private channel

Cause: channel has `@everyone` deny and no explicit bot role/user allow for `View Channel`.

Fix: server admin must explicitly grant `View Channel` and normal message/thread permissions to bot role/user in the private channel.

### Messages in project channel are silently ignored

Possible causes:

- message did not mention `@sv2bot` and is correctly ignored;
- message used a role mention (`<@&...>`) instead of a direct bot-user mention, and direct-only bootstrap is enabled;
- `hostChannelId` is incorrectly set to the project channel;
- Picord is not running or not in `full mode`;
- access allowlists do not include the guild/channel.

Fix: verify config, runtime, and mention-gating behavior. For bootstrap tests, always use direct `<@1501137386631860254>` mention.

### Literal `<tool_call>{...}</tool_call>` appears in Discord

Cause: Picord failed to wire Pi tools as executable SDK tools.

Fix: restore/port `src/pi-session.ts` tool allowlist and `baseToolsOverride` / `customTools` patch from `sv2bot-discord`.

### Docker permission denied from Discord sessions

Cause: long-running Picord process did not inherit current Docker group membership.

Fix: restart Picord under `tmux -L picord-docker ...` so the process inherits Docker group access.

### New thread appears but bot reply is delayed or missing

Symptoms:

- A new thread is created from the mention, sometimes with only Discord system message (`type: 21`) initially.
- Bot may show `_thinking…_` later, then eventually produce a final answer.

Observed trigger pattern:

- Discord typing-indicator API (`sendTyping`) can stall/timeout and delay visible feedback.
- This does not necessarily mean `respond()` failed.

Stability guidance:

- Do not block response flow on `sendTyping`; treat typing as best-effort.
- Keep direct-mention bootstrap and avoid role-mention bootstrap for new sessions.
- Wait up to ~60 seconds before declaring failure on first-thread reply.

Targeted diagnostics:

```bash
# Runtime status
 tmux -L picord-docker capture-pane -t picord -p -S -200

# Verify latest channel/thread state (system message vs _thinking…_ vs final answer)
 cd /home/sv2bot/sv2bot-discord
 set -a && source /home/sv2bot/.picord/.env && set +a
 node --input-type=module - <<'NODE'
import { Client, GatewayIntentBits } from 'discord.js';
const token=process.env.PICORD_DISCORD_TOKEN;
const channelId='1501133804058710116';
const client=new Client({intents:[GatewayIntentBits.Guilds,GatewayIntentBits.GuildMessages]});
client.once('ready', async () => {
  const ch=await client.channels.fetch(channelId);
  const threads=await ch.threads.fetchActive();
  const recent=[...threads.threads.values()].sort((a,b)=>b.createdTimestamp-a.createdTimestamp).slice(0,2);
  for (const t of recent) {
    console.log(`thread ${t.id} ${t.name}`);
    const msgs=await t.messages.fetch({limit:10});
    for (const m of [...msgs.values()].sort((a,b)=>a.createdTimestamp-b.createdTimestamp)) {
      console.log(new Date(m.createdTimestamp).toISOString(), m.author.tag, 'type', m.type, JSON.stringify(m.content));
    }
  }
  await client.destroy();
});
client.login(token);
NODE
```

### PPQ multi-auth failure

Symptom:

```text
Provider error: multi-auth rotation failed for ppq: No credentials available for ppq.
```

Fix: read `{baseDir}/domains/ppq-monitor.md`. Do not print secrets. Verify Pi `models.json`, `auth.json`, and `multi-auth.json` state carefully, then restart Picord.

### Local Picord edits disappeared after reinstall/update

Cause: edits were made in the globally installed npm package and overwritten.

Fix: restore from `/home/sv2bot/sv2bot-discord`, then port any runtime-only patch back to the fork and update patch inventory/vault.

---

## Bootstrap/rebuild checklist

For a future full re-bootstrap of `sv2bot` Discord access:

1. Read `$HOME/vault/README.md`, the Discord synthesis note, and this domain.
2. Verify GitHub source: `/home/sv2bot/sv2bot-discord` and `https://github.com/SV2-bot/sv2bot-discord`.
3. Install/prepare Picord runtime from the maintained fork when practical; avoid accumulating new untracked global npm edits.
4. Create or verify `/home/sv2bot/.picord/.env` with the Discord token — do not print it.
5. Create or verify `/home/sv2bot/.picord/picord.config.json` with the intended access posture and authority policy.
6. Ensure Discord bot is invited, Message Content Intent is enabled, and private-channel permissions are correct.
7. Start Picord with `tmux -L picord-docker ...`.
8. Verify `full mode`, guild/channel access, mention-gated thread creation, tool execution, and Docker access.
9. Verify pool monitor Discord report path if required.
10. Verify daily Discord digest timer if persistent community-memory logging is required.
11. Update the vault with the final state, caveats, and any new commands.

If all of this is in place, `/skill:sv2pi` should be enough to recover the Discord-facing `sv2bot` deployment in a future session.
