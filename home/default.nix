{
  config,
  lib,
  pkgs,
  ...
}:

{
  # 用户 kun 的 home-manager 配置入口
  home.username = "kun";
  home.homeDirectory = "/home/kun";
  home.stateVersion = "26.05";
  home.file.".npmrc".text = ''
    registry=https://registry.npmmirror.com
    prefix=${config.home.homeDirectory}/.local
  '';
  # npm -g 装到 ~/.local（pi/context-mode 等自管工具落点）、pdtm/go install 落点，并进 PATH
  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.pdtm/go/bin"
    "$HOME/go/bin"
  ];

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

  # ============ 默认打开方式（mimeapps.list） ============
  # 目录交给 thunar；zcode 的 deep-link 必须一起声明——该文件原先由 zcode
  # 命令式写入（只有 x-scheme-handler/zcode 一行），纳入 nix 后由 HM 接管，
  # 漏声明就会静默丢失。
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "inode/directory" = "thunar.desktop";
      "x-scheme-handler/zcode" = "zcode.desktop";
    };
  };
  # 原文件是普通文件（非符号链接），HM 默认拒绝覆盖，需 force（同 user-dirs.dirs）
  xdg.configFile."mimeapps.list".force = true;
  # 按程序拆分子模块，新用户级配置在这里 import
  imports = [
    ./packages.nix # 用户级软件包（LSP/MCP 二进制等）
    ./hyprland.nix # Hyprland 桌面 dotfiles + 配套组件
    ./apps.nix # Alacritty / Helix / Fish / Yazi / uv / Obsidian
    ./wl-harness.nix # wl-harness 共享 agent 层（skills + codegraph MCP，见 decisions/0004）
    ./agent-usage.nix # agent 用量监测：采集 + 定时器 + agent-usage 报告命令
    ./sysops.nix # 系统运维助手：体检采集 + noctalia 对话入口 + 审批执行流（见 decisions/0007）
    ./noctalia-plugins.nix # noctalia 本地插件启用重申（换机可复现，幂等）
  ];
}
