# 0005. AI 工具链快慢分层：dsh 删除、hermes-agent 移出 nix、nixpkgs 改 git 镜像

- Status: accepted
- Date: 2026-10-13

## Context

与 Omarchy（DHH 的 Arch + Hyprland omakase 发行版）对比复盘后确认，本仓库
最大的维护负担来自 AI 工具链同时存在四种管理范式（flake 输入 / AppImage
overlay / npm 自管 / vendored 外部仓库），以及 nixpkgs channel tarball 输入
的周期性锁漂移。其中两块成本/收益明显失衡：

- **dsh**（DeepSeek Harness CLI）：`buildNpmPackage` 打包，每次升级要重新
  生成 369KB package-lock.json 并重算 npmDepsHash，node addon 还需要
  `--expose-internals` wrapper 绕过 HMR 故障。**已不再使用**。
- **hermes-agent**（Nous Research）：flake 输入拖进 uv2nix / pyproject-nix /
  flake-parts 等 5 个传递输入，锁图里出现第二个 home-manager 实例，
  ~700MB closure；而它在 PyPI 有原生发布渠道，属于 0001 判定线里
  「自带更新机制，nix 锁定只会拖慢它」的情形（0001 当年以「走 flake」
  为由留下，代价事后看偏高）。

另一项周期性维护税：nixpkgs 用 TUNA channel tarball（无版本号、
lastModified 是 1980 假时间戳），锁随镜像滚动悄悄漂移，需要定期提交
「刷新漂移的锁」（git log 里可见多次）。

## Decision

1. **快慢两层**（把 0001 的判定线升格为显式规则，AGENTS.md 同步改写）：
   - **慢层（nix 声明式）**：桌面 GUI、系统依赖、LSP/MCP 二进制、稳定
     发布通道的工具、nix 包装后自更新失效的（zcode / orca-ide /
     grok-bot / wechat / codegraph / herdr）。享受版本锁定 + 整机回滚。
   - **快层（`~/.local` 自管）**：npm/uv 原生渠道、自带更新机制、发版
     频率跟不上 flake 刷新节奏的（pi 全家桶、hermes-agent、agy、
     context-mode/rtk）。更新即时，不可复现（单机可接受）。
2. **dsh 整体删除**：overlay、wrapper 目录（含 package-lock.json）、
   update.sh 条目、home.packages 引用一并移除。
3. **hermes-agent 移出 nix**：`uv tool install hermes-agent` 装到
   `~/.local/bin`，升级用 `uv tool upgrade hermes-agent`；flake 删
   hermes-agent 输入与 overlay，nixpkgs-unstable 输入（仅服务其 follow）
   一并删除。锁图从 16 节点大幅缩小（uv2nix 子图、第二个 home-manager、
   假时间戳 tarball 节点全部消失）。
4. **nixpkgs 输入改官方 GitHub 的 git 协议**（`git+https://github.com/NixOS/nixpkgs.git?ref=nixos-26.05&shallow=1`）：
   锁里是真实 commit + 时间戳，tarball 假时间戳锁漂移从根上消灭；
   substituters（TUNA store 镜像）不变，二进制缓存命中不受影响。
   方案选择的实测依据：
   - `github:` 简写走 GitHub REST API，代理共享出口 IP 的匿名限额
     （60 次/时）经常 403；`git+https` 直连无此限制。
   - TUNA 的 git 镜像晚高峰服务端排队严重（实测两次 fetch 各排队
     25+ 分钟零字节），只留作无代理环境的备选（见 flake.nix 注释）。
   - lmclient 的内部 nixpkgs 输入加 `follows` 指向主输入，避免锁图
     里再生假时间戳 tarball 节点。

## Consequences

- flake 输入 7 → 5（nixpkgs / home-manager / noctalia / lmclient /
  wl-harness），hermes 的 ~700MB closure 与 uv2nix 子图从系统闭包消失。
- hermes 不再随 nixos-rebuild 更新；换机时按 AGENTS.md 快层清单重装。
- nixpkgs 升级命令不变（`nix flake update nixpkgs`），锁条目从 tarball
  变为 git rev；日常 rebuild 用已缓存的锁不碰网络，只有 flake update
  需要代理在线。CI 每周自动刷新远端输入并开 PR（runner 访问 GitHub
  原生速度，不依赖代理）。
- zcode / orca-ide / grok-bot 维持 nix（各有留 nix 的记录在案理由：
  zcode 官方不自更新；orca 的 electron-updater 在 nix 包装下失效；
  grok-bot 同为 GUI），升级仍走 `scripts/update.sh`（范围缩小为三项）。
- 新增 AI CLI 时先过快慢判定线：自带更新机制且 nix 包装无增益 → 快层；
  GUI / 不自更新 / 需要 patchelf → 慢层。
