{pkgs}:
pkgs.writeShellScriptBin "config-menu" ''
  #!/usr/bin/env bash
  set -euo pipefail

  EDITOR_BIN="''${EDITOR:-hx}"
  TERM_BIN="''${TERMINAL:-}"

  pick_term() {
    if [ -n "''${TERM_BIN}" ] && command -v "''$TERM_BIN" >/dev/null 2>&1; then
      echo "''$TERM_BIN"
      return
    fi
    for t in alacritty kitty foot wezterm ghostty; do
      if command -v "''$t" >/dev/null 2>&1; then
        echo "''$t"
        return
      fi
    done
  }

  # Find repo directory (本仓库位于 /etc/nixos）
  repo=""
  for candidate in "/etc/nixos" "''$HOME/nixos-config"; do
    if [ -d "''$candidate" ] && [ -f "''$candidate/flake.nix" ]; then
      repo="''$candidate"
      break
    fi
  done
  if [ -z "''$repo" ]; then
    echo "Error: nixos-config repo not found" >&2
    exit 1
  fi

  # Create temp file for name->path mapping
  tmpmap=$(mktemp)
  trap "rm -f $tmpmap" EXIT

  # All config files with their display names
  files_data=(
    "flake.nix:''$repo/flake.nix"
    "home/default.nix:''$repo/home/default.nix"
    "home/hyprland.nix:''$repo/home/hyprland.nix"
    "home/hyprland/hypr/hyprland.lua:''$repo/home/hyprland/hypr/hyprland.lua"
    "home/hyprland/hypr/lua/keybinds.lua:''$repo/home/hyprland/hypr/lua/keybinds.lua"
    "home/hyprland/hypr/lua/env.lua:''$repo/home/hyprland/hypr/lua/env.lua"
    "home/hyprland/hypr/lua/startup.lua:''$repo/home/hyprland/hypr/lua/startup.lua"
    "home/hyprland/hypr/lua/window_rules.lua:''$repo/home/hyprland/hypr/lua/window_rules.lua"
    "home/hyprland/hypr/lua/decorations.lua:''$repo/home/hyprland/hypr/lua/decorations.lua"
    "home/hyprland/hypr/lua/animations.lua:''$repo/home/hyprland/hypr/lua/animations.lua"
    "home/hyprland/hypr/lua/settings.lua:''$repo/home/hyprland/hypr/lua/settings.lua"
    "home/hyprland/waybar/config.jsonc:''$repo/home/hyprland/waybar/config.jsonc"
    "home/hyprland/waybar/style.css:''$repo/home/hyprland/waybar/style.css"
    "home/hyprland/noctalia-config.toml:''$repo/home/hyprland/noctalia-config.toml"
    "modules/desktop/hyprland.nix:''$repo/modules/desktop/hyprland.nix"
    "hosts/nixos/default.nix:''$repo/hosts/nixos/default.nix"
  )

  # Build display list and mapping, only for existing files
  for entry in "''${files_data[@]}"; do
    display=$(echo "''$entry" | cut -d: -f1)
    path=$(echo "''$entry" | cut -d: -f2-)
    if [ -f "''$path" ]; then
      echo "''$display|''$path" >> "''$tmpmap"
    fi
  done

  # Show rofi menu with sorted display names only
  choice=$(cut -d'|' -f1 "''$tmpmap" | sort | rofi -dmenu -i -config "''$HOME/.config/rofi/config-menu.rasi" -p ' Edit Config')
  [ -z "''$choice" ] && exit 0

  # Look up path from mapping
  target=$(grep "^''$choice|" "''$tmpmap" | cut -d'|' -f2)
  [ -z "''$target" ] && exit 1

  term="$(pick_term)"
  if [ -n "''$term" ] && [[ "''$EDITOR_BIN" =~ ^(nvim|vim|vi|nano|helix|hx)$ ]]; then
    exec "''$term" -e "''$EDITOR_BIN" "''$target"
  else
    exec "''$EDITOR_BIN" "''$target"
  fi
''
