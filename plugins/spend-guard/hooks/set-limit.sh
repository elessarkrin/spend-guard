#!/usr/bin/env bash
set -u
export PYTHONUTF8=1

AMOUNT="${1:-}"
if [ -z "${AMOUNT}" ]; then
  printf "Usage: /spend-guard:limit <amount>\n  e.g. /spend-guard:limit 25\n" >&2
  exit 1
fi
case "${AMOUNT}" in
  ""|*[!0-9.]*|*.*.*)
    printf "spend-guard: invalid amount %q — must be a positive number (e.g. 25 or 25.50)\n" "${AMOUNT}" >&2
    exit 1
    ;;
esac
IS_POSITIVE="$(AMOUNT="${AMOUNT}" python3 -c "import os; v=float(os.environ['AMOUNT']); print(1 if v>0 else 0)" 2>/dev/null || echo 0)"
if [ "${IS_POSITIVE}" != "1" ]; then
  printf "spend-guard: invalid amount %q — must be greater than 0\n" "${AMOUNT}" >&2
  exit 1
fi
mkdir -p "${HOME}/.config/spend-guard"
printf "%s\n" "${AMOUNT}" > "${HOME}/.config/spend-guard/limit"
if [ -n "${CLAUDE_DAILY_LIMIT:-}" ]; then
  printf "Note: CLAUDE_DAILY_LIMIT=%s overrides the config file for this session.\n" "${CLAUDE_DAILY_LIMIT}"
fi
bash "$(dirname "$0")/status.sh" 2>/dev/null || printf "Limit set to \$%s.\n" "${AMOUNT}"
