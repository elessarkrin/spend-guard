---
description: Set the daily Claude Code API spend limit (USD) enforced by the spend-guard plugin. Writes ~/.config/spend-guard/limit. Use when the user wants to change, raise, or lower the daily spend cap.
model: haiku
allowed-tools:
  - Bash
argument-hint: <amount>
---

# spend-guard: limit

Run **exactly one** Bash command. Output nothing else — no summary, no rephrasing, no commentary before or after.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/set-limit.sh" "${ARGUMENTS}"
```
