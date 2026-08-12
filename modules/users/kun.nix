{ config, lib, pkgs, ... }:

{
  # ============ 用户 kun ============
  # 注意：密码用 `passwd kun` 设置，不保存在配置里

  # 系统级 fish：把 /etc/fish 与基础 nix PATH 配好（shell=fish 的前提）
  programs.fish.enable = true;

  users.users."kun" = {
    isNormalUser = true;
    description = "kun";
    # libvirtd：使用 virt-manager 管理 KVM 虚拟机；podman：连接 /run/podman/podman.sock
    # video: 亮度控制（brightnessctl 读 /sys/class/backlight）
    # audio/input: 传统设备组，Wayland 桌面常用
    extraGroups = [ "networkmanager" "wheel" "libvirtd" "podman" "video" "audio" "input" ];
    # 默认 shell：fish（配置见 home/apps.nix 的 programs.fish）
    shell = pkgs.fish;
    packages = with pkgs; [
      # 用户级软件包放这里（也可留空，用 home-manager 更彻底）
    ];
  };
}
