# NixOS 配置仓库

使用 **flake** + **模块化** 管理 NixOS 配置，配置托管在 **GitHub**（P0m32Kun/nixos-config），
国内使用 **清华 TUNA 镜像**。软件分**快慢两层**管理（慢层 nix 声明式 / 快层 `~/.local`
自管），见 `docs/decisions/0001` 与 `0005`。

## 目录结构

```
nixos-config/
├── flake.nix                    # flake 入口（nixpkgs 来源、主机定义、overlays）
├── flake.lock                   # 版本锁定（真实 commit，提交到 GitHub 保证可复现）
├── hosts/nixos/                 # 本机配置（主机名 nixos）
│   ├── default.nix              #   入口：导入模块 + 本机特有配置
│   └── hardware-configuration.nix  # 硬件配置（生成，勿手改）
├── modules/                     # 系统级 NixOS 模块
│   ├── base.nix                 #   时区 / 中文 / SSH / 代际清理
│   ├── mirrors.nix              #   TUNA substituters + nix-daemon 代理 env
│   ├── packages.nix             #   系统软件包 + 允许 unfree
│   ├── virtualization.nix       #   libvirt / Podman（国内镜像链）
│   ├── desktop/                 #   Hyprland 桌面 / PipeWire 音频
│   ├── networking/              #   Tailscale
│   ├── security/                #   sudo / 指纹
│   └── users/kun.nix            #   用户 kun（shell = fish）
├── home/                        # home-manager 用户级配置
│   ├── default.nix              #   入口（imports 注册处）
│   ├── packages.nix             #   用户级软件包（LSP/MCP/GUI/工具链）
│   ├── hyprland.nix             #   Hyprland dotfiles + noctalia/lmclient 服务
│   ├── apps.nix                 #   Alacritty / Helix / Fish / Yazi / uv / Obsidian
│   ├── wl-harness.nix           #   wl-harness 共享 agent 层（见 decisions/0004）
│   └── agent-usage.nix          #   agent token 用量监测（采集 + 15 分钟 timer）
├── overlays/                    # 不在 nixpkgs 的自定义包
│   ├── pi-tools.nix             #   codegraph（autoPatchelf）
│   ├── herdr.nix                #   herdr（静态二进制）
│   ├── wechat.nix               #   微信（src 换官方 CDN）
│   ├── zcode.nix / orca.nix / grok-bot.nix   # AI 桌面客户端（AppImage）
├── scripts/
│   ├── update.sh                # 慢层 overlay 包升级（orca/zcode/grok-bot）
│   └── check.sh                 # nixfmt + dry 构建冒烟
├── docs/decisions/              # 决策记录（ADR 0001-0005）
└── .github/workflows/ci.yml     # push 格式检查 + 每周自动刷新远端输入开 PR
```

**设计思想**：
- 所有机器共享 `modules/`，差异只体现在 `hosts/<主机>/default.nix`
- 新增功能 = 新建一个模块文件 → 在主机入口 import 它
- 新增慢层软件 = 包名加进 `home/packages.nix` 或 `modules/packages.nix`

## 日常使用

```bash
# 本机重建/升级
sudo nixos-rebuild switch --flake /etc/nixos

# 更新 nixpkgs 等输入到最新（GitHub git 协议，锁真实 commit；需代理在线）
cd /etc/nixos && nix flake update nixpkgs
sudo nixos-rebuild switch --flake /etc/nixos
# （远端输入 nixpkgs / home-manager / noctalia 每周有 CI 自动 PR）

# 慢层 overlay 包（zcode / orca / grok-bot）升级
./scripts/update.sh              # 全部；或 ./scripts/update.sh zcode 只更一项

# 快层工具升级（不随 rebuild）
hermes update                    # hermes（官方 install.sh 渠道；PyPI 渠道已停更勿用）
pi update self                   # pi 本体

# 改完配置先自检再 switch
./scripts/check.sh               # nixfmt + dry 构建冒烟

# 回滚到上一个版本
sudo nixos-rebuild switch --rollback
```

## 国内镜像说明

- **nixpkgs 源**：`flake.nix` 使用 GitHub 的 **git 协议 shallow 克隆**
  `git+https://github.com/NixOS/nixpkgs.git?ref=nixos-26.05&shallow=1`
  （锁真实 commit，杜绝 channel tarball 的假时间戳锁漂移，见 decisions/0005；
  需代理在线。不用 `github:` 简写是避开 REST API 匿名限额 403；
  TUNA git 镜像排队严重仅作无代理备选）
- **二进制缓存**：`modules/mirrors.nix` 的 substituters 优先 TUNA store 镜像，
  官方兜底，另有 noctalia 官方 cachix
- **nix-daemon 代理**：github.com 等下载走 `127.0.0.1:7892`（lmclient），
  无代理时删掉 `modules/mirrors.nix` 对应 block 即可

## 换机/重装

flake 依赖两个**本地路径输入**，换机前先就位（详见 AGENTS.md 的清单）：

1. clone 本仓库（如 `~/nixos-config`），并建符号链接
   `sudo ln -sfn ~/nixos-config /etc/nixos`（fish 的 `rebuild`/`update`
   别名与本文档所有命令都走 `/etc/nixos`；本机即此布局）
2. `~/Projects/wl-harness`（私有）与 `~/Projects/lmclient-nix` 两个目录就位
3. `sudo nixos-generate-config --show-hardware-config > /etc/nixos/hosts/<主机名>/hardware-configuration.nix`
4. `sudo NIX_CONFIG='experimental-features = nix-command flakes' nixos-rebuild switch --flake /etc/nixos#<主机名>`
5. 快层重装（`npm i -g` pi 全家桶、`uv tool install hermes-agent`）与密钥恢复
