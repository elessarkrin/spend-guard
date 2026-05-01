---
description: Set the daily Claude Code API spend limit (USD) enforced by the spend-guard plugin. Writes ~/.config/spend-guard/limit. Use when the user wants to change, raise, or lower the daily spend cap.
allowed-tools: Bash
argument-hint: <amount>
---

# spend-guard: limit

The user's requested limit is in `$ARGUMENTS`. Run **exactly one** Bash command (the script below), passing `$ARGUMENTS` as `$1`. Print its output verbatim.

```bash
bash -c '
set -u
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
IS_POSITIVE="$(AMOUNT="${AMOUNT}" python3 -c "import os; v=float(os.environ[\"AMOUNT\"]); print(1 if v>0 else 0)" 2>/dev/null || echo 0)"
if [ "${IS_POSITIVE}" != "1" ]; then
  printf "spend-guard: invalid amount %q — must be greater than 0\n" "${AMOUNT}" >&2
  exit 1
fi
mkdir -p "${HOME}/.config/spend-guard"
printf "%s\n" "${AMOUNT}" > "${HOME}/.config/spend-guard/limit"
printf "spend-guard: daily limit set to \$%s (saved to ~/.config/spend-guard/limit)\n" "${AMOUNT}"
if [ -n "${CLAUDE_DAILY_LIMIT:-}" ]; then
  printf "Note: CLAUDE_DAILY_LIMIT=%s is set in this session and overrides the config file.\n" "${CLAUDE_DAILY_LIMIT}"
fi
printf "Run /spend-guard:status to see current usage against the new limit.\n"
' _ "$ARGUMENTS"
```

After running, do not add commentary unless the user asks a follow-up question.
