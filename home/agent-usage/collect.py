#!/usr/bin/env python3
"""agent-usage 采集层：解析各 harness 的本地会话数据，按 agent 原子写
~/.local/state/agent-usage/<agent>.json（display-ready，展示层只读不算）。

设计参照 Omarchy 的 agent-usage 架构：采集与展示解耦、文件系统当 IPC、
每 agent 一条 JSON。数据源（2026-10 实测）：

- zcode : ~/.zcode/cli/db/db.sqlite 的 model_usage 表（每请求一行，
          含 input/output/reasoning/cache token；只读 URI 打开，WAL 下
          读不阻塞写）。无成本字段（coding-plan 订阅制）。
- pi    : ~/.pi/agent/sessions/**/*.jsonl 的 assistant message.usage
          （含 cost）。增量：按 path+mtime+size 缓存每文件的解析结果，
          只重扫变化过的文件（缓存在 ~/.cache/agent-usage/）。
- codex : ~/.codex/sessions/**/*.jsonl（本机暂未使用，按标准 rollout
          格式尽力解析：token_count 事件是会话累计值，取每文件最后一条，
          按天聚合是会话粒度的近似——记录里以 granularity 标明）。
- hermes: 未在本地持久化 token 用量（logs 无 token 字段），标记
          available=false，报告里明说而不是静默缺失。

用法：collect.py [agent ...]   # 缺省全部；失败 agent 退出码非零
"""

import datetime as dt
import fcntl
import json
import os
import sqlite3
import sys
import tempfile
from pathlib import Path

HOME = Path.home()
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "agent-usage"
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache")) / "agent-usage"

TOKEN_KEYS = ("input", "output", "cache_read", "cache_write", "reasoning")

# ---- 人民币成本（2026-10-14 调研官方牌价，元/百万 token）----
# 智谱 GLM-5.3：输入8/输出28/缓存读2（缓存写限时免费）
#   来源 docs.bigmodel.cn/cn/guide/start/pricing
# 小米 mimo-v2.6-pro：3/6/0.025 来源 mimo.mi.com/docs/zh-CN/price/pay-as-you-go
# DeepSeek flash 档（v4 已退役、与 v4.1 同价）：高峰2/8/0.04，空闲1/4/0.02，
#   此处取峰谷均值近似 来源 api-docs.deepseek.com/zh-cn/quick_start/pricing
# pi / hermes 上报的美元成本按下方汇率折算（更新牌价/汇率改这里）
USD_CNY = 6.705
CNY_PER_MTOK = {
    "glm-5.3": {"input": 8, "output": 28, "cache_read": 2, "cache_write": 0},
    "mimo-v2.6-pro": {"input": 3, "output": 6, "cache_read": 0.025, "cache_write": 0},
    "deepseek-v4-flash": {"input": 1.5, "output": 6, "cache_read": 0.03, "cache_write": 0},
    "deepseek-v4.1-flash": {"input": 1.5, "output": 6, "cache_read": 0.03, "cache_write": 0},
    "deepseek-flash": {"input": 1.5, "output": 6, "cache_read": 0.03, "cache_write": 0},
}


def cost_cny_of(cost_usd, usage, model):
    """上报成本优先（折算汇率）；无上报（订阅制）则按官方牌价估算"""
    if cost_usd is not None and cost_usd > 0:
        return cost_usd * USD_CNY
    key = (model or "").lower()
    for name, p in CNY_PER_MTOK.items():
        if name in key:
            return (
                usage.get("input", 0) * p["input"]
                + usage.get("output", 0) * p["output"]
                + usage.get("cache_read", 0) * p["cache_read"]
                + usage.get("cache_write", 0) * p["cache_write"]
            ) / 1e6
    return None


def today_str() -> str:
    return dt.date.today().isoformat()


def local_date_from_ms(ms: int) -> str:
    return dt.datetime.fromtimestamp(ms / 1000).date().isoformat()


def local_date_from_iso(ts) -> str:
    if isinstance(ts, (int, float)):  # pi 部分记录用 epoch 毫秒
        return dt.datetime.fromtimestamp(ts / 1000).date().isoformat()
    return (
        dt.datetime.fromisoformat(str(ts).replace("Z", "+00:00")).astimezone().date().isoformat()
    )


def new_bucket(**extra):
    b = {k: 0 for k in TOKEN_KEYS}
    b["requests"] = 0
    b["cost"] = 0.0
    b["cost_cny"] = 0.0
    b.update(extra)
    return b


def add_into(bucket, usage, cost=None, requests=1, cost_cny=None):
    for k in TOKEN_KEYS:
        bucket[k] += usage.get(k) or 0
    bucket["requests"] += requests
    if cost is not None:
        bucket["cost"] += cost
    if cost_cny is not None:
        bucket["cost_cny"] += cost_cny


def in_days(day, days):
    return (dt.date.today() - dt.timedelta(days=days - 1)).isoformat() <= day


def summarize(rows, extra=None):
    """rows: [{date, model, usage{...}, cost}] → 汇总记录"""
    today = today_str()
    out = {
        "today": new_bucket(),
        "week": new_bucket(),
        "total": new_bucket(),
        "by_day": [],
        "by_model": {},
    }
    days = {}
    for r in rows:
        reqs = r.get("requests", 1)
        cc = r.get("cost_cny")
        if cc is None:
            cc = cost_cny_of(r.get("cost"), r["usage"], r.get("model"))
        add_into(out["total"], r["usage"], r.get("cost"), reqs, cc)
        add_into(days.setdefault(r["date"], new_bucket()), r["usage"], r.get("cost"), reqs, cc)
        m = out["by_model"].setdefault(r.get("model") or "unknown", new_bucket())
        add_into(m, r["usage"], r.get("cost"), reqs, cc)
        if in_days(r["date"], 7):
            add_into(out["week"], r["usage"], r.get("cost"), reqs, cc)
    for d, b in sorted(days.items(), reverse=True):
        if in_days(d, 30):
            out["by_day"].append({"date": d, **b})
    out["today"] = days.get(today, new_bucket())
    out["by_model"] = [
        {"model": k, **v} for k, v in sorted(out["by_model"].items(), key=lambda kv: -kv[1]["input"])
    ]
    out["sessions_today"] = len({r["session"] for r in rows if r["date"] == today and r.get("session")})
    if extra:
        out.update(extra)
    return out


def write_record(agent, record):
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=STATE_DIR, prefix=f".{agent}.", text=True)
    with os.fdopen(fd, "w") as f:
        json.dump(record, f, ensure_ascii=False, indent=1)
    os.replace(tmp, STATE_DIR / f"{agent}.json")


def base_record(agent, source):
    return {
        "agent": agent,
        "collected_at": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
        "available": True,
        "source": source,
        **summarize([]),
    }


# ---------------- zcode ----------------

def collect_zcode():
    db = HOME / ".zcode/cli/db/db.sqlite"
    if not db.exists():
        return {**base_record("zcode", str(db)), "available": False,
                "reason": f"未找到 {db}"}
    # 只读 URI：WAL 模式下读不阻塞正在写入的会话
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    rows = []
    for r in con.execute(
        """
        SELECT started_at, model_id, session_id, input_tokens, output_tokens,
               reasoning_tokens, cache_read_input_tokens, cache_creation_input_tokens
        FROM model_usage WHERE status='completed'
        """
    ):
        rows.append({
            "date": local_date_from_ms(r["started_at"]),
            "model": r["model_id"],
            "session": r["session_id"],
            "usage": {
                "input": r["input_tokens"] or 0,
                "output": r["output_tokens"] or 0,
                "cache_read": r["cache_read_input_tokens"] or 0,
                "cache_write": r["cache_creation_input_tokens"] or 0,
                "reasoning": r["reasoning_tokens"] or 0,
            },
            "cost": None,
        })
    con.close()
    return {**base_record("zcode", f"{db}:model_usage"), **summarize(rows),
            "cost_note": "按智谱官方牌价估算（coding-plan 订阅制实际不按量计费）"}


# ---------------- pi ----------------

def _pi_file_entries(path: Path):
    out = []
    for line in open(path, encoding="utf-8", errors="replace"):
        try:
            d = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue
        if d.get("type") != "message":
            continue
        m = d.get("message") or {}
        if m.get("role") != "assistant":
            continue
        u = m.get("usage") or {}
        if not any(u.get(k) for k in ("input", "output", "cacheRead", "cacheWrite")):
            continue
        ts = m.get("timestamp") or d.get("timestamp")
        if not ts:
            continue
        cost = (u.get("cost") or {}).get("total")
        out.append({
            "date": local_date_from_iso(ts),
            "model": m.get("model") or d.get("model"),
            "session": str(path),
            "usage": {
                "input": u.get("input") or 0,
                "output": u.get("output") or 0,
                "cache_read": u.get("cacheRead") or 0,
                "cache_write": u.get("cacheWrite") or 0,
                "reasoning": u.get("reasoning") or 0,
            },
            "cost": cost,
        })
    return out


def collect_pi():
    root = HOME / ".pi/agent/sessions"
    cache_file = CACHE_DIR / "pi-files.json"
    cache = {}
    if cache_file.exists():
        try:
            cache = json.loads(cache_file.read_text())
        except (json.JSONDecodeError, OSError):
            cache = {}
    files = sorted(root.glob("*/*.jsonl")) if root.exists() else []
    sig = {str(p): (p.stat().st_mtime_ns, p.stat().st_size) for p in files}
    rows = []
    for p in files:
        key = str(p)
        hit = cache.get(key)
        if hit and tuple(hit["sig"]) == sig[key]:
            rows.extend(hit["entries"])
        else:
            entries = _pi_file_entries(p)
            cache[key] = {"sig": sig[key], "entries": entries}
            rows.extend(entries)
    for k in list(cache):  # 清掉已删除文件的缓存
        if k not in sig:
            del cache[k]
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = cache_file.with_suffix(".tmp")
    tmp.write_text(json.dumps(cache))
    os.replace(tmp, cache_file)
    if not files:
        return {**base_record("pi", str(root)), "available": False,
                "reason": f"未找到会话文件（{root}）"}
    return {**base_record("pi", f"{root}/*/*.jsonl"), **summarize(rows),
            "cost_note": f"pi 上报美元成本 × {USD_CNY} 折算"}


# ---------------- codex ----------------

def _codex_file_total(path: Path):
    """rollout 格式：token_count 事件携带会话累计值，取最后一条的
    total_token_usage 作为该会话总量；按天归属用最后一个事件的时间。"""
    total, last_ts, model = None, None, None
    for line in open(path, encoding="utf-8", errors="replace"):
        try:
            d = json.loads(line)
        except (json.JSONDecodeError, ValueError):
            continue
        ts = d.get("timestamp")
        if ts:
            last_ts = ts
        p = d.get("payload") or {}
        info = p.get("info") or {}
        tu = info.get("total_token_usage")
        if tu:
            total = tu
        mi = info.get("model_context_window") or {}
        if not model and mi.get("model"):
            model = mi["model"]
    if not total or not last_ts:
        return None
    return {
        "date": local_date_from_iso(last_ts),
        "model": model,
        "session": str(path),
        "usage": {
            "input": total.get("input_tokens") or 0,
            "output": total.get("output_tokens") or 0,
            "cache_read": total.get("cached_input_tokens") or 0,
            "cache_write": 0,
            "reasoning": total.get("reasoning_output_tokens") or 0,
        },
        "cost": None,
    }


def collect_codex():
    root = HOME / ".codex/sessions"
    if not root.exists():
        return {**base_record("codex", str(root)), "available": False,
                "reason": "未找到 ~/.codex/sessions（codex 尚未在本机使用）"}
    rows = [r for p in sorted(root.glob("**/*.jsonl")) if (r := _codex_file_total(p))]
    return {**base_record("codex", f"{root}/**/*.jsonl"), **summarize(rows),
            "granularity": "session（按会话归并，跨天会话计入结束日）"}


# ---------------- hermes ----------------

def collect_hermes():
    # v0.22+（官方 install.sh 渠道）：~/.hermes/state.db 的
    # session_model_usage 表按 session×model 聚合，含
    # api_call_count 与 estimated_cost_usd；日期归属用 sessions.started_at
    db = HOME / ".hermes/state.db"
    if not db.exists():
        return {**base_record("hermes", str(db)), "available": False,
                "reason": f"未找到 {db}（hermes 尚未使用官方渠道安装/使用）"}
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    rows = []
    for r in con.execute(
        """
        SELECT u.session_id, u.model, u.input_tokens, u.output_tokens,
               u.cache_read_tokens, u.cache_write_tokens, u.reasoning_tokens,
               u.api_call_count, u.estimated_cost_usd, s.started_at
        FROM session_model_usage u
        LEFT JOIN sessions s ON s.id = u.session_id
        """
    ):
        ts = r["started_at"] or 0
        date = (
            dt.datetime.fromtimestamp(float(ts)).date().isoformat()
            if ts
            else r["session_id"][:4] + "-" + r["session_id"][4:6] + "-" + r["session_id"][6:8]
        )
        rows.append({
            "date": date,
            "model": r["model"],
            "session": r["session_id"],
            "usage": {
                "input": r["input_tokens"] or 0,
                "output": r["output_tokens"] or 0,
                "cache_read": r["cache_read_tokens"] or 0,
                "cache_write": r["cache_write_tokens"] or 0,
                "reasoning": r["reasoning_tokens"] or 0,
            },
            "cost": r["estimated_cost_usd"] or None,
            "requests": r["api_call_count"] or 1,
        })
    con.close()
    return {**base_record("hermes", f"{db}:session_model_usage"), **summarize(rows),
            "cost_note": f"hermes estimated_cost_usd × {USD_CNY} 折算"}


COLLECTORS = {"zcode": collect_zcode, "pi": collect_pi, "codex": collect_codex,
              "hermes": collect_hermes}


def main(argv):
    wanted = argv or list(COLLECTORS)
    for name in wanted:
        if name not in COLLECTORS:
            print(f"未知 agent：{name}（可用：{' '.join(COLLECTORS)}）", file=sys.stderr)
            return 2
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    lock = open(STATE_DIR / ".lock", "w")
    fcntl.flock(lock, fcntl.LOCK_EX)
    failed = []
    for name in wanted:
        try:
            write_record(name, COLLECTORS[name]())
        except Exception as e:  # 单个失败不影响其余
            failed.append(name)
            print(f"collect {name}: {e}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
