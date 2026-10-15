# 0008. 配置归属边界（nixos-config=系统 / wl-harness=快层与 agent）+ agent 自检清单

- Status: accepted
- Date: 2026-10-15

## Context

需求：以后每次重装系统，clone 项目就能一键恢复配置。只读盘点后发现仓库
已能恢复系统骨架，但"配置"散落在几层里，无法全部迁移。用户明确了一条
关键边界：**工具本体下载不强求一键复现（可写脚本装），但配置必须能够迁移**
——"配置丢了很难，工具下载我们可以另外加一个 install 脚本就搞定了"。

经 grill 追问定案的争议点：

1. **迁移目标边界**：系统+agent 配置可恢复（凭据单独备份）vs 连 OAuth/API
   key 也声明式 vs 只恢复系统 skeleton
2. **agent 插件安装方式**：是维护安装脚本，还是给每个 agent 一份可读 md
   自检清单让 agent 自助补齐
3. **机读清单 vs 人读文档**：md 是唯一真源，还是 md + 机读清单/校验脚本兜底
4. **baseline 配置迁移方式**：自动 seed 还是只靠 agent 读 md 手工处理
5. **凭据管理**：是否上 sops-nix/agenix
6. **验收标准**：现机冒烟还是 fresh VM

同时确认职责划分：**nixos-config 只管系统；wl-harness 管快层与 agent/AI 相关
工具**。这与既定 0004（wl-harness 共享 agent 层）、0001/0005（快慢分层）
一致，本条把"配置迁移"这一维度补进边界。

## Decision

1. **职责边界**：
   - `nixos-config`：系统硬件、NixOS 模块、桌面系统服务、HM dotfiles、
     `sysops` 实现与 timer、`install-from-clone.sh` 引导
   - `wl-harness`：pinned skills、MCP 接线、agent baseline 配置 seed、
     agent 自检清单、`agent-check.sh`、快层工具清单
   - 凭据/登录态：两仓都不入；示例只进 `wl-harness/secrets/*.example`

2. **配置迁移三件套**（同一批事实、单一真源、互不矛盾）：
   - `shared/agents/checklists/<agent>.md`：给人和 agent 看的自检清单
     （该有什么、缺什么、怎么补、登录态提示）
   - `scripts/agent-check.sh`：确定性兜底（读 `packages.txt` + grep 配置键，
     `--install` 幂等补齐）
   - `nixos/hm-module.nix` activation：rebuild 时自动 seed 无 secret 的 baseline
   - 包清单唯一真源是 `shared/agents/pi/packages.txt`，**不在脚本/清单里重复**

3. **add-only 铁律**：任何自动补齐都不覆盖已有键／entry／值；改动前写
   `*.wl-harness.bak`。zcode model 只在整个 `model` 段缺失时写；hermes
   `external_dirs` 只在该键缺失时插入。

4. **凭据永不入库**（Q1=A、Q3=是）：OAuth/订阅登录保持每机手动；env 类
   API key 若要声明式，留 sops-nix/agenix 接口但本期不实施。

5. **noctalia 插件启用重申**：启用状态是命令式（`~/.local/state/noctalia/
   settings.toml`），换机后不重申会静默关闭。用 systemd user oneshot
   （`After=noctalia.service`）幂等重申，**不覆盖**面板/布局/monitor 等其余
   状态。理由：`noctalia msg plugins enable` 走 IPC 且异步导出，需运行中实例，
   不能只靠 home-manager activation。

6. **验收 = fresh VM**（Q5/Q8）：build + verify 必须过；`agent-check.sh` 报告
   作附加项。系统层与快层的失败分开报，不混淆。

## Consequences

- 收益：新机 clone + `install-from-clone.sh` + `agent-check.sh --install`
  即可恢复系统与 agent 工作方式；agent 能读清单自助补齐，无需维护逐工具
  安装脚本；配置与凭据分离，凭据不进 git。
- **残余风险（明确接受）**：
  - ~~`lmclient-nix` 不在 git（含 64MB AppImage），换机必须从备份还原到
    `flake.nix` 声明的绝对路径~~ **已解除（2026-10-15）**：lmclient 是
    临时代理客户端，按"工具下载可脚本化"原则移出 flake（删 input +
    `home/packages.nix` 引用）；`home/hyprland.nix` 的 launcher 改为从
    PATH / `~/.local/bin` 解析，未安装即干净跳过。换机不再需要该目录。
  - agent baseline 的模板默认值会补进缺失键（如 pi `defaultModel`），
    属"seed-if-missing"而非纯 no-op；用户已有值永远优先。
  - `agent-check.sh` 的 `--install` 与 activation 覆盖同一批事实，理论上
    可能重复写；两者均幂等且 add-only，实测不冲突，但改动其一时须同步另一处。
  - noctalia 启用是异步导出，重申后立即读 `settings.toml` 可能尚未落盘；
    下次登录会收敛。
- 与 0004/0005 不冲突：0004 定义 wl-harness 为共享 agent 层，本条扩展其
  职责到"agent baseline 配置"；0005 的快慢分层不变，本条只是明确了
  "配置"归属哪一层。
