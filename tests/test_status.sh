#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/helpers.sh"

HOOK="${HOOKS_DIR}/status.sh"

echo "=== status.sh ==="

# ---- no usage data ----
setup_env
printf "5.00\n" > "${FAKE_HOME}/.config/spend-guard/limit"
out="$(bash "$HOOK" 2>&1)"; ec=$?
assert_eq "no data: exits 0" "0" "$ec"
assert_contains "no data: shows \$0.00 spent" '$0.00 spent' "$out"
assert_contains "no data: shows limit" '$5.00 limit' "$out"
teardown_env

# ---- single record ----
setup_env
printf "10.00\n" > "${FAKE_HOME}/.config/spend-guard/limit"
write_record 2.5 "msg-001"
out="$(bash "$HOOK" 2>&1)"; ec=$?
assert_eq "single record: exits 0" "0" "$ec"
assert_contains "single record: spend shown" '$2.50 spent' "$out"
assert_contains "single record: remaining shown" '$7.50 remaining' "$out"
teardown_env

# ---- deduplication: same msg_id written 3× ----
setup_env
printf "10.00\n" > "${FAKE_HOME}/.config/spend-guard/limit"
write_record 1.0 "msg-dup"
write_record 1.0 "msg-dup"
write_record 1.0 "msg-dup"
out="$(bash "$HOOK" 2>&1)"
assert_contains "dedup: counted only once" '$1.00 spent' "$out"
teardown_env

# ---- two distinct records ----
setup_env
printf "10.00\n" > "${FAKE_HOME}/.config/spend-guard/limit"
write_record 1.0 "msg-a"
write_record 2.0 "msg-b"
out="$(bash "$HOOK" 2>&1)"
assert_contains "two records: summed correctly" '$3.00 spent' "$out"
teardown_env

# ---- CLAUDE_DAILY_LIMIT env overrides config ----
setup_env
printf "10.00\n" > "${FAKE_HOME}/.config/spend-guard/limit"
write_record 1.0 "msg-env"
out="$(CLAUDE_DAILY_LIMIT="50" bash "$HOOK" 2>&1)"
assert_contains "env limit: uses env value" '$50.00 limit' "$out"
teardown_env

# ---- default limit when no config ----
setup_env
write_record 1.0 "msg-def"
out="$(bash "$HOOK" 2>&1)"
assert_contains "default limit: shows \$40.00" '$40.00 limit' "$out"
teardown_env

summary
