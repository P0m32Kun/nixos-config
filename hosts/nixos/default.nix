{ config, lib, pkgs, ... }:

{
  imports = [
    # 本机硬件配置（由 nixos-generate-config 生成，勿手改）
    ./hardware-configuration.nix

    # 共享模块（多台机器时全部复用）
    ../../modules/base.nix          # 时区 / 语言 / 网络 / SSH / 打印
    ../../modules/mirrors.nix       # 国内镜像
    ../../modules/packages.nix      # 软件包
    ../../modules/desktop/gnome.nix # 桌面环境
    ../../modules/desktop/audio.nix # 声音
    ../../modules/users/kun.nix     # 用户

    # 新机器迁移时：删掉上面"本机特有配置"下不需要的部分即可
  ];

  # ============ 本机特有配置 ============
  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # 使用最新内核
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # 主机名
  networking.hostName = "nixos";

  # 系统状态版本：从哪个 NixOS 版本开始保持默认状态设置
  # 不要随意改动（只在跨大版本升级时按官方指引修改）
  system.stateVersion = "26.05";
}
