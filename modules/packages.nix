{ config, lib, pkgs, ... }:

{
  # ============ 允许非自由软件 ============
  nixpkgs.config.allowUnfree = true;

  # ============ 系统级软件包 ============
  # 添加新软件：把包名加进列表，然后执行
  #   sudo nixos-rebuild switch --flake /etc/nixos
  environment.systemPackages = with pkgs; [
    git # 版本管理（GitHub 管理配置必需）
    neovim # 编辑器
    wget
    curl
    pi-coding-agent
    codex
  ];
}
