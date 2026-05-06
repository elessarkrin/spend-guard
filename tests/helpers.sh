#!/usr/bin/env bash
# Shared test helpers: assertions, setup/teardown, fixtures.

PASS=0; FAIL=0; ERRORS=()

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS+1))
    printf "  PASS  %s\n" "$desc"
  else
    FAIL=$((FAIL+1))
    ERRORS+=("$desc")
    printf "  FAIL  %s\n         expected: %s\n         got:      %s\n" "$desc" "$expected" "$actual"
  fi
}

assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  assert_eq "$desc (exit $expected)" "$expected" "$actual"
}

assert_contains() {
  local desc="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    PASS=$((PASS+1))
    printf "  PASS  %s\n" "$desc"
  else
    FAIL=$((FAIL+1))
    ERRORS+=("$desc")
    printf "  FAIL  %s\n         expected to contain: %s\n         got: %s\n" "$desc" "$needle" "$haystack"
  fi
}

summary() {
  echo ""
  printf "Results: %d passed, %d failed\n" "$PASS" "$FAIL"
  if [ "$FAIL" -gt 0 ]; then
    exit 1
  fi
}

# Call at the start of each test file. Sets FAKE_HOME and stubs npx so the
# JSONL fallback is always exercised (ccusage is never invoked).
setup_env() {
  FAKE_HOME="$(mktemp -d)"
  mkdir -p "${FAKE_HOME}/.claude/projects/test-project"
  mkdir -p "${FAKE_HOME}/.config/spend-guard"

  # Stub npx that always fails → forces JSONL fallback
  FAKE_BIN="$(mktemp -d)"
  cat >"${FAKE_BIN}/npx" <<'SH'
#!/usr/bin/env bash
exit 1
SH
  chmod +x "${FAKE_BIN}/npx"

  export HOME="$FAKE_HOME"
  export PATH="${FAKE_BIN}:${PATH}"
  unset CLAUDE_DAILY_LIMIT
}

teardown_env() {
  rm -rf "$FAKE_HOME" "$FAKE_BIN"
}

# Write a single JSONL record for today into the fixture project.
# Usage: write_record <cost_usd> [msg_id]
write_record() {
  local cost="$1" msg_id="${2:-}"
  local today_ts
  today_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local record
  if [ -n "$msg_id" ]; then
    record="{\"timestamp\":\"${today_ts}\",\"message\":{\"id\":\"${msg_id}\",\"role\":\"assistant\",\"model\":\"claude-sonnet-4-6\"},\"costUSD\":${cost}}"
  else
    record="{\"timestamp\":\"${today_ts}\",\"message\":{\"role\":\"assistant\",\"model\":\"claude-sonnet-4-6\"},\"costUSD\":${cost}}"
  fi
  printf '%s\n' "$record" >> "${FAKE_HOME}/.claude/projects/test-project/session.jsonl"
}

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../plugins/spend-guard/hooks" && pwd)"
