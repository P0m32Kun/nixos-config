local session = os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or "default"

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function exec_once(cmd)
  local key = tostring(cmd):gsub("[^%w_.-]", "_"):sub(1, 80)
  local marker = "/tmp/hypr-lua-exec-once-" .. session .. "-" .. key
  local log = "/tmp/hypr-lua-startup-" .. key .. ".log"

  local script = "[ -e "
    .. shell_quote(marker)
    .. " ] || { touch "
    .. shell_quote(marker)
    .. " && sh -lc "
    .. shell_quote(cmd)
    .. " >>"
    .. shell_quote(log)
    .. " 2>&1 & }"

  os.execute("sh -lc " .. shell_quote(script))
end

local startup_commands = {
  "fcitx5 -d --replace",
  "hyprpaper",
  "qs -c overview",
  "nm-applet",
  -- 龙猫云_Lite 由 systemd 用户服务托管（见 home/hyprland.nix），随图形会话启停
  -- 拉起 systemd 图形会话目标（noctalia / xdg-desktop-portal 等挂在它下面）：
  -- graphical-session.target 拒绝手动启动（RefuseManualStart=yes），所以启停
  -- 自己的 hyprland-session.target（见 home/hyprland.nix），由它 Wants 依赖拉起。
  -- 先停再启：用户 systemd 管理器跨登录存活（KillUserProcesses=false），
  -- 保证每次登录/重启合成器都得到全新图形会话，而不是复用旧的死连接。
  "systemctl --user stop hyprland-session.target || true; systemctl --user start hyprland-session.target",
  -- noctalia 由 systemd 用户服务启动（见 home/hyprland.nix），避免双实例
  -- lmclient 由 systemd 用户服务启动（见 home/hyprland.nix），时序/重启/单实例由 systemd 保证
}

local function run_startup_commands()
  for _, cmd in ipairs(startup_commands) do
    exec_once(cmd)
  end
end

if hl and hl.on then
  hl.on("hyprland.start", run_startup_commands)
  hl.on("hyprland.shutdown", function()
    -- 退出时停掉 hyprland-session.target；graphical-session.target 会因
    -- StopWhenUnneeded=yes 自动停止，noctalia 等随 PartOf 停止
    os.execute("systemctl --user stop hyprland-session.target")
  end)
else
  run_startup_commands()
end
