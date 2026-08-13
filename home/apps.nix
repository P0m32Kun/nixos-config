{ config, lib, pkgs, ... }:

# ============================================================
# 用户应用：Alacritty + Starship + Fish + Yazi + uv + Obsidian
# 全部通过 home-manager 模块声明式配置，随系统一起 rebuild
# ============================================================
{
  home.packages = with pkgs; [
    uv          # Python 包/虚拟环境管理器（hermes 的官方运行时）
    obsidian    # 笔记（Electron，Wayland 原生见 hyprland.nix 的 env）
    # 文件浏览辅助
    file
    ripgrep
    fd
    # 提效 CLI 工具
    lazygit    # TUI git 客户端（diff/staging/分支可视化）
    bat        # cat 高亮版（配 fzf 预览）
    eza        # 现代 ls（图标/颜色/树形）
    btop       # 系统监控（CPU/内存/网络/进程）
    duf        # 磁盘用量一览
    ncdu       # 交互式磁盘分析（找大文件）
    tldr       # 命令速查（比 man 简洁）
    # 解压工具族（配合 extract 函数）
    unzip      # zip 解压
    p7zip      # 7z/7za：7z、rar 等多格式
    unrar      # rar 原生解压
    zip        # 创建 zip（与 unzip 配套）
  ];

  # ============ Alacritty（终端） ============
  programs.alacritty = {
    enable = true;
    settings = {
      env = {
        TERM = "xterm-256color";
      };
      window = {
        opacity = 0.95;
        decorations = "Full";
        padding = {
          x = 8;
          y = 8;
        };
      };
      font = {
        normal = {
          family = "JetBrainsMono Nerd Font";
          style = "Regular";
        };
        bold = {
          family = "JetBrainsMono Nerd Font";
          style = "Bold";
        };
        size = 11.0;
      };
      # Catppuccin Mocha
      colors = {
        primary = {
          background = "#1e1e2e";
          foreground = "#cdd6f4";
        };
        normal = {
          black = "#45475a";
          red = "#f38ba8";
          green = "#a6e3a1";
          yellow = "#f9e2af";
          blue = "#89b4fa";
          magenta = "#f5c2e7";
          cyan = "#94e2d5";
          white = "#bac2de";
        };
        bright = {
          black = "#585b70";
          red = "#f38ba8";
          green = "#a6e3a1";
          yellow = "#f9e2af";
          blue = "#89b4fa";
          magenta = "#f5c2e7";
          cyan = "#94e2d5";
          white = "#a6adc8";
        };
      };
    };
  };

  # ============ Fish（shell） ============
  programs.fish = {
    enable = true;
    shellInit = ''
      # 关闭欢迎语
      set -g fish_greeting
      # 编辑器
      set -gx EDITOR nvim
      set -gx VISUAL nvim
    '';
    interactiveShellInit = lib.mkMerge [
      ''
      # 别名
      alias ll 'eza -lah --icons'
      alias la 'eza -A'
      alias l 'eza -F'
      # 一键重建系统（与 rebuild.sh 一致）
      alias rebuild 'sudo nixos-rebuild switch --flake /etc/nixos'
      # 更新 flake 锁 + 重建
      alias update 'nix flake update --flake /etc/nixos && sudo nixos-rebuild switch --flake /etc/nixos'
      # nix 商店 GC
      alias gc 'nix-collect-garbage -d'
      ''
      # atuin 接管 Ctrl-R：fzf 的 fish 集成用 mkOrder 200 绑定，mkAfter 保证 atuin 胜出
      (lib.mkAfter ''
        bind ctrl-r _atuin_search
      '')
    ];

    # ============ extract：一键解压 ============
    # 按扩展名自动选工具；函数文件自动加载，无需 source
    functions.extract.body = ''
      if test (count $argv) -lt 1
        echo "用法: extract <压缩包> [-d 目标目录]"
        return 1
      end
      set -l file $argv[1]
      set -l outdir ""
      if test (count $argv) -ge 3; and test "$argv[2]" = "-d"
        set outdir $argv[3]
      end
      if not test -f "$file"
        echo "extract: 文件不存在: $file"
        return 1
      end
      # 目标目录参数：tar 用 -C / unzip 用 -d / 7z 用 -o（无空格，目录须已存在）
      set -l targ
      set -l uarg
      set -l zarg
      if test -n "$outdir"
        mkdir -p "$outdir"
        set targ -C "$outdir"
        set uarg -d "$outdir"
        set zarg -o"$outdir"
      end
      switch $file
        case '*.tar.gz' '*.tgz'
          tar -xzf $targ "$file"
        case '*.tar.xz' '*.txz'
          tar -xJf $targ "$file"
        case '*.tar.zst' '*.tzst'
          tar --zstd -xf $targ "$file"
        case '*.tar.bz2' '*.tbz2' '*.tbz'
          tar -xjf $targ "$file"
        case '*.tar'
          tar -xf $targ "$file"
        case '*.zip'
          # Windows 工具打的流式/GBK 包 unzip 可能误报 zip bomb，失败自动回退 7z
          # -o：覆盖已有文件不询问，避免交互/非交互下返回非零误触发回退
          if not unzip -o $uarg "$file"
            echo "extract: unzip 失败，自动回退 7z…"
            7z x -y $zarg "$file"
          end
        case '*.7z'
          7z x -y $zarg "$file"
        case '*.rar'
          if test -n "$outdir"
            unrar x "$file" "$outdir"/
          else
            unrar x "$file"
          end
        case '*.gz'
          gunzip "$file"
        case '*.xz'
          unxz "$file"
        case '*.bz2'
          bunzip2 "$file"
        case '*.zst'
          unzstd "$file"
        case '*'
          echo "extract: 不支持的格式: $file"
          return 1
      end
    '';
  };

  # ============ 提效 CLI 工具 ============
  # zoxide：智能 cd，z 跳转历史目录（yazi 内置 z 键也依赖它）
  programs.zoxide.enable = true;
  # fzf：模糊搜索，Ctrl-T 插入文件路径 / Alt-C 跳转目录
  programs.fzf.enable = true;
  # atuin：历史搜索，Ctrl-R 接管（比 fzf 的历史搜索更强）
  programs.atuin.enable = true;

  # ============ Starship（提示符） ============
  # 取代原 fish_prompt；fish 集成由 home-manager 自动注入 `starship init fish`
  programs.starship = {
    enable = true;
    settings = {
      palette = "catppuccin_mocha";

      palettes.catppuccin_mocha = {
        rosewater = "#f5e0dc";
        flamingo = "#f2cdcd";
        pink = "#f5c2e7";
        mauve = "#cba6f7";
        red = "#f38ba8";
        maroon = "#eba0ac";
        peach = "#fab387";
        yellow = "#f9e2af";
        green = "#a6e3a1";
        teal = "#94e2d5";
        sky = "#89dceb";
        sapphire = "#74c7ec";
        blue = "#89b4fa";
        lavender = "#b4befe";
        text = "#cdd6f4";
        subtext1 = "#bac2de";
        subtext0 = "#a6adc8";
        overlay2 = "#9399b2";
        overlay1 = "#7f849c";
        overlay0 = "#6c7086";
        surface2 = "#585b70";
        surface1 = "#45475a";
        surface0 = "#313244";
        base = "#1e1e2e";
        mantle = "#181825";
        crust = "#11111b";
      };

      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
      };

      directory = {
        style = "blue";
      };

      git_branch = {
        style = "green";
      };

      git_status = {
        style = "red";
      };

      cmd_duration = {
        style = "yellow";
      };

      python = {
        style = "peach";
      };

      nodejs = {
        style = "green";
      };

      rust = {
        style = "maroon";
      };
    };
  };

  # ============ Yazi（文件管理器） ============
  programs.yazi = {
    enable = true;
    # 默认配置即可用；打开文件用 xdg-open（桌面环境）
    settings = {
      manager = {
        sort_by = "natural";
        show_hidden = true;
      };
    };
  };

  # ============ udiskie（U 盘自动挂载） ============
  # 插入 U 盘自动挂载到 /run/media/kun/，弹出时自动卸载
  services.udiskie = {
    enable = true;
    settings = {
      notify = true;   # 插入/挂载/弹出时桌面通知
      automount = {
        options = [ "nosuid" "noexec" "nodev" ];
      };
    };
  };

  # ============ uv（Python 工具链） ============
  # uv 自管理 Python 版本（~/.local/share/uv），无需 nix 装 python
  home.sessionVariables = {
    # uv 安装的工具（如 `uv tool install`）进 PATH
    UV_TOOL_BIN_DIR = "$HOME/.local/bin";
  };
}
