---
description: Show today's Claude Code API spend, the configured daily limit, and remaining budget enforced by spend-guard. Use when asked about current spend, today's usage, or remaining budget.
allowed-tools: Bash
---

# spend-guard: status

Run **exactly one** Bash command. The script prints its own report. Output nothing else — no summary, no rephrasing, no commentary before or after.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/hooks/status.sh"
```
