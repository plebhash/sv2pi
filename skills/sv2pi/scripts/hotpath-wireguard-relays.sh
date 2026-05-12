#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
if [ -z "$ACTION" ]; then
    echo "ERROR: action required"
    echo "Usage: $0 <up|down|status|verify> [wireguard-ip] [pool] [jdc] [translator]"
    echo "  wireguard-ip: required for up/verify unless SV2PI_WIREGUARD_IP is set"
    exit 1
fi
shift || true

is_service() {
    case "$1" in
        pool|jdc|translator) return 0 ;;
        *) return 1 ;;
    esac
}

resolve_roles() {
    if [ "$#" -eq 0 ]; then
        ROLES=(pool jdc translator)
        return
    fi

    ROLES=()
    for role in "$@"; do
        if ! is_service "$role"; then
            echo "ERROR: unknown role '$role'"
            echo "  Accepted: pool jdc translator"
            exit 1
        fi
        ROLES+=("$role")
    done
}

relay_container_name() {
    role="$1"
    port="$2"
    printf 'sv2pi_hotpath_relay_%s_%s' "$role" "$port"
}

ports_for_role() {
    case "$1" in
        pool)
            PROFILER_PORT=6781
            MCP_PORT=6791
            ;;
        jdc)
            PROFILER_PORT=6782
            MCP_PORT=6792
            ;;
        translator)
            PROFILER_PORT=6783
            MCP_PORT=6793
            ;;
        *)
            echo "ERROR: unsupported role '$1'"
            exit 1
            ;;
    esac
}

up_relay() {
    role="$1"
    port="$2"
    name="$(relay_container_name "$role" "$port")"

    docker rm -f "$name" >/dev/null 2>&1 || true
    docker run -d --name "$name" --restart unless-stopped --network host alpine/socat \
        "TCP4-LISTEN:${port},bind=${WG_IP},fork,reuseaddr" \
        "TCP4:127.0.0.1:${port}" >/dev/null
}

down_relay() {
    role="$1"
    port="$2"
    name="$(relay_container_name "$role" "$port")"
    docker rm -f "$name" >/dev/null 2>&1 || true
}

status_relay() {
    role="$1"
    port="$2"
    name="$(relay_container_name "$role" "$port")"
    if docker ps --filter "name=^/${name}$" --format '{{.Names}}' | grep -q "^${name}$"; then
        echo "  ${name}: running"
    else
        echo "  ${name}: missing"
    fi
}

verify_role() {
    role="$1"
    profiler_port="$2"
    mcp_port="$3"

    curl -sf "http://${WG_IP}:${profiler_port}/profiler_status" >/dev/null
    mcp_code="$(curl -s -o /dev/null -w '%{http_code}' "http://${WG_IP}:${mcp_port}/mcp" || true)"
    if [ "$mcp_code" = "000" ]; then
        echo "ERROR: ${role} MCP endpoint unreachable on ${WG_IP}:${mcp_port}"
        exit 1
    fi
}

WG_IP="${SV2PI_WIREGUARD_IP:-}"
if [ "$ACTION" = "up" ] || [ "$ACTION" = "verify" ]; then
    if [ "$#" -gt 0 ] && ! is_service "$1"; then
        WG_IP="$1"
        shift
    fi
    if [ -z "$WG_IP" ]; then
        echo "ERROR: wireguard IP required for action '$ACTION'"
        echo "  Pass it as the next argument or set SV2PI_WIREGUARD_IP"
        exit 1
    fi
fi

resolve_roles "$@"

case "$ACTION" in
    up)
        echo "=== Creating WireGuard relays on ${WG_IP} ==="
        for role in "${ROLES[@]}"; do
            ports_for_role "$role"
            up_relay "$role" "$PROFILER_PORT"
            up_relay "$role" "$MCP_PORT"
            echo "  ${role}: ${WG_IP}:${PROFILER_PORT} -> 127.0.0.1:${PROFILER_PORT}, ${WG_IP}:${MCP_PORT} -> 127.0.0.1:${MCP_PORT}"
        done
        ;;
    down)
        echo "=== Removing WireGuard relays ==="
        for role in "${ROLES[@]}"; do
            ports_for_role "$role"
            down_relay "$role" "$PROFILER_PORT"
            down_relay "$role" "$MCP_PORT"
            echo "  ${role}: removed"
        done
        ;;
    status)
        echo "=== WireGuard relay container status ==="
        for role in "${ROLES[@]}"; do
            ports_for_role "$role"
            status_relay "$role" "$PROFILER_PORT"
            status_relay "$role" "$MCP_PORT"
        done
        ;;
    verify)
        echo "=== Verifying WireGuard relay endpoints on ${WG_IP} ==="
        for role in "${ROLES[@]}"; do
            ports_for_role "$role"
            verify_role "$role" "$PROFILER_PORT" "$MCP_PORT"
            echo "  ${role}: profiler+MCP reachable"
        done
        ;;
    *)
        echo "ERROR: invalid action '$ACTION'"
        echo "  Accepted: up down status verify"
        exit 1
        ;;
esac
