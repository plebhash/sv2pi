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

cat > /tmp/generate-keypair.rs <<'RUST'
use key_utils::Secp256k1SecretKey;
use std::str::FromStr;

fn main() {
    let key = Secp256k1SecretKey::new();
    let pubkey = key.public_key();
    let secret = key.to_string();  // base58 encoded
    let public = pubkey.to_string();

    println!("authority_public_key = \"{}\"", public);
    println!("authority_secret_key = \"{}\"", secret);
}
RUST

cat > /tmp/keygen-crate <<'TOML'
[package]
name = "keygen"
version = "0.1.0"
edition = "2021"

[dependencies]
key-utils = "1.2"
TOML

docker run --rm \
    -v /tmp/generate-keypair.rs:/build/src/main.rs:ro \
    -v /tmp/keygen-crate:/build/Cargo.toml:ro \
    -w /build \
    rust:1.75-slim \
    bash -c 'mkdir -p src && cargo run --release --quiet 2>/dev/null'

rm -f /tmp/generate-keypair.rs /tmp/keygen-crate

echo ''
ok 'keypair generated'
echo ''
echo 'Copy these into your pool/jdc config TOML and share the public key with downstream apps.'
