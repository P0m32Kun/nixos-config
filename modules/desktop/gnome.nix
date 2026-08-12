{ config, lib, pkgs, ... }:

{
  # ============ X11 ============
  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "cn";
    variant = "";
  };

  # ============ GNOME 桌面 ============
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # ============ 浏览器 ============
  programs.firefox.enable = true;
}
