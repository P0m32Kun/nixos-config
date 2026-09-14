#!/usr/bin/env bash
# ============================================================
# 升级 zcode 到官网最新版本（替代手动 2 步）：
#   1. 抓官网首页取得最新版本号
#   → 2. 改 overlays/zcode.nix 的 version
#   → 3. 用新版本 URL 重算 hash 写回
#   → 4. nix build 验证
# 用法：./scripts/update-zcode.sh
# 之后：sudo nixos-rebuild switch --flake /etc/nixos
#
# 说明：官方 CDN 没有 latest 指针（releases/latest*.yml 实测全 404），
#   版本号只能从官网首页 HTML 里的 releases/<ver>/linux-x64/... 链接解析；
#   App 自身的 app-update.yml 指向占位 localhost:8081，不会自更新也不会提示。
# ============================================================
set -euo pipefail

cd "$(dirname "$0")/.."

NIX_FILE="overlays/zcode.nix"
BASE="https://cdn-zcode.z.ai/zcode/electron/releases"

# 1. 抓官网首页，列出所有 linux-x64 AppImage 的版本号，取最高者
new="$(curl -fsSL --max-time 60 -A 'Mozilla/5.0' https://zcode.z.ai/ \
  | grep -oE 'releases/[0-9]+\.[0-9]+\.[0-9]+/linux-x64/ZCode-[0-9.]+-linux-x64\.AppImage' \
  | sed -E 's|^releases/([0-9.]+)/.*$|\1|' \
  | sort -uV | tail -1)"
if [ -z "$new" ]; then
  echo "✗ 未能从官网解析出版本号（网站结构可能变了）" >&2
  exit 1
fi

old="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";$/\1/p' "$NIX_FILE" | head -1)"
echo "zcode: ${old} -> ${new}"
if [ "$old" = "$new" ]; then
  echo "已经是最新版本，无需更新"
  exit 0
fi

# 2. 改版本号（src.url 由 version 推出，无需单独改）
sed -i "s|^\([[:space:]]*\)version = \"$old\";|\1version = \"$new\";|" "$NIX_FILE"
echo "✓ version 已更新：$old -> $new"

# 3. 用新 URL 重算 hash（新 AppImage 约 200MB，需下载一次）
url="$BASE/$new/linux-x64/ZCode-$new-linux-x64.AppImage"
hash="$(nix store prefetch-file --hash-type sha256 "$url" | grep -oE 'sha256-[A-Za-z0-9+/=]+' | tail -1)"
if [ -z "$hash" ]; then
  echo "✗ 计算 hash 失败：$url" >&2
  exit 1
fi
sed -i "s|^\([[:space:]]*\)hash = \"sha256-[^\"]*\";|\1hash = \"$hash\";|" "$NIX_FILE"
echo "✓ hash 已更新：$hash"

# 4. 验证构建
nix build .#nixosConfigurations.nixos.pkgs.zcode --no-link --print-out-paths >/dev/null

echo "✓ zcode $new 构建成功"
echo "下一步：sudo nixos-rebuild switch --flake /etc/nixos"
