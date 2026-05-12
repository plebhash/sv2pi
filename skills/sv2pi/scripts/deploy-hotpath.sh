#!/usr/bin/env bash
set -euo pipefail

NO_BUILD=false
BUILD_ONLY=false
CHECK_ONLY=false
NO_RESET=false
NO_CACHE=false
HOTPATH_ALLOC=false
MONITORING_BIND_MODE="${MONITORING_BIND_MODE:-localhost}"
MONITORING_BIND_IP="${MONITORING_BIND_IP:-}"
HOTPATH_WG_RELAYS_MODE="${HOTPATH_WG_RELAYS_MODE:-auto}"
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
        --monitoring-localhost)
            MONITORING_BIND_MODE="localhost"
            MONITORING_BIND_IP=""
            ;;
        --monitoring-wireguard)
            i=$((i+1))
            if [ $i -gt $# ]; then
                echo "ERROR: --monitoring-wireguard requires a WireGuard IP argument"
                exit 1
            fi
            MONITORING_BIND_MODE="wireguard"
            MONITORING_BIND_IP="${!i}"
            ;;
        --hotpath-wireguard-relays)
            HOTPATH_WG_RELAYS_MODE="on"
            ;;
        --no-hotpath-wireguard-relays)
            HOTPATH_WG_RELAYS_MODE="off"
            ;;
        pool|jdc|translator)
            if [ "$arg" = "jdc" ]; then
                SERVICES+=("jd_client_sv2")
            else
                SERVICES+=("${arg}_sv2")
            fi
            ;;
        *)
            if [ $i -eq 1 ] && [[ "$arg" != --* ]]; then
                VERSION="$arg"
            else
                echo "ERROR: Unknown argument: $arg"
                echo "  Accepted: pool jdc translator --no-build --build-only --check --no-reset --no-cache --hotpath-alloc --monitoring-localhost --monitoring-wireguard <wireguard-ip> --hotpath-wireguard-relays --no-hotpath-wireguard-relays"
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
    echo "  --hotpath-alloc: pass HOTPATH_FEATURES=hotpath-alloc,hotpath-mcp to docker compose build."
    echo "  --monitoring-localhost: bind monitoring APIs to localhost only (default)."
    echo "  --monitoring-wireguard <ip>: bind monitoring APIs to the provided WireGuard IP."
    echo "  --hotpath-wireguard-relays: expose profiler+MCP on WireGuard IP (default in wireguard mode)."
    echo "  --no-hotpath-wireguard-relays: keep profiler+MCP localhost-only even in wireguard mode."
    echo "  pool|jdc|translator: services to deploy. Omit to deploy all three."
    echo ""
    echo "  Environment variables:"
    echo "    BITCOIN_IPC_PATH  - path to IPC socket (default: ~/.sv2pi/bitcoin/data/node.sock)"
    echo "    CONFIG_POOL       - pool config dir (default: ~/.sv2pi/pool/config)"
    echo "    CONFIG_JDC        - JDC config dir (default: ~/.sv2pi/jdc/config)"
    echo "    CONFIG_TPROXY     - translator config dir (default: ~/.sv2pi/translator/config)"
    echo "    DATA_POOL         - pool data dir (default: ~/.sv2pi/pool/data)"
    echo "    MONITORING_BIND_MODE - localhost|wireguard (default: localhost)"
    echo "    MONITORING_BIND_IP   - WireGuard IP when MONITORING_BIND_MODE=wireguard"
    echo "    SV2PI_WIREGUARD_IP   - fallback WireGuard IP if MONITORING_BIND_IP is unset"
    echo "    HOTPATH_WG_RELAYS_MODE - auto|on|off (default: auto)"
    echo "    HOTPATH_GIT_RETRY_ATTEMPTS - retries for git fetch/clone (default: 5)"
    exit 1
fi

resolve_bind_ip() {
    case "$1" in
        localhost)
            printf '127.0.0.1'
            ;;
        wireguard)
            if [ -n "$2" ]; then
                printf '%s' "$2"
                return
            fi
            if [ -n "${SV2PI_WIREGUARD_IP:-}" ]; then
                printf '%s' "$SV2PI_WIREGUARD_IP"
                return
            fi
            echo "ERROR: wireguard monitoring mode requires an explicit WireGuard IP."
            echo "  Pass it via --monitoring-wireguard <ip>, MONITORING_BIND_IP, or SV2PI_WIREGUARD_IP."
            exit 1
            ;;
        *)
            echo "ERROR: invalid monitoring bind mode: $1 (use localhost or wireguard)"
            exit 1
            ;;
    esac
}

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
MONITORING_HOST_BIND="$(resolve_bind_ip "$MONITORING_BIND_MODE" "$MONITORING_BIND_IP")"
MONITORING_HEALTH_HOST="$MONITORING_HOST_BIND"
if [ "$MONITORING_BIND_MODE" = "localhost" ]; then
    MONITORING_HEALTH_HOST="localhost"
fi

case "$HOTPATH_WG_RELAYS_MODE" in
    auto)
        if [ "$MONITORING_BIND_MODE" = "wireguard" ]; then
            HOTPATH_WG_RELAYS_ENABLED=true
        else
            HOTPATH_WG_RELAYS_ENABLED=false
        fi
        ;;
    on|true|1)
        HOTPATH_WG_RELAYS_ENABLED=true
        ;;
    off|false|0)
        HOTPATH_WG_RELAYS_ENABLED=false
        ;;
    *)
        echo "ERROR: invalid HOTPATH_WG_RELAYS_MODE: $HOTPATH_WG_RELAYS_MODE (use auto, on, or off)"
        exit 1
        ;;
esac

if [ "$HOTPATH_WG_RELAYS_ENABLED" = true ] && [ "$MONITORING_BIND_MODE" != "wireguard" ]; then
    echo "ERROR: WireGuard hotpath relays require wireguard monitoring mode."
    echo "  Use --monitoring-wireguard <ip> or set MONITORING_BIND_MODE=wireguard."
    exit 1
fi

HOTPATH_ENDPOINT_HOST="localhost"
if [ "$HOTPATH_WG_RELAYS_ENABLED" = true ]; then
    HOTPATH_ENDPOINT_HOST="$MONITORING_HOST_BIND"
fi

relay_container_name() {
    role="$1"
    port="$2"
    printf 'sv2pi_hotpath_relay_%s_%s' "$role" "$port"
}

setup_hotpath_relay() {
    role="$1"
    listen_port="$2"
    target_port="$3"
    name="$(relay_container_name "$role" "$listen_port")"

    docker rm -f "$name" >/dev/null 2>&1 || true
    if ! docker run -d --name "$name" --restart unless-stopped --network host alpine/socat \
        "TCP4-LISTEN:${listen_port},bind=${MONITORING_HOST_BIND},fork,reuseaddr" \
        "TCP4:127.0.0.1:${target_port}" >/dev/null; then
        echo "ERROR: failed to start WireGuard relay container: $name"
        exit 1
    fi
}

teardown_hotpath_relay() {
    role="$1"
    listen_port="$2"
    name="$(relay_container_name "$role" "$listen_port")"
    docker rm -f "$name" >/dev/null 2>&1 || true
}

run_with_retry() {
    description="$1"
    shift

    max_attempts="${HOTPATH_GIT_RETRY_ATTEMPTS:-5}"
    attempt=1
    delay=2

    while true; do
        if "$@"; then
            return 0
        fi

        if [ "$attempt" -ge "$max_attempts" ]; then
            echo "ERROR: ${description} failed after ${attempt} attempts"
            return 1
        fi

        echo "WARN: ${description} failed (attempt ${attempt}/${max_attempts}); retrying in ${delay}s"
        sleep "$delay"
        delay=$((delay * 2))
        attempt=$((attempt + 1))
    done
}

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
            if [ ! -f "$CONFIG_POOL/pool-config.toml" ]; then
                echo "ERROR: Pool config file not found: $CONFIG_POOL/pool-config.toml"
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
            if [ ! -f "$CONFIG_JDC/jdc-config.toml" ]; then
                echo "ERROR: JDC config file not found: $CONFIG_JDC/jdc-config.toml"
                echo "  Deploy standard JDC first to generate configs (expected: jdc-config.toml)."
                exit 1
            fi
            ;;
        translator_sv2)
            if [ ! -d "$CONFIG_TPROXY" ]; then
                echo "ERROR: Translator config directory not found: $CONFIG_TPROXY"
                echo "  Deploy standard translator first to generate configs (expected: translator-config.toml)."
                exit 1
            fi
            if [ ! -f "$CONFIG_TPROXY/translator-config.toml" ]; then
                echo "ERROR: Translator config file not found: $CONFIG_TPROXY/translator-config.toml"
                echo "  Deploy standard translator first to generate configs (expected: translator-config.toml)."
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
HOTPATH_CONFIG_RENDER_ROOT="/tmp/sv2pi-hotpath-config-v${VERSION}"

render_monitoring_config() {
    src="$1"
    dst="$2"
    port="$3"

    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"

    python3 - "$dst" "$MONITORING_HOST_BIND" "$port" <<'PY'
from pathlib import Path
import re
import sys

cfg_path = Path(sys.argv[1])
bind_host = sys.argv[2]
port = sys.argv[3]
line = f'monitoring_address = "{bind_host}:{port}"'

text = cfg_path.read_text()
if re.search(r'(?m)^\s*monitoring_address\s*=.*$', text):
    text = re.sub(r'(?m)^\s*monitoring_address\s*=.*$', line, text, count=1)
else:
    text = text.rstrip() + "\n" + line + "\n"

cfg_path.write_text(text)
PY
}

CONFIG_POOL_EFFECTIVE="$CONFIG_POOL"
CONFIG_JDC_EFFECTIVE="$CONFIG_JDC"
CONFIG_TPROXY_EFFECTIVE="$CONFIG_TPROXY"

rm -rf "$HOTPATH_CONFIG_RENDER_ROOT"

for svc in "${SERVICES[@]}"; do
    case "$svc" in
        pool_sv2)
            CONFIG_POOL_EFFECTIVE="$HOTPATH_CONFIG_RENDER_ROOT/pool"
            render_monitoring_config "$CONFIG_POOL/pool-config.toml" "$CONFIG_POOL_EFFECTIVE/pool-config.toml" 9090
            ;;
        jd_client_sv2)
            CONFIG_JDC_EFFECTIVE="$HOTPATH_CONFIG_RENDER_ROOT/jdc"
            render_monitoring_config "$CONFIG_JDC/jdc-config.toml" "$CONFIG_JDC_EFFECTIVE/jdc-config.toml" 9091
            ;;
        translator_sv2)
            CONFIG_TPROXY_EFFECTIVE="$HOTPATH_CONFIG_RENDER_ROOT/translator"
            render_monitoring_config "$CONFIG_TPROXY/translator-config.toml" "$CONFIG_TPROXY_EFFECTIVE/translator-config.toml" 9092
            ;;
    esac
done

export BITCOIN_SOCKET_PATH="$BITCOIN_IPC_PATH"
export BITCOIN_IPC_DIR=$(dirname "$BITCOIN_IPC_PATH")
export CONFIG_POOL="$CONFIG_POOL_EFFECTIVE"
export CONFIG_JDC="$CONFIG_JDC_EFFECTIVE"
export CONFIG_TPROXY="$CONFIG_TPROXY_EFFECTIVE"
export DATA_POOL

echo "=== Stopping existing containers ==="
docker rm -f $SERVICE_NAMES 2>/dev/null || true

if [ "$NO_BUILD" = true ]; then
    echo "=== Skipping build (--no-build) ==="
else
    if [ -d "$HOTPATH_CLONE/.git" ]; then
        if [ "$NO_RESET" = true ]; then
            echo "=== Clone exists, preserving local edits (--no-reset) ==="
        else
echo "=== Updating clone to $HOTPATH_TAG ==="
            run_with_retry "git fetch for ${HOTPATH_TAG}" \
                git -c http.version=HTTP/1.1 -C "$HOTPATH_CLONE" fetch --tags --force origin --depth 1
            git -C "$HOTPATH_CLONE" checkout --force "$HOTPATH_TAG"
        fi
    else
        rm -rf "$HOTPATH_CLONE"
        echo "=== Cloning SV2-bot/sv2-apps at $HOTPATH_TAG ==="
        run_with_retry "git clone for ${HOTPATH_TAG}" \
            git -c http.version=HTTP/1.1 clone --branch "$HOTPATH_TAG" --depth 1 https://github.com/SV2-bot/sv2-apps "$HOTPATH_CLONE"
    fi

    BUILD_ARGS=()
    if [ "$NO_CACHE" = true ]; then
        BUILD_ARGS+=(--no-cache)
    fi
    if [ "$HOTPATH_ALLOC" = true ]; then
        BUILD_ARGS+=(--build-arg HOTPATH_FEATURES=hotpath-alloc,hotpath-mcp)
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

echo "=== Reconciling WireGuard hotpath relays ==="
for svc in "${SERVICES[@]}"; do
    case "$svc" in
        pool_sv2)
            if [ "$HOTPATH_WG_RELAYS_ENABLED" = true ]; then
                setup_hotpath_relay pool 6781 6781
                setup_hotpath_relay pool 6791 6791
            else
                teardown_hotpath_relay pool 6781
                teardown_hotpath_relay pool 6791
            fi
            ;;
        jd_client_sv2)
            if [ "$HOTPATH_WG_RELAYS_ENABLED" = true ]; then
                setup_hotpath_relay jdc 6782 6782
                setup_hotpath_relay jdc 6792 6792
            else
                teardown_hotpath_relay jdc 6782
                teardown_hotpath_relay jdc 6792
            fi
            ;;
        translator_sv2)
            if [ "$HOTPATH_WG_RELAYS_ENABLED" = true ]; then
                setup_hotpath_relay translator 6783 6783
                setup_hotpath_relay translator 6793 6793
            else
                teardown_hotpath_relay translator 6783
                teardown_hotpath_relay translator 6793
            fi
            ;;
    esac
done

if [ "$HOTPATH_WG_RELAYS_ENABLED" = true ]; then
    echo "=== Verifying WireGuard hotpath relays ==="
    for svc in "${SERVICES[@]}"; do
        case "$svc" in
            pool_sv2)
                curl -sf "http://${HOTPATH_ENDPOINT_HOST}:6781/profiler_status" >/dev/null
                mcp_code="$(curl -s -o /dev/null -w '%{http_code}' "http://${HOTPATH_ENDPOINT_HOST}:6791/mcp" || true)"
                [ "$mcp_code" != "000" ] || { echo "ERROR: pool MCP relay unreachable on ${HOTPATH_ENDPOINT_HOST}:6791"; exit 1; }
                ;;
            jd_client_sv2)
                curl -sf "http://${HOTPATH_ENDPOINT_HOST}:6782/profiler_status" >/dev/null
                mcp_code="$(curl -s -o /dev/null -w '%{http_code}' "http://${HOTPATH_ENDPOINT_HOST}:6792/mcp" || true)"
                [ "$mcp_code" != "000" ] || { echo "ERROR: JDC MCP relay unreachable on ${HOTPATH_ENDPOINT_HOST}:6792"; exit 1; }
                ;;
            translator_sv2)
                curl -sf "http://${HOTPATH_ENDPOINT_HOST}:6783/profiler_status" >/dev/null
                mcp_code="$(curl -s -o /dev/null -w '%{http_code}' "http://${HOTPATH_ENDPOINT_HOST}:6793/mcp" || true)"
                [ "$mcp_code" != "000" ] || { echo "ERROR: translator MCP relay unreachable on ${HOTPATH_ENDPOINT_HOST}:6793"; exit 1; }
                ;;
        esac
    done
fi

echo "=== Running health probes ==="
sleep 3
for svc in "${SERVICES[@]}"; do
    case "$svc" in
        pool_sv2)
            echo -n "  pool_sv2:    "
            curl -sf "http://${MONITORING_HEALTH_HOST}:9090/api/v1/health" >/dev/null 2>&1 && echo "OK" || echo "UNREACHABLE"
            echo -n "  hotpath:     "
            curl -sf "http://${HOTPATH_ENDPOINT_HOST}:6781/profiler_status" >/dev/null 2>&1 && echo "OK" || echo "UNREACHABLE"
            ;;
        jd_client_sv2)
            echo -n "  jd_client:   "
            curl -sf "http://${MONITORING_HEALTH_HOST}:9091/api/v1/health" >/dev/null 2>&1 && echo "OK" || echo "UNREACHABLE"
            echo -n "  hotpath:     "
            curl -sf "http://${HOTPATH_ENDPOINT_HOST}:6782/profiler_status" >/dev/null 2>&1 && echo "OK" || echo "UNREACHABLE"
            ;;
        translator_sv2)
            echo -n "  translator:  "
            curl -sf "http://${MONITORING_HEALTH_HOST}:9092/api/v1/health" >/dev/null 2>&1 && echo "OK" || echo "UNREACHABLE"
            echo -n "  hotpath:     "
            curl -sf "http://${HOTPATH_ENDPOINT_HOST}:6783/profiler_status" >/dev/null 2>&1 && echo "OK" || echo "UNREACHABLE"
            ;;
    esac
done

echo ""
echo "=== Hotpath-enabled SRI apps deployed ==="
echo "  Tag:      $HOTPATH_TAG"
echo "  Repo:     https://github.com/SV2-bot/sv2-apps"
echo "  Monitoring bind: ${MONITORING_HOST_BIND} (${MONITORING_BIND_MODE})"
echo "  Hotpath profiler/MCP host: ${HOTPATH_ENDPOINT_HOST} (wireguard-relays=${HOTPATH_WG_RELAYS_ENABLED})"
echo ""
PORT_TABLE() {
cat <<PORTS
  Port mappings:
    pool_sv2:       http://${MONITORING_HEALTH_HOST}:9090 (monitoring)  localhost:3333 (stratum)  ${HOTPATH_ENDPOINT_HOST}:6781 (profiler)  http://${HOTPATH_ENDPOINT_HOST}:6791/mcp
    jd_client_sv2:  http://${MONITORING_HEALTH_HOST}:9091 (monitoring)  localhost:34265 (sv2)     ${HOTPATH_ENDPOINT_HOST}:6782 (profiler)  http://${HOTPATH_ENDPOINT_HOST}:6792/mcp
    translator_sv2: http://${MONITORING_HEALTH_HOST}:9092 (monitoring)  localhost:34255 (sv1)     ${HOTPATH_ENDPOINT_HOST}:6783 (profiler)  http://${HOTPATH_ENDPOINT_HOST}:6793/mcp
PORTS
}
PORT_TABLE
echo ""
echo "Logs:"
for svc in "${SERVICES[@]}"; do
    echo "  docker logs $svc --tail 50"
done
