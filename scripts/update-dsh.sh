#!/usr/bin/env bash
# ============================================================
# 升级 dsh 到 npm 最新版本（替代手动 5 步）：
#   1. 查最新版本 → 2. 改 overlays/dsh.nix + package.json 版本号
#   → 3. 重生成 package-lock.json → 4. 重算 npmDepsHash 写回
#   → 5. nix build 验证
# 用法：./scripts/update-dsh.sh
# 之后：sudo nixos-rebuild switch --flake /etc/nixos
# ============================================================
set -euo pipefail

cd "$(dirname "$0")/.."

REGISTRY="https://registry.npmmirror.com"
NIX_FILE="overlays/dsh.nix"
PKG_JSON="overlays/dsh/package.json"
LOCK_FILE="overlays/dsh/package-lock.json"

# 1. 查最新版本
new="$(npm view @deepseek-ai/dsh version --registry="$REGISTRY")"
old="$(sed -n 's/^    version = "\([^"]*\)";/\1/p' "$NIX_FILE")"
echo "dsh: $old -> $new"
if [ "$old" = "$new" ]; then
  echo "已经是最新版本，无需更新"
  exit 0
fi

# 2. 改版本号（overlay + package.json）
sed -i "s/version = \"$old\"/version = \"$new\"/" "$NIX_FILE"
sed -i "s/\"@deepseek-ai\/dsh\": \"^$old\"/\"@deepseek-ai\/dsh\": \"^$new\"/" "$PKG_JSON"
echo "✓ 版本号已更新：$old -> $new"

# 3. 重新生成 lockfile（npmmirror 解析；588+ 包可能需要一两分钟）
(cd overlays/dsh && npm install --package-lock-only --ignore-scripts --no-audit --no-fund --registry="$REGISTRY")
echo "✓ package-lock.json 已重新生成"

# 4. 重算依赖 hash 并写回 overlays/dsh.nix
if command -v prefetch-npm-deps >/dev/null; then
  hash="$(prefetch-npm-deps "$LOCK_FILE")"
else
  hash="$(nix run nixpkgs#prefetch-npm-deps -- "$LOCK_FILE")"
fi
sed -i "s|npmDepsHash = \"sha256-[^\"]*\"|npmDepsHash = \"$hash\"|" "$NIX_FILE"
echo "✓ npmDepsHash 已更新"

# 5. 验证构建
nix build .#nixosConfigurations.nixos.pkgs.dsh --no-link --print-out-paths >/dev/null

echo "✓ dsh $new 构建成功"
echo "下一步：sudo nixos-rebuild switch --flake /etc/nixos"
