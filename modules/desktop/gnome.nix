{ config, lib, pkgs, ... }:

{
  # ============ X11 ============
  services.xserver.enable = true;
  services.xserver.xkb = {
    # 基础布局用 us，中文输入完全交给 fcitx5
    layout = "us";
    variant = "";
  };

  # ============ GNOME 桌面 ============
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # ============ 输入法：fcitx5 + 雾凇拼音（Rime） ============
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

  # ============ 浏览器 ============
  programs.firefox.enable = true;
}
