{ config, lib, pkgs, inputs, ... }:
let
  # hyprland-btw 的辅助脚本（home.packages 里的可执行文件）
  rofiLegacyMenu = import ./hyprland/scripts/rofi-legacy.menu.nix { inherit pkgs; };
  configMenu = import ./hyprland/scripts/config-menu.nix { inherit pkgs; };
  keybindsMenu = import ./hyprland/scripts/keybinds.nix { inherit pkgs; };
  hyprlandChangeLayout = import ./hyprland/scripts/hyprland-change-layout.nix { inherit pkgs; };
  hyprlandCycleWindow = import ./hyprland/scripts/hyprland-cycle-window.nix { inherit pkgs; };
  noctaliaMsg = import ./hyprland/scripts/noctalia-msg.nix { inherit pkgs; };

  # noctalia v5（C++ 版桌面外壳，来自 flake 输入，Cachix 缓存）
  noctaliaPkg = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # 等待 Wayland socket 就绪后再启动 noctalia（参考 hyprland-btw config/noctalia.nix）
  noctaliaLauncher = pkgs.writeShellScript "noctalia-launcher" ''
    set -eu
    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
    display="''${WAYLAND_DISPLAY:-}"
    attempts=0
    if [ -z "$display" ]; then
      while [ "$attempts" -lt 50 ]; do
        for sock in "$runtime_dir"/wayland-*; do
          if [ -S "$sock" ]; then
            display="''${sock##*/}"
            break
          fi
        done
        if [ -n "$display" ]; then
          break
        fi
        attempts=$((attempts + 1))
        ${pkgs.coreutils}/bin/sleep 0.2
      done
    fi
    if [ -z "$display" ]; then
      echo "noctalia-launcher: unable to find WAYLAND_DISPLAY under $runtime_dir" >&2
      exit 1
    fi
    export WAYLAND_DISPLAY="$display"
    exec ${noctaliaPkg}/bin/noctalia
  '';

  # 龙猫云_Lite（ClashMeta 代理客户端，本地 flake lmclient-nix 打包，见 home/packages.nix）
  lmclientPkg = inputs.lmclient.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # 等待 Wayland socket + noctalia 的 SNI 托盘 watcher 就绪后再启动 lmclient。
  # QSystemTrayIcon 在宿主未就绪时注册会静默丢失且不重试（托盘图标消失根因）。
  lmclientLauncher = pkgs.writeShellScript "lmclient-launcher" ''
    set -eu
    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}"
    display="''${WAYLAND_DISPLAY:-}"
    if [ -z "$display" ]; then
      attempts=0
      while [ "$attempts" -lt 50 ]; do
        for sock in "$runtime_dir"/wayland-*; do
          if [ -S "$sock" ]; then
            display="''${sock##*/}"
            break
          fi
        done
        if [ -n "$display" ]; then
          break
        fi
        attempts=$((attempts + 1))
        ${pkgs.coreutils}/bin/sleep 0.2
      done
      if [ -z "$display" ]; then
        echo "lmclient-launcher: unable to find WAYLAND_DISPLAY under $runtime_dir" >&2
        exit 1
      fi
      export WAYLAND_DISPLAY="$display"
    fi
    # 等 noctalia 的 SNI 托盘 watcher 就绪（最多 20s，超时照常启动，不阻塞）
    for i in $(${pkgs.coreutils}/bin/seq 1 100); do
      ${pkgs.systemd}/bin/busctl --user get-property org.kde.StatusNotifierWatcher /StatusNotifierWatcher org.kde.StatusNotifierWatcher IsStatusNotifierHostRegistered >/dev/null 2>&1 && break
      ${pkgs.coreutils}/bin/sleep 0.2
    done
    exec ${lmclientPkg}/bin/lmclient
  '';
in
{
  # ============================================================
  # Hyprland 用户级配置（hyprland-btw 风格）
  # ------------------------------------------------------------
  # 键位/外壳借鉴 hyprland-btw（dwilliam62），其灵感来自 tony,btw；
  # 组件全部 NixOS 声明式：
  #   状态栏/启动器/通知/锁屏/壁纸 → noctalia（v5，官方当前版本）
  #   备用状态栏                 → waybar
  #   启动器（备用）             → rofi（2.x，wayland 原生）
  #   工作区预览                 → quickshell-overview
  #   壁纸守护                   → hyprpaper
  #   剪贴板历史                 → cliphist + wl-clipboard
  #   截图                       → hyprshot（grim/slurp 封装）
  #   取色                       → hyprpicker
  #   输入法                     → fcitx5（保留）
  # ============================================================

  home.packages = with pkgs; [
    # ---- 辅助脚本（hyprland-btw 原版） ----
    rofiLegacyMenu
    configMenu
    keybindsMenu
    hyprlandChangeLayout
    hyprlandCycleWindow
    noctaliaMsg

    # ---- noctalia v5 本体 ----
    noctaliaPkg

    # ---- Hyprland 配套 ----
    hyprpaper          # 壁纸守护（startup.lua 启动）
    hyprshot           # 截图（grim + slurp 封装）
    hypridle           # 空闲管理
    hyprlock           # 锁屏（noctalia 也会调）
    hyprpicker         # 取色器
    libnotify          # notify-send（noctalia/脚本通知）
    xdg-desktop-portal-hyprland
    rofi               # 启动器（wayland 原生，rofi-wayland 已并入）
    waybar             # 备用状态栏
    quickshell         # quickshell-overview 运行时（qs 命令）
    matugen             # Material You 取色（可选）
    nwg-look           # GTK 设置 GUI
    cliphist           # 剪贴板历史
    wl-clipboard       # wl-copy / wl-paste
    grim               # 截屏（hyprshot 后端）
    slurp              # 区域选择（hyprshot 后端）
    swappy             # 截图编辑

    # ---- 常用工具 ----
    playerctl          # 媒体控制（XF86 按键）
    brightnessctl      # 亮度控制（XF86 按键）
    pavucontrol        # 音量 GUI
    networkmanagerapplet # 网络托盘（nm-applet）
    hyprpolkitagent    # polkit 认证代理
  ];

  # ============ GTK / 光标（Dracula 主题，hyprland-btw 风格） ============
  gtk = {
    enable = true;
    theme = {
      name = "Dracula";
      package = pkgs.dracula-theme;
    };
    iconTheme = {
      name = "Dracula";
      package = pkgs.dracula-icon-theme;
    };
    cursorTheme = {
      name = "Bibata-Modern-Ice";
      package = pkgs.bibata-cursors;
      size = 24;
    };
    gtk3.extraConfig = {
      "gtk-application-prefer-dark-theme" = 1;
    };
    gtk4 = {
      theme = config.gtk.theme;
      extraConfig = {
        "gtk-application-prefer-dark-theme" = 1;
      };
    };
  };

  home.pointerCursor = {
    name = "Bibata-Modern-Ice";
    package = pkgs.bibata-cursors;
    size = 24;
  };

  # ============ Hyprland 配置（hyprland.lua + lua/ 模块） ============
  # hyprland 0.55 起支持 Lua 配置（hl.* API），hyprland.lua 为主入口
  home.file.".config/hypr" = {
    source = ./hyprland/hypr;
    recursive = true;
  };

  # ============ Waybar（备用状态栏） ============
  home.file.".config/waybar" = {
    source = ./hyprland/waybar;
    recursive = true;
  };

  # ============ rofi（备用启动器 + 配置菜单） ============
  home.file.".config/rofi/legacy.config.rasi" = {
    source = ./hyprland/rofi/legacy.config.rasi;
  };
  home.file.".config/rofi/legacy-rofi.jpg" = {
    source = ./hyprland/rofi/legacy-rofi.jpg;
  };
  home.file.".config/rofi/config-menu.rasi" = {
    source = ./hyprland/rofi/config-menu.rasi;
  };

  # ============ Noctalia 配置（~/.config/noctalia/config.toml） ============
  home.file.".config/noctalia/config.toml" = {
    source = ./hyprland/noctalia-config.toml;
  };

  # ============ quickshell-overview（工作区预览） ============
  # 复制（非符号链接）到 ~/.config/quickshell/overview，QML 模块解析需要
  home.activation.seedOverviewCode = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -eu
    DEST="$HOME/.config/quickshell/overview"
    SRC="${./hyprland/overview}"

    mkdir -p "$HOME/.config/quickshell"
    rm -rf "$DEST"
    cp -R "$SRC" "$DEST"
    chmod -R u+rwX "$DEST"
  '';

  # ============ 壁纸：seed 到 ~/Pictures/Wallpapers ============
  home.activation.seedWallpapers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -eu
    SRC=${./hyprland/wallpapers}
    DEST="$HOME/Pictures/Wallpapers"
    mkdir -p "$DEST"
    find "$SRC" -maxdepth 1 -type f -print0 | while IFS= read -r -d $'\0' f; do
      bn="$(basename "$f")"
      if [ ! -e "$DEST/$bn" ]; then
        cp "$f" "$DEST/$bn"
      fi
    done
  '';

  # ============ Noctalia systemd 用户服务 ============
  # 等待 Wayland socket 就绪后启动（参考 hyprland-btw config/noctalia.nix）
  systemd.user.services.noctalia = {
    Unit = {
      Description = "Noctalia shell";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${noctaliaLauncher}";
      Restart = "on-failure";
      RestartSec = 2;
      TimeoutStopSec = 10;
      Environment = [
        "XDG_CURRENT_DESKTOP=Hyprland"
        "XDG_SESSION_TYPE=wayland"
      ];
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # ============ 龙猫云_Lite systemd 用户服务 ============
  # lmclient（ClashMeta 代理客户端）由 systemd 托管：
  #   - After noctalia → 托盘宿主先起（launcher 内再轮询 SNI watcher 兜底）
  #   - Restart=on-failure → 崩溃自动拉起
  #   - PartOf graphical-session.target → 随会话停止
  #   - systemd 单实例 → 双实例/锁文件问题从根上杜绝
  systemd.user.services.lmclient = {
    Unit = {
      Description = "Longmao Cloud (lmclient)";
      After = [ "graphical-session.target" "noctalia.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${lmclientLauncher}";
      Restart = "on-failure";
      RestartSec = 2;
      TimeoutStopSec = 15;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # ============ Hyprland systemd 会话目标 ============
  # graphical-session.target 拒绝手动启动（RefuseManualStart=yes），
  # 所以建一个 hyprland-session.target：Wants 依赖方式拉起它（绕开限制），
  # BindsTo 绑定生命周期；停止本 target 时 graphical-session.target 因
  # StopWhenUnneeded=yes 自动停止，noctalia 等随 PartOf 停止。
  # 由 startup.lua 在 hyprland.start / hyprland.shutdown 时启停。
  systemd.user.targets.hyprland-session = {
    Unit = {
      Description = "Hyprland session";
      Documentation = [ "man:systemd.special(7)" ];
      BindsTo = [ "graphical-session.target" ];
      Wants = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
  };

  # ============ 会话变量 ============
  home.sessionVariables = {
    # Electron 应用走 Wayland 原生（obsidian 等）
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    # 编辑器
    EDITOR = "nvim";
    VISUAL = "nvim";
  };
}
