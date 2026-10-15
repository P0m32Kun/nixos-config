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
   - 判定线：「有原生更新命令，且不需要 patchelf / FHS 补丁」→ 快层；
     **选渠道先验明官方当前活跃的分发方式**（hermes 的 PyPI 渠道
     停更就是教训，见 0005）
   - 现有：pi 全家桶（`npm -g`，`pi update self`）、hermes-agent
     （官方 `install.sh`，git 快照落 `~/.hermes/hermes-agent`）、agy、
     context-mode / rtk、herdr（官方 installer `herdr.dev/install` 落
     `~/.local/bin`，升级 `herdr update`，见 0006）
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
- **配置迁移边界（见 decisions/0008）**：nixos-config 管系统；wl-harness 管
  快层与 agent/AI 工具的 baseline 配置（add-only seed + 自检清单 + 
  `agent-check.sh`）。工具本体下载可脚本化，配置必须可迁移；凭据永不入库。

## 版本锁定与升级

- flake 输入：nixpkgs（GitHub **git 协议** shallow，锁真实 commit，见 0005；
  勿用 `github:` 简写——REST API 限额会 403）、home-manager、noctalia
  （官方 cachix 分支，**勿加** nixpkgs.follows）、
  wl-harness（本地 git+file）。lmclient（龙猫云_Lite）是**临时代理客户端，
  已不进 flake**，装到 PATH / `~/.local/bin` 即可
- 升级 = `nix flake update` + `sudo nixos-rebuild switch --flake /etc/nixos`；
  三个远端输入由 CI 每周自动刷新并开 PR
- wl-harness 更新：`git -C ~/Projects/wl-harness pull && nix flake update wl-harness`
- 改完配置先跑 `./scripts/check.sh`（nixfmt + dry 构建冒烟）再 switch

## 仓库结构速览

```
flake.nix                     # 输入 + nixosSystem（home-manager、overlays）
overlays/                     # 不在 nixpkgs 的自定义包（codegraph/wechat/zcode/orca/grok-bot）
scripts/update.sh             # 慢层 overlay 包升级（orca/zcode/grok-bot）
scripts/check.sh              # nixfmt + dry 构建冒烟
scripts/install-from-clone.sh # 换机一键引导（校验前置 + check.sh + rebuild）
modules/                      # 系统级 NixOS 模块
  desktop/hyprland.nix        #   Hyprland 桌面（SDDM/fcitx5/字体/portal）
  mirrors.nix                 #   TUNA substituters + nix-daemon 代理 env
home/
  default.nix                 # 用户级模块入口（imports 注册处）
  packages.nix                # 用户级软件包（LSP/MCP/GUI/工具链）
  hyprland.nix                # Hyprland dotfiles + noctalia 服务 + lmclient launcher（可选）
  apps.nix                    # Alacritty / Helix / Fish / Yazi / uv / Obsidian
  wl-harness.nix              # wl-harness 共享 agent 层（skills + MCP 合并，见 0004）
  agent-usage.nix             # agent token 用量监测（采集 + timer + agent-usage 命令）
  noctalia-plugins.nix        # noctalia 插件启用重申（换机可复现，幂等）
hosts/nixos/                  # 本机配置（单机）
docs/decisions/               # ADR（0001-0008）
```

## 桌面（Hyprland）约定

- 系统级：`modules/desktop/hyprland.nix`（合成器、SDDM、输入法、字体、portal）
- 用户级 dotfiles 一律在 `home/hyprland.nix` 的 `home.file` 里声明，禁止手改 `~/.config`
- Hyprland 0.55 走 **Lua 配置**（`home/hyprland/hypr/`，hyprland.lua 加载
  lua/ 下模块）；`hyprctl dispatch` 需要 Lua dispatcher 表达式
  （`hl.dsp.xxx`），不是旧的字符串 dispatcher
- 改完配置 = `nix flake lock`（仅当输入变了）+ `sudo nixos-rebuild switch --flake /etc/nixos`

## 换机/重装清单（flake 本地输入与快层依赖）

> **一键引导**：`./scripts/install-from-clone.sh`（幂等）自动做下面 1–5 步的
> 校验、建符号链接、`check.sh` 与 rebuild；前置不满足会阻塞并说清缺什么。
> 下面分条仍是权威清单（脚本不代办凭据与快层安装）。

1. clone 本仓库（GitHub: P0m32Kun/nixos-config，如 `~/nixos-config`），并建
   符号链接 `sudo ln -sfn ~/nixos-config /etc/nixos`（fish 的 `rebuild`/`update`
   别名与本文档命令都走 `/etc/nixos`；本机即此布局）
2. `~/Projects/wl-harness`：私有仓库 git clone（flake 输入 wl-harness 依赖）
3. 龙猫云_Lite（lmclient）：**临时代理客户端，已不进 flake**，无需随仓库
   迁移。要用时装到 PATH 或 `~/.local/bin`，`home/hyprland.nix` 的 launcher
   自动发现并启动，没装就干净跳过（不影响 rebuild 或会话）
4. 新机生成 `hosts/nixos/hardware-configuration.nix`
   （`nixos-generate-config` 后替换）；**显示器名不同**的改
   `home/hyprland/noctalia-config.toml` 与 `hypr/lua/monitors.lua` 里的
   `eDP-1`；N 卡机器另需动 `modules/desktop/hyprland.nix` 的 Intel 驱动段
5. noctalia 插件启用：**已自动化**——`home/noctalia-plugins.nix` 每次登录
   用 systemd user oneshot 幂等重申（`After=noctalia.service`，因为
   `noctalia msg plugins enable` 走 IPC 且异步导出，需运行中实例）。新插件
   在该文件的 `plugins` 列表登记即可。异常时手工兜底：
   `noctalia msg plugins enable kun/agent-usage`、`kun/sysops`
   （启用状态是 imperative 的，存 `~/.local/state/noctalia/settings.toml`）
6. sysops 运维助手运行时初始化（见 decisions/0007）：建 hermes sysops
   profile（`hermes profile create sysops --clone` + alias）；启用 webhook
   平台并 `hermes gateway install --start-now --start-on-login`；两个订阅
   （sysops-execute / sysops-diagnose，`--route-profile sysops`）；HMAC secret
   写 `~/.local/state/sysops/webhook.env`（0600，SYSOPS_WEBHOOK_URL /
   SYSOPS_WEBHOOK_SECRET）。三个易漏点：①订阅 prompt 用**根级引用**
   （`{proposal_id}`），`{payload.x}` 不替换；②`webhook_subscriptions.json`
   两个路由手工补 `"toolsets": ["terminal", "file"]`（webhook 默认 web 类
   工具，无法执行）；③gateway 执行环境 drop-in
   `~/.config/systemd/user/hermes-gateway.service.d/override.conf`：SHELL=bash
   + 含 `/etc/profiles/per-user/kun/bin` 的 PATH（否则 terminal 包装器被
   fish 解析报错、找不到 sysops-ctl/rg）
7. 快层重装：`npm i -g` pi 全家桶、hermes 官方 `install.sh`（见
   https://hermes-agent.nousresearch.com ，**勿用 PyPI 渠道**，已停更）、
   agy 官方脚本、herdr 官方 installer（https://herdr.dev/install）。
   装完跑 **agent 自检补齐**（插件 / MCP / hermes `external_dirs` 等
   无 secret 基线，add-only、改前备份 `*.wl-harness.bak`）：
   `~/Projects/wl-harness/scripts/agent-check.sh all --install`
   每个 agent 的自检清单在 `~/Projects/wl-harness/shared/agents/checklists/`
   （agent 可直接读取自助补齐）。其中 hermes 的 `skills.external_dirs` 指到
   `${HOME}/.agents/skills` 已由 wl-harness 模块在 rebuild 时自动 seed
   （hermes 默认不读共享技能目录，这是接入点；`hermes skills list` 里
   source=external 即生效），自检脚本只是兜底复核。
8. 备份恢复（重装不丢的命令式状态）：`~/.pi/agent/auth.json`、`~/.hermes/`
   （整目录：含 `skills/` 自写技能库如 noctalia-plugins、`state.db` 会话与
   用量数据）、`~/.local/state/agent-usage/`（面板偏好 `panel-config.json` +
   用量账本 `hermes-ledger.json`——账本含按天归属，丢了只能按 first_seen
   近似重建）、SSH keys、tailscale 认证
