#!/usr/bin/env bash
set -u
export PYTHONUTF8=1

DEFAULT_LIMIT="40.00"
LIMIT_FILE="${HOME}/.config/spend-guard/limit"
HOOK_PATH="$(dirname "$0")/spend-guard.sh"

LIMIT=""
LIMIT_SOURCE=""
if [ -n "${CLAUDE_DAILY_LIMIT:-}" ]; then
  LIMIT="${CLAUDE_DAILY_LIMIT}"
  LIMIT_SOURCE="env (CLAUDE_DAILY_LIMIT)"
elif [ -r "${LIMIT_FILE}" ]; then
  LIMIT="$(tr -d '[:space:]' <"${LIMIT_FILE}" 2>/dev/null || true)"
  LIMIT_SOURCE="config (~/.config/spend-guard/limit)"
fi
case "${LIMIT}" in
  ''|*[!0-9.]*|*.*.*) LIMIT="${DEFAULT_LIMIT}"; LIMIT_SOURCE="default" ;;
esac
[ -z "${LIMIT_SOURCE}" ] && LIMIT_SOURCE="default"

if ! command -v python3 >/dev/null 2>&1; then
  printf 'spend-guard: python3 is required for spend calculation.\n'
  printf 'Configured limit: $%s (source: %s)\n' "${LIMIT}" "${LIMIT_SOURCE}"
  exit 0
fi

TODAY_UTC="$(date -u +%Y-%m-%d)"
TODAY_LOCAL="$(date +%Y-%m-%d)"
SPEND=""
SOURCE=""

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
                    if isinstance(msg, dict) and msg.get("role") == "assistant":
                        c = cost_from_usage(msg.get("model", ""), msg.get("usage"))
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

if [ -z "${SPEND}" ]; then
  SPEND="0"
  SOURCE="none (no usage data found for today)"
fi

LIMIT="${LIMIT}" SPEND="${SPEND}" python3 - <<'PY'
import os
limit = float(os.environ["LIMIT"])
spend = float(os.environ["SPEND"])
remaining = max(limit - spend, 0.0)
pct = 0 if limit <= 0 else min(int(round((spend / limit) * 100)), 100)
print(f"${spend:.2f} spent today, ${remaining:.2f} remaining of ${limit:.2f} limit ({pct}%)")
PY
