# 0003. kun 的 sudo 全免密，SSH 禁止 root 登录

- Status: accepted
- Date: 2026-09-24

## Context

要求只有两条：

1. SSH 允许密码登录，但登录用户不能是 root。
2. kun 的 sudo 免密。

改动前的实测现状（`sshd -T` / 直读配置，非推断）：

| 项 | 改前 |
| --- | --- |
| root 密码 | **本来就没有**。root 未在配置中声明，nixpkgs `nixos/modules/config/users-groups.nix:108` 明确：未设密码选项 = 不分配密码 = 无法密码登录 |
| `PermitRootLogin` | `prohibit-password`（NixOS 默认）——root 用**密钥**仍可登录 |
| `PasswordAuthentication` | `yes`（NixOS 默认） |
| 监听面 | `0.0.0.0:22`，`networking.firewall.enable = false`（hosts/nixos/default.nix） |
| 入站公钥 | **不存在**：无 `~/.ssh/authorized_keys`，`/root/.ssh/authorized_keys` 不存在 → 全靠密码登录 |
| sudo | 仅 `/run/current-system/sw/bin/nixos-rebuild` 免密（`sudo -n true` 实测失败） |

被争议的问题是：

> **提权门槛是否要降到「无」？如果降，SSH 侧要同步收紧到什么程度？**

考虑过并被**主动放弃**的更紧方案（不是没想到，是选不做）：

- 装 SSH 公钥 + `PasswordAuthentication = false` + `KbdInteractiveAuthentication = false`；
- `networking.firewall.enable = true` + `tailscale0` 放行 22，把 22 从公网收掉；
- `users.mutableUsers = false`（彻底声明式锁死密码）。
  这条有陷阱：`/etc/shadow` 会完全由 nix 生成，而 kun 的密码目前是 `passwd kun`
  命令式设的（见 `modules/users/kun.nix` 注释），叠加"没有入站公钥"会**远程自锁**。

## Decision

**`security.sudo.wheelNeedsPassword = false`（关掉 wheel 默认规则的密码要求），
密码认证保持开启，root 的 SSH 登录收紧为 `no`。**

- `modules/security/sudo.nix`：wheel 组默认规则改挂 `NOPASSWD`（nixpkgs
  `nixos/modules/security/sudo.nix:260`）。本机 wheel 成员只有 kun，故等价于「kun 免密」。
  代价是**日后新增的 wheel 用户会自动继承免密**——若哪天不再想要这个语义，改成
  `extraRules` 里 `users = [ "kun" ]` + `command = "ALL"` + `options = [ "NOPASSWD" ]` 即可。
- `modules/base.nix`：`services.openssh.settings.PermitRootLogin = "no"`。原值
  `prohibit-password` 只挡住密码，挡不住密钥；按"用户不可以是 root"的要求应为 `no`。
- **不动 `PasswordAuthentication`**（保持 `yes`）、**不装公钥**、**不碰防火墙**。

## Consequences

- 收益：`sudo` 全免密，自动化工具（pi 等）无需在环中等人输密码。
- **残余风险（明确接受，不再重复论证）**：22 端口对全网开放 + 防火墙关闭 +
  密码认证开启 + sudo 免密 ⟹ **撞对 kun 的密码 = 直接拿到 root**，中间没有任何
  第二道门槛。公网爆破脚本对这个组合的命中是自动化的。
- **失去「人在场输密码」这个刹车**：任何以 kun 身份运行的代码（pi、npm
  postinstall、浏览器/编辑器插件）都能静默 `sudo` 提权。这与
  `modules/security/sudo.nix` 头部原已声明的信任模型一致——只是从"需要一次人工
  密码"变成"全自动"。
- **指纹保护失效**：`modules/security/fingerprint.nix` 给 sudo PAM 挂了 `fprintAuth`，
  但 `NOPASSWD` 直接短路 PAM，指纹不再有机会介入。
- **polkit 不受影响**：桌面弹窗提权（`hyprpolkitagent`）走 polkit 而非 sudo，仍要密码。
  「免密 sudo」≠「桌面免密」。
- root 侧：本来无密码 + 现在 `PermitRootLogin = "no"`，root 无法从 SSH 进入。
  仍可通过 `sudo -i` 或物理控制台以 root 操作。
- 回滚：删掉 `wheelNeedsPassword = false` 一行（恢复为默认 `true`）+
  `PermitRootLogin` 改回 `prohibit-password`，一次 `nixos-rebuild switch`。
- **未验证项**：本轮改动未做任何攻击面实测（未从外部网络尝试爆破、未做端口扫描）。
  上面"穷举密码即 root"是配置层面的推断，不是渗透测试结论。
- 日后若要收紧，最小路径是：装 `authorizedKeys` → 关 `PasswordAuthentication` →
  保留本决策的免密 sudo。此时密码不再是单点。
