{ config, lib, pkgs, ... }:

{
  # ============ 时区 ============
  time.timeZone = "Asia/Shanghai";

  # ============ 国际化（中文） ============
  i18n.defaultLocale = "zh_CN.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "zh_CN.UTF-8";
    LC_IDENTIFICATION = "zh_CN.UTF-8";
    LC_MEASUREMENT = "zh_CN.UTF-8";
    LC_MONETARY = "zh_CN.UTF-8";
    LC_NAME = "zh_CN.UTF-8";
    LC_NUMERIC = "zh_CN.UTF-8";
    LC_PAPER = "zh_CN.UTF-8";
    LC_TELEPHONE = "zh_CN.UTF-8";
    LC_TIME = "zh_CN.UTF-8";
  };

  # ============ 网络 ============
  networking.networkmanager.enable = true;

  # ============ SSH 服务 ============
  services.openssh.enable = true;

  # ============ 打印 ============
  services.printing.enable = true;
}
