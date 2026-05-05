<p align="center">
  <img src="https://avatars.githubusercontent.com/u/205658058?v=4" width="128" alt="sv2pi logo">
</p>

<h1 align="center">🤖 sv2pi ⛏️</h1>

<p align="center"><a href="https://pi.dev" target="_blank">Pi</a> skill for <strong>agentic deployment</strong> of the <a href="https://stratumprotocol.org/">Stratum V2 Reference Implementation (SRI)</a> <br>for decentralized and efficient Bitcoin Mining.</p>

## Scope

- **Production mainnet deployments only.** Not a development or testing tool.
- Docker-based deployment of SRI apps from [Docker Hub](https://hub.docker.com/u/stratumv2).
- Orchestrates:
  - [`stratumv2/pool_sv2`](https://hub.docker.com/r/stratumv2/pool_sv2/tags) ✅
  - [`stratumv2/jd_client_sv2`](https://hub.docker.com/r/stratumv2/jd_client_sv2/tags) ✅
  - [`stratumv2/translator_sv2`](https://hub.docker.com/r/stratumv2/translator_sv2/tags) ✅
  - [`stratumv2/sv2-ui`](https://hub.docker.com/r/stratumv2/sv2/tags) ❌ soon ™️


| In scope | Out of scope |
|---|---|
| Docker-based deployment | Rust source builds |
| Rust source code analysis | sv2-ui (planned for next iteration) |
| Production mainnet | Devnet / testnet / regtest |
| Bitcoin Core deployment with IPC | Mock / headless Bitcoin Core |
| Crash diagnostics | E2E testing |

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/plebhash/sv2pi/refs/heads/main/sv2pi.sh | sh
```

Or manually:

```
pi install git:github.com/plebhash/sv2pi
```

Then invoke with `/skill:sv2pi` from any project.

## Requirements

- [Pi Coding Agent](https://pi.dev/)
- [Docker](https://docs.docker.com/engine/install/)

## Contributing

See [AGENTS.md](AGENTS.md) for the worktree-based feature workflow, commit conventions, and skill development guidance.

## License

MIT
