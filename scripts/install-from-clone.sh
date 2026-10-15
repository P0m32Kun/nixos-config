#!/usr/bin/env bash
# ============================================================
# install-from-clone.sh — 换机/重装一键引导（幂等）
#
# 用法：./scripts/install-from-clone.sh [--dry-run] [--no-rebuild]
#
# 做什么（顺序）：
#   1. 校验 flake 依赖就位（wl-harness / lmclient-nix）——缺哪个就报哪个
#   2. 建 /etc/nixos -> 本仓库 的符号链接（fish 的 rebuild/update 别名都走 /etc/nixos）
#   3. 硬件配置就位检查（缺就给出 nixos-generate-config 命令，不自动覆盖）
#   4. ./scripts/check.sh（nixfmt + 整机求值冒烟）
#   5. sudo nixos-rebuild switch --flake /etc/nixos
#   6. 提示快层工具安装与 agent 自检（scripts/agent-check.sh，属 wl-harness）
#
# 不做什么（有意留白）：
#   - 不下载快层工具（pi 全家桶 / hermes / agy / herdr）——见下方提示
#   - 不碰任何凭据（SSH key / tailscale / OAuth / API key）
#   - 不覆盖已存在的 hardware-configuration.nix
# ============================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRY=0
NO_REBUILD=0
for arg in "$@"; do
  case "$arg" in
    -n|--dry-run) DRY=1 ;;
    --no-rebuild) NO_REBUILD=1 ;;
    -h|--help) sed -n '3,24p' "$0"; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

ok()   { printf '  [ok]   %s\n' "$*"; }
miss() { printf '  [MISS] %s\n' "$*"; }
info() { printf '  [....] %s\n' "$*"; }
fail() { printf '  [FAIL] %s\n' "$*" >&2; }
run()  { if [ "$DRY" = 1 ]; then printf '  [dry]  %s\n' "$*"; else "$@"; fi; }

BLOCKED=0

echo "===== 1/6 flake 依赖就位 ====="
WL_DIR="$HOME/Projects/wl-harness"
LM_DIR="$HOME/Projects/lmclient-nix"

if [ -d "$WL_DIR/.git" ]; then
  ok "wl-harness: $WL_DIR"
else
  miss "wl-harness 未就位：$WL_DIR"
  info "私有仓库，先 clone：git clone git@github.com:P0m32Kun/wl-harness.git $WL_DIR"
  BLOCKED=1
fi

if [ -d "$LM_DIR" ]; then
  ok "lmclient-nix: $LM_DIR"
  if [ -f "$LM_DIR/flake.nix" ]; then
    ok "lmclient-nix/flake.nix 存在"
  else
    miss "lmclient-nix 缺 flake.nix（目录内容不完整）"
    BLOCKED=1
  fi
else
  miss "lmclient-nix 未就位：$LM_DIR"
  fail "该目录**不在 git 里**（含 64MB AppImage + 图标 + flake），无法 clone"
  fail "必须从备份还原到 $LM_DIR（路径要与 flake.nix 的 path: 输入完全一致）"
  BLOCKED=1
fi

echo
echo "===== 2/6 /etc/nixos 符号链接 ====="
if [ -L /etc/nixos ]; then
  target="$(readlink -f /etc/nixos)"
  if [ "$target" = "$REPO_ROOT" ]; then
    ok "/etc/nixos -> $REPO_ROOT"
  else
    miss "/etc/nixos 指向 $target（期望 $REPO_ROOT）"
    run sudo ln -sfn "$REPO_ROOT" /etc/nixos
  fi
elif [ -e /etc/nixos ]; then
  miss "/etc/nixos 是实体目录（非符号链接），请人工确认后再处理"
  BLOCKED=1
else
  miss "/etc/nixos 不存在"
  run sudo ln -sfn "$REPO_ROOT" /etc/nixos
fi

echo
echo "===== 3/6 硬件配置 ====="
HW="$REPO_ROOT/hosts/nixos/hardware-configuration.nix"
if [ ! -f "$HW" ]; then
  miss "hosts/nixos/hardware-configuration.nix 不存在"
  info "新机生成（**按新机硬件重生成，不要沿用旧机的**）："
  info "  sudo nixos-generate-config --show-hardware-config > $HW"
  BLOCKED=1
else
  if grep -q 'by-uuid' "$HW"; then
    ok "hardware-configuration.nix 存在（含磁盘 UUID）"
    info "若这是**新机器**，请确认 UUID/驱动属于本机，不要沿用旧机的"
  else
    ok "hardware-configuration.nix 存在"
  fi
fi

echo
echo "===== 4/6 配置自检（nixfmt + 整机求值冒烟） ====="
if [ "$DRY" = 1 ]; then
  info "dry-run：跳过 ./scripts/check.sh"
else
  if "$REPO_ROOT/scripts/check.sh"; then
    ok "check.sh 通过"
  else
    fail "check.sh 未通过——先修配置再 rebuild"
    BLOCKED=1
  fi
fi

echo
echo "===== 5/6 重建系统 ====="
if [ "$BLOCKED" -ne 0 ]; then
  fail "前置未满足（见上方 [MISS]/[FAIL]），跳过 rebuild"
else
  if [ "$NO_REBUILD" = 1 ]; then
    info "--no-rebuild：跳过 rebuild"
  else
    run sudo nixos-rebuild switch --flake /etc/nixos
  fi
fi

echo
echo "===== 6/6 重建后必做（快层 + 凭据，本脚本不代办） ====="
cat <<'EOF'
  1. 快层工具安装（工具下载可脚本化，配置已由 wl-harness seed）：
       npm i -g pi 全家桶、hermes 官方 install.sh（勿用 PyPI 渠道）、
       agy 官方脚本、herdr 官方 installer（herdr.dev/install）
     详见 AGENTS.md 换机清单第 7 条
  2. agent 自检（补插件/MCP/external_dirs）：
       ~/Projects/wl-harness/scripts/agent-check.sh all --install
     每个 agent 的自检清单：~/Projects/wl-harness/shared/agents/checklists/
  3. 凭据恢复（不入库，必须手动）：
       ~/.pi/agent/auth.json、~/.hermes/、SSH keys、tailscale 认证、
       ~/.local/state/sysops/webhook.env —— 见 AGENTS.md 换机清单第 8 条
  4. sysops 运行时初始化（profile/gateway/webhook/toolsets）—— 见 AGENTS.md #6
  5. noctalia 插件启用：已由 home/noctalia-plugins.nix 每次登录自动重申；
     若仍关闭，手动 `noctalia msg plugins enable kun/agent-usage`、`kun/sysops`
EOF

echo
if [ "$BLOCKED" -ne 0 ]; then
  echo "RESULT: 前置未满足，未完成部署"
  exit 1
fi
echo "RESULT: 部署完成（快层/凭据按上方清单收尾）"
