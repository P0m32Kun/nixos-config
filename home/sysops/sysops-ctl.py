#!/usr/bin/env python3
"""sysops-ctl —— 系统运维助手（hermes sysops profile）的确定性外壳。

架构（docs/decisions/0007）：采集/展示/审批解耦，文件系统当 IPC：
  - collect：浅检查（零 token），原子写 report.json，timer 每小时跑
  - propose / decide / job：方案、审批、执行状态的状态机（原子写 + queue.json 派生视图）
  - dispatch / diagnose：HMAC 签名 POST 到 hermes gateway webhook（触发即执行/诊断）
  - noctalia 插件（kun/sysops）只读 report.json + queue.json，动作全部回本 CLI

子命令：
  collect [--full]                    体检采集（--full 加网络类检查）
  report [--json]                     终端体检报告
  propose --from-issue ID             按 report.json 里的 quick_fix 生成方案
  propose --update                    系统更新方案（flake update + check.sh + rebuild）
  propose --rollback N                回滚到第 N 代的方案
  propose --file PATH                 注册外部（hermes 诊断产出的）方案 JSON
  diagnose ISSUE_ID                   触发 hermes 诊断并产出方案
  decide ID --approve|--reject        审批决定（approve 触发 webhook 执行）
  job ID --status running|done|failed [--result TEXT] [--log-append TEXT] [--mark-notified]
  sync                                重建 queue.json
方案 JSON schema：{id,title,risk(low|medium|high),rollback,steps:[{cmd,desc}],
issue_id?,source,created_at,status(pending|approved|rejected|running|done|failed)}
"""

import argparse
import hashlib
import hmac
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

STATE = Path(os.environ.get("SYSOPS_STATE_DIR", os.path.expanduser("~/.local/state/sysops")))
PROPOSALS = STATE / "proposals"
JOBS = STATE / "jobs"
LOGS = STATE / "logs"
QUEUE = STATE / "queue.json"
REPORT = STATE / "report.json"
WEBHOOK_ENV = STATE / "webhook.env"

SEVERITY_ORDER = {"crit": 0, "warn": 1, "info": 2}


# ============ 基础设施 ============

def now_iso():
    return time.strftime("%Y-%m-%dT%H:%M:%S")


def atomic_write(path: Path, text: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


def write_json(path: Path, data):
    atomic_write(path, json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def run(cmd, timeout=30):
    """只读执行 helper：返回 (exit_code, stdout)。失败不抛，由调用方决定。"""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout
    except (OSError, subprocess.TimeoutExpired) as e:
        return -1, f"{type(e).__name__}: {e}"


def issue(iid, severity, category, title, detail, quick_fix=None):
    return {
        "id": iid,
        "severity": severity,
        "category": category,
        "title": title,
        "detail": detail,
        "quick_fix": quick_fix,
    }


IGNORED = STATE / "ignored.json"
CHAT = STATE / "chat.json"
DEEP_REPORT = STATE / "deep-report.md"
HERMES = os.environ.get("SYSOPS_HERMES", os.path.expanduser("~/.local/bin/hermes-sysops"))


def load_ignored():
    return read_json(IGNORED) or {"issues": {}}


# ============ 体检采集（浅检查，零 token） ============

def check_units():
    issues, failed = [], []
    for scope, prefix in (([], "sudo "), (["--user"], "")):
        rc, out = run(["systemctl", *scope, "--failed", "--plain", "--no-legend", "--no-pager"])
        for line in out.splitlines():
            parts = line.split(None, 4)
            if rc == 0 and len(parts) >= 4 and parts[0].endswith(".service"):
                unit = parts[0]
                failed.append({"scope": "user" if scope else "system", "unit": unit})
                issues.append(issue(
                    f"unit:{'user:' if scope else ''}{unit}", "crit", "service",
                    f"单元失败：{unit}",
                    (parts[4] if len(parts) > 4 else "").strip() or f"{parts[2]}/{parts[3]}",
                    {"commands": [f"{prefix}systemctl restart {unit}"],
                     "risk": "medium",
                     "rollback": f"再次 restart 或 journalctl -u {unit} 排查；服务本身可随时 stop"},
                ))
    return issues, failed


def check_journal():
    rc, out = run(["journalctl", "-p", "3", "--since", "-24 hours", "--no-pager",
                   "-q", "--output=short-iso", "-n", "600"], timeout=45)
    lines = [l for l in out.splitlines() if l.strip()]
    count = len(lines)
    info = {"err24h": count, "samples": lines[:3]}
    if count == 0:
        return [], info
    sev = "crit" if count >= 50 else "warn"
    return [issue(
        "journal:err24h", sev, "journal",
        f"24 小时内 {count} 条 error 级日志",
        "示例：\n" + "\n".join(lines[:3]),
        None,  # 归因复杂：走「发起修复」→ hermes 诊断（B1）
    )], info


def check_disk():
    issues, info = [], {}
    for label, path in (("root", "/"), ("boot", "/boot")):
        if not os.path.exists(path):
            continue
        try:
            usage = shutil.disk_usage(path)
        except OSError:
            continue
        pct = usage.total and round(usage.used / usage.total * 100, 1)
        info[label] = {"total": usage.total, "used": usage.used, "pct": pct}
        sev = "crit" if pct >= 90 else "warn" if pct >= 80 else None
        if sev:
            qf = ({"commands": ["sudo nix-collect-garbage --delete-older-than 7d"],
                   "risk": "medium",
                   "rollback": "被清理的旧代际不可恢复（引导菜单本就只保留最近 10 代）"}
                  if label == "root" else None)
            issues.append(issue(
                f"disk:{label}", sev, "disk",
                f"{label} 分区已用 {pct}%",
                f"{usage.used // 2**30}G / {usage.total // 2**30}G", qf))
    return issues, info


def check_swap():
    try:
        mem = Path("/proc/meminfo").read_text()
        mt, mf = re.search(r"SwapTotal:\s+(\d+)", mem), re.search(r"SwapFree:\s+(\d+)", mem)
        if not mt or not mf:
            return [], {}
        total, free = int(mt.group(1)), int(mf.group(1))
    except OSError:
        return [], {}
    if total == 0:
        return [], {"swap_total": 0}
    pct = round((total - free) / total * 100, 1)
    info = {"swap_total": total, "swap_used_pct": pct}
    if pct >= 80:
        return [issue("swap:usage", "warn", "memory",
                      f"Swap 已用 {pct}%", "内存压力较大或有进程泄漏", None)], info
    return [], info


def check_drivers_firmware():
    issues, info = [], {}
    # 显示驱动模块
    display_mods = [m for m in ("nvidia", "nouveau", "i915", "xe", "amdgpu", "radeon")
                    if os.path.isdir(f"/sys/module/{m}")]
    info["display_modules"] = display_mods
    if not display_mods:
        issues.append(issue("driver:display", "warn", "driver",
                            "未检测到显卡驱动模块",
                            "/sys/module 下没有 nvidia/nouveau/i915/xe/amdgpu 任何一个", None))
    # 固件加载失败（内核日志）
    rc, out = run(["journalctl", "-k", "--since", "-24 hours", "--no-pager",
                   "-q", "--output=short-iso", "-n", "400"], timeout=45)
    pat = re.compile(r"firmware.*(?:failed|fail)|(?:failed|fail).*firmware", re.I)
    bad = [l for l in out.splitlines() if pat.search(l)]
    info["firmware_failures"] = len(bad)
    if bad:
        names = sorted(set(re.findall(r"'([^']+)'", "\n".join(bad))))[:8]
        issues.append(issue(
            "firmware:load-fail", "warn", "firmware",
            f"固件加载失败 {len(bad)} 条（内核日志）",
            ("缺失固件：" + ", ".join(names) if names else "示例：\n" + bad[0]),
            None))
    return issues, info


def check_generations():
    rc, out = run(["nix-env", "--list-generations", "-p", "/nix/var/nix/profiles/system"])
    gens = []
    for line in out.splitlines():
        m = re.match(r"\s*(\d+)\s+(\S+(?:\s+\S+)?)(?:\s+\(current\))?", line)
        if m:
            gens.append({"number": int(m.group(1)), "date": m.group(2),
                         "current": "(current)" in line})
    gens.sort(key=lambda g: g["number"])
    info = {"count": len(gens), "generations": gens[-12:]}
    issues = []
    if len(gens) > 20:
        issues.append(issue("generations:count", "info", "generation",
                            f"系统代际累积 {len(gens)} 个",
                            "代际修剪服务会按保留策略清理，如需立即清理可发起修复", None))
    return issues, info


def check_flake_updates():
    """--full 才跑：对比 flake.lock 锁定版本与远端 HEAD（纯网络，不耗 token）。"""
    issues, info = [], {}
    lock = read_json(Path("/etc/nixos/flake.lock"))
    if not lock:
        return [], {"flake": "flake.lock 读取失败"}
    nodes, root_name = lock.get("nodes", {}), lock.get("root")
    inputs = (nodes.get(root_name) or {}).get("inputs", {})
    outdated = []
    for name, target in sorted(inputs.items()):
        if not isinstance(target, str):  # follows
            continue
        node = nodes.get(target) or {}
        locked, original = node.get("locked", {}), node.get("original", {})
        if locked.get("type") not in ("github", "git"):
            continue
        if locked.get("type") == "github":
            url = f"https://github.com/{locked.get('owner')}/{locked.get('repo')}"
            ref = original.get("ref") or "HEAD"
        else:
            url = re.sub(r"^git\+", "", locked.get("url", ""))
            if not url.startswith("https"):
                continue
            ref = original.get("ref") or "HEAD"
        rc, out = run(["git", "ls-remote", url, ref], timeout=15)
        head = out.split()[0] if rc == 0 and out.split() else ""
        if head and head != locked.get("rev"):
            outdated.append({"input": name, "locked": (locked.get("rev") or "")[:8],
                             "remote": head[:8]})
    info["flake_outdated"] = outdated
    if outdated:
        issues.append(issue(
            "flake:outdated", "info", "update",
            f"{len(outdated)} 个 flake 输入有新版本",
            "、".join(f"{o['input']}({o['locked']}→{o['remote']})" for o in outdated),
            None))  # 更新走面板「系统更新」按钮（方案含 check.sh + rebuild）
    return issues, info


def check_substituter():
    ok, err = True, ""
    try:
        req = urllib.request.Request(
            "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store/nix-cache-info",
            method="GET")
        with urllib.request.urlopen(req, timeout=8) as resp:
            ok = resp.status == 200
    except Exception as e:  # noqa: BLE001 —— 网络检查失败本身就是体检结果
        ok, err = False, str(e)
    info = {"tuna_reachable": ok}
    if not ok:
        return [issue("mirror:tuna", "warn", "network",
                      "TUNA substituter 不可达", err, None)], info
    return [], info


def cmd_collect(args):
    STATE.mkdir(parents=True, exist_ok=True)
    # 忽略语义（Q7/Q16）：round=本轮忽略，采集即到期（下轮体检重新出现）；
    # permanent=永久忽略，从报告过滤掉（存 ignored 供面板撤销）
    ignored = load_ignored()
    imap = ignored.setdefault("issues", {})
    for k in [k for k, v in imap.items() if v.get("mode") != "permanent"]:
        del imap[k]
    write_json(IGNORED, ignored)

    issues, system = [], {}
    checks = [check_units, check_journal, check_disk, check_swap,
              check_drivers_firmware, check_generations]
    if args.full:
        checks += [check_flake_updates, check_substituter]
    for fn in checks:
        iss, info = fn()
        issues.extend(iss)
        system.update(info)
    issues = [i for i in issues if i["id"] not in imap]
    issues.sort(key=lambda i: SEVERITY_ORDER.get(i["severity"], 9))
    summary = {s: sum(1 for i in issues if i["severity"] == s) for s in ("crit", "warn", "info")}
    write_json(REPORT, {
        "schema": 1,
        "collected_at": now_iso(),
        "full": bool(args.full),
        "summary": summary,
        "issues": issues,
        "ignored": [{"id": k, **v} for k, v in sorted(imap.items())],
        "system": system,
    })
    sync_queue()
    print(f"体检完成：crit {summary['crit']} / warn {summary['warn']} / info {summary['info']}"
          f"（{'深' if args.full else '浅'}检查，{now_iso()}）")


def cmd_report(args):
    r = read_json(REPORT)
    if not r:
        sys.exit("report.json 不存在，先跑：sysops-ctl collect")
    if args.json:
        print(json.dumps(r, ensure_ascii=False, indent=2))
        return
    s = r.get("summary", {})
    print(f"系统体检报告  采集于 {r.get('collected_at')}"
          f"（{'深' if r.get('full') else '浅'}检查）")
    print(f"crit {s.get('crit', 0)} / warn {s.get('warn', 0)} / info {s.get('info', 0)}\n")
    for i, it in enumerate(r.get("issues", []), 1):
        print(f"[{it['severity'].upper()}] {i}. {it['title']}  ({it['id']})")
        if it.get("detail"):
            print("   " + it["detail"].replace("\n", "\n   "))
        if it.get("quick_fix"):
            print("   建议命令：" + "; ".join(it["quick_fix"]["commands"]))
        print()
    gen = r.get("system", {})
    if gen.get("generations"):
        cur = next((g["number"] for g in gen["generations"] if g.get("current")), "?")
        print(f"系统代际：共 {gen.get('count')} 个，当前第 {cur} 个")


# ============ 方案（propose） ============

def new_proposal(title, risk, rollback, steps, source, issue_id=None):
    pid = f"prop-{time.strftime('%Y%m%d-%H%M%S')}-{secrets.token_hex(2)}"
    return {
        "schema": 1,
        "id": pid,
        "title": title,
        "risk": risk,
        "rollback": rollback,
        "steps": steps,
        "source": source,
        "issue_id": issue_id,
        "created_at": now_iso(),
        "status": "pending",
    }


def save_proposal(p):
    write_json(PROPOSALS / f"{p['id']}.json", p)
    sync_queue()
    print(f"方案已进入待审批框：{p['id']}  {p['title']}（风险 {p['risk']}）")


def cmd_propose(args):
    if args.from_issue:
        r = read_json(REPORT)
        it = next((x for x in (r or {}).get("issues", []) if x["id"] == args.from_issue), None)
        if not it:
            sys.exit(f"report.json 里没有问题 {args.from_issue}")
        qf = it.get("quick_fix")
        if not qf:
            sys.exit(f"问题 {args.from_issue} 没有规则化修复，用 diagnose 走 hermes 诊断")
        save_proposal(new_proposal(
            f"修复：{it['title']}", qf.get("risk", "medium"), qf.get("rollback", ""),
            [{"cmd": c, "desc": ""} for c in qf["commands"]], "quick_fix", it["id"]))
    elif args.update:
        save_proposal(new_proposal(
            "系统更新（nix flake update + rebuild）", "medium",
            "sudo nixos-rebuild switch --rollback，或面板回滚入口选上一代",
            [{"cmd": "test -z \"$(git -C /etc/nixos status --porcelain)\"",
              "desc": "配置仓库工作区必须干净（脏则本步失败、流程即停）"},
             {"cmd": "cd /etc/nixos && nix flake update", "desc": "刷新 flake 输入锁定"},
             {"cmd": "cd /etc/nixos && ./scripts/check.sh", "desc": "nixfmt + dry 构建冒烟"},
             {"cmd": "sudo nixos-rebuild switch --flake /etc/nixos", "desc": "应用系统更新"}],
            "update"))
    elif args.rollback is not None:
        n = args.rollback
        save_proposal(new_proposal(
            f"回滚到第 {n} 代", "high",
            "切回原代际（nix-env --switch-generation <原代> 后再 switch）",
            [{"cmd": f"sudo nix-env --switch-generation {n} -p /nix/var/nix/profiles/system",
              "desc": f"把 system profile 切到第 {n} 代"},
             {"cmd": "sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch",
              "desc": "激活该代际的系统配置"}],
            "rollback"))
    elif args.file:
        p = read_json(Path(args.file))
        required = {"id", "title", "risk", "rollback", "steps"}
        if not p or not required.issubset(p) or not p["steps"] \
                or not all(isinstance(s, dict) and s.get("cmd") for s in p["steps"]):
            sys.exit(f"方案 JSON 不合法，需要字段：{sorted(required)}，steps 为非空 [{{cmd, desc}}]")
        if p["risk"] not in ("low", "medium", "high"):
            sys.exit("risk 必须是 low / medium / high")
        if "diff" in p and p["diff"] is not None and not isinstance(p["diff"], str):
            sys.exit("diff 字段必须是字符串（unified diff）")
        if (PROPOSALS / f"{p['id']}.json").exists():
            sys.exit(f"方案 {p['id']} 已存在")
        p.setdefault("created_at", now_iso())
        p.setdefault("source", "diagnose")
        p["status"] = "pending"
        save_proposal(p)


# ============ 对话与深度分析（hermes sysops profile，LLM 通道） ============

CHAT_DISCIPLINE = (
    "【sysops 运维对话】你是本机系统运维助手（sysops）。规则：只做只读诊断与解答；"
    "任何修复/变更只能写成方案注册到待审批框（用 sysops-ctl propose --file），"
    "绝不执行任何系统变更（不 sudo、不改配置、不动服务、不删文件）。"
    "方案 JSON schema：{id,title,risk(low|medium|high),rollback,"
    'steps:[{cmd,desc}],issue_id?,source:"chat",diff?}。'
    "体检数据读 ~/.local/state/sysops/report.json（或 sysops-ctl report --json）。"
    "回答用简体中文。\n\n用户消息：\n"
)


def cmd_chat(args):
    if not args.text:
        sys.exit("用法：sysops-ctl chat \"消息\"")
    chat = read_json(CHAT) or {"schema": 1, "messages": []}
    chat["messages"].append({"role": "user", "at": now_iso(), "text": args.text})
    write_json(CHAT, chat)
    qfile = STATE / ".chat-query.tmp"
    qfile.write_text(CHAT_DISCIPLINE + args.text, encoding="utf-8")
    rc, out = run([HERMES, "chat", "--query-file", str(qfile), "--continue", "sysops-chat",
                   "--create-if-missing", "--oneshot", "-Q",
                   "--skills", "nixos-managing", "--format", "text"], timeout=600)
    qfile.unlink(missing_ok=True)
    reply = out.strip() if rc == 0 else f"[对话执行失败 rc={rc}] {out.strip()[:500]}"
    chat = read_json(CHAT) or {"schema": 1, "messages": []}
    chat["messages"].append({"role": "assistant", "at": now_iso(), "text": reply})
    write_json(CHAT, chat)
    print(reply)


def cmd_deep(_args):
    """每周深度分析：一次性无状态会话（Q14——不掺进对话会话）。"""
    prompt_file = Path(__file__).with_name("deep-prompt.md")
    if not prompt_file.exists():
        sys.exit("deep-prompt.md 缺失")
    qfile = STATE / ".deep-query.tmp"
    qfile.write_text(prompt_file.read_text(encoding="utf-8"), encoding="utf-8")
    rc, out = run([HERMES, "chat", "--query-file", str(qfile), "--oneshot",
                   "-Q", "--skills", "nixos-managing", "--format", "text"], timeout=1200)
    qfile.unlink(missing_ok=True)
    atomic_write(STATE / "deep-last.txt", out)
    print(out[-2000:] if len(out) > 2000 else out)
    sys.exit(rc)


# ============ 忽略管理（两级语义，Q7/Q16） ============

def cmd_ignore(args):
    d = load_ignored()
    mode = "permanent" if args.permanent else "round"
    d["issues"][args.issue_id] = {"mode": mode, "at": now_iso()}
    write_json(IGNORED, d)
    if mode == "permanent":
        sync_queue()
    print(f"已忽略 {args.issue_id}（{'永久，collect 过滤、可撤销' if mode == 'permanent' else '本轮，下次体检重现'}）")


def cmd_unignore(args):
    d = load_ignored()
    if d.get("issues", {}).pop(args.issue_id, None) is None:
        sys.exit(f"{args.issue_id} 不在忽略列表")
    write_json(IGNORED, d)
    print(f"已恢复 {args.issue_id}（下次体检重新出现在报告中）")


def cmd_ignored(_args):
    d = load_ignored()
    if not d.get("issues"):
        print("（忽略列表为空）")
    for iid, meta in sorted(d.get("issues", {}).items()):
        print(f"{iid}  [{meta.get('mode')}]  {meta.get('at')}")


# ============ 审批（decide）与执行状态（job） ============

def cmd_decide(args):
    path = PROPOSALS / f"{args.id}.json"
    p = read_json(path)
    if not p:
        sys.exit(f"方案不存在：{args.id}")
    if p.get("status") != "pending":
        sys.exit(f"方案 {args.id} 状态是 {p.get('status')}，只有 pending 可审批")
    if args.reject:
        p["status"], p["decided_at"] = "rejected", now_iso()
        write_json(path, p)
        sync_queue()
        print(f"已拒绝：{args.id}（问题保留在体检报告中，可再次发起）")
        return
    # approve：建执行任务（queued）→ 尝试串行派发（Q3：同一时间只跑一个）
    p["status"], p["decided_at"] = "approved", now_iso()
    write_json(path, p)
    write_json(JOBS / f"{args.id}.json", {
        "schema": 1, "id": args.id, "status": "queued", "created_at": now_iso(),
        "result": "", "notified": False,
    })
    (LOGS / f"{args.id}.log").parent.mkdir(parents=True, exist_ok=True)
    sync_queue()
    ok, msg = dispatch_next()
    if ok:
        print(f"已批准并派发执行：{args.id}")
    else:
        print(f"已批准：{args.id}（{msg}）")


# ============ 串行派发（dispatch-next） ============

def dispatch_next():
    """无 dispatched/running 任务时派发最旧的 queued 任务；文件锁防并发派发。
    v2.1 起执行串行化（Q3）：2026-10-15 四方案并发曾致 patch 上下文竞态。"""
    lock = STATE / ".dispatch.lock"
    try:
        fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        try:
            if time.time() - lock.stat().st_mtime < 60:
                return False, "另一派发进程进行中"
            lock.unlink()
            fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        except OSError:
            return False, "派发锁竞争"
    try:
        os.write(fd, str(os.getpid()).encode())
        os.close(fd)
        jobs = [j for f in JOBS.glob("*.json") if (j := read_json(f))]
        if any(j.get("status") in ("dispatched", "running") for j in jobs):
            return False, "有任务在执行，排队等待接力"
        queued = sorted((j for j in jobs if j.get("status") == "queued"),
                        key=lambda j: j.get("created_at", ""))
        if not queued:
            return False, "队列为空"
        target = queued[0]
        mark_job(target["id"], "dispatched", chain=False)
        ok, msg = dispatch("sysops-execute", {"action": "execute", "proposal_id": target["id"]})
        if not ok:
            mark_job(target["id"], "failed", result=f"webhook 触发失败：{msg}", chain=False)
            return False, f"派发 {target['id']} 失败：{msg}"
        return True, f"已派发 {target['id']}"
    finally:
        try:
            lock.unlink()
        except OSError:
            pass


def cmd_dispatch_next(_args):
    ok, msg = dispatch_next()
    print(msg)
    if not ok and msg.startswith("派发"):
        sys.exit(1)


def mark_job(jid, status, result=None, log_append=None, chain=True):
    path = JOBS / f"{jid}.json"
    j = read_json(path) or {"schema": 1, "id": jid, "created_at": now_iso()}
    j["status"] = status
    j["updated_at"] = now_iso()
    if result is not None:
        j["result"] = result
    if status in ("done", "failed"):
        j["finished_at"] = now_iso()
        j["notified"] = False  # 供顶栏组件发一次完成通知
    write_json(path, j)
    if log_append:
        logf = LOGS / f"{jid}.log"
        logf.parent.mkdir(parents=True, exist_ok=True)
        with logf.open("a", encoding="utf-8") as f:
            f.write(f"[{now_iso()}] {log_append}\n")
    sync_queue()
    if chain and status in ("done", "failed"):
        # 串行接力：任务终态立即尝试派发队列中的下一个
        dispatch_next()


def cmd_job(args):
    if args.mark_notified:
        path = JOBS / f"{args.id}.json"
        j = read_json(path) or {"id": args.id}
        j["notified"] = True
        write_json(path, j)
        sync_queue()
        return
    if args.status:
        mark_job(args.id, args.status, result=args.result, log_append=args.log_append)
        print(f"任务 {args.id} → {args.status}")
        return
    if args.log_append:
        # append-only：执行协议允许每步前单独追加日志（不改状态）
        logf = LOGS / f"{args.id}.log"
        logf.parent.mkdir(parents=True, exist_ok=True)
        with logf.open("a", encoding="utf-8") as f:
            f.write(f"[{now_iso()}] {args.log_append}\n")
        return
    sys.exit("需要 --status / --log-append / --mark-notified 之一")


# ============ webhook 触发（HMAC V2 签名） ============

def load_webhook_env():
    env = {}
    if WEBHOOK_ENV.exists():
        for line in WEBHOOK_ENV.read_text().splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                k, _, v = line.partition("=")
                env[k.strip()] = v.strip()
    base = env.get("SYSOPS_WEBHOOK_URL", "")
    secret = env.get("SYSOPS_WEBHOOK_SECRET", "")
    if not base or not secret:
        raise SystemExit(f"{WEBHOOK_ENV} 缺少 SYSOPS_WEBHOOK_URL / SYSOPS_WEBHOOK_SECRET（运行时初始化未完成）")
    return base.rstrip("/"), secret


def dispatch(route, payload):
    """POST 到 hermes gateway webhook（Generic HMAC V2：<timestamp>.<body> 的 HMAC-SHA256）。"""
    try:
        base, secret = load_webhook_env()
    except SystemExit as e:
        return False, str(e)
    body = json.dumps(payload, ensure_ascii=False).encode()
    ts = str(int(time.time()))
    sig = hmac.new(secret.encode(), f"{ts}.".encode() + body, hashlib.sha256).hexdigest()
    req = urllib.request.Request(
        f"{base}/p/sysops/webhooks/{route}", data=body, method="POST",
        headers={"Content-Type": "application/json",
                 "X-Webhook-Timestamp": ts,
                 "X-Webhook-Signature-V2": sig})
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return 200 <= resp.status < 300, f"HTTP {resp.status}"  # 202 = 异步受理，成功
    except Exception as e:  # noqa: BLE001
        return False, str(e)


def cmd_diagnose(args):
    ok, msg = dispatch("sysops-diagnose", {"action": "diagnose", "issue_id": args.issue_id})
    if ok:
        print(f"已触发 hermes 诊断：{args.issue_id}（方案产出后自动进入待审批框）")
    else:
        sys.exit(f"触发失败：{msg}")


# ============ queue.json（面板读的派生视图） ============

def sync_queue():
    entries = []
    for f in sorted(PROPOSALS.glob("*.json")) if PROPOSALS.exists() else []:
        p = read_json(f)
        if not p:
            continue
        job = read_json(JOBS / f"{p['id']}.json")
        log_tail = ""
        logf = LOGS / f"{p['id']}.log"
        if logf.exists():
            try:
                log_tail = logf.read_text(encoding="utf-8")[-1500:]
            except OSError:
                pass
        entries.append({**p, "job": job, "log_tail": log_tail})
    entries.sort(key=lambda e: e.get("created_at", ""), reverse=True)
    write_json(QUEUE, {
        "schema": 1,
        "updated_at": now_iso(),
        "counts": {
            "pending": sum(1 for e in entries if e["status"] == "pending"),
            "running": sum(1 for e in entries if e["status"] in ("approved", "running")),
        },
        "proposals": entries,
    })


def cmd_sync(_args):
    sync_queue()
    print("queue.json 已刷新")


# ============ 入口 ============

def main():
    ap = argparse.ArgumentParser(prog="sysops-ctl", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("collect", help="体检采集")
    s.add_argument("--full", action="store_true", help="加网络类检查（flake 更新、镜像源）")
    s.set_defaults(fn=cmd_collect)

    s = sub.add_parser("report", help="终端体检报告")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_report)

    s = sub.add_parser("propose", help="生成/注册修复方案")
    g = s.add_mutually_exclusive_group(required=True)
    g.add_argument("--from-issue", metavar="ID")
    g.add_argument("--update", action="store_true")
    g.add_argument("--rollback", metavar="N", type=int)
    g.add_argument("--file", metavar="PATH")
    s.set_defaults(fn=cmd_propose)

    s = sub.add_parser("diagnose", help="触发 hermes 诊断")
    s.add_argument("issue_id")
    s.set_defaults(fn=cmd_diagnose)

    s = sub.add_parser("decide", help="审批方案")
    s.add_argument("id")
    d = s.add_mutually_exclusive_group(required=True)
    d.add_argument("--approve", action="store_true")
    d.add_argument("--reject", action="store_true")
    s.set_defaults(fn=cmd_decide)

    s = sub.add_parser("job", help="更新执行状态（hermes 执行器调用）")
    s.add_argument("id")
    s.add_argument("--status", choices=["queued", "running", "done", "failed"])
    s.add_argument("--result")
    s.add_argument("--log-append")
    s.add_argument("--mark-notified", action="store_true")
    s.set_defaults(fn=cmd_job)

    s = sub.add_parser("sync", help="重建 queue.json")
    s.set_defaults(fn=cmd_sync)

    s = sub.add_parser("dispatch-next", help="串行派发下一个 queued 任务（timer 兜底）")
    s.set_defaults(fn=cmd_dispatch_next)

    s = sub.add_parser("chat", help="运维对话（延续 sysops-chat 会话）")
    s.add_argument("text", nargs="?", help="用户消息")
    s.set_defaults(fn=cmd_chat)

    s = sub.add_parser("deep", help="跑一次每周深度分析（无状态一次性会话）")
    s.set_defaults(fn=cmd_deep)

    s = sub.add_parser("ignore", help="忽略问题")
    s.add_argument("issue_id")
    g = s.add_mutually_exclusive_group(required=True)
    g.add_argument("--round", action="store_true", help="本轮忽略（下次体检重现）")
    g.add_argument("--permanent", action="store_true", help="永久忽略（collect 过滤，可撤销）")
    s.set_defaults(fn=cmd_ignore)

    s = sub.add_parser("unignore", help="恢复已忽略的问题")
    s.add_argument("issue_id")
    s.set_defaults(fn=cmd_unignore)

    s = sub.add_parser("ignored", help="列出忽略的问题")
    s.set_defaults(fn=cmd_ignored)

    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
