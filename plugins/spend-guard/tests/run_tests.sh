#!/usr/bin/env bash
# Run all spend-guard unit tests.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

TOTAL_PASS=0; TOTAL_FAIL=0

run_suite() {
  local file="$1"
  bash "$file"
  local ec=$?
  if [ $ec -ne 0 ]; then
    TOTAL_FAIL=$((TOTAL_FAIL+1))
  else
    TOTAL_PASS=$((TOTAL_PASS+1))
  fi
}

run_suite "${SCRIPT_DIR}/test_set_limit.sh"
echo ""
run_suite "${SCRIPT_DIR}/test_status.sh"
echo ""
run_suite "${SCRIPT_DIR}/test_spend_guard.sh"

echo ""
echo "================================================"
printf "Suites: %d passed, %d failed\n" "$TOTAL_PASS" "$TOTAL_FAIL"
[ "$TOTAL_FAIL" -eq 0 ]
