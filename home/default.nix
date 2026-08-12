{ config, lib, pkgs, ... }:

{
  # 用户 kun 的 home-manager 配置入口
  home.username = "kun";
  home.homeDirectory = "/home/kun";
  home.stateVersion = "26.05";
  home.file.".npmrc".text = ''
    registry=https://registry.npmmirror.com
  '';

  # XDG 用户目录统一英文名（原为中文，避免工具/编码兼容问题）
  xdg.userDirs = {
    enable = true;
    desktop = "$HOME/Desktop";
    download = "$HOME/Downloads";
    templates = "$HOME/Templates";
    publicShare = "$HOME/Public";
    documents = "$HOME/Documents";
    music = "$HOME/Music";
    pictures = "$HOME/Pictures";
    videos = "$HOME/Videos";
    # 项目目录：Projects（26.05 起有独立的 projects 选项，勿用 extraConfig——
    # extraConfig 的 key 会被再包一层 XDG_${k}_DIR，写成 XDG_PROJECTS_DIR
    # 会生成错误的 XDG_XDG_PROJECTS_DIR_DIR）
    projects = "$HOME/Projects";
    # 激活时自动创建英文目录（原 GNOME 中文目录均为空，已改名为英文）
    createDirectories = true;
  };
  # 强制接管旧文件：GNOME 生成的 ~/.config/user-dirs.dirs 是普通文件，
  # home-manager 默认拒绝覆盖非符号链接文件，需 force 换成符号链接
  xdg.configFile."user-dirs.dirs".force = true;
  # 按程序拆分子模块，新用户级配置在这里 import
  imports = [
    ./pi.nix       # pi 插件/扩展/MCP/LSP 配置
    ./packages.nix # 用户级软件包（LSP/MCP 二进制等）
    ./hyprland.nix # Hyprland 桌面 dotfiles + 配套组件
    ./apps.nix     # Alacritty / Helix / Fish / Yazi / uv / Obsidian
    ./agent-skills.nix # agent-skills 技能平台（pi/codex/hermes）
  ];
}
