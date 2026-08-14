# 0001. 自更新工具移出 nix，改由原生机制维护

- Status: accepted
- Date: 2026-08-13

## Context

本仓库此前硬性约定「一切软件与配置声明式管理」，把 pi 全家桶（本体、插件、
MCP/LSP 配置）、agent-skills 也全部塞进 nix。但实践发现这条原则被过度套用：

- pi 装在 `/nix/store`（只读），`pi update self` 的底层 `npm install -g` 无法写入，
  原生自更新被彻底废掉（实测 `pi update` 报 self-update unavailable / 前缀不可写）。
- pi 的插件清单（`settings.json` 的 `packages`）被 nix 只读接管，`pi install/remove`
  写入被静默丢弃，而插件实体却仍由 pi 自己装进 `~/.pi/agent/npm/`，形成双重管理。
- agent-skills 是自己的仓库、有原生 CLI（`kun init/update/doctor`），但 flake 输入
  把它打成无 git checkout 的 store 包，`kun update` 报 `KUN_UPDATE_SOURCE`；
  且 clone 已漂移到 flake.lock 之前（split-brain）。

被争议的问题：**哪些工具适合 nix 声明式，哪些该抽出来自管？**

## Decision

自管理生态内的工具从 nix 抽离，用原生更新命令维护；其余维持 nix。判定线：

> 「它有自己维护更新的机制，且 nix 锁定只会拖慢它 / 废掉它」→ 抽出去。

具体落地：

- **pi 本体**：`npm install -g --ignore-scripts @earendil-works/pi-coding-agent`，
  落 `~/.local/bin/pi`，升级用 `pi update self`。
- **pi 插件**：`~/.pi/agent/settings.json` 交给 pi 自管（`pi install/remove/update`），
  nix 不再生成 `packages` 清单。
- **pi 的 MCP/LSP 配置**（`mcp.json` / `pi-lsp.json` / `models.json`）：全部 pi 自管。
- **MCP 二进制 context-mode / rtk**：`npm -g` / 官方 GitHub release 自管到 `~/.local`。
- **agent-skills**：完全移除 nix（flake 输入 + overlay + home 模块 + 符号链接），
  以 `~/.local/share/agent-skills` clone 为唯一真相源，`git pull && npm ci && kun init --layout direct`。

**留在 nix 的**（nix 提供版本锁定之外的硬价值，或不自更新）：

- 系统依赖（git/curl/nodejs/python3/gcc 等）
- LSP 服务器（typescript-language-server / pyright / rust-analyzer / gopls）
- playwright-mcp + 浏览器（nix 托管浏览器二进制）
- GUI（wechat / wemeet / wps / obsidian，FHS 补丁）
- 稳定 CLI（ripgrep/bat/eza/fzf/atuin/starship 等）
- herdr / hermes-agent（不自更新或走 flake）

**例外（自更新但 NixOS 跑不了，仍留 nix）**：

- **codegraph**：npm 包自带 vendored node，是通用发行版动态链接的，NixOS 必须
  `autoPatchelfHook` 补 glibc/libstdc++ 才能跑，`npm -g` 自装是坏的（实测
  `Could not start dynamically linked executable`）。故保留 `overlays/pi-tools.nix`。

## Consequences

- **npm 全局前缀**固定为 `~/.local`（`~/.npmrc` 加 `prefix`），`~/.local/bin` 进 PATH，
  否则 `pi update self` 仍会因前缀不可写而失效。
- pi 配置文件变成普通文件（非 nix 符号链接），改配置不再需要 rebuild；
  副作用是失去「改配置即 rebuild」的声明式，需接受 pi 的 imperative 状态。
- agent-skills 更新不再跟随 `nixos-rebuild`，需手动 `git pull && npm ci && kun init`。
- 自管工具的版本不再被 flake.lock 锁定，升级时效更快，但不可复现（单机可接受）。
- 未来新增安全扫描类工具（nuclei 等）遵循同一判定线：`go install` / 官方 installer
  自管，不进 nix。
