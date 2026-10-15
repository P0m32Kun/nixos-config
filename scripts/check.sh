#!/usr/bin/env bash
# ============================================================
# 一键自检：nixfmt 格式检查 + 全量求值冒烟
#
# 用法：./scripts/check.sh
# 行为：
#   1. nixfmt --check 所有 git 追踪的 .nix 文件（CI 只做这一步）
#   2. nix build --dry-run 整机 toplevel（求值级冒烟，不真实构建、
#      不生效；真实构建/生效用 rebuild.sh 或 nixos-rebuild switch）
# 任一步失败退出码非零。
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0

echo "===== 1/2 nixfmt 格式检查 ====="
mapfile -t nix_files < <(git ls-files '*.nix')
if (( ${#nix_files[@]} == 0 )); then
  echo "✗ 未找到 .nix 文件" >&2
  exit 1
fi
if nix run nixpkgs#nixfmt -- --check "${nix_files[@]}"; then
  echo "✓ 格式全部通过"
else
  echo "✗ 存在未格式化文件（nix run nixpkgs#nixfmt -- <files> 修复后重试）" >&2
  fail=1
fi

echo
echo "===== 2/2 整机求值冒烟（dry-run） ====="
# 需要 wl-harness 本地输入就位，故只在本地跑，CI 不做这步
if nix build .#nixosConfigurations.nixos.config.system.build.toplevel --dry-run; then
  echo "✓ 求值通过"
else
  echo "✗ 求值失败" >&2
  fail=1
fi

exit $fail
