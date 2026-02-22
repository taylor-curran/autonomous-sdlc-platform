#!/usr/bin/env bash
set -uo pipefail

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
COUNT=${#REPOS[@]}

# Parallel arrays instead of associative arrays (bash 3 compat)
RUN_IDS=()
RESULTS=()

echo "=== Autonomous SDLC Integration Test ==="
echo "Triggering workflow on ${COUNT} repos..."
echo ""

# Trigger all workflows
for i in $(seq 0 $(( COUNT - 1 ))); do
  repo="${REPOS[$i]}"
  echo "▶ Triggering ${repo}..."
  if ! gh workflow run "$WORKFLOW" --repo "$repo" 2>&1; then
    echo "  ✗ Failed to trigger ${repo}"
    RUN_IDS+=("")
    RESULTS+=("SKIP")
    continue
  fi
  sleep 2  # give GitHub a moment to register the run
  RUN_ID=$(gh run list --repo "$repo" --workflow "$WORKFLOW" --limit 1 --json databaseId --jq '.[0].databaseId')
  RUN_IDS+=("$RUN_ID")
  RESULTS+=("")
  echo "  ✓ Run ID: ${RUN_ID}"
done

echo ""
echo "=== Waiting for results (timeout: ${TIMEOUT}s) ==="
echo ""

START_TIME=$(date +%s)

while true; do
  ALL_DONE=true

  for i in $(seq 0 $(( COUNT - 1 ))); do
    # Skip if already resolved
    [[ -n "${RESULTS[$i]}" ]] && continue

    RUN_ID="${RUN_IDS[$i]}"
    [[ -z "$RUN_ID" ]] && { RESULTS[$i]="SKIP"; continue; }

    STATUS_JSON=$(gh run view "$RUN_ID" --repo "${REPOS[$i]}" --json status,conclusion 2>&1)
    STATUS=$(echo "$STATUS_JSON" | jq -r '.status')
    CONCLUSION=$(echo "$STATUS_JSON" | jq -r '.conclusion')

    if [[ "$STATUS" == "completed" ]]; then
      RESULTS[$i]="$CONCLUSION"
    else
      ALL_DONE=false
    fi
  done

  $ALL_DONE && break

  ELAPSED=$(( $(date +%s) - START_TIME ))
  if (( ELAPSED > TIMEOUT )); then
    echo "⏰ Timeout reached (${TIMEOUT}s). Marking remaining as timed out."
    for i in $(seq 0 $(( COUNT - 1 ))); do
      [[ -z "${RESULTS[$i]}" ]] && RESULTS[$i]="TIMEOUT"
    done
    break
  fi

  REMAINING=0
  for i in $(seq 0 $(( COUNT - 1 ))); do
    [[ -z "${RESULTS[$i]}" ]] && REMAINING=$(( REMAINING + 1 ))
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
for i in $(seq 0 $(( COUNT - 1 ))); do
  RESULT="${RESULTS[$i]:-UNKNOWN}"
  RUN_ID="${RUN_IDS[$i]:-N/A}"

  if [[ "$RESULT" == "success" ]]; then
    ICON="✅"
    PASS=$(( PASS + 1 ))
  else
    ICON="❌"
    FAIL=$(( FAIL + 1 ))
  fi

  printf "%-50s %-15s %s %s\n" "${REPOS[$i]}" "$RUN_ID" "$ICON" "$RESULT"
done

echo ""
echo "=== Summary: ${PASS} passed, ${FAIL} failed/other ==="
echo ""

# Print links
echo "Run links:"
for i in $(seq 0 $(( COUNT - 1 ))); do
  RUN_ID="${RUN_IDS[$i]}"
  [[ -n "$RUN_ID" ]] && echo "  https://github.com/${REPOS[$i]}/actions/runs/${RUN_ID}"
done
