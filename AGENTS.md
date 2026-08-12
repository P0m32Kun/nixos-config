# 本仓库的硬性约定（所有改动必须遵守）

## 核心原则：一切软件与配置声明式管理，跟随系统一起更新

1. **软件安装只用三种方式，按优先级：**
   - 优先 nixpkgs 现有包（`pkgs.xxx`）
   - 不在 nixpkgs 的 → 在 `overlays/` 里用 `fetchurl` + `stdenv.mkDerivation` /
     `buildNpmPackage` 打包，通过 flake overlay 挂载
   - 用户级工具放 home-manager 的 `home.packages`；系统级放
     `modules/packages.nix`
   - **禁止**：`curl | sh`、`npm i -g`、`pip install`、手动下载二进制到
     `~/bin` 等任何非声明式安装。装新软件一律改配置 + `nixos-rebuild switch`。

2. **配置管理：**
   - 系统级配置 → `modules/` 下的 NixOS 模块
   - 用户级配置（dotfiles、编辑器、pi 等）→ `home/` 下的 home-manager 模块
   - 新增用户级软件/配置：在 `home/default.nix` 的 `imports` 里注册
   - 新增自定义包：在 `overlays/` 建文件，并在 `flake.nix` 的 `overlays` 列表注册

3. **版本锁定与升级：**
   - nixpkgs / nixpkgs-unstable / home-manager 版本锁在 `flake.lock`
   - 升级 = `nix flake update` + `nixos-rebuild switch`，一次完成所有内容更新
   - 升级 pi 本体后，若 pi 反复弹 changelog，更新 `home/pi.nix` 里的
     `piSettings.lastChangelogVersion`

4. **pi 插件生态的具体约定：**
   - pi 插件（npm 包）→ 声明在 `home/pi.nix` 的 `piPackages`，**禁用** `pi install`
   - pi 的 MCP 服务器 / LSP 服务器二进制 → nix 声明（nixpkgs 或 overlay），
     配置文件（`~/.pi/agent/mcp.json`、`pi-lsp.json`）由 home-manager 生成
   - 自写 pi 扩展 → `home/pi-extensions/`（符号链接到 `~/.pi/agent/extensions/`）
   - 密钥类（如 `~/.pi/agent/auth.json`）**不进** nix store，保持命令式管理

## 仓库结构速览

```
flake.nix                     # 输入 + nixosSystem（home-manager、overlays、hermes-agent/p-skills）
overlays/                     # 不在 nixpkgs 的自定义包（每个工具一个文件）
modules/                      # 系统级 NixOS 模块
  desktop/hyprland.nix        # Hyprland 桌面（SDDM/fcitx5/字体，替代原 gnome.nix）
home/
  default.nix                 # 用户级模块入口（imports 注册处）
  pi.nix                      # pi 插件/MCP/LSP 声明 + p-skills 技能 symlink
  packages.nix                # 用户级软件包（含 hermes-agent）
  hyprland.nix                # Hyprland dotfiles（waybar/rofi/awww/hyprlock...）
  apps.nix                    # Alacritty / Helix / Fish / Yazi / uv / Obsidian
  pi-extensions/              # 自写 pi 扩展源码
hosts/<host>/                 # 每台机器的本机配置
```

## 桌面（Hyprland）约定

- 系统级：`modules/desktop/hyprland.nix`（合成器、SDDM、输入法、字体、portal）
- 用户级 dotfiles 一律在 `home/hyprland.nix` 的 `home.file` 里声明，禁止手改 `~/.config`
- 改完配置 = `nix flake lock`（仅当输入变了）+ `sudo nixos-rebuild switch --flake /etc/nixos`
