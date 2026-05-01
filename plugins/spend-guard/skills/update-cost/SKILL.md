---
description: Fetch latest Anthropic model pricing and update the spend-guard pricing table in hooks/spend-guard.sh and hooks/status.sh. Use when asked to update costs, refresh pricing, or sync prices.
allowed-tools: WebFetch, Edit, Bash
---

# spend-guard: update-cost

Fetch current Anthropic pricing and update the PRICING dict in both hook scripts.

## Step 1 — Fetch pricing

Fetch: `https://platform.claude.com/docs/en/docs/about-claude/pricing`

If WebFetch returns a redirect notice, follow the redirect URL and fetch again.

Extract the **Model pricing** table. For each row collect:
- Model name
- Base Input Tokens ($/MTok)
- 5m Cache Writes ($/MTok)
- 1h Cache Writes ($/MTok)
- Cache Hits & Refreshes ($/MTok)
- Output Tokens ($/MTok)

## Step 2 — Build PRICING dict

Convert model names to prefix keys using this pattern:
- "Claude Opus 4.7" → `"claude-opus-4-7"`
- "Claude Sonnet 4.6" → `"claude-sonnet-4-6"`
- "Claude Haiku 4.5" → `"claude-haiku-4-5"`
- etc.

Rules:
- More specific prefixes must appear before less specific ones (e.g. `claude-opus-4-5` before `claude-opus-4`).
- Keep one prefix per model version — do not merge across versions even if prices match today (e.g. Opus 4.5/4.6/4.7 all $5 → keep as `claude-opus-4-5`, `claude-opus-4-6`, `claude-opus-4-7` separately).
- Keep deprecated models if they appear in the table.
- Dict format: `{"input": X, "output": X, "cache_read": X, "cw_5m": X, "cw_1h": X}`

## Step 3 — Update both scripts

Replace the PRICING dict and DEFAULT_PRICE in **both** of these files:
- `${CLAUDE_PLUGIN_ROOT}/hooks/spend-guard.sh`
- `${CLAUDE_PLUGIN_ROOT}/hooks/status.sh`

The block to replace looks like:
```python
PRICING = {
    ...
}
DEFAULT_PRICE = {...}
```

Set DEFAULT_PRICE to the Sonnet 4.x entry (or the most common interactive model).

Add a comment above PRICING with today's date:
```python
# Prices in USD per million tokens — source: https://platform.claude.com/docs/en/docs/about-claude/pricing
# Updated: YYYY-MM-DD
```

## Step 4 — Report

After editing, print a summary table of the new prices. Do not commit — leave that to the user.
