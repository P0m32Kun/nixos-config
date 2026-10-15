{
  config,
  lib,
  pkgs,
  ...
}:

# ============================================================
# noctalia 插件自动启用（换机可复现）
#
# 背景：插件文件由 home-manager seed 到 ~/.local/share/noctalia/plugins/
# （见 home/agent-usage.nix / home/sysops.nix），但**启用状态**是命令式的，
# 存 ~/.local/state/noctalia/settings.toml 的 [plugins] enabled 数组。
# 换机后不重申一次，插件会静默保持关闭（noctalia-plugins skill 的已知坑）。
#
# 方案：systemd user oneshot，noctalia.service 起来后幂等重申启用。
# 为什么不用 home-manager activation 直接跑：`noctalia msg plugins enable`
# 走 IPC 且**异步导出**（实测返回 "ok (exporting in background)"，状态落盘
# 滞后），需要运行中的 shell 实例才能真正持久化。故放在 After=noctalia.service。
# 反复执行安全：对已启用插件再 enable 不改变 settings.toml（实测幂等）。
#
# 不覆盖用户布局：只重申插件启用，panel/widget 排列、monitor 绑定等
# settings.toml 其余内容一律不动。
# ============================================================
let
  # 换机后必须启用的本地插件（新增插件在这里登记即可）
  plugins = [
    "kun/agent-usage"
    "kun/sysops"
  ];

  enablePlugins = pkgs.writeShellScriptBin "noctalia-plugins-enable" ''
    set -uo pipefail
    if ! command -v noctalia >/dev/null 2>&1; then
      echo "noctalia-plugins-enable: noctalia CLI 不在 PATH（快层未装），跳过"
      exit 0
    fi

    # 等 noctalia IPC 就绪（fresh 登录时 shell 可能还没起好）
    for _ in $(seq 1 30); do
      if noctalia msg plugins list >/dev/null 2>&1; then break; fi
      sleep 1
    done

    listed="$(noctalia msg plugins list 2>/dev/null || true)"
    if [ -z "$listed" ]; then
      echo "noctalia-plugins-enable: 取不到插件列表，跳过（下次登录会再试）"
      exit 0
    fi

    ${lib.concatMapStringsSep "\n" (p: ''
      if printf '%s\n' "$listed" | grep -q '^${p} .*enabled'; then
        echo "noctalia-plugins-enable: ${p} 已启用"
      else
        noctalia msg plugins enable ${p} >/dev/null 2>&1 \
          && echo "noctalia-plugins-enable: 已启用 ${p}" \
          || echo "noctalia-plugins-enable: 启用 ${p} 失败（下次登录会重试）"
      fi
    '') plugins}

    exit 0
  '';
in
{
  home.packages = [ enablePlugins ];

  systemd.user.services.noctalia-plugins-enable = {
    Unit = {
      Description = "noctalia 本地插件启用重申（换机可复现，幂等）";
      After = [ "noctalia.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${enablePlugins}/bin/noctalia-plugins-enable";
      RemainAfterExit = true;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
