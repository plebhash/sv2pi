#!/usr/bin/env bash
set -euo pipefail

TIMEOUT_SECS="${TIMEOUT_SECS:-60}"
URL="${1:-}"
USER="${2:-}"
PASS="${3:-}"
MODE="${4:-}"

usage() {
    echo "Usage: $0 <url> <user> <pass> <mode>"
    echo ""
    echo "  url   - Stratum endpoint (stratum+tcp://HOST:PORT)"
    echo "  user  - Worker username"
    echo "  pass  - Worker password"
    echo "  mode  - 'handshake' or 'oneshot'"
    echo ""
    echo "  handshake  - exit after SV1 handshake completes"
    echo "  oneshot    - exit after first accepted share"
    echo ""
    echo "Environment:"
    echo "  MINERD_BINARY  - path to minerd binary (default: try built-in detection)"
    echo "  TIMEOUT_SECS   - max wait seconds (default: 60)"
    exit 1
}

if [ -z "$URL" ] || [ -z "$USER" ] || [ -z "$PASS" ] || [ -z "$MODE" ]; then
    echo "ERROR: Missing required arguments."
    usage
fi

if [ "$MODE" != "handshake" ] && [ "$MODE" != "oneshot" ]; then
    echo "ERROR: mode must be 'handshake' or 'oneshot'"
    usage
fi

if [ -z "${MINERD_BINARY:-}" ]; then
    if [ -x "$HOME/.sv2pi/minerd/v2.5.1/minerd" ]; then
        MINERD_BINARY="$HOME/.sv2pi/minerd/v2.5.1/minerd"
    else
        echo "ERROR: MINERD_BINARY not set and no default installation found."
        echo "  Run fetch-minerd.sh first:"
        echo "    eval \"\$(bash scripts/fetch-minerd.sh)\""
        exit 1
    fi
fi

if [ ! -x "$MINERD_BINARY" ]; then
    echo "ERROR: minerd binary not found or not executable: $MINERD_BINARY"
    echo "  Run fetch-minerd.sh first."
    exit 1
fi

case "$MODE" in
    handshake)
        echo "=== minerd handshake test ==="
        echo "  URL:    $URL"
        echo "  User:   $USER"
        echo "  Timeout: ${TIMEOUT_SECS}s"
        echo ""

        MATCHER="Stratum difficulty set to"
        FLAGS="-q"
        ;;
    oneshot)
        echo "=== minerd handshake + oneshot ==="
        echo "  URL:    $URL"
        echo "  User:   $USER"
        echo "  Timeout: ${TIMEOUT_SECS}s (note: depends on vardiff)"
        echo ""

        MATCHER="accepted:"
        FLAGS="-P -q"
        ;;
esac

LOGFILE="$(mktemp -t minerd.XXXXXX)"
trap 'rm -f "$LOGFILE"' EXIT

"$MINERD_BINARY" -a sha256d -o "$URL" -u "$USER" -p "$PASS" $FLAGS >"$LOGFILE" 2>&1 &
MINERD_PID=$!

ELAPSED=0
while [ "$ELAPSED" -lt "$TIMEOUT_SECS" ]; do
    if grep -qF "$MATCHER" "$LOGFILE" 2>/dev/null; then
        grep -F "$MATCHER" "$LOGFILE"
        kill "$MINERD_PID" 2>/dev/null || true
        wait "$MINERD_PID" 2>/dev/null || true
        echo ""
        echo "=== $MODE completed successfully ==="
        exit 0
    fi
    if ! kill -0 "$MINERD_PID" 2>/dev/null; then
        wait "$MINERD_PID" 2>/dev/null || true
        MINERD_EXIT=$?
        if [ $MINERD_EXIT -ne 0 ]; then
            echo ""
            echo "=== minerd exited with code $MINERD_EXIT (before match) ===" >&2
            tail -20 "$LOGFILE" >&2
            exit 1
        fi
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

kill "$MINERD_PID" 2>/dev/null || true
wait "$MINERD_PID" 2>/dev/null || true

echo ""
echo "=== $MODE FAILED (timed out after ${TIMEOUT_SECS}s) ===" >&2
echo "Last 20 log lines:" >&2
tail -20 "$LOGFILE" >&2
exit 1
