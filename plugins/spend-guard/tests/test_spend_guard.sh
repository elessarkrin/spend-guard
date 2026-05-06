#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

HOOK="${HOOKS_DIR}/spend-guard.sh"

echo "=== spend-guard.sh ==="

# ---- under limit: allow ----
setup_env
printf "10.00\n" > "${FAKE_HOME}/.config/spend-guard/limit"
write_record 1.0 "msg-under"
echo '{}' | bash "$HOOK"; ec=$?
assert_exit "under limit: exit 0 (allow)" "0" "$ec"
teardown_env

# ---- at limit: block ----
setup_env
printf "2.00\n" > "${FAKE_HOME}/.config/spend-guard/limit"
write_record 2.0 "msg-at"
out="$(echo '{}' | bash "$HOOK" 2>&1)"; ec=$?
assert_exit "at limit: exit 2 (block)" "2" "$ec"
assert_contains "at limit: block message shown" 'Daily spend limit reached' "$out"
teardown_env

# ---- over limit: block ----
setup_env
printf "1.00\n" > "${FAKE_HOME}/.config/spend-guard/limit"
write_record 5.0 "msg-over"
out="$(echo '{}' | bash "$HOOK" 2>&1)"; ec=$?
assert_exit "over limit: exit 2 (block)" "2" "$ec"
teardown_env

# ---- bypass: UserPromptSubmit with spend-guard:limit ----
setup_env
printf "1.00\n" > "${FAKE_HOME}/.config/spend-guard/limit"
write_record 5.0 "msg-bypass1"
payload='{"prompt":"/spend-guard:limit 10"}'
printf '%s' "$payload" | bash "$HOOK"; ec=$?
assert_exit "bypass skill invocation: exit 0" "0" "$ec"
teardown_env

# ---- bypass: PreToolUse with .config/spend-guard/limit in command ----
setup_env
printf "1.00\n" > "${FAKE_HOME}/.config/spend-guard/limit"
write_record 5.0 "msg-bypass2"
payload='{"tool_name":"Bash","tool_input":{"command":"printf \"10\n\" > /home/user/.config/spend-guard/limit"}}'
printf '%s' "$payload" | bash "$HOOK"; ec=$?
assert_exit "bypass limit write command: exit 0" "0" "$ec"
teardown_env

# ---- no spend data: fail open ----
setup_env
printf "1.00\n" > "${FAKE_HOME}/.config/spend-guard/limit"
# no JSONL records at all
out="$(echo '{}' | bash "$HOOK" 2>&1)"; ec=$?
assert_exit "no data: fail open (exit 0)" "0" "$ec"
teardown_env

# ---- deduplication: 3× same id should not inflate to block ----
setup_env
printf "2.00\n" > "${FAKE_HOME}/.config/spend-guard/limit"
write_record 1.5 "msg-dup-guard"
write_record 1.5 "msg-dup-guard"
write_record 1.5 "msg-dup-guard"
# Deduplicated spend = $1.50, limit = $2.00 → should allow
echo '{}' | bash "$HOOK"; ec=$?
assert_exit "dedup prevents false block: exit 0" "0" "$ec"
teardown_env

summary
