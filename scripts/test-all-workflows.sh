#!/usr/bin/env bash
set -euo pipefail

# Integration test: trigger and monitor the Autonomous SDLC workflow on all 5 target repos
REPOS=(
  "taylor-curran/tb-fineract"
  "taylor-curran/tb-OBP-API"
  "taylor-curran/tb-mozilla-telemetry-airflow"
  "taylor-curran/tb-online-banking-microservices-api"
  "taylor-curran/tb-OpenCBS-Cloud"
)

WORKFLOW="autonomous-sdlc.yml"
POLL_INTERVAL=15
TIMEOUT=600  # 10 minutes max

echo "=== Autonomous SDLC Integration Test ==="
echo "Triggering workflow on ${#REPOS[@]} repos..."
echo ""

# Trigger all workflows
declare -A RUN_IDS
for repo in "${REPOS[@]}"; do
  echo "▶ Triggering ${repo}..."
  gh workflow run "$WORKFLOW" --repo "$repo" 2>&1 || {
    echo "  ✗ Failed to trigger ${repo}"
    continue
  }
  sleep 2  # give GitHub a moment to register the run
  RUN_ID=$(gh run list --repo "$repo" --workflow "$WORKFLOW" --limit 1 --json databaseId --jq '.[0].databaseId')
  RUN_IDS["$repo"]="$RUN_ID"
  echo "  ✓ Run ID: ${RUN_ID}"
done

echo ""
echo "=== Waiting for results (timeout: ${TIMEOUT}s) ==="
echo ""

START_TIME=$(date +%s)
declare -A RESULTS

while true; do
  ALL_DONE=true

  for repo in "${REPOS[@]}"; do
    # Skip if already resolved
    [[ -n "${RESULTS[$repo]:-}" ]] && continue

    RUN_ID="${RUN_IDS[$repo]:-}"
    [[ -z "$RUN_ID" ]] && { RESULTS["$repo"]="SKIP (no run)"; continue; }

    STATUS_JSON=$(gh run view "$RUN_ID" --repo "$repo" --json status,conclusion 2>&1)
    STATUS=$(echo "$STATUS_JSON" | jq -r '.status')
    CONCLUSION=$(echo "$STATUS_JSON" | jq -r '.conclusion')

    if [[ "$STATUS" == "completed" ]]; then
      RESULTS["$repo"]="$CONCLUSION"
    else
      ALL_DONE=false
    fi
  done

  $ALL_DONE && break

  ELAPSED=$(( $(date +%s) - START_TIME ))
  if (( ELAPSED > TIMEOUT )); then
    echo "⏰ Timeout reached (${TIMEOUT}s). Marking remaining as timed out."
    for repo in "${REPOS[@]}"; do
      [[ -z "${RESULTS[$repo]:-}" ]] && RESULTS["$repo"]="TIMEOUT"
    done
    break
  fi

  REMAINING=0
  for repo in "${REPOS[@]}"; do
    [[ -z "${RESULTS[$repo]:-}" ]] && (( REMAINING++ ))
  done
  echo "  ⏳ ${REMAINING} still running... (${ELAPSED}s elapsed)"
  sleep "$POLL_INTERVAL"
done

echo ""
echo "=== Results ==="
echo ""
printf "%-50s %-15s %-12s\n" "REPO" "RUN ID" "RESULT"
printf "%-50s %-15s %-12s\n" "----" "------" "------"

PASS=0
FAIL=0
for repo in "${REPOS[@]}"; do
  RESULT="${RESULTS[$repo]:-UNKNOWN}"
  RUN_ID="${RUN_IDS[$repo]:-N/A}"

  if [[ "$RESULT" == "success" ]]; then
    ICON="✅"
    (( PASS++ ))
  else
    ICON="❌"
    (( FAIL++ ))
  fi

  printf "%-50s %-15s %s %s\n" "$repo" "$RUN_ID" "$ICON" "$RESULT"
done

echo ""
echo "=== Summary: ${PASS} passed, ${FAIL} failed/other ==="
echo ""

# Print links
echo "Run links:"
for repo in "${REPOS[@]}"; do
  RUN_ID="${RUN_IDS[$repo]:-}"
  [[ -n "$RUN_ID" ]] && echo "  https://github.com/${repo}/actions/runs/${RUN_ID}"
done
