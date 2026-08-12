{ config, lib, pkgs, ... }:

# ============================================================
# Hyprland 桌面（替换原 GNOME 模块）
# ------------------------------------------------------------
# 说明：
#   - dots-hyprland（end-4）是 Arch 导向的（curl 安装脚本 + AUR 依赖 +
#     Quickshell/AGS 组件），不适用 NixOS；这里用 NixOS 标准方案：
#     nixpkgs 的 programs.hyprland（TUNA 有二进制缓存），组件换成
#     NixOS 社区热门通用组件（waybar / rofi / awww / hyprlock ...），
#     用户级配置在 home/hyprland.nix。
#   - 输入法 fcitx5（原 gnome.nix 中配置）原样迁移到这里，桌面无关。
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
  # （从原 gnome.nix 迁移；env 变量在 home/hyprland.nix 的 hyprland.conf 里设）
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
  environment.systemPackages = with pkgs; [
    # 基础 + 中文（CJK）
    noto-fonts
    noto-fonts-cjk-sans
    # 图标字体：Waybar / rofi 图标
    nerd-fonts.symbols-only
    # 等宽 + 图标：Alacritty / Helix 主字体
    nerd-fonts.jetbrains-mono
    # 光标 + 图标主题（Wayland 下 GTK 应用需要；adwaita 有缓存，
    # catppuccin-cursors 需用 inkscape 构建全部 64 变体，暂不用）
    adwaita-icon-theme
    papirus-icon-theme
  ];
}
