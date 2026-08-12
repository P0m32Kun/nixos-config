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
    interactiveShellInit = ''
      # 别名
      alias ll 'ls -lah'
      alias la 'ls -A'
      alias l 'ls -F'
      # 一键重建系统（与 rebuild.sh 一致）
      alias rebuild 'sudo nixos-rebuild switch --flake /etc/nixos'
      # 更新 flake 锁 + 重建
      alias update 'nix flake update --flake /etc/nixos && sudo nixos-rebuild switch --flake /etc/nixos'
      # nix 商店 GC
      alias gc 'nix-collect-garbage -d'
    '';
  };

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

  # ============ uv（Python 工具链） ============
  # uv 自管理 Python 版本（~/.local/share/uv），无需 nix 装 python
  home.sessionVariables = {
    # uv 安装的工具（如 `uv tool install`）进 PATH
    UV_TOOL_BIN_DIR = "$HOME/.local/bin";
  };
}
