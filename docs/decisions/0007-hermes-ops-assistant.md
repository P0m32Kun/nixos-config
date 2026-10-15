# 0007. hermes 作为系统运维助手（noctalia 入口 + 两段审批执行流）

- Status: accepted
- Date: 2026-10-14

## Context

目标：hermes 成为整台设备的运维助手——系统报错、系统更新、配置文件编辑、
回滚都交给 hermes 操作；通过 noctalia shell 的对话入口反馈体检情况（有哪些
问题需要修复、驱动是否缺失等），人工审批后才实施。

经三轮追问（grill）定案的争议点：审批交互位置（面板内 vs 终端）、sudo 权限
模型、体检频率与 token 成本、修复方案由谁生成、拒绝/忽略语义、交付分期。
其中 sudo 一项在只读调研时发现与既定决策 0003 冲突：**本机 sudo 早已全免密**
（`security.sudo.wheelNeedsPassword = false`），"NOPASSWD 四命令白名单"实为
对 0003 的收紧且波及 pi 等既有自动化，最终拍板维持 0003 不动。

## Decision

1. **三层架构**（采集/分析/展示解耦，文件系统当 IPC，沿用 agent-usage 先例）：
   - 确定性采集层：`sysops-ctl collect`（纯标准库，零 token）+
     systemd user timer 每小时浅检查 → `~/.local/state/sysops/report.json`
   - hermes 分析执行层：独立 **sysops profile**（隔离技能/记忆/cron），
     经 gateway + webhook 触发（`--route-profile sysops` 多路复用，
     Generic HMAC V2 签名）；只读诊断产出方案，批准后执行
   - noctalia 展示审批层：插件 `kun/sysops`（顶栏状态灯 + 面板：体检问题
     卡片 + 待审批框），动作全部回 `sysops-ctl` 子命令
2. **两段式审批**：hermes 诊断产出方案（改什么/跑什么命令/风险/回滚方式）
   → 面板待审批框逐问题批准 → 才执行。所有写操作（root 命令、配置修改、
   回滚、删除）逐次批准；只读诊断免批；**git push 永不自动**；失败即停、
   出诊断、不自动重试不自动回滚。拒绝 = 方案作废问题保留；忽略（二期）=
   问题不再报（两级、可撤销）。
3. **sudo 维持 0003 全免密不动**，安全闸门 = 面板审批流（二选一里选了
   "不加第二道重复锁"）。hermes 不是新暴露面：0003 的信任模型本就是
   "以 kun 身份运行的代码都能提权"。
4. **频率**：浅检查每小时（纯脚本零 token）；深分析每周一早（hermes，二期）。
   修复方案生成（B1）：简单问题卡片带规则化命令直接成方案；复杂问题
   （配置编辑等）"发起修复" → hermes 现场诊断出方案，覆盖全部四类职责。
5. **快慢分层归属**（0005）：`sysops-ctl` 与 noctalia 插件 = 慢层
   （nix 声明式，`home/sysops*`）；hermes = 快层（不打包进 nix）。
   webhook HMAC secret 落 `~/.local/state/sysops/webhook.env`（0600），
   不进 nix store（密钥约定见 AGENTS.md）。
6. **分期**：一期 = 体检采集 + 面板展示 + 报告修复的审批执行闭环；
   二期 = 对话区、每周深分析、两级忽略、严重问题主动告警、diff 级配置方案。

## Consequences

- 收益：体检 → 审批 → 修复 → 回滚闭环全在桌面面板内完成；hermes 获得
  "批准后执行 root 命令"的能力，且每一步有方案文本 + 审批记录 + 执行日志。
- **残余风险（明确接受）**：sysops profile 的 `approvals.mode = off`
  （webhook 触发的非交互执行不能在环中等人），"不执行方案外写操作"只靠
  prompt 约束；webhook HMAC secret 泄露 = 可触发任意方案执行。secret 以
  0600 存用户家目录。hermes 执行时实际拥有 0003 的全免密 sudo——信任模型
  未变，但"批准"这道人工闸门是唯一刹车。
- 一期不含对话区：面板只做结构化修复 + 审批，自由提问二期随对话区交付。
- 二期通道补充（2026-10-15）：对话走 `hermes chat --continue sysops-chat`
  命名会话（上下文连续）、每周深分析走一次性无状态会话；执行/诊断仍走
  webhook。原因：webhook 每次投递都会开新会话（实测），不适合对话连续性。
- 执行串行化（2026-10-15，v2.1）：同一时间只执行一个方案（dispatch-next
  队列接力 + 30 秒 timer 兜底）。起因：四方案并发执行时 cntk 先改了
  base.nix，bscr 的预生成 diff 上下文失效。运维操作宁慢勿乱。
- 回滚路径：删 `home/sysops.nix` + `home/default.nix` 一行 import + rebuild
  即摘除整套采集/插件；webhook 订阅 `hermes webhook remove`；gateway
  平台配置可留可删。
- 未验证项：noctalia 面板的视觉/交互验收是人工的（实现后按
  "implemented, awaiting acceptance" 等本人验收）。
