#!/usr/bin/env bash
# ============================================================
# 升级 orca-ide 到 GitHub 最新版本（替代手动 2 步）：
#   1. 查 GitHub releases/latest 取最新 tag
#   → 2. 改 overlays/orca.nix 的 version
#   → 3. 用新版本 URL 重算 hash 写回
#   → 4. nix build 验证
# 用法：./scripts/update-orca.sh
# 之后：sudo nixos-rebuild switch --flake /etc/nixos
#
# 说明：
#   - AppImage 资产名固定为 orca-linux.AppImage（不含版本号），
#     版本只体现在 release tag 上，故升级只改 version + hash 两处。
#   - api.github.com 国内直连实测可达；若失败，确认 http(s)_proxy 后重试。
#   - App 自带 electron-updater 但 nix 包装后失效，版本以本文件为准。
# ============================================================
set -euo pipefail

cd "$(dirname "$0")/.."

NIX_FILE="overlays/orca.nix"
REPO="stablyai/orca"

# 1. 查 GitHub 最新非 prerelease 版本
tag="$(curl -fsSL --max-time 60 -H 'Accept: application/vnd.github+json' \
  "https://api.github.com/repos/${REPO}/releases/latest" \
  | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
case "$tag" in
  v*) new="${tag#v}" ;;
  *) echo "✗ 未能解析最新 tag（拿到：${tag:-空}）" >&2; exit 1 ;;
esac

old="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";$/\1/p' "$NIX_FILE" | head -1)"
echo "orca-ide: ${old} -> ${new}"
if [ "$old" = "$new" ]; then
  echo "已经是最新版本，无需更新"
  exit 0
fi

# 2. 改版本号（src.url 由 version 推出，无需单独改）
sed -i "s|^\([[:space:]]*\)version = \"$old\";|\1version = \"$new\";|" "$NIX_FILE"
echo "✓ version 已更新：$old -> $new"

# 3. 重算 hash（AppImage 约 210MB，需下载一次；--json 才带 hash 字段）
url="https://github.com/${REPO}/releases/download/v${new}/orca-linux.AppImage"
hash="$(nix store prefetch-file --json --hash-type sha256 "$url" \
  | sed -n 's/.*"hash"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
if [ -z "$hash" ]; then
  echo "✗ 计算 hash 失败：$url" >&2
  exit 1
fi
sed -i "s|^\([[:space:]]*\)hash = \"sha256-[^\"]*\";|\1hash = \"$hash\";|" "$NIX_FILE"
echo "✓ hash 已更新：$hash"

# 4. 验证构建
nix build .#nixosConfigurations.nixos.pkgs.orca-ide --no-link --print-out-paths >/dev/null

echo "✓ orca-ide $new 构建成功"
echo "下一步：sudo nixos-rebuild switch --flake /etc/nixos"
