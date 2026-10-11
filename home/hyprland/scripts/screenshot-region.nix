{pkgs}:
pkgs.writeShellScriptBin "screenshot-region" ''
  #!/usr/bin/env bash
  # 区域截图 → 落盘 + 剪贴板 → 立刻进 swappy 标注
  # 绑定：SUPER + S（见 hypr/hl 配置的 keybinds）
  set -euo pipefail

  DIR="''${SCREENSHOT_DIR:-$HOME/Pictures/Screenshots}"
  mkdir -p "$DIR"
  NAME="screenshot_$(date +'%Y-%m-%d_%H-%M-%S')-region.png"

  # hyprshot：框选区域 → 存 $DIR/$NAME 并 wl-copy 到剪贴板
  # -s 静音通知（反馈交给 swappy 窗口）；Esc 取消选区时不生成文件
  hyprshot -m region -o "$DIR" -f "$NAME" -s || true

  # 选区被取消（无输出/空文件）→ 收尾退出，不弹标注器
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
