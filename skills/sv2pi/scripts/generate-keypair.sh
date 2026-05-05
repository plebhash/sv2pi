#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

err() { printf '%bERROR:%b %s\n' "${RED}" "${NC}" "$*" >&2; }
ok()  { printf '%bOK:%b %s\n' "${GREEN}" "${NC}" "$*"; }

printf '\n%bGenerating Noise authority keypair...%b\n' "${CYAN}" "${NC}"
echo '  Using: rust:1.75-slim via Docker (no local Rust toolchain required)'
echo '  Crate: key-utils v1.2.0 (stratum-mining)'
echo ''

TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/src"

cat > "$TMPDIR/src/main.rs" <<'RUST'
use secp256k1::{Secp256k1, SecretKey};
use key_utils::{Secp256k1SecretKey, Secp256k1PublicKey};

fn main() {
    let secp = Secp256k1::new();
    let (secret_key, _) = secp.generate_keypair(&mut rand::thread_rng());

    let k = Secp256k1SecretKey(secret_key);
    let pubkey: Secp256k1PublicKey = k.into();

    println!("authority_public_key = \"{}\"", pubkey.to_string());
    println!("authority_secret_key = \"{}\"", k.to_string());
}
RUST

cat > "$TMPDIR/Cargo.toml" <<'TOML'
[package]
name = "keygen"
version = "0.1.0"
edition = "2021"

[dependencies]
key-utils = "1.2"
secp256k1 = { version = "0.28", features = ["rand-std"] }
rand = "0.8"
TOML

docker run --rm --network host \
    -v "$TMPDIR:/build" \
    -w /build \
    rust:1.75-slim \
    bash -c 'cargo run --release --quiet'

rm -rf "$TMPDIR"

echo ''
ok 'keypair generated'
echo ''
echo 'Copy these into your pool/jdc config TOML and share the public key with downstream apps.'