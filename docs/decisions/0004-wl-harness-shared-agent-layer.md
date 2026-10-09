# 0004. 跨设备 agent 共享层由 wl-harness 提供，本仓库只做导入

- Status: proposed（分支 `wl-harness`，未合入 main）
- Date: 2026-10-10

## Context

Mac（家里执行主机）与本机需要同一套 agent 共享层：第三方 skills、Orca 路由 skill、
codegraph MCP 接线。这些放在私有仓库 `P0m32Kun/wl-harness`（Mac 走 `mac/install.sh`，
无 nix）。wl-harness 最初的 `nixos/` 是独立 flake，会用 `npm -g` 装 codex/pi/codegraph/zcode、
下载 Orca AppImage——与本仓库的 overlay（zcode/orca-ide/codegraph）、nixpkgs codex、
决策 0001 的 pi 自管全部重复，且 `npm -g` codegraph 在 NixOS 上本来就是坏的（0001）。

## Decision

wl-harness 改为只导出 `homeManagerModules.default`（flake 无 inputs，用宿主的 pkgs），
本仓库以 `git+file:///home/kun/Projects/wl-harness` 输入导入（`home/wl-harness.nix`）。
模块**只**提供：

- pinned skills：清单 `shared/skills/manifest.txt`（与 Mac 同一份），rev+hash 在
  `shared/skills/sources.json`（nix 锁定）。本机用 `wl-harness.skills.exclude` 去掉与
  agent-skills 同名的 code-review/grill-with-docs/grilling/tdd/wayfinder。
- pick-agent skill。
- codegraph MCP「只增不改」合并（首次改动前留 `*.wl-harness.bak`）。

Pi `settings.json` 模板（Hindsight pi.js 扩展 + pi-mcp-adapter）不在本机合并，Pi 配置仍归 Pi 自管（0001）。二进制仍按本仓库现有方式；Hindsight 接线交给它自己的 installer；Tailscale 已在
`modules/networking/tailscale.nix`；`orca serve` 只在 Mac 跑。

为什么 git+file 而不是 git+ssh：`sudo nixos-rebuild` 以 root 求值，root 没有 GitHub
密钥；git+file 只取已提交文件（`secrets/` 不会进 store），与 /etc/nixos 本身同一读法。

## Consequences

- skills 由 nix 锁定（静态 markdown，无自更新机制，不违反 0001 的判定线）；升级 =
  在 wl-harness 改 `sources.json` 的 rev+hash → push → 本机 `git pull` +
  `nix flake update wl-harness` + rebuild。
- `~/.agents/skills/<name>` 是指向 store 的只读符号链接，与 `npx skills` 装的条目共存；
  同名时 home-manager 会拒绝覆盖（需先删掉命令式的那份）。
- pi 同时有 npm 包 `@dietrichgebert/ponytail`（自带同名 skills）→ pi 报 name collision
  诊断、first wins，无功能影响；若只想要 skills，可从 pi packages 去掉该包。
- 回滚：删 `home/wl-harness.nix` 的 import 与 flake 输入，rebuild；配置文件用
  `*.wl-harness.bak` 或 `~/wl-harness-backup-*.tgz` 还原。
