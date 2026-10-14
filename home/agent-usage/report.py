#!/usr/bin/env python3
"""agent-usage：读 ~/.local/state/agent-usage/*.json 出终端报告。

用法：
  agent-usage               # 读现有数据（timer 每 15 分钟已刷新）
  agent-usage --refresh     # 先跑一遍采集再报告
  agent-usage --json        # 输出原始 JSON（给未来的桌面组件用）
"""

import json
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()
STATE_DIR = Path(
    __import__("os").environ.get("XDG_STATE_HOME", HOME / ".local/state")
) / "agent-usage"
STALE_SECONDS = 30 * 60


def fmt(n):
    if n is None:
        return "-"
    f = float(n)
    for unit, div in (("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if f >= div:
            return f"{f / div:.1f}{unit}"
    return str(int(f))


def fmt_cost(cny):
    return f"¥{cny:.2f}" if cny else "-"


def load_records():
    records = []
    for p in sorted(STATE_DIR.glob("*.json")):
        try:
            records.append(json.loads(p.read_text()))
        except (json.JSONDecodeError, OSError):
            pass
    return records


def table(records):
    now = time.time()
    header = (
        f"{'agent':8} {'今日(in/out/cache)':>26} {'7天in':>8} {'本月in':>8} "
        f"{'累计in':>8} {'本月¥':>8} {'累计¥':>8}  模型(30天)"
    )
    lines = [header, "-" * len(header)]
    for r in records:
        if not r.get("available"):
            lines.append(f"{r['agent']:8} （{r.get('reason', '不可用')}）")
            continue
        t = r["today"]
        today = f"{fmt(t['input'])}/{fmt(t['output'])}/{fmt(t['cache_read'])}"
        models = ", ".join(
            f"{m['model']}({fmt(m['input'])})" for m in r.get("by_model", [])[:3]
        )
        stale = ""
        ts = r.get("collected_at")
        if ts and time.mktime(time.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S")) < now - STALE_SECONDS:
            stale = " ⚠数据过期"
        lines.append(
            f"{r['agent']:8} {today:>26} {fmt(r['week']['input']):>8} "
            f"{fmt(r['month']['input']):>8} {fmt(r['total']['input']):>8} "
            f"{fmt_cost(r['month']['cost_cny']):>8} {fmt_cost(r['total']['cost_cny']):>8}  {models}{stale}"
        )
    note = {r.get("cost_note") for r in records if r.get("cost_note")}
    if note:
        lines.append("")
        lines.extend(f"  · {n}" for n in sorted(note))
    return "\n".join(lines)


def main(argv):
    refresh = "--refresh" in argv
    as_json = "--json" in argv
    if refresh:
        here = Path(__file__).parent
        rc = subprocess.call([sys.executable, str(here / "collect.py")])
        if rc and not as_json:
            print(f"⚠ 采集部分失败（exit {rc}）", file=sys.stderr)
    records = load_records()
    if not records:
        print(
            f"暂无数据（{STATE_DIR} 为空）。先跑：agent-usage --refresh",
            file=sys.stderr,
        )
        return 1
    print(json.dumps(records, ensure_ascii=False, indent=1) if as_json else table(records))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
