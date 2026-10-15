{
  config,
  lib,
  pkgs,
  ...
}:

# ============================================================
# sysops：系统运维助手的确定性外壳（hermes sysops profile，见 decisions/0007）
# 架构参照 agent-usage（采集/展示解耦，文件系统当 IPC）：
#   - sysops-ctl：体检采集（collect/report，零 token）+ 方案审批执行状态机
#     （propose/decide/job）+ hermes webhook 触发（dispatch/diagnose），
#     状态原子写 ~/.local/state/sysops/（report.json / queue.json / proposals / jobs）
#   - systemd user timer 每小时浅检查（深分析由 hermes cron 每周跑，二期）
#   - noctalia 插件 kun/sysops：顶栏状态灯 + 运维面板（问题卡片 + 待审批框）
# 首次部署后的运行时初始化（命令式，不进 nix，见 AGENTS.md 换机清单）：
#   sysops profile / gateway webhook 订阅 / `noctalia msg plugins enable kun/sysops`
# ============================================================
let
  python = pkgs.python3; # 纯标准库（json/hmac/urllib/subprocess）
  src = pkgs.copyPathToStore ./sysops;

  sysops-ctl = pkgs.writeShellScriptBin "sysops-ctl" ''
    exec ${python}/bin/python3 ${src}/sysops-ctl.py "$@"
  '';
in
{
  home.packages = [
    sysops-ctl
  ];

  systemd.user.services.sysops-collect = {
    Unit = {
      Description = "sysops 系统体检采集（浅检查）";
      # 无桌面依赖：只读 journalctl/systemctl/procfs，登录期即可跑
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${sysops-ctl}/bin/sysops-ctl collect";
    };
  };

  systemd.user.timers.sysops-collect = {
    Unit = {
      Description = "sysops 定时体检（每小时）";
    };
    Timer = {
      OnCalendar = "hourly";
      Persistent = true; # 错过的周期开机补跑一次，登录即有新鲜报告
      Unit = "sysops-collect.service";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };

  # 串行派发兜底（v2.1）：任务终态会链式接力，timer 是安全网
  # （崩溃/时序边缘导致接力丢失时，30 秒内自动推进队列）
  systemd.user.services.sysops-dispatch = {
    Unit = {
      Description = "sysops 执行队列串行派发（兜底 sweep）";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${sysops-ctl}/bin/sysops-ctl dispatch-next";
    };
  };

  systemd.user.timers.sysops-dispatch = {
    Unit = {
      Description = "sysops 派发队列 sweep（30 秒）";
    };
    Timer = {
      OnUnitActiveSec = "30s";
      Unit = "sysops-dispatch.service";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };

  # 每周深度分析（Q13：每周一早）：hermes 一次性无状态会话深挖归因，
  # 产出 deep-report.md + 方案进待审批框。依赖快层 hermes-sysops alias
  # （AGENTS.md 换机清单第 6 条）；LLM 成本只花在这一处与对话区。
  systemd.user.services.sysops-deep = {
    Unit = {
      Description = "sysops 每周深度分析（hermes，LLM）";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${sysops-ctl}/bin/sysops-ctl deep";
    };
  };

  systemd.user.timers.sysops-deep = {
    Unit = {
      Description = "sysops 每周深度分析（周一 08:00）";
    };
    Timer = {
      OnCalendar = "Mon *-*-* 08:00:00";
      Persistent = true; # 错过的周期开机补跑一次
      Unit = "sysops-deep.service";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };

  # noctalia 插件（plugin.toml + Luau）：seed 成真实文件复制
  # （理由同 agent-usage——插件目录扫描 + Luau 热重载监听需要普通文件）。
  # 首次部署后需启用一次：`noctalia msg plugins enable kun/sysops`
  home.activation.seedNoctaliaSysOps = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -eu
    DEST="$HOME/.local/share/noctalia/plugins/sysops"
    SRC="${./sysops/plugin}"

    mkdir -p "$HOME/.local/share/noctalia/plugins"
    rm -rf "$DEST"
    cp -R "$SRC" "$DEST"
    chmod -R u+rwX "$DEST"
  '';
}
