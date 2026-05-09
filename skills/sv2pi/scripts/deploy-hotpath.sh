#!/usr/bin/env bash
set -euo pipefail

NO_BUILD=false
BUILD_ONLY=false
CHECK_ONLY=false
NO_RESET=false
NO_CACHE=false
HOTPATH_ALLOC=false
SERVICES=()

i=1
while [ $i -le $# ]; do
    arg="${!i}"
    case "$arg" in
        --no-build)      NO_BUILD=true   ;;
        --build-only)    BUILD_ONLY=true ;;
        --check)         CHECK_ONLY=true ;;
        --no-reset)      NO_RESET=true   ;;
        --no-cache)      NO_CACHE=true   ;;
        --hotpath-alloc) HOTPATH_ALLOC=true ;;
        pool|jdc|translator) SERVICES+=("${arg}_sv2") ;;
        *)
            if [ $i -eq 1 ] && [[ "$arg" != --* ]]; then
                VERSION="$arg"
            else
                echo "ERROR: Unknown argument: $arg"
                echo "  Accepted: pool jdc translator --no-build --build-only --check --no-reset --no-cache --hotpath-alloc"
                exit 1
            fi
            ;;
    esac
    i=$((i+1))
done

VERSION="${VERSION:-}"

if [ -z "$VERSION" ]; then
    echo "ERROR: Version required."
    echo "Usage: $0 <version> [flags] [pool] [jdc] [translator]"
    echo "  version:         SRI release version (e.g. 0.4.0). Must be >= 0.4.0."
    echo "  --no-build:      skip clone+build, just docker compose up -d."
    echo "  --build-only:    clone+build but do not start containers."
    echo "  --check:         validate prerequisites only, no build or deployment."
    echo "  --no-reset:      if clone exists, do not git checkout (preserve local edits)."
    echo "  --no-cache:      pass --no-cache to docker compose build."
    echo "  --hotpath-alloc: pass HOTPATH_FEATURES=hotpath-alloc to docker compose build."
    echo "  pool|jdc|translator: services to deploy. Omit to deploy all three."
    echo ""
    echo "  Environment variables:"
    echo "    BITCOIN_IPC_PATH  - path to IPC socket (default: ~/.sv2pi/bitcoin/data/node.sock)"
    echo "    CONFIG_POOL       - pool config dir (default: ~/.sv2pi/pool/config)"
    echo "    CONFIG_JDC        - JDC config dir (default: ~/.sv2pi/jdc/config)"
    echo "    CONFIG_TPROXY     - translator config dir (default: ~/.sv2pi/translator/config)"
    echo "    DATA_POOL         - pool data dir (default: ~/.sv2pi/pool/data)"
    exit 1
fi

MAJOR=$(echo "$VERSION" | cut -d. -f1)
MINOR=$(echo "$VERSION" | cut -d. -f2)

if [ "$MAJOR" -eq 0 ] && [ "$MINOR" -lt 4 ]; then
    echo "ERROR: Hotpath-enabled builds require SRI version >= 0.4.0. Got: $VERSION"
    exit 1
fi

BITCOIN_IPC_PATH="${BITCOIN_IPC_PATH:-$HOME/.sv2pi/bitcoin/data/node.sock}"
CONFIG_POOL="${CONFIG_POOL:-$HOME/.sv2pi/pool/config}"
CONFIG_JDC="${CONFIG_JDC:-$HOME/.sv2pi/jdc/config}"
CONFIG_TPROXY="${CONFIG_TPROXY:-$HOME/.sv2pi/translator/config}"
DATA_POOL="${DATA_POOL:-$HOME/.sv2pi/pool/data}"

ALL_SERVICES=(pool_sv2 jd_client_sv2 translator_sv2)
if [ ${#SERVICES[@]} -eq 0 ]; then
    SERVICES=("${ALL_SERVICES[@]}")
fi

SERVICE_NAMES=""
for svc in "${SERVICES[@]}"; do
    SERVICE_NAMES="$SERVICE_NAMES $svc"
done

echo "=== Deploying: $SERVICE_NAMES ==="

NEED_IPC=""
for svc in "${SERVICES[@]}"; do
    case "$svc" in
        pool_sv2|jd_client_sv2) NEED_IPC=1 ;;
    esac
done

if [ -n "$NEED_IPC" ]; then
    if [ ! -S "$BITCOIN_IPC_PATH" ]; then
        echo "ERROR: Bitcoin IPC socket not found at: $BITCOIN_IPC_PATH"
        echo "  Verify Bitcoin Core is running with -ipcbind=unix"
        exit 1
    fi
fi

for svc in "${SERVICES[@]}"; do
    case "$svc" in
        pool_sv2)
            if [ ! -d "$CONFIG_POOL" ]; then
                echo "ERROR: Pool config directory not found: $CONFIG_POOL"
                echo "  Deploy standard pool first to generate configs (expected: pool-config.toml)."
                exit 1
            fi
            mkdir -p "$DATA_POOL"
            ;;
        jd_client_sv2)
            if [ ! -d "$CONFIG_JDC" ]; then
                echo "ERROR: JDC config directory not found: $CONFIG_JDC"
                echo "  Deploy standard JDC first to generate configs (expected: jdc-config.toml)."
                exit 1
            fi
            ;;
        translator_sv2)
            if [ ! -d "$CONFIG_TPROXY" ]; then
                echo "ERROR: Translator config directory not found: $CONFIG_TPROXY"
                echo "  Deploy standard translator first to generate configs (expected: tproxy-config.toml)."
                exit 1
            fi
            ;;
    esac
done

if [ "$CHECK_ONLY" = true ]; then
    echo "=== Pre-flight check passed ==="
    exit 0
fi

HOTPATH_TAG="v${VERSION}-hotpath-rs"
HOTPATH_CLONE="/tmp/sv2-apps-hotpath-v${VERSION}"

export BITCOIN_SOCKET_PATH="$BITCOIN_IPC_PATH"
export BITCOIN_IPC_DIR=$(dirname "$BITCOIN_IPC_PATH")
export CONFIG_POOL CONFIG_JDC CONFIG_TPROXY DATA_POOL

if [ "$NO_BUILD" = true ]; then
    echo "=== Skipping build (--no-build) ==="
else
    echo "=== Stopping existing containers ==="
    docker rm -f $SERVICE_NAMES 2>/dev/null || true

    if [ -d "$HOTPATH_CLONE/.git" ]; then
        if [ "$NO_RESET" = true ]; then
            echo "=== Clone exists, preserving local edits (--no-reset) ==="
        else
            echo "=== Updating clone to $HOTPATH_TAG ==="
            git -C "$HOTPATH_CLONE" fetch origin "$HOTPATH_TAG" --depth 1
            if git -C "$HOTPATH_CLONE" diff --quiet; then
                git -C "$HOTPATH_CLONE" checkout "$HOTPATH_TAG"
            else
                echo "WARNING: Local edits detected in $HOTPATH_CLONE."
                echo "  git checkout would overwrite them. Use --no-reset to skip."
                echo "  Run with --no-build to use existing images, or clone fresh."
                exit 1
            fi
        fi
    else
        rm -rf "$HOTPATH_CLONE"
        echo "=== Cloning SV2-bot/sv2-apps at $HOTPATH_TAG ==="
        git clone --branch "$HOTPATH_TAG" --depth 1 https://github.com/SV2-bot/sv2-apps "$HOTPATH_CLONE"
    fi

    BUILD_ARGS=()
    if [ "$NO_CACHE" = true ]; then
        BUILD_ARGS+=(--no-cache)
    fi
    if [ "$HOTPATH_ALLOC" = true ]; then
        BUILD_ARGS+=(--build-arg HOTPATH_FEATURES=hotpath-alloc)
    fi

    echo "=== Building hotpath images ==="
    docker compose -f "$HOTPATH_CLONE/docker/docker-compose.yml" build "${BUILD_ARGS[@]}" $SERVICE_NAMES

    echo "=== Validating built images ==="
    for svc in "${SERVICES[@]}"; do
        base="${svc%_sv2}"
        if ! docker image inspect "${base}_sv2:hotpath" >/dev/null 2>&1; then
            echo "ERROR: Image ${base}_sv2:hotpath not found after build"
            exit 1
        fi
    done
    echo "All images validated."
fi

if [ "$BUILD_ONLY" = true ]; then
    echo "=== Build-only mode, skipping deploy ==="
    exit 0
fi

echo "=== Starting hotpath-enabled services ==="
docker compose -f "$HOTPATH_CLONE/docker/docker-compose.yml" up -d $SERVICE_NAMES

echo "=== Running health probes ==="
sleep 3
for svc in "${SERVICES[@]}"; do
    case "$svc" in
        pool_sv2)
            echo -n "  pool_sv2:    "
            curl -sf http://localhost:9090/api/v1/health >/dev/null 2>&1 && echo "OK" || echo "UNREACHABLE"
            echo -n "  hotpath:     "
            nc -z localhost 6771 2>/dev/null && echo "OK" || echo "CLOSED"
            ;;
        jd_client_sv2)
            echo -n "  jd_client:   "
            curl -sf http://localhost:9091/api/v1/health >/dev/null 2>&1 && echo "OK" || echo "UNREACHABLE"
            echo -n "  hotpath:     "
            nc -z localhost 6772 2>/dev/null && echo "OK" || echo "CLOSED"
            ;;
        translator_sv2)
            echo -n "  translator:  "
            curl -sf http://localhost:9092/api/v1/health >/dev/null 2>&1 && echo "OK" || echo "UNREACHABLE"
            echo -n "  hotpath:     "
            nc -z localhost 6773 2>/dev/null && echo "OK" || echo "CLOSED"
            ;;
    esac
done

echo ""
echo "=== Hotpath-enabled SRI apps deployed ==="
echo "  Tag:      $HOTPATH_TAG"
echo "  Repo:     https://github.com/SV2-bot/sv2-apps"
echo ""
PORT_TABLE() {
cat <<'PORTS'
  Port mappings:
    pool_sv2:       http://localhost:9090 (monitoring)  localhost:3333 (stratum)  localhost:6771 (hotpath)
    jd_client_sv2:  http://localhost:9091 (monitoring)  localhost:34265 (sv2)     localhost:6772 (hotpath)
    translator_sv2: http://localhost:9092 (monitoring)  localhost:34255 (sv1)     localhost:6773 (hotpath)
PORTS
}
PORT_TABLE
echo ""
echo "Logs:"
for svc in "${SERVICES[@]}"; do
    echo "  docker logs $svc --tail 50"
done
