{ pkgs }:
pkgs.writeShellScriptBin "screenshot-region" ''
  #!/usr/bin/env bash
  # 区域截图 → 落盘 + 剪贴板 → 立刻进 swappy 标注
  # 绑定：SUPER + S 与顶栏截图按钮（见 keybinds.lua / noctalia-config.toml）
  #
  # 实现用 slurp+grim 直连，不走 hyprshot：hyprshot 1.3.0 把抓图放后台
  # 子 shell（`begin_grab &`），选区一结束主进程就退出，后续「文件是否
  # 已保存」的检查会与 grim 写文件竞态——曾表现为 swappy「隔一次才弹」。
  # 同一管道内 tee 写完文件才返回，顺序有保证，竞态不存在。
  set -euo pipefail

  DIR="''${SCREENSHOT_DIR:-$HOME/Pictures/Screenshots}"
  mkdir -p "$DIR"
  NAME="screenshot_$(date +'%Y-%m-%d_%H-%M-%S')-region.png"

  # -d 显示选区尺寸（与 hyprshot region 同交互）；Esc 取消 → 非零退出
  geometry=$(slurp -d) || exit 0

  # grim 截图写 stdout → tee 落盘 + wl-copy 进剪贴板
  grim -g "$geometry" - | tee "$DIR/$NAME" | wl-copy --type image/png

  # 空选区兜底（正常不会走到）
  if [ ! -s "$DIR/$NAME" ]; then
    rm -f "$DIR/$NAME"
    exit 0
  fi

  # swappy 标注（配置见 ~/.config/swappy/config）：
  #   Ctrl+S → 标注版另存 $DIR/annotated_*.png
  #   Ctrl+C → 标注版进剪贴板
  #   Esc / 关闭窗口 → 保留上面的原图，不产生额外文件
  exec swappy -f "$DIR/$NAME"
''
