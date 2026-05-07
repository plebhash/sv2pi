#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="${9:-$HOME/.sv2pi/cpu-miner/src}"
CONFIG_FILE="$SRC_DIR/config.toml"
RUST_IMAGE="rust:latest"
CONTAINER_NAME="sv2-cpu-miner"

SERVER_ADDR="${1:-}"
AUTH_PK="${2:-}"
N_EXTENDED="${3:-}"
N_STANDARD="${4:-}"
CPU_USAGE="${5:-}"
USER_IDENTITY="${6:-username}"
HASHRATE_MULT="${7:-1.0}"
SINGLE_SUBMIT="${8:-false}"
DEVICE_ID="${10:-sv2-cpu-miner}"

usage() {
    echo "Usage: $0 <server_addr> <auth_pk> <n_extended_channels> <n_standard_channels> <cpu_usage_percent>"
    echo "          [user_identity] [nominal_hashrate_multiplier] [single_submit] [src_dir] [device_id]"
    echo ""
    echo "Required:"
    echo "  server_addr             Pool or JDC Stratum endpoint (e.g. 127.0.0.1:3333)"
    echo "  auth_pk                 Authority public key of the mining server"
    echo "  n_extended_channels     Number of Extended (Group) channels to open (0 for direct pool)"
    echo "  n_standard_channels     Number of Standard channels to open"
    echo "  cpu_usage_percent       CPU throttle 1-100 (100 = full speed)"
    echo ""
    echo "Optional:"
    echo "  user_identity           Identity string for Sv2 channel opening (default: username)"
    echo "  nominal_hashrate_multiplier  Multiplier on advertised hashrate (default: 1.0)"
    echo "  single_submit           Stop after first share per channel (default: false)"
    echo "  src_dir                 Clone destination (default: ~/.sv2pi/cpu-miner/src)"
    echo "  device_id               Device identifier (default: sv2-cpu-miner)"
    exit 1
}

if [ -z "$SERVER_ADDR" ] || [ -z "$AUTH_PK" ] || [ -z "$N_EXTENDED" ] || [ -z "$N_STANDARD" ] || [ -z "$CPU_USAGE" ]; then
    echo "ERROR: Missing required arguments."
    usage
fi

# Validate port in server_addr
SERVER_PORT="${SERVER_ADDR##*:}"
if ! [[ "$SERVER_PORT" =~ ^[0-9]+$ ]] || [ "$SERVER_PORT" -lt 1 ] || [ "$SERVER_PORT" -gt 65535 ]; then
    echo "ERROR: Invalid port in server_addr: $SERVER_ADDR"
    exit 1
fi

# Validate channel counts
if ! [[ "$N_EXTENDED" =~ ^[0-9]+$ ]] || [ "$N_EXTENDED" -lt 0 ]; then
    echo "ERROR: n_extended_channels must be a non-negative integer"
    exit 1
fi
if ! [[ "$N_STANDARD" =~ ^[0-9]+$ ]] || [ "$N_STANDARD" -lt 0 ]; then
    echo "ERROR: n_standard_channels must be a non-negative integer"
    exit 1
fi
if [ "$N_EXTENDED" -eq 0 ] && [ "$N_STANDARD" -eq 0 ]; then
    echo "ERROR: At least one channel (extended or standard) must be > 0"
    exit 1
fi

# Validate cpu_usage_percent
if ! [[ "$CPU_USAGE" =~ ^[0-9]+$ ]] || [ "$CPU_USAGE" -lt 1 ] || [ "$CPU_USAGE" -gt 100 ]; then
    echo "ERROR: cpu_usage_percent must be an integer between 1 and 100"
    exit 1
fi

echo "=== Cloning sv2-cpu-miner ==="
if [ -d "$SRC_DIR/.git" ]; then
    echo "  Source already exists at $SRC_DIR — pulling latest..."
    git -C "$SRC_DIR" fetch origin main --depth 1 2>/dev/null || true
    git -C "$SRC_DIR" checkout main 2>/dev/null || true
    git -C "$SRC_DIR" pull origin main --depth 1 2>/dev/null || true
else
    mkdir -p "$(dirname "$SRC_DIR")"
    git clone --depth 1 https://github.com/plebhash/sv2-cpu-miner "$SRC_DIR"
fi

echo ""
echo "=== Writing config.toml ==="
cat > "$CONFIG_FILE" <<TOML
# address of the mining server
server_addr = "$SERVER_ADDR"

# public key of the mining server
auth_pk = "$AUTH_PK"

# how many Sv2 channels to open
n_extended_channels = $N_EXTENDED
n_standard_channels = $N_STANDARD

# user_identity string for Sv2 channel opening messages
user_identity = "$USER_IDENTITY"

# device_id string for Sv2 connection
device_id = "$DEVICE_ID"

# flag to stop hashing on the job after submitting the first share
single_submit = $SINGLE_SUBMIT

# CPU usage percentage (1-100)
cpu_usage_percent = $CPU_USAGE

# value to multiply the advertised nominal hashrate during channel opening
nominal_hashrate_multiplier = $HASHRATE_MULT
TOML

echo ""
echo "=== Pulling Rust Docker image ($RUST_IMAGE) ==="
docker pull "$RUST_IMAGE"

echo ""
echo "=== Building and launching sv2-cpu-miner ==="
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

docker run -d \
    --name "$CONTAINER_NAME" \
    --network host \
    -v "$SRC_DIR:/app" \
    -w /app \
    "$RUST_IMAGE" \
    bash -c 'cargo build --release && cargo run --release -- -c config.toml'

echo ""
echo "=== Sv2 CPU Miner deployed ==="
echo "  Container:        $CONTAINER_NAME"
echo "  Image:            $RUST_IMAGE"
echo "  Source:           $SRC_DIR"
echo "  Config:           $CONFIG_FILE"
echo "  Server:           $SERVER_ADDR"
echo "  Extended channels: $N_EXTENDED"
echo "  Standard channels: $N_STANDARD"
echo "  CPU usage:        $CPU_USAGE%"
echo ""
echo "Compilation takes 2-5 minutes. Monitor with:"
echo "  docker logs $CONTAINER_NAME --tail 10"
echo ""
echo "Verify shares flowing:"
echo "  docker logs $CONTAINER_NAME --tail 50 | grep -E 'Submitting share'"
