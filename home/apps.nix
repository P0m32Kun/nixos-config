{ config, lib, pkgs, ... }:

# ============================================================
# 用户应用：Alacritty + Helix + Fish + Yazi + uv + Obsidian
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

  # ============ Helix（编辑器） ============
  programs.helix = {
    enable = true;
    settings = {
      theme = "catppuccin_mocha";
      editor = {
        line-number = "relative";
        cursorline = true;
        color-modes = true;
        true-color = true;
        bufferline = "multiple";
        lsp.display-messages = true;
        auto-save = true;
      };
      keys.normal = {
        # 空格 = 前缀，习惯与终端一致
        space.space = "file_picker";
        space.w = "save";
        space.q = "quit";
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
      set -gx EDITOR hx
      set -gx VISUAL hx
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
    functions = {
      fish_prompt = {
        body = ''
          # 精简提示符：用户@主机 路径 分支（git）>
          set -l last_status $status
          set -l cyan (set_color cyan)
          set -l blue (set_color blue)
          set -l green (set_color green)
          set -l red (set_color red)
          set -l normal (set_color normal)

          echo -n -s $blue (prompt_pwd) ' '

          # git 分支
          if git rev-parse --is-inside-work-tree >/dev/null 2>&1
              set -l branch (git branch --show-current 2>/dev/null; or git rev-parse --short HEAD)
              set -l dirty (git status --porcelain 2>/dev/null | wc -l)
              if test $dirty -gt 0
                  echo -n -s $red '±' $branch ' '
              else
                  echo -n -s $green $branch ' '
              end
          end

          if test $last_status -ne 0
              echo -n -s $red '✗ '
          end

          echo -n -s $cyan '❯ ' $normal
        '';
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
