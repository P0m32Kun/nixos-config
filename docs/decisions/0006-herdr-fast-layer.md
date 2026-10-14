# 0006. herdr 重分类：慢层 → 快层（AI 工具链自管）

- Status: accepted
- Date: 2026-10-14

## Context

[0001](0001-self-updating-tools-outside-nix.md) 把 herdr 列入「留在 nix」的依据是
「不自更新」，该判断已过时，实测（herdr 0.9.4）：

- 自带原生更新：`herdr update`（Download and install the latest version）、
  `herdr channel set <stable|preview>`（发布通道）。
- 官方活跃分发渠道是 herdr.dev/install 的 installer，落
  `${HERDR_INSTALL_DIR:-~/.local/bin}`，且与 `herdr update` 共用同一
  latest.json 发布清单（带 sha256 校验）——安装与自更新同源。
- 二进制是 static-pie（无动态依赖），不需要 patchelf / FHS 补丁。

按 [0005](0005-fast-slow-layering.md) 的判定线「有原生更新命令，且不需要
patchelf / FHS 补丁」→ 快层，herdr 两个条件都满足。继续留在 nix 反而会废掉
`herdr update`（nix store 只读），重演 0001 中 `pi update self` 失效的教训。
herdr 是 AI coding agent 的运行时，发版 0.8.0 → 0.9.4 约两个月，与 pi 全家桶 /
hermes-agent / agy 同属「发版频率跟不上 flake 刷新节奏」的 AI 工具。

## Decision

1. **herdr 移入快层**：删除 `overlays/herdr.nix` 与 flake.nix 的 overlay 注册、
   `home/packages.nix` 条目；`scripts/update.sh` 当日新增的 herdr 条目一并撤掉
   （范围回到 orca / zcode / grok-bot）。
2. **安装/升级渠道**：官方 installer（herdr.dev/install）装 `~/.local/bin/herdr`，
   升级用 `herdr update`（默认 stable 通道，`herdr channel set preview` 可切）。
   换机时先看官方 install 页当前脚本，不沿用历史认知（0005 的渠道教训）。
3. 0001「留在 nix」清单与 0005 慢层清单里的 herdr，均由本决策取代。

## Consequences

- herdr 版本不再被 flake.lock 锁定；更新即时、不可复现（单机可接受，同 pi/hermes）。
- herdr 不再随 `nixos-rebuild` 更新；换机/重装清单的快层步骤新增 herdr。
- `update.sh` 范围回到三项；overlays/ 里的 AI 桌面客户端剩 zcode / orca-ide / grok-bot。
- 判定线经验：**分类前先实测目标版本有无自更新命令**。「不自更新」这类结论会随
  上游版本过期，重分类时以实测为准，不以旧 ADR 的事实陈述为准。
