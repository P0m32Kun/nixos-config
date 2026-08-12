{ config, lib, pkgs, ... }:

# ============================================================
# Hyprland 桌面（hyprland-btw 风格）
# ------------------------------------------------------------
# 说明：
#   - 键位/外壳借鉴 hyprland-btw（dwilliam62），其灵感来自 tony,btw；
#     用户级配置在 home/hyprland.nix（hyprland.lua + noctalia + waybar）。
#   - 输入法 fcitx5（原 gnome.nix 中配置）原样保留，桌面无关。
# ============================================================
{
  # ============ X11 基础（SDDM 与 XWayland 需要） ============
  services.xserver.enable = true;
  services.xserver.xkb = {
    # 基础布局用 us，中文输入完全交给 fcitx5
    layout = "us";
    variant = "";
  };

  # ============ 显示管理器：SDDM + Catppuccin 主题 ============
  # （GNOME 的 GDM 已移除；SDDM 是 Hyprland 用户的主流选择）
  services.displayManager.sddm.enable = true;
  services.displayManager.sddm.theme = "catppuccin-mocha-mauve";
  services.displayManager.defaultSession = "hyprland";

  # ============ Hyprland 合成器 ============
  # nixpkgs 自带模块：自动配置 xdg-desktop-portal-hyprland、
  # XWayland、systemd 集成等；0.55.x 与 flake.lock 一起锁定
  programs.hyprland.enable = true;

  # ============ 图形驱动（Intel iGPU → mesa） ============
  hardware.graphics.enable = true;

  # ============ 输入法：fcitx5 + 雾凇拼音（Rime） ============
  # （从原 gnome.nix 迁移；env 变量在 home/hyprland.nix 的 hypr/env.lua 里设）
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = [
      # 备用拼音引擎 / emoji 等（26.05 起在 qt6Packages 作用域）
      pkgs.qt6Packages.fcitx5-chinese-addons
      (pkgs.fcitx5-rime.override {
        # 在默认 rime-data 之上叠加雾凇拼音（rime-ice）词典
        rimeDataPkgs = with pkgs; [ rime-data rime-ice ];
      })
      # Catppuccin 主题（含 Mocha 全 14 种 accent，见 ~/.config/fcitx5/conf/classicui.conf）
      pkgs.catppuccin-fcitx5
    ];
  };

  # ============ Wayland portals（屏幕共享等） ============
  xdg.portal = {
    enable = true;
    config.common.default = [ "hyprland" "gtk" ];
  };

  # ============ 认证（hyprpolkitagent 需要） / dconf ============
  security.polkit.enable = true;
  programs.dconf.enable = true;

  # ============ 浏览器 ============
  programs.firefox.enable = true;

  # ============ 字体（GNOME 移除后需要显式声明） ============
  fonts = {
    packages = with pkgs; [
      # 基础 + 中文（CJK）
      noto-fonts
      noto-fonts-cjk-sans
      # 图标字体：Waybar / rofi 图标
      nerd-fonts.symbols-only
      # 等宽 + 图标：Alacritty / Helix 主字体
      nerd-fonts.jetbrains-mono
      # Maple Mono NF-CN：等宽 + Nerd Font 图标 + 简体中文（v7.9）
      # 变体：maple-mono.NF（仅图标）/ maple-mono.CN（仅中文）/ "NF-CN"（两者）
      maple-mono."NF-CN"
      # 图标字体：font-awesome（waybar/rofi 图标）
      font-awesome
      # DejaVu（noctalia 默认字体回退）
      dejavu_fonts
    ];
    # Maple Mono NF CN 设为系统默认字体（sans-serif + monospace；
    # serif 保持默认——Maple 是无衬线等宽字体，不适合衬线场景）
    fontconfig = {
      defaultFonts = {
        sansSerif = [ "Maple Mono NF CN" ];
        monospace = [ "Maple Mono NF CN" ];
      };
    };
  };

  # ============ 系统包 ============
  environment.systemPackages = with pkgs; [
    # 光标 + 图标主题（Wayland 下 GTK 应用需要）
    adwaita-icon-theme
    papirus-icon-theme
    # 鼠标光标（hyprland-btw 用 Bibata）
    bibata-cursors
  ];

  # ============ Qt6 环境（quickshell / noctalia 需要） ============
  environment.sessionVariables = {
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
  };

  # ============ Noctalia 推荐服务（官方文档） ============
  # 让 Noctalia 的 wifi/蓝牙/电源/电池功能可用
  services.upower.enable = true;
  # power-profiles-daemon 提供 org.freedesktop.UPower.PowerProfiles 接口，
  # noctalia v5 的电源配置（省电/均衡/性能）依赖它（官方 recommendedServices 含此项）
  services.power-profiles-daemon.enable = true;
  hardware.bluetooth.enable = true;
}
