#!/usr/bin/env bash
# trigger-vault-consolidation.sh — daily vault consolidation trigger
#
# This script is invoked by the sv2pi-vault-consolidation.timer once per day.
# It writes a trigger marker so the next sv2pi agent session picks up
# the consolidation workflow and runs it via ADMIN_MODEL.
#
# The agent is responsible for the actual consolidation — this script is
# a zero-token fire-and-forget marker, similar to pool-monitor.sh.

set -euo pipefail

TRIGGER_FILE="${SV2PI_VAULT:-$HOME/vault}/.consolidation-trigger"

cat > "$TRIGGER_FILE" <<'EOF'
{
  "triggered_at": "TRIGGER_TIMESTAMP_PLACEHOLDER",
  "action": "vault-consolidation",
  "model": "ADMIN_MODEL",
  "instructions": "Run the daily vault consolidation workflow as defined in domains/vault.md. Use ADMIN_MODEL. Read the full consolidation section in domains/vault.md, follow the pre-flight checklist, analysis phase, and consolidation phase with all safety rules."
}
EOF

# Replace placeholder with actual ISO-8601 UTC timestamp
TIMESTAMP_NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
sed -i "s/TRIGGER_TIMESTAMP_PLACEHOLDER/${TIMESTAMP_NOW}/" "$TRIGGER_FILE"

echo "vault-consolidation: trigger written to ${TRIGGER_FILE} at ${TIMESTAMP_NOW}"
