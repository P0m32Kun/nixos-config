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
    # 免密 SSH：Mac (kun@macbook) 的登录公钥
    # 指纹 SHA256:SPX+5lkGOK/j1S7LA1XJ2gFlWJc9b2+Jc/VGV4rfUMk
    # 生成 /etc/ssh/authorized_keys.d/kun（不碰 ~/.ssh/authorized_keys）
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDFduzxGvHUt1GArXDJ2SYLLx9feWlvGzCrb3V7q8xDD kun@macbook->nixos"
    ];
  };
}
