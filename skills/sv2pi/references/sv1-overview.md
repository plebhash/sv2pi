# Stratum V1 Mining Protocol Overview

**There is no formal BIP or official specification for Stratum V1.** The protocol evolved organically through pool implementations, forum discussion, and community documentation. The canonical reference is the [Bitcoin Wiki: Stratum mining protocol](https://en.bitcoin.it/wiki/Stratum_mining_protocol), which this document distills for sv2pi deployment context.

Stratum V1 replaced the obsolete `getwork` (HTTP pull-based) protocol in late 2012. It was first deployed by Slush's Pool and later documented by BTCGuild as a "cheat sheet."

## Transport and Encoding

```
+------------+------------------------------------------+-----------------------------------------------+
| Property   | SV1                                      | SV2 (for contrast)                            |
+------------+------------------------------------------+-----------------------------------------------+
| Encoding   | JSON-RPC 2.0 (text)                      | Binary framing                                |
| Transport  | Plain TCP (persistent socket)            | TCP with Noise encryption                     |
| Framing    | Newline-delimited (\n)                   | Length-prefixed binary frames                 |
| Security   | None - plaintext                         | Authenticated encryption (Noise NX/KK/HH)    |
| Bandwidth  | High (verbose JSON, hex-encoded fields)  | Low (compact binary)                          |
+------------+------------------------------------------+-----------------------------------------------+
```

SV1 is a simple line-based protocol: each JSON-RPC message is a single line terminated by `\n`. The client and server exchange JSON-RPC requests, responses, and notifications over a persistent TCP connection.

## SV1 Handshake

Every new connection begins with the SV1 handshake — a 3-step exchange that
initializes the session, authenticates the worker, and delivers the first mining job:

```
miner -> pool: mining.subscribe(user_agent, optional_resume_id)
pool  -> miner: subscription ids, extranonce1, extranonce2_size

miner -> pool: mining.authorize(username, password)
pool  -> miner: true / false

pool  -> miner: mining.set_difficulty(difficulty)
pool  -> miner: mining.notify(job...)
```

After the handshake completes, the miner enters the steady-state loop:

```
miner -> pool: mining.submit(username, job_id, ExtraNonce2, nTime, nOnce)
pool  -> miner: true / false

pool  -> miner: mining.notify(...)           ← new block or forced job
pool  -> miner: mining.set_difficulty(...)   ← difficulty adjustment (any time)

miner -> pool: mining.submit(...)
        ... repeat ...
```

### Handshake variance

**There is no canonical standard for the SV1 handshake.** The 3-step flow above
reflects common practice, but message ordering varies across pool implementations.
Known divergences include:

- `mining.set_difficulty` may arrive **before** `mining.subscribe`'s response,
  interleaved with it, or bundled inside the subscription result.
- `mining.notify` may arrive **before** `mining.authorize` completes, or may be
  sent immediately after the subscribe response (before the miner even authorizes).
- Some pools do not send `mining.set_difficulty` at all, expecting the miner to
  assume a default.
- The first `mining.notify` may or may not carry `clean_jobs=true`.

Robust SV1 clients must tolerate any interleaving of `mining.set_difficulty` and
`mining.notify` with the subscribe/authorize exchange. Do not assume a fixed
sequence — buffer notifications and apply them once authorization succeeds.

If a connection drops, the miner must reconnect and perform the full handshake
from scratch. The optional resume ID in `mining.subscribe` *hints* that the miner
wants the same extranonce1, but pools are not required to honor it.

## Methods (Client → Server)

### mining.subscribe
```
→ mining.subscribe("user agent/version", "extranonce1")
← [[["mining.set_difficulty","sub-id-1"],["mining.notify","sub-id-2"]], "extranonce1", extranonce2_size]
```

The first message a miner sends. Returns:
- **Subscription IDs** — two tuples mapping `mining.set_difficulty` and `mining.notify` to subscription IDs for this connection.
- **extranonce1** — a hex-encoded, per-connection unique string. The miner inserts this into the generation (coinbase) transaction.
- **extranonce2_size** — number of bytes the miner uses for its `ExtraNonce2` counter (typically 4, giving 2^32 unique values).

The optional second parameter requests resumption of a prior session's extranonce1 (servers may honor it).

### mining.authorize
```
→ mining.authorize("username", "password")
← true / false
```

Authenticates the worker. The username typically identifies the worker (e.g. `"username.workername"`). The password may be omitted if the pool does not require one.

### mining.submit
```
→ mining.submit("username", "job_id", "ExtraNonce2", "nTime", "nOnce")
← true / false
```

Submits a share (proof of work). Parameters:
1. **Worker name** — matches the authorized username.
2. **Job ID** — identifies which `mining.notify` job this share belongs to.
3. **ExtraNonce2** — hex-encoded counter value (length determined by `extranonce2_size`).
4. **nTime** — hex-encoded timestamp (32-bit Unix epoch, big-endian). Miners may roll this to extend the nonce search space.
5. **nOnce** — hex-encoded nonce (32-bit). Together with the job-specific fields, this determines the block header hash.

The pool responds `true` if the share meets the pool's difficulty target, `false` otherwise.

### mining.suggest_difficulty
```
→ mining.suggest_difficulty(preferred_difficulty_float)
```

Miner requests a preferred share difficulty. Servers are **not required** to honor this.

### mining.suggest_target
```
→ mining.suggest_target("hex_target")
```

Same intent as `suggest_difficulty` but expressed as a full hex target. Also advisory only.

### mining.extranonce.subscribe
```
→ mining.extranonce.subscribe()
```

Indicates that the miner supports the `mining.set_extranonce` server notification (allows the pool to change extranonce1 mid-session).

### mining.get_transactions
```
→ mining.get_transactions("job_id")
← [array of hex-encoded transactions]
```

Requests the full transaction set for a given job. Used by miners that perform their own block template verification.

## Methods (Server → Client)

### mining.notify
```
← {"method": "mining.notify", "params": ["job_id", "prevhash", "coinb1", "coinb2", "merkle_branches", "version", "nbits", "ntime", clean_jobs]}
```

The core job distribution message. Each notification provides everything needed to construct a valid block header:

```
+-----------------+---------------------------------------------------------------------+
| Field           | Description                                                         |
+-----------------+---------------------------------------------------------------------+
| job_id          | Unique identifier for this job                                      |
| prevhash        | Hash of the previous block (32-byte hex, little-endian)             |
| coinb1          | Generation transaction, part 1 (hex)                                |
| coinb2          | Generation transaction, part 2 (hex)                                |
| merkle_branches | Array of hex merkle siblings for computing the merkle root          |
| version         | Bitcoin block version (4-byte hex, little-endian)                   |
| nbits           | Encoded network difficulty target (4-byte hex, as in block header)  |
| ntime           | Current network time (4-byte hex, little-endian)                    |
| clean_jobs      | Boolean - if true, miner must discard current work immediately      |
+-----------------+---------------------------------------------------------------------+
```

### Block Header Construction

The miner assembles the block header by:

1. **Construct the coinbase transaction**: `coinb1 + extranonce1 + extranonce2 + coinb2`
2. **Compute the merkle root**: hash the coinbase transaction with each merkle branch.
3. **Assemble the 80-byte header**:
   ```
   version (4 LE) + prevhash (32 LE) + merkle_root (32 LE) + ntime (4 LE) + nbits (4 LE) + nonce (4 LE)
   ```
4. Hash with SHA-256d and compare to the target.

nTime rolling is supported: miners may increment `nTime` to extend the search space beyond 2^32 nonces. nTime must not advance faster than real clock time.

### mining.set_difficulty
```
← mining.set_difficulty(difficulty_float)
```

The pool adjusts the miner's share difficulty. The miner should apply this on the next job. Some pools force a new `mining.notify` with `clean_jobs=true` to apply it immediately.

### mining.set_extranonce
```
← mining.set_extranonce("extranonce1", extranonce2_size)
```

Replaces the initial subscription extranonce1 and extranonce2_size. Takes effect beginning with the next `mining.notify`.

### client.reconnect
```
← client.reconnect("hostname", port, wait_seconds)
```

Instructs the miner to disconnect, wait, and reconnect to a (possibly different) server.

### client.get_version / client.show_message
```
← client.get_version()
← client.show_message("message")
```

`get_version` asks the miner to identify its software. `show_message` asks the miner to display a message to the user.

## SV1 in the sv2pi Deployment Context

SV1 miners connect to the **translator_sv2** proxy on port **34255**:

```
SV1 Miner ──(SV1 plain JSON-RPC)──► translator_sv2:34255
                                         └──(SV2 Noise-encrypted)──► JDC:34265 or Pool:3333
```

The translator:
- Terminates SV1 JSON-RPC connections
- Translates `mining.subscribe` → SV2 `SetupConnection`
- Translates `mining.authorize` → SV2 `SetCustomMiningJob` or `OpenStandardMiningChannel`
- Translates `mining.submit` → SV2 `SubmitShares`
- Translates SV2 `NewMiningJob` → SV1 `mining.notify`
- Translates SV2 `SetNewPrevHash` → SV1 `mining.notify` with updated prevhash
- Manages vardiff by translating SV2 difficulty messages to SV1 `mining.set_difficulty`
- Handles extranonce derivation (translator owns extranonce1, assigns extranonce2 ranges to each downstream miner)

## Key Observations for Mining Pool Debugging

- **All SV1 traffic is plaintext.** Any intermediary on the network path can see worker credentials, job data, and shares. This is why SV1 is considered insecure for production deployments without additional network-layer security (VPN, WireGuard, etc.).
- **The pool controls block templates entirely.** Miners have no input on transaction selection — they simply hash whatever the pool sends. This is the centralization problem SV2's Job Declaration Protocol addresses.
- **Extranonce1 is a session identifier.** If two miners share the same extranonce1 (e.g., through connection cloning), they will produce duplicate shares that appear as stale or invalid to the pool.
- **nTime rolling is common.** Miners increment `nTime` to get more nonce space. Pools must tolerate nTime values slightly ahead of the current time.
- **JSON parse errors are the #1 SV1 interop problem.** Deviations from expected field types or ordering can cause silent failures. Reference implementations are inconsistent across pool software and miner firmware.
