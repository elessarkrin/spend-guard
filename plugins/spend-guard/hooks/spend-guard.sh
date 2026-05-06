#!/usr/bin/env bash
# spend-guard hook: enforce a daily Claude Code API spend limit.
# Wired to UserPromptSubmit (block new turns) and PreToolUse (block mid-session).
# Exit 2 = hard block; exit 0 = allow (also used to fail open on errors).

set -u
# Stay tolerant: never let an unexpected failure block the user (fail-open).
trap 'exit 0' ERR

# Capture hook payload from stdin (needed for bypass checks below).
HOOK_PAYLOAD=""
if [ ! -t 0 ]; then
  HOOK_PAYLOAD="$(cat 2>/dev/null || true)"
fi

# ---- 0. Bypass: always allow /spend-guard:limit through ----------------------
# UserPromptSubmit: let the skill invocation reach Claude.
# PreToolUse: let the Bash command that writes the limit file execute.
printf '%s' "${HOOK_PAYLOAD}" > "${HOME}/sg-payload.txt" 2>/dev/null || true
printf 'spend-guard debug: payload written to %s/sg-payload.txt\n' "${HOME}" >&2
if printf '%s\n' "${HOOK_PAYLOAD}" | grep -qF 'spend-guard:limit' 2>/dev/null; then
  exit 0
fi
if printf '%s\n' "${HOOK_PAYLOAD}" | grep -qF '.config/spend-guard/limit' 2>/dev/null; then
  exit 0
fi

# ---- 1. Resolve limit ---------------------------------------------------------
DEFAULT_LIMIT="40.00"
LIMIT_FILE="${HOME}/.config/spend-guard/limit"
LIMIT=""
LIMIT_SOURCE=""

if [ -n "${CLAUDE_DAILY_LIMIT:-}" ]; then
  LIMIT="${CLAUDE_DAILY_LIMIT}"
  LIMIT_SOURCE="env"
elif [ -r "${LIMIT_FILE}" ]; then
  LIMIT="$(tr -d '[:space:]' <"${LIMIT_FILE}" 2>/dev/null || true)"
  LIMIT_SOURCE="config"
fi

# Validate; fall back to default on anything weird.
case "${LIMIT}" in
  ''|*[!0-9.]*|*.*.*) LIMIT="${DEFAULT_LIMIT}"; LIMIT_SOURCE="default" ;;
esac
if [ -z "${LIMIT_SOURCE}" ]; then
  LIMIT_SOURCE="default"
fi

# ---- 2. Compute today's spend -------------------------------------------------
if ! command -v python3 >/dev/null 2>&1; then
  exit 0
fi

TODAY_UTC="$(date -u +%Y-%m-%d)"
TODAY_LOCAL="$(date +%Y-%m-%d)"
SPEND=""
SOURCE=""

# Strategy 1: ccusage
if [ "${TODAY_LOCAL}" = "${TODAY_UTC}" ] && command -v npx >/dev/null 2>&1; then
  CCU_JSON="$(npx --yes ccusage@latest daily --json 2>/dev/null || true)"
  if [ -n "${CCU_JSON}" ]; then
    CCU_OUT="$(printf '%s' "${CCU_JSON}" | TODAY="${TODAY_UTC}" python3 - 2>/dev/null <<'PY'
import json, os, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
today = os.environ.get("TODAY", "")
days = data.get("daily") if isinstance(data, dict) else None
if not isinstance(days, list):
    sys.exit(0)
total = 0.0
matched = False
for d in days:
    if not isinstance(d, dict):
        continue
    date = d.get("date") or d.get("day") or ""
    if isinstance(date, str) and date.startswith(today):
        for k in ("totalCost", "cost", "totalCostUSD", "total_cost"):
            v = d.get(k)
            if isinstance(v, (int, float)):
                total += float(v)
                matched = True
                break
if matched:
    print(f"{total:.6f}")
PY
)"
    if [ -n "${CCU_OUT}" ]; then
      SPEND="${CCU_OUT}"
      SOURCE="ccusage"
    fi
  fi
fi

# Strategy 2: raw JSONL fallback — compute cost from token counts
if [ -z "${SPEND}" ]; then
  JSONL_OUT="$(TODAY_LOCAL="${TODAY_LOCAL}" python3 - 2>/dev/null <<'PY'
import json, os, glob
from datetime import datetime, timezone

# Prices in USD per million tokens — source: https://docs.anthropic.com/en/docs/about-claude/pricing
# More specific prefixes must come before less specific ones (insertion order matters).
PRICING = {
    "claude-opus-4-5":  {"input": 5.0,   "output": 25.0,  "cache_read": 0.50, "cw_5m": 6.25,  "cw_1h": 10.0},
    "claude-opus-4-6":  {"input": 5.0,   "output": 25.0,  "cache_read": 0.50, "cw_5m": 6.25,  "cw_1h": 10.0},
    "claude-opus-4-7":  {"input": 5.0,   "output": 25.0,  "cache_read": 0.50, "cw_5m": 6.25,  "cw_1h": 10.0},
    "claude-opus-4":    {"input": 15.0,  "output": 75.0,  "cache_read": 1.50, "cw_5m": 18.75, "cw_1h": 30.0},
    "claude-sonnet-4":  {"input": 3.0,   "output": 15.0,  "cache_read": 0.30, "cw_5m": 3.75,  "cw_1h": 6.0},
    "claude-haiku-4-5": {"input": 1.0,   "output": 5.0,   "cache_read": 0.10, "cw_5m": 1.25,  "cw_1h": 2.0},
    "claude-haiku-3-5": {"input": 0.80,  "output": 4.0,   "cache_read": 0.08, "cw_5m": 1.00,  "cw_1h": 1.60},
    "claude-opus-3":    {"input": 15.0,  "output": 75.0,  "cache_read": 1.50, "cw_5m": 18.75, "cw_1h": 30.0},
    "claude-sonnet-3":  {"input": 3.0,   "output": 15.0,  "cache_read": 0.30, "cw_5m": 3.75,  "cw_1h": 6.0},
    "claude-haiku-3":   {"input": 0.25,  "output": 1.25,  "cache_read": 0.03, "cw_5m": 0.30,  "cw_1h": 0.50},
}
DEFAULT_PRICE = {"input": 3.0, "output": 15.0, "cache_read": 0.30, "cw_5m": 3.75, "cw_1h": 6.0}

def get_price(model):
    if not isinstance(model, str):
        return DEFAULT_PRICE
    m = model.lower()
    for prefix, p in PRICING.items():
        if m.startswith(prefix):
            return p
    return DEFAULT_PRICE

def cost_from_usage(model, usage):
    if not isinstance(usage, dict):
        return 0.0
    p = get_price(model)
    inp = usage.get("input_tokens", 0) or 0
    out = usage.get("output_tokens", 0) or 0
    cr  = usage.get("cache_read_input_tokens", 0) or 0
    cc  = usage.get("cache_creation", {}) or {}
    cw_5m = cc.get("ephemeral_5m_input_tokens") or 0
    cw_1h = cc.get("ephemeral_1h_input_tokens") or 0
    if cw_5m + cw_1h > 0:
        cw_cost = (cw_5m * p["cw_5m"] + cw_1h * p["cw_1h"]) / 1_000_000
    else:
        cw = usage.get("cache_creation_input_tokens", 0) or 0
        cw_cost = cw * p["cw_1h"] / 1_000_000
    return (inp * p["input"] + out * p["output"] + cr * p["cache_read"]) / 1_000_000 + cw_cost

today_local = os.environ.get("TODAY_LOCAL", datetime.now().strftime("%Y-%m-%d"))

def ts_is_local_today(ts_str):
    if not isinstance(ts_str, str) or not ts_str:
        return False
    try:
        dt_utc = datetime.fromisoformat(ts_str.rstrip("Z")).replace(tzinfo=timezone.utc)
        return dt_utc.astimezone().strftime("%Y-%m-%d") == today_local
    except Exception:
        return False

home = os.path.expanduser("~")
paths = glob.glob(os.path.join(home, ".claude", "projects", "**", "*.jsonl"), recursive=True)
status_path = os.path.join(home, ".claude", "statusline.jsonl")
if os.path.exists(status_path):
    paths.append(status_path)
total = 0.0
seen = False
seen_msg_ids = set()
for p in paths:
    try:
        with open(p, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                if not isinstance(rec, dict):
                    continue
                ts = rec.get("timestamp") or rec.get("ts") or ""
                if not ts_is_local_today(ts):
                    continue
                # Try pre-computed cost fields first
                msg = rec.get("message")
                msg_id = (msg.get("id") if isinstance(msg, dict) else None) or ""
                if msg_id and msg_id in seen_msg_ids:
                    continue
                for k in ("costUSD", "cost_usd", "cost"):
                    v = rec.get(k)
                    if isinstance(v, (int, float)) and v > 0:
                        total += float(v)
                        seen = True
                        if msg_id:
                            seen_msg_ids.add(msg_id)
                        break
                else:
                    # Compute from nested message token counts
                    if isinstance(msg, dict) and msg.get("role") == "assistant":
                        usage = msg.get("usage")
                        model = msg.get("model", "")
                        c = cost_from_usage(model, usage)
                        if c > 0:
                            total += c
                            seen = True
                            if msg_id:
                                seen_msg_ids.add(msg_id)
    except OSError:
        continue
if seen:
    print(f"{total:.6f}")
PY
)"
  if [ -n "${JSONL_OUT}" ]; then
    SPEND="${JSONL_OUT}"
    SOURCE="jsonl"
  fi
fi

# Fail open if we couldn't compute anything.
if [ -z "${SPEND}" ] || [ -z "${SOURCE}" ]; then
  exit 0
fi

# ---- 3. Compare and (maybe) block --------------------------------------------
DECISION="$(LIMIT="${LIMIT}" SPEND="${SPEND}" python3 - 2>/dev/null <<'PY'
import os
try:
    limit = float(os.environ["LIMIT"])
    spend = float(os.environ["SPEND"])
except Exception:
    print("allow")
    raise SystemExit
remaining = limit - spend
print(f"{'block' if spend >= limit else 'allow'}|{spend:.2f}|{limit:.2f}|{max(remaining,0):.2f}")
PY
)"

case "${DECISION}" in
  block\|*)
    SPEND_F="${DECISION#block|}"; SPEND_F="${SPEND_F%%|*}"
    REST="${DECISION#block|*|}"
    LIMIT_F="${REST%%|*}"
    REMAINING_F="${REST#*|}"
    {
      printf '🚫 Daily spend limit reached: $%s / $%s\n' "${SPEND_F}" "${LIMIT_F}"
      printf '   Remaining: $%s — resets at local midnight.\n' "${REMAINING_F}"
      printf '   To change limit: /spend-guard:limit <amount>\n'
      printf '   [debug] payload_len=%d payload_start="%s"\n' "${#HOOK_PAYLOAD}" "${HOOK_PAYLOAD:0:80}"
    } >&2
    exit 2
    ;;
esac

exit 0
