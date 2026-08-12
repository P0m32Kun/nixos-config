{ config, lib, pkgs, ... }:

# ============================================================
# Hyprland 用户级配置（dotfiles）+ 桌面配套组件
# ------------------------------------------------------------
# 键位借鉴 end-4/dots-hyprland 的常用习惯（Super+Enter 终端、
# Super+D 启动器、Super+E 文件管理器、Super+L 锁屏等），
# 组件全部换成 NixOS 社区热门方案（对应关系见各文件头注释）：
#   Quickshell/AGS 状态栏 → waybar
#   启动器               → rofi（2.x，wayland 原生）
#   壁纸                 → awww（swww 的新名字，26.05 起）
#   锁屏/空闲            → hyprlock + hypridle（Hyprland 官方套件）
#   通知                 → dunst
#   剪贴板历史           → cliphist + wl-clipboard
#   截图                 → grim + slurp + swappy
#   取色                 → hyprpicker
#   认证代理             → hyprpolkitagent（polkit-kde-agent 已随 Plasma5 移除）
# ============================================================
{
  home.packages = with pkgs; [
    # ---- Hyprland 配套 ----
    waybar            # 状态栏
    rofi              # 启动器（wayland 原生，rofi-wayland 已并入）
    awww              # 壁纸守护进程（原 swww）
    hyprlock          # 锁屏
    hypridle          # 空闲管理（自动锁屏/熄屏）
    hyprpicker        # 取色器（复制到剪贴板）
    hyprsunset        # 夜间色温
    dunst             # 通知守护
    cliphist          # 剪贴板历史
    wl-clipboard      # wl-copy / wl-paste
    grim              # 截屏
    slurp             # 区域选择
    swappy            # 截图编辑
    brightnessctl     # 亮度控制（XF86 按键）
    playerctl         # 媒体控制（XF86 按键）
    pavucontrol       # 音量 GUI
    networkmanagerapplet # 网络托盘（nm-applet）
    hyprpolkitagent   # polkit 认证代理（Hyprland 原生）

    # ---- 常用工具 ----
    wlogout           # 电源菜单
  ];

  # ============ GTK / 光标 ============
  gtk = {
    enable = true;
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
    cursorTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      size = 24;
    };
  };

  home.pointerCursor = {
    name = "Adwaita";
    package = pkgs.adwaita-icon-theme;
    size = 24;
  };

  # ============ Hyprland 主配置 ============
  home.file.".config/hypr/hyprland.conf" = {
    text = ''
      # ============================================================
      # Hyprland 配置（0.55.x）— Catppuccin Mocha 风格
      # 键位借鉴 dots-hyprland（end-4）：$mod = SUPER
      # ============================================================

      # ---- 环境变量 ----
      env = XCURSOR_SIZE,24
      env = XCURSOR_THEME,Adwaita
      # 输入法（fcitx5）Wayland 下仍需这些变量
      env = GTK_IM_MODULE,fcitx
      env = QT_IM_MODULE,fcitx
      env = XMODIFIERS,@im=fcitx
      # Electron 应用（obsidian 等）Wayland 原生运行
      env = ELECTRON_OZONE_PLATFORM_HINT,auto

      # ---- 输入 ----
      input {
          kb_layout = us
          follow_mouse = 1
          numlock_by_default = true
          touchpad {
              natural_scroll = true
          }
      }

      # ---- 通用 ----
      general {
          gaps_in = 4
          gaps_out = 8
          border_size = 2
          col.active_border = rgba(89b4faee) rgba(cba6f7ee) 45deg
          col.inactive_border = rgba(313244ee)
          layout = dwindle
      }

      dwindle {
          pseudotile = true
          preserve_split = true
      }

      # ---- 美化 ----
      decoration {
          rounding = 10
          active_opacity = 1.0
          inactive_opacity = 1.0
          blur {
              enabled = true
              size = 6
              passes = 2
              vibrancy = 0.17
          }
          shadow {
              enabled = true
              range = 20
              render_power = 3
              color = rgba(00000055)
          }
      }

      animations {
          enabled = true
          bezier = easeOutCubic, 0.33, 1, 0.68, 1
          animation = windows, 1, 4, easeOutCubic, popin 80%
          animation = windowsOut, 1, 4, easeOutCubic, popin 80%
          animation = fade, 1, 4, easeOutCubic
          animation = workspaces, 1, 4, easeOutCubic, slide
      }

      # ---- 杂项 ----
      misc {
          disable_hyprland_logo = true
          force_default_wallpaper = 0
      }

      # ---- 开机自启 ----
      exec-once = fcitx5 -d --replace
      exec-once = waybar
      exec-once = awww-daemon
      exec-once = awww img ~/.config/awww/wallpaper.png
      exec-once = hypridle
      exec-once = hyprpolkitagent
      exec-once = nm-applet --indicator
      exec-once = wl-paste --type text --watch cliphist store
      exec-once = hyprsunset -t 4500

      # ---- 键位 ----
      $mod = SUPER

      # 应用
      bind = $mod, Return, exec, alacritty        # 终端
      bind = $mod, D, exec, rofi -show drun       # 启动器
      bind = $mod, E, exec, yazi                  # 文件管理器
      bind = $mod, L, exec, hyprlock              # 锁屏

      # 窗口管理
      bind = $mod, Q, killactive
      bind = $mod, F, fullscreen
      bind = $mod, V, togglefloating
      bind = $mod, J, togglesplit
      bind = $mod, P, pseudo
      bind = $mod, left, movefocus, l
      bind = $mod, right, movefocus, r
      bind = $mod, up, movefocus, u
      bind = $mod, down, movefocus, d
      bind = $mod SHIFT, left, movewindow, l
      bind = $mod SHIFT, right, movewindow, r
      bind = $mod SHIFT, up, movewindow, u
      bind = $mod SHIFT, down, movewindow, d
      bindm = $mod, mouse:272, movewindow
      bindm = $mod, mouse:273, resizewindow

      # 工作区
      bind = $mod, 1, workspace, 1
      bind = $mod, 2, workspace, 2
      bind = $mod, 3, workspace, 3
      bind = $mod, 4, workspace, 4
      bind = $mod, 5, workspace, 5
      bind = $mod, 6, workspace, 6
      bind = $mod, 7, workspace, 7
      bind = $mod, 8, workspace, 8
      bind = $mod, 9, workspace, 9
      bind = $mod SHIFT, 1, movetoworkspace, 1
      bind = $mod SHIFT, 2, movetoworkspace, 2
      bind = $mod SHIFT, 3, movetoworkspace, 3
      bind = $mod SHIFT, 4, movetoworkspace, 4
      bind = $mod SHIFT, 5, movetoworkspace, 5
      bind = $mod SHIFT, 6, movetoworkspace, 6
      bind = $mod SHIFT, 7, movetoworkspace, 7
      bind = $mod SHIFT, 8, movetoworkspace, 8
      bind = $mod SHIFT, 9, movetoworkspace, 9
      bind = $mod, mouse_down, workspace, e+1
      bind = $mod, mouse_up, workspace, e-1

      # 截图 / 剪贴板 / 取色
      bind = , Print, exec, grim - | wl-copy                        # 全屏 → 剪贴板
      bind = $mod SHIFT, S, exec, grim -g "$(slurp)" - | wl-copy    # 区域 → 剪贴板
      bind = $mod SHIFT, P, exec, grim -g "$(slurp)" - | swappy -f - # 区域 → 编辑
      bind = $mod, V, exec, cliphist list | rofi -dmenu -display-columns 2 | cliphist decode | wl-copy
      bind = $mod, C, exec, hyprpicker -a                            # 取色 → 剪贴板

      # 音量 / 亮度 / 媒体
      bindel = , XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
      bindel = , XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
      bindl = , XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
      bindl = , XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
      bindel = , XF86MonBrightnessUp, exec, brightnessctl set +5%
      bindel = , XF86MonBrightnessDown, exec, brightnessctl set 5%-
      bindl = , XF86AudioPlay, exec, playerctl play-pause
      bindl = , XF86AudioNext, exec, playerctl next
      bindl = , XF86AudioPrev, exec, playerctl previous

      # 系统
      bind = $mod, R, exec, hyprctl reload
      bind = $mod SHIFT, Q, exit
      bind = $mod, Escape, exec, wlogout

      # ---- 窗口规则 ----
      windowrule = float, class:^(pavucontrol)$
      windowrule = float, title:^(Picture-in-Picture)$
      windowrule = float, class:^(xdg-desktop-portal-gtk)$
      windowrule = center, class:^(pavucontrol)$
      windowrule = size 640 480, class:^(pavucontrol)$
    '';
  };

  # ============ Waybar ============
  home.file.".config/waybar/config" = {
    text = ''
      {
        "layer": "top",
        "position": "top",
        "height": 32,
        "spacing": 6,
        "margin-top": 6,
        "margin-left": 8,
        "margin-right": 8,
        "modules-left": ["hyprland/workspaces", "hyprland/window"],
        "modules-center": [],
        "modules-right": ["pulseaudio", "network", "cpu", "memory", "battery", "clock", "tray"],
        "hyprland/workspaces": {
          "format": "{id}",
          "on-click": "activate",
          "sort-by-number": true
        },
        "hyprland/window": {
          "format": "{}",
          "max-length": 40
        },
        "pulseaudio": {
          "format": "{icon} {volume}%",
          "format-muted": "🔇 {volume}%",
          "format-icons": {
            "default": ["🔈", "🔉", "🔊"]
          },
          "on-click": "pavucontrol"
        },
        "network": {
          "format-wifi": " {signalStrength}%",
          "format-ethernet": "󰈀",
          "format-disconnected": "⚠",
          "on-click": "nm-connection-editor"
        },
        "cpu": {
          "format": "󰻠 {usage}%"
        },
        "memory": {
          "format": "󰍛 {}%"
        },
        "battery": {
          "format": "{icon} {capacity}%",
          "format-icons": ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"],
          "states": {
            "warning": 20,
            "critical": 10
          }
        },
        "clock": {
          "format": " {:%H:%M}",
          "format-alt": "{:%Y-%m-%d %A}"
        },
        "tray": {
          "spacing": 8
        }
      }
    '';
  };

  home.file.".config/waybar/style.css" = {
    text = ''
      /* Catppuccin Mocha */
      * {
        border: none;
        border-radius: 10px;
        font-family: "JetBrainsMono Nerd Font", "Noto Sans CJK SC", sans-serif;
        font-size: 13px;
        min-height: 0;
      }

      window#waybar {
        background: rgba(30, 30, 46, 0.85);
        color: #cdd6f4;
      }

      window#waybar.empty #window {
        background: transparent;
      }

      #workspaces button {
        padding: 0 8px;
        margin: 4px 2px;
        color: #6c7086;
        background: transparent;
      }

      #workspaces button.active {
        color: #1e1e2e;
        background: #89b4fa;
      }

      #workspaces button:hover {
        background: #45475a;
        color: #cdd6f4;
      }

      #window {
        padding: 0 10px;
        color: #a6adc8;
      }

      #cpu, #memory, #network, #pulseaudio, #battery, #clock, #tray {
        padding: 0 10px;
        margin: 4px 2px;
        color: #cdd6f4;
        background: #313244;
      }

      #battery.warning {
        color: #f9e2af;
      }

      #battery.critical {
        color: #f38ba8;
      }

      #clock {
        color: #b4befe;
      }
    '';
  };

  # ============ rofi（启动器） ============
  home.file.".config/rofi/config.rasi" = {
    text = ''
      configuration {
        modi: "drun,run,window";
        show-icons: true;
        icon-theme: "Papirus-Dark";
        display-drun: " 󰀄 Apps  ";
        display-run: " 󰥠 Run  ";
        display-window: " 󰖯 Windows  ";
        drun-display-format: "{icon} {name}";
        location: 0;
        width: 50;
        lines: 12;
        columns: 1;
        padding: 10;
        font: "JetBrainsMono Nerd Font 12";
      }

      @theme "~/.config/rofi/catppuccin-mocha"
    '';
  };

  home.file.".config/rofi/catppuccin-mocha.rasi" = {
    text = ''
      /* Catppuccin Mocha for rofi 2.x */
      * {
        background-color: #1e1e2e;
        background-color-alt: #181825;
        foreground-color: #cdd6f4;
        foreground-color-alt: #a6adc8;
        accent-color: #89b4fa;
        selected-background-color: #313244;
        selected-foreground-color: #89b4fa;
        border-color: #89b4fa;
        highlight-color: #cba6f7;
        active-background-color: #313244;
        active-foreground-color: #a6e3a1;
        urgent-background-color: #313244;
        urgent-foreground-color: #f38ba8;
        separator-color: #45475a;
        border: 0;
        border-radius: 10;
        spacing: 4;
        padding: 6;
        margin: 0;
        text-color: @foreground-color;
        background: @background-color;
        width: 100%;
      }

      window {
        background-color: @background-color;
        border-radius: 10;
        border: 1;
        border-color: @border-color;
        padding: 12;
        width: 50%;
      }

      mainbox {
        background-color: transparent;
      }

      inputbar {
        background-color: @background-color-alt;
        border-radius: 8;
        padding: 8;
        text-color: @foreground-color;
      }

      listview {
        background-color: transparent;
        padding: 4 0 0 0;
        lines: 10;
        columns: 1;
      }

      element {
        background-color: transparent;
        padding: 8;
        border-radius: 6;
        text-color: @foreground-color;
      }

      element selected {
        background-color: @selected-background-color;
        text-color: @selected-foreground-color;
      }

      element-icon {
        size: 1.2em;
        padding: 0 8 0 0;
      }

      message {
        background-color: transparent;
      }
    '';
  };

  # ============ awww 壁纸 ============
  home.file.".config/awww/wallpaper.png" = {
    source = ./hyprland/wallpaper.png;
  };

  # ============ hyprlock（锁屏） ============
  home.file.".config/hypr/hyprlock.conf" = {
    text = ''
      background {
          monitor =
          path = ~/.config/awww/wallpaper.png
          color = rgba(17, 17, 27, 1.0)
          blur_passes = 2
          blur_size = 6
      }

      input-field {
          monitor =
          size = 340, 60
          outline_thickness = 2
          dots_size = 0.25
          dots_spacing = 0.6
          outer_color = rgba(137, 180, 250, 0.8)
          inner_color = rgba(30, 30, 46, 0.8)
          font_color = rgba(205, 214, 244, 1.0)
          fade_on_empty = true
          placeholder_text = <i>Password...</i>
          position = 0, -120
          halign = center
          valign = center
      }

      label {
          monitor =
          text = cmd[update:1000] date +"%H:%M"
          font_size = 90
          color = rgba(205, 214, 244, 1.0)
          position = 0, 90
          halign = center
          valign = center
      }

      label {
          monitor =
          text = cmd[update:1000] date +"%A, %d %B %Y"
          font_size = 20
          color = rgba(186, 194, 222, 1.0)
          position = 0, 30
          halign = center
          valign = center
      }
    '';
  };

  # ============ hypridle（空闲管理） ============
  home.file.".config/hypr/hypridle.conf" = {
    text = ''
      general {
          lock_cmd = pidof hyprlock || hyprlock
          before_sleep_cmd = loginctl lock-session
          after_sleep_cmd = hyprctl dispatch dpms on
      }

      # 5 分钟无操作 → 锁屏
      listener {
          timeout = 300
          on-timeout = loginctl lock-session
      }

      # 5 分半 → 熄屏
      listener {
          timeout = 330
          on-timeout = hyprctl dispatch dpms off
          on-resume = hyprctl dispatch dpms on
      }

      # 30 分钟 → 休眠
      listener {
          timeout = 1800
          on-timeout = systemctl suspend
      }
    '';
  };

  # ============ dunst（通知） ============
  home.file.".config/dunst/dunstrc" = {
    text = ''
      [global]
          monitor = 0
          width = 300
          height = 300
          origin = top-right
          offset = 12x56
          scale = 0
          corner_radius = 8
          font = "Noto Sans CJK SC 10"
          frame_width = 2
          frame_color = "#89b4fa"
          separator_color = frame
          transparency = 10
          padding = 8
          horizontal_padding = 8
          text_icon_padding = 8
          word_wrap = yes
          show_age_threshold = 60
          timeout = 5
          icon_position = left
          max_icon_size = 48

      [urgency_low]
          background = "#313244"
          foreground = "#cdd6f4"
          timeout = 5

      [urgency_normal]
          background = "#313244"
          foreground = "#cdd6f4"
          timeout = 8

      [urgency_critical]
          background = "#1e1e2e"
          foreground = "#f38ba8"
          frame_color = "#f38ba8"
          timeout = 0
    '';
  };

  # ============ wlogout（电源菜单） ============
  home.file.".config/wlogout/style.css" = {
    text = ''
      /* Catppuccin Mocha */
      * {
        font-family: "JetBrainsMono Nerd Font", sans-serif;
        background-image: none;
        box-shadow: none;
      }

      window {
        background-color: rgba(30, 30, 46, 0.8);
        border-radius: 12px;
      }

      button {
        color: #cdd6f4;
        background-color: #313244;
        border: 2px solid #45475a;
        border-radius: 12px;
        margin: 8px;
        padding: 16px;
        min-width: 120px;
        font-size: 16px;
      }

      button:hover {
        background-color: #89b4fa;
        color: #1e1e2e;
        border-color: #89b4fa;
      }
    '';
  };

  # ============ 会话变量 ============
  home.sessionVariables = {
    # Electron 应用走 Wayland 原生（obsidian 等）
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
    # 编辑器
    EDITOR = "hx";
    VISUAL = "hx";
  };
}
