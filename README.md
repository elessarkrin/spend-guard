# spend-guard

A Claude Code plugin that enforces a hard daily API spend limit across every session. When today's spend reaches the configured cap, both new prompts and mid-session tool calls are blocked until local midnight. No wrappers, no daemons — everything runs inline through Claude Code's hook lifecycle.

**Limitations**

- **Spend figures are estimates.** Claude Code's JSONL files store raw token counts, not pre-computed costs. spend-guard multiplies tokens by a hardcoded pricing table. If Anthropic changes prices, the table will be stale until the plugin is updated. Install [ccusage](https://github.com/ryoppippi/ccusage) (`npm install -g ccusage`) for more accurate figures — it is used as the primary source when available.
- **Status is a point-in-time snapshot.** `/spend-guard:status` calculates spend at the moment you invoke it. Tokens consumed in the current turn are not yet written to disk and will not appear until the next invocation.
- **Fails open.** If spend cannot be determined (Python missing, JSONL unreadable, parse error), the plugin allows the action through rather than locking you out. A broken setup means no enforcement.
- **Pricing table may lag.** The token × price calculation uses a bundled table. Run `/spend-guard:update-cost` to pull the latest prices from Anthropic's docs.

## Install

From the official Claude Code marketplace flow:

```
/plugin marketplace add elessarkrin/spend-guard
/plugin install spend-guard@spend-guard
```

Local development:

```bash
git clone https://github.com/elessarkrin/spend-guard
claude --plugin-dir ./spend-guard/plugins/spend-guard
```

## Usage

Plugin commands in Claude Code are always namespaced as `/<plugin>:<command>`:

```
/spend-guard:status        # show today's spend, configured limit, and remaining budget
/spend-guard:limit 25      # set the daily limit to $25 (writes ~/.config/spend-guard/limit)
/spend-guard:update-cost   # fetch latest Anthropic pricing and update the local pricing table
```

Once installed, no further action is required for enforcement — the hooks run automatically on every prompt and every tool call.

**Status:**

```
$ /spend-guard:status
$10.66 spent today, $24.34 remaining of $35.00 limit (30%)
```

**Change limit:**

```
$ /spend-guard:limit 50
spend-guard: daily limit set to $50 (saved to ~/.config/spend-guard/limit)
Run /spend-guard:status to see current usage against the new limit.
```

**When the limit is reached:**

```
UserPromptSubmit operation blocked by hook:
  [bash ${CLAUDE_PLUGIN_ROOT}/hooks/spend-guard.sh]: 🚫 Daily spend limit reached: $36.70 / $35.00
     Remaining: $0.00 — resets at local midnight.
     To change limit: /spend-guard:limit <amount>
```

## How it works

spend-guard registers two Claude Code hooks (see `hooks/hooks.json`):

| Hook | Matcher | Why |
|---|---|---|
| `UserPromptSubmit` | (any) | **Launch guard.** Fires when you submit a prompt, before Claude processes it. Blocks new turns when the limit is already crossed. |
| `PreToolUse` | `.*` | **Mid-session guard.** Fires before every tool call (Write, Bash, Edit, Read, etc.). Blocks the moment a tool call would execute after the limit is crossed during a turn. |

Both invoke `hooks/spend-guard.sh`. If today's spend is below the limit, the script exits `0` and the action proceeds. If spend has reached the limit, it writes a clear message to stderr and exits `2`, which Claude Code surfaces as a hard block.

The script fails open: if spend cannot be determined (no Python, no JSONL files, parse error), it exits `0` rather than locking you out.

## Configuration

The limit is resolved in this priority order:

| Source | Example | Notes |
|---|---|---|
| `CLAUDE_DAILY_LIMIT` env var | `export CLAUDE_DAILY_LIMIT=25` | Highest priority. Per-shell override. |
| `~/.config/spend-guard/limit` | `echo 40 > ~/.config/spend-guard/limit` | Persistent. Written by `/spend-guard:limit <amount>`. |
| Hardcoded default | `40.00` | Used when neither of the above is set. |

The config file holds nothing but the number (e.g. `25.00`). Whitespace is stripped.

## Spend calculation

Two strategies, in order:

1. **ccusage (preferred).** Runs `npx --yes ccusage@latest daily --json` and parses the daily total. Used only when local date matches UTC date — skipped near UTC midnight to avoid cross-day miscounting.
2. **Raw JSONL (fallback).** Walks `~/.claude/projects/**/*.jsonl` plus `~/.claude/statusline.jsonl`. Claude Code stores raw token counts in `message.usage`, not pre-computed costs — spend-guard multiplies tokens by a bundled pricing table to compute cost. Timestamps are UTC but filtered against **local date** to capture the full local day.

For best accuracy on API-key sessions:

```bash
npm install -g ccusage
```

This avoids the `npx` cold-start cost and ensures Strategy 1 is always available.

## WSL / API-key note

Hooks and Claude Code's JSONL log files live under `~/.claude/`. On WSL this is the **WSL home directory** (e.g. `/home/<user>/.claude/`), and that's where this plugin reads from.

If you launch Claude Code from Windows CMD or PowerShell instead of from inside WSL, sessions write to `%USERPROFILE%\.claude\` on the Windows filesystem. Those sessions are invisible to a WSL-installed spend-guard, and the plugin will under-count your spend. Pick one launch context and stick to it; for shared environments, install spend-guard in both.

## Why not `--max-budget-usd`?

Claude Code ships a `--max-budget-usd` flag, but it only applies to **single non-interactive `claude -p` print-mode commands**. It does not enforce a limit across an interactive session, and it does not persist a daily cap across sessions. spend-guard fills exactly that gap: an interactive, persistent, daily hard stop that Claude Code itself does not provide.
