#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

HOOK="${HOOKS_DIR}/set-limit.sh"

echo "=== set-limit.sh ==="

setup_env

# No argument
out="$(bash "$HOOK" 2>&1)"; ec=$?
assert_eq "no arg: exits non-zero" "1" "$ec"
assert_contains "no arg: usage hint" "Usage:" "$out"

# Letters only
out="$(bash "$HOOK" "abc" 2>&1)"; ec=$?
assert_eq "letters: exits non-zero" "1" "$ec"
assert_contains "letters: error message" "invalid amount" "$out"

# Zero
out="$(bash "$HOOK" "0" 2>&1)"; ec=$?
assert_eq "zero: exits non-zero" "1" "$ec"

# Negative
out="$(bash "$HOOK" -- "-5" 2>&1)"; ec=$?
assert_eq "negative: exits non-zero" "1" "$ec"

# Multiple dots
out="$(bash "$HOOK" "1.2.3" 2>&1)"; ec=$?
assert_eq "multi-dot: exits non-zero" "1" "$ec"

# Valid integer
out="$(bash "$HOOK" "25" 2>&1)"; ec=$?
assert_eq "integer: exits 0" "0" "$ec"
stored="$(cat "${FAKE_HOME}/.config/spend-guard/limit")"
assert_eq "integer: stored value" "25" "$stored"

# Valid decimal
out="$(bash "$HOOK" "12.50" 2>&1)"; ec=$?
assert_eq "decimal: exits 0" "0" "$ec"
stored="$(cat "${FAKE_HOME}/.config/spend-guard/limit")"
assert_eq "decimal: stored value" "12.50" "$stored"

# Overwrites existing
printf "99\n" > "${FAKE_HOME}/.config/spend-guard/limit"
bash "$HOOK" "10" >/dev/null 2>&1
stored="$(cat "${FAKE_HOME}/.config/spend-guard/limit")"
assert_eq "overwrite: new value stored" "10" "$stored"

# CLAUDE_DAILY_LIMIT env override warning
out="$(CLAUDE_DAILY_LIMIT="30" bash "$HOOK" "20" 2>&1)"
assert_contains "env override: warning shown" "CLAUDE_DAILY_LIMIT" "$out"

teardown_env
summary
