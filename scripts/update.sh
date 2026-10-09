#!/usr/bin/env bash
# ============================================================
# 统一的 overlay 自定义包升级脚本
# （原 update-dsh.sh / update-orca.sh / update-zcode.sh /
#   update-grok-bot.sh 四个脚本合并，逻辑原样保留）
#
# 用法：
#   ./scripts/update.sh              # 依次更新全部
#   ./scripts/update.sh orca zcode   # 只更新指定项（dsh/orca/zcode/grok-bot）
#
# 行为：
#   - 每项独立执行，单项失败不中断其余，末尾输出汇总表；
#     任一失败退出码非零。
#   - 下载走 nix-daemon 的代理 env（见 docs/decisions/0002）。
#   - 更新成功后：sudo nixos-rebuild switch --flake /etc/nixos
# ============================================================
set -euo pipefail
cd "$(dirname "$0")/.."

RESULT_DIR="$(mktemp -d)"
trap 'rm -rf "$RESULT_DIR"' EXIT

# ---------- 通用小工具 ----------

# 取 overlay 文件里第一个 version = "x.y.z";
get_version() { # <nix-file>
  sed -n 's/^[[:space:]]*version = "\([^"]*\)";$/\1/p' "$1" | head -1
}

set_version() { # <nix-file> <old> <new>
  sed -i "s|^\([[:space:]]*\)version = \"$2\";|\1version = \"$3\";|" "$1"
}

set_hash() { # <nix-file> <sha256-...>
  sed -i "s|^\([[:space:]]*\)hash = \"sha256-[^\"]*\";|\1hash = \"$2\";|" "$1"
}

# 下载并计算 sha256 hash（--json 才带 hash 字段）
prefetch_sha256() { # <url>
  nix store prefetch-file --json --hash-type sha256 "$1" \
    | sed -n 's/.*"hash"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

build_verify() { # <attr>
  nix build ".#nixosConfigurations.nixos.pkgs.$1" --no-link --print-out-paths >/dev/null
}

# ---------- 各包更新逻辑 ----------

# dsh：npm 最新版（npmmirror 解析），改 dsh.nix + package.json，
#      重生成 lockfile，重算 npmDepsHash
update_dsh() {
  local REGISTRY="https://registry.npmmirror.com"
  local NIX_FILE="overlays/dsh.nix"
  local PKG_JSON="overlays/dsh/package.json"
  local LOCK_FILE="overlays/dsh/package-lock.json"
  local new old hash

  new="$(npm view @deepseek-ai/dsh version --registry="$REGISTRY")"
  old="$(sed -n 's/^    version = "\([^"]*\)";/\1/p' "$NIX_FILE")"
  if [ "$old" = "$new" ]; then
    echo "- $old → $new（已是最新）" > "$RESULT_DIR/dsh"; return 0
  fi

  sed -i "s/version = \"$old\"/version = \"$new\"/" "$NIX_FILE"
  sed -i "s/\"@deepseek-ai\/dsh\": \"^$old\"/\"@deepseek-ai\/dsh\": \"^$new\"/" "$PKG_JSON"
  echo "  版本号已更新：$old -> $new"

  # 重新生成 lockfile（588+ 包可能需要一两分钟）
  (cd overlays/dsh && npm install --package-lock-only --ignore-scripts \
    --no-audit --no-fund --registry="$REGISTRY")
  echo "  package-lock.json 已重新生成"

  if command -v prefetch-npm-deps >/dev/null; then
    hash="$(prefetch-npm-deps "$LOCK_FILE")"
  else
    hash="$(nix run nixpkgs#prefetch-npm-deps -- "$LOCK_FILE")"
  fi
  sed -i "s|npmDepsHash = \"sha256-[^\"]*\"|npmDepsHash = \"$hash\"|" "$NIX_FILE"
  echo "  npmDepsHash 已更新"

  build_verify dsh
  echo "✓ $old → $new" > "$RESULT_DIR/dsh"
}

# orca：GitHub releases/latest 取最新 tag（资产名固定 orca-linux.AppImage）
update_orca() {
  local REPO="stablyai/orca"
  local NIX_FILE="overlays/orca.nix"
  local tag new old url hash

  tag="$(curl -fsSL --max-time 60 -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/${REPO}/releases/latest" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  case "$tag" in
    v*) new="${tag#v}" ;;
    *) echo "  ✗ 未能解析最新 tag（拿到：${tag:-空}）" >&2; return 1 ;;
  esac

  old="$(get_version "$NIX_FILE")"
  if [ "$old" = "$new" ]; then
    echo "- $old → $new（已是最新）" > "$RESULT_DIR/orca"; return 0
  fi

  set_version "$NIX_FILE" "$old" "$new"
  echo "  version 已更新：$old -> $new"

  url="https://github.com/${REPO}/releases/download/v${new}/orca-linux.AppImage"
  hash="$(prefetch_sha256 "$url")"
  if [ -z "$hash" ]; then
    echo "  ✗ 计算 hash 失败：$url" >&2; return 1
  fi
  set_hash "$NIX_FILE" "$hash"
  echo "  hash 已更新：$hash"

  build_verify orca-ide
  echo "✓ $old → $new" > "$RESULT_DIR/orca"
}

# zcode：官方 CDN 无 latest 指针（releases/latest*.yml 全 404），
#        版本号只能从官网首页 HTML 里的 releases/<ver>/linux-x64/... 链接解析
update_zcode() {
  local BASE="https://cdn-zcode.z.ai/zcode/electron/releases"
  local NIX_FILE="overlays/zcode.nix"
  local new old url hash

  new="$(curl -fsSL --max-time 60 -A 'Mozilla/5.0' https://zcode.z.ai/ \
    | grep -oE 'releases/[0-9]+\.[0-9]+\.[0-9]+/linux-x64/ZCode-[0-9.]+-linux-x64\.AppImage' \
    | sed -E 's|^releases/([0-9.]+)/.*$|\1|' \
    | sort -uV | tail -1)"
  if [ -z "$new" ]; then
    echo "  ✗ 未能从官网解析出版本号（网站结构可能变了）" >&2; return 1
  fi

  old="$(get_version "$NIX_FILE")"
  if [ "$old" = "$new" ]; then
    echo "- $old → $new（已是最新）" > "$RESULT_DIR/zcode"; return 0
  fi

  set_version "$NIX_FILE" "$old" "$new"
  echo "  version 已更新：$old -> $new"

  url="$BASE/$new/linux-x64/ZCode-$new-linux-x64.AppImage"
  hash="$(prefetch_sha256 "$url")"
  if [ -z "$hash" ]; then
    echo "  ✗ 计算 hash 失败：$url" >&2; return 1
  fi
  set_hash "$NIX_FILE" "$hash"
  echo "  hash 已更新：$hash"

  build_verify zcode
  echo "✓ $old → $new" > "$RESULT_DIR/zcode"
}

# grok-bot：下载页 URL 含上游 commit 段（stable/<commit>/linux/x64/...），
#           每次发布都变，version / commit 两处都要改
update_grok_bot() {
  local NIX_FILE="overlays/grok-bot.nix"
  local url new_ver new_commit old_ver old_commit hash

  url="$(curl -fsSL --max-time 60 https://cursor.com/download/bot \
    | grep -oE 'https://downloads\.cursor\.com/grokbot/stable/[0-9a-f]+/linux/x64/Grok_Bot_[0-9.]+\.AppImage' \
    | head -1)"
  case "$url" in
    https://*) : ;;
    *) echo "  ✗ 未能从下载页解析 x64 AppImage URL" >&2; return 1 ;;
  esac

  new_ver="$(sed -n 's|.*/Grok_Bot_\([0-9.]*\)\.AppImage|\1|p' <<<"$url")"
  new_commit="$(sed -n 's|.*/stable/\([0-9a-f]*\)/.*|\1|p' <<<"$url")"
  old_ver="$(get_version "$NIX_FILE")"
  old_commit="$(sed -n 's/^[[:space:]]*commit = "\([0-9a-f]*\)";$/\1/p' "$NIX_FILE" | head -1)"

  if [ "$old_ver" = "$new_ver" ] && [ "$old_commit" = "$new_commit" ]; then
    echo "- $old_ver → $new_ver（已是最新）" > "$RESULT_DIR/grok-bot"; return 0
  fi

  set_version "$NIX_FILE" "$old_ver" "$new_ver"
  sed -i "s|^\([[:space:]]*\)commit = \"$old_commit\";|\1commit = \"$new_commit\";|" "$NIX_FILE"
  echo "  version/commit 已更新：$old_ver -> $new_ver"

  hash="$(prefetch_sha256 "$url")"
  if [ -z "$hash" ]; then
    echo "  ✗ 计算 hash 失败：$url" >&2; return 1
  fi
  set_hash "$NIX_FILE" "$hash"
  echo "  hash 已更新：$hash"

  build_verify grok-bot
  echo "✓ $old_ver → $new_ver" > "$RESULT_DIR/grok-bot"
}

# ---------- 入口 ----------

requested=("$@")
if [ ${#requested[@]} -eq 0 ]; then
  requested=(dsh orca zcode grok-bot)
fi

for t in "${requested[@]}"; do
  case "$t" in
    dsh|orca|zcode|grok-bot) ;;
    *) echo "✗ 未知项：$t（可用：dsh / orca / zcode / grok-bot）" >&2; exit 2 ;;
  esac
done

for t in "${requested[@]}"; do
  echo
  echo "===== $t ====="
  # 子 shell 里重开 set -e：函数内任一步失败即判定该项失败，但不中断其余项
  if ( set -euo pipefail; "update_${t//-/_}" ); then
    [ -s "$RESULT_DIR/$t" ] || echo "✓（无版本变化）" > "$RESULT_DIR/$t"
  else
    echo "✗ 失败（详见上方输出；相关文件可能已被部分修改）" > "$RESULT_DIR/$t"
  fi
done

echo
echo "================ 汇总 ================"
fail=0
for t in "${requested[@]}"; do
  printf '%-10s %s\n' "$t" "$(cat "$RESULT_DIR/$t" 2>/dev/null || echo '✗ 未执行')"
  grep -q '^✗' "$RESULT_DIR/$t" 2>/dev/null && fail=1
done

exit $fail
