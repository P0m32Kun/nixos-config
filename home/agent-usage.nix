{
  config,
  lib,
  pkgs,
  ...
}:

# ============================================================
# agent-usage：本地 AI harness 的 token 用量监测（采集层）
# 架构参照 Omarchy（采集/展示解耦，文件系统当 IPC）：
#   - agent-usage-collect：解析各 harness 本地数据 → 每家一条
#     display-ready JSON 原子写 ~/.local/state/agent-usage/<agent>.json
#     （zcode=sqlite model_usage 表；pi=会话 JSONL 增量缓存；
#       codex/hermes 见 collect.py 头注释）
#   - systemd user timer 每 15 分钟刷新一次
#   - agent-usage：终端报告（--refresh 先采集 / --json 给桌面组件用）
# 桌面组件（noctalia 自定义模块或独立 Quickshell）为二期，只读这些 JSON。
# ============================================================
let
  python = pkgs.python3; # 纯标准库（sqlite3/json/fcntl）
  # 两个脚本要进同一个 store 目录：report.py 的 --refresh 会
  # 通过 __file__ 同目录找 collect.py，分开引用会各自落不同路径
  src = pkgs.copyPathToStore ./agent-usage;

  agent-usage = pkgs.writeShellScriptBin "agent-usage" ''
    exec ${python}/bin/python3 ${src}/report.py "$@"
  '';

  agent-usage-collect = pkgs.writeShellScriptBin "agent-usage-collect" ''
    exec ${python}/bin/python3 ${src}/collect.py "$@"
  '';
in
{
  home.packages = [
    agent-usage
    agent-usage-collect
  ];

  systemd.user.services.agent-usage = {
    Unit = {
      Description = "agent-usage 采集（本地 harness token 用量）";
      # 无桌面依赖：纯文件解析，登录期即可跑
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${agent-usage-collect}/bin/agent-usage-collect";
    };
  };

  systemd.user.timers.agent-usage = {
    Unit = {
      Description = "agent-usage 定时采集（15 分钟）";
    };
    Timer = {
      OnCalendar = "*:0/15";
      Persistent = false; # 用量统计不需要补跑错过的周期
      Unit = "agent-usage.service";
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };

  # noctalia 顶栏组件（plugin.toml + Luau）：seed 成真实文件复制
  # （同 quickshell overview 先例——插件目录扫描 + Luau 热重载监听
  # 需要普通文件，symlink 到 /nix/store 不可靠）。
  # 首次部署后需启用一次：`noctalia msg plugins enable kun/agent-usage`
  home.activation.seedNoctaliaAgentUsage = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    set -eu
    DEST="$HOME/.local/share/noctalia/plugins/agent-usage"
    SRC="${./agent-usage/plugin}"

    mkdir -p "$HOME/.local/share/noctalia/plugins"
    rm -rf "$DEST"
    cp -R "$SRC" "$DEST"
    chmod -R u+rwX "$DEST"
  '';
}
