{ config, lib, pkgs, ... }:

{
  # 用户 kun 的 home-manager 配置入口
  home.username = "kun";
  home.homeDirectory = "/home/kun";
  home.stateVersion = "26.05";
  home.file.".npmrc".text = ''
    registry=https://registry.npmmirror.com
  '';

  # 按程序拆分子模块，新用户级配置在这里 import
  imports = [
    ./pi.nix       # pi 插件/扩展/MCP/LSP 配置
    ./packages.nix # 用户级软件包（LSP/MCP 二进制等）
    ./hyprland.nix # Hyprland 桌面 dotfiles + 配套组件
    ./apps.nix     # Alacritty / Helix / Fish / Yazi / uv / Obsidian
    ./agent-skills.nix # agent-skills 技能平台（pi/codex/hermes）
  ];
}
