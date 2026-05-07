#!/usr/bin/env bash
set -euo pipefail

URL="${1:-}"
USER_PREFIX="${2:-}"
PASS="${3:-}"
MODE="${4:-}"
INSTANCES="${5:-1}"
YES_OVERCOMMIT="${6:-}"

usage() {
    echo "Usage: $0 <url> <user_prefix> <pass> <mode> <instances> [--yes-overcommit]"
    echo ""
    echo "  url            - Stratum endpoint (stratum+tcp://HOST:PORT)"
    echo "  user_prefix    - Base worker name, instances get '.N' suffix (e.g. worker.1)"
    echo "  pass           - Password for all instances"
    echo "  mode           - 'minimal' | 'full' | float multiplier (e.g. '2.5')"
    echo "  instances      - Number of parallel minerd processes (default 1)"
    echo ""
    echo "Modes:"
    echo "  minimal   1 thread per instance"
    echo "  full      auto-detect cores per instance (no -t flag)"
    echo "  <float>   ceil(mult × cores) per instance (explicit -t N)"
    echo ""
    echo "Multi-instance safety:"
    echo "  When instances > 1, --yes-overcommit is required."
    echo "  This blocks accidental resource exhaustion."
    exit 1
}

if [ -z "$URL" ] || [ -z "$USER_PREFIX" ] || [ -z "$PASS" ] || [ -z "$MODE" ]; then
    echo "ERROR: Missing required arguments."
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

if ! [[ "$INSTANCES" =~ ^[0-9]+$ ]] || [ "$INSTANCES" -lt 1 ]; then
    echo "ERROR: instances must be a positive integer"
    exit 1
fi

if command -v nproc >/dev/null 2>&1; then
    CPU_CORES="$(nproc)"
else
    CPU_CORES="$(sysctl -n hw.ncpu 2>/dev/null || echo 1)"
fi

case "$MODE" in
    minimal)
        THREADS_PER_INSTANCE=1
        THREAD_FLAG="-t 1"
        MODE_LABEL="minimal (1 thread)"
        ;;
    full)
        THREADS_PER_INSTANCE="$CPU_CORES"
        THREAD_FLAG=""
        MODE_LABEL="full (auto-detect, ~${CPU_CORES} threads)"
        ;;
    *)
        if ! [[ "$MODE" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            echo "ERROR: mode must be 'minimal', 'full', or a float multiplier (e.g. '2.5')"
            exit 1
        fi
        MULTIPLIER="$MODE"
        THREADS_PER_INSTANCE=$(python3 -c "import math; print(math.ceil($MULTIPLIER * $CPU_CORES))" 2>/dev/null || \
                               awk "BEGIN { x = $MULTIPLIER * $CPU_CORES; y = int(x); print (x == y) ? y : y + 1 }")
        THREAD_FLAG="-t $THREADS_PER_INSTANCE"
        MODE_LABEL="${MODE}× cores (${THREADS_PER_INSTANCE} threads)"
        ;;
esac

TOTAL_THREADS=$((INSTANCES * THREADS_PER_INSTANCE))
OVERRATIO=$(python3 -c "print(round($TOTAL_THREADS / $CPU_CORES, 1))" 2>/dev/null || echo "$TOTAL_THREADS/$CPU_CORES")

echo "=== minerd sustained deployment ==="
echo "  URL:               $URL"
echo "  User prefix:       $USER_PREFIX"
echo "  Password:          $PASS"
echo "  Mode:              $MODE_LABEL"
echo "  Instances:         $INSTANCES"
echo "  CPU cores:         $CPU_CORES"
echo "  Threads/instance:  $THREADS_PER_INSTANCE"
echo "  Total threads:     $TOTAL_THREADS"
echo "  Oversubscription:  ${OVERRATIO}x"
echo ""

if [ "$INSTANCES" -gt 1 ] && [ "$YES_OVERCOMMIT" != "--yes-overcommit" ]; then
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║  RESOURCE EXHAUSTION WARNING                                ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║                                                              ║"
    echo "║  This will allocate $TOTAL_THREADS threads across $CPU_CORES CPU cores   ║"
    echo "║  Oversubscription ratio: ${OVERRATIO}x                                    ║"
    echo "║                                                              ║"
    echo "║  Running more threads than cores can cause:                  ║"
    echo "║    - Severe system slowdown                                  ║"
    echo "║    - OOM kills                                               ║"
    echo "║    - Unresponsive system under heavy context switching       ║"
    echo "║    - Degraded translator/pool performance (share loss)       ║"
    echo "║                                                              ║"
    echo "║  If you understand these risks, re-run with:                 ║"
    echo "║    $0 $URL $USER_PREFIX $PASS $MODE $INSTANCES --yes-overcommit"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    exit 1
fi

if [ "$INSTANCES" -gt 1 ]; then
    echo "  --yes-overcommit: resource warning acknowledged"
    echo ""
fi

SYSTEMD_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$SYSTEMD_DIR"

CREATED_UNITS=()

for i in $(seq 1 "$INSTANCES"); do
    UNIT_NAME="minerd-${i}"
    UNIT_FILE="$SYSTEMD_DIR/${UNIT_NAME}.service"
    WORKER="${USER_PREFIX}.${i}"

    cat > "$UNIT_FILE" <<UNIT
[Unit]
Description=minerd SV1 Load Generator (Instance ${i})
After=network.target

[Service]
ExecStart=${MINERD_BINARY} -a sha256d -o ${URL} -u ${WORKER} -p ${PASS} -q ${THREAD_FLAG}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
UNIT

    CREATED_UNITS+=("$UNIT_NAME")
    echo "  Created:  $UNIT_FILE"
done

echo ""
echo "=== Enabling and starting systemd units ==="
systemctl --user daemon-reload
for unit in "${CREATED_UNITS[@]}"; do
    systemctl --user enable --now "$unit" 2>/dev/null || systemctl --user start "$unit"
    echo "  Started:  $unit"
done

echo ""
echo "=== minerd sustained deployment complete ==="
echo "  Instances:  $INSTANCES"
echo "  Total threads: $TOTAL_THREADS"
echo ""
echo "Monitor:"
echo "  journalctl --user -u minerd-1 -f"
echo "  systemctl --user status minerd-1"
