# 本仓库的硬性约定（所有改动必须遵守）

## 核心原则：软件分快慢两层管理（见 docs/decisions/0001 + 0005）

1. **慢层 = nix 声明式**（版本锁定、跟随系统更新、可整机回滚）：
   - 优先 nixpkgs 现有包（`pkgs.xxx`）；不在 nixpkgs 的 → `overlays/` 打包
     （`fetchurl` + `mkDerivation` / `appimageTools`），并在 `flake.nix` 的
     overlays 列表注册
   - 用户级工具放 home-manager 的 `home.packages`；系统级放 `modules/packages.nix`
   - 适用：桌面 GUI（zcode / orca-ide / grok-bot / wechat / wemeet / wps）、
     系统依赖、LSP / MCP 二进制、稳定 CLI
2. **快层 = `~/.local` 自管**（自带更新机制、原生渠道发布、nix 锁定只会
   拖慢或废掉它）：
   - 判定线：「有原生更新命令，且不需要 patchelf / FHS 补丁」→ 快层
   - 现有：pi 全家桶（`npm -g`，`pi update self`）、hermes-agent
     （`uv tool install` / `uv tool upgrade hermes-agent`）、agy、
     context-mode / rtk
   - npm 全局 prefix 已设 `~/.local`（`home/default.nix` 的 `.npmrc`），
     `~/.local/bin` 已进 PATH
3. **禁止**：给慢层工具用 `curl | sh` / 手动下载二进制冒充声明式；给快层
   工具强行打包进 nix；手改 `~/.config` 里由 home-manager 接管的文件。
   新增 AI CLI 先过快慢判定线（0005 的 Consequences 有示例）。

## 配置管理

- 系统级配置 → `modules/` 下的 NixOS 模块；用户级（dotfiles、编辑器）→
  `home/` 下的 home-manager 模块
- 新增用户级软件/配置：在 `home/default.nix` 的 `imports` 里注册
- 密钥类（`~/.pi/agent/auth.json`、`~/.hermes/`、tailscale 认证）**不进**
  nix store，保持命令式管理

## 版本锁定与升级

- flake 输入：nixpkgs（GitHub **git 协议** shallow，锁真实 commit，见 0005；
  勿用 `github:` 简写——REST API 限额会 403）、home-manager、noctalia
  （官方 cachix 分支，**勿加** nixpkgs.follows）、lmclient（本地 path）、
  wl-harness（本地 git+file）
- 升级 = `nix flake update` + `sudo nixos-rebuild switch --flake /etc/nixos`；
  三个远端输入由 CI 每周自动刷新并开 PR
- wl-harness 更新：`git -C ~/Projects/wl-harness pull && nix flake update wl-harness`
- 改完配置先跑 `./scripts/check.sh`（nixfmt + dry 构建冒烟）再 switch

## 仓库结构速览

```
flake.nix                     # 输入 + nixosSystem（home-manager、overlays）
overlays/                     # 不在 nixpkgs 的自定义包（codegraph/herdr/wechat/zcode/orca/grok-bot）
scripts/update.sh             # 慢层 overlay 包升级（orca/zcode/grok-bot）
scripts/check.sh              # nixfmt + dry 构建冒烟
modules/                      # 系统级 NixOS 模块
  desktop/hyprland.nix        #   Hyprland 桌面（SDDM/fcitx5/字体/portal）
  mirrors.nix                 #   TUNA substituters + nix-daemon 代理 env
home/
  default.nix                 # 用户级模块入口（imports 注册处）
  packages.nix                # 用户级软件包（LSP/MCP/GUI/工具链）
  hyprland.nix                # Hyprland dotfiles + noctalia/lmclient 服务
  apps.nix                    # Alacritty / Helix / Fish / Yazi / uv / Obsidian
  wl-harness.nix              # wl-harness 共享 agent 层（skills + MCP 合并，见 0004）
  agent-usage.nix             # agent token 用量监测（采集 + timer + agent-usage 命令）
hosts/nixos/                  # 本机配置（单机）
docs/decisions/               # ADR（0001-0005）
```

## 桌面（Hyprland）约定

- 系统级：`modules/desktop/hyprland.nix`（合成器、SDDM、输入法、字体、portal）
- 用户级 dotfiles 一律在 `home/hyprland.nix` 的 `home.file` 里声明，禁止手改 `~/.config`
- Hyprland 0.55 走 **Lua 配置**（`home/hyprland/hypr/`，hyprland.lua 加载
  lua/ 下模块）；`hyprctl dispatch` 需要 Lua dispatcher 表达式
  （`hl.dsp.xxx`），不是旧的字符串 dispatcher
- 改完配置 = `nix flake lock`（仅当输入变了）+ `sudo nixos-rebuild switch --flake /etc/nixos`

## 换机/重装清单（flake 本地输入与快层依赖）

1. clone 本仓库到 `/etc/nixos`（GitHub: P0m32Kun/nixos-config）
2. `~/Projects/wl-harness`：私有仓库 git clone（flake 输入 wl-harness 依赖）
3. `~/Projects/lmclient-nix`：本地 flake（flake 输入 lmclient 依赖，含 AppImage 源）
4. 快层重装：`npm i -g` pi 全家桶、`uv tool install hermes-agent`、agy 官方脚本
5. 密钥恢复：`~/.pi/agent/auth.json`、`~/.hermes/`、SSH keys、tailscale 认证
