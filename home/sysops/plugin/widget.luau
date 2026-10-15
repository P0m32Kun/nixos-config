--!nonstrict
-- sysops 顶栏组件：系统健康状态灯（✗ crit 数 / ⚠ warn 数 / ✓）。
-- 数据来自 ~/.local/state/sysops/report.json（collect timer 每小时一刷，
-- 这里 30 秒重读一次文件，两层刷新解耦——widget 自己不做任何检查）。
-- 另负责执行完成的一次性通知：queue.json 里 job.notified == false 的
-- done/failed 任务 → noctalia.notify / notifyError + 回标 notified。

local REPORT = "~/.local/state/sysops/report.json"
local QUEUE = "~/.local/state/sysops/queue.json"
local SYSOPS_BIN = "/etc/profiles/per-user/kun/bin/sysops-ctl"

local function readJson(path)
  local raw = noctalia.readFile(path)
  if not raw then
    return nil
  end
  local ok, decoded = pcall(noctalia.json.decode, raw)
  if ok and type(decoded) == "table" then
    return decoded
  end
  return nil
end

-- 执行完成/失败 → 桌面通知（每个任务只发一次，回标 notified）
local function notifyTransitions()
  local q = readJson(QUEUE)
  if not q or type(q.proposals) ~= "table" then
    return
  end
  for _, p in q.proposals do
    local job = p.job
    if type(job) == "table" and job.notified == false and (job.status == "done" or job.status == "failed") then
      local title = (job.status == "done" and "运维方案执行完成" or "运维方案执行失败") .. "：" .. (p.title or p.id)
      if job.status == "done" then
        noctalia.notify(title, job.result or "")
      else
        noctalia.notifyError(title, job.result or "详见面板执行日志")
      end
      local pid = p.id -- 每次迭代新局部，避免闭包共享循环变量
      noctalia.runAsync({ SYSOPS_BIN, "job", pid, "--mark-notified" })
    end
  end
end

-- 严重问题主动告警（Q17）：新出现的 crit 问题一次性 notifyError，
-- 已告警指纹存 pluginDataDir/alerts.json（不打扰：warn/info 只进报告）。
local function notifyCrits()
  local r = readJson(REPORT)
  if not r then
    return
  end
  local path = noctalia.pluginDataDir() .. "/alerts.json"
  local seen = {}
  local raw = noctalia.readFile(path)
  if raw then
    local ok, decoded = pcall(noctalia.json.decode, raw)
    if ok and type(decoded) == "table" then
      seen = decoded
    end
  end
  local changed = false
  for _, it in (r.issues or {}) do
    if it.severity == "crit" and not seen[it.id] then
      noctalia.notifyError("运维助手发现严重问题", it.title or it.id)
      seen[it.id] = true
      changed = true
    end
  end
  if changed then
    noctalia.writeFile(path, noctalia.json.encode(seen))
  end
end

local function render()
  barWidget.setGlyph(noctalia.getConfig("glyph"))
  local r = readJson(REPORT)
  if not r then
    barWidget.setText("运维 ?")
    barWidget.setTooltip("暂无体检数据：先跑 sysops-ctl collect")
    return
  end
  local s = r.summary or {}
  local crit, warn = s.crit or 0, s.warn or 0
  if crit > 0 then
    barWidget.setText("✗ " .. tostring(crit))
  elseif warn > 0 then
    barWidget.setText("⚠ " .. tostring(warn))
  else
    barWidget.setText("✓")
  end
  local tip = { ("采集于 %s（%s检查）"):format(r.collected_at or "?", r.full and "深" or "浅") }
  for _, it in (r.issues or {}) do
    table.insert(tip, ("%s  %s"):format(it.severity or "?", it.title or ""))
  end
  if #tip == 1 then
    table.insert(tip, "未发现问题")
  end
  barWidget.setTooltip(table.concat(tip, "\n"))
end

function update()
  noctalia.setUpdateInterval(30000)
  render()
  notifyTransitions()
  notifyCrits()
end

function onClick()
  noctalia.togglePanel("kun/sysops:ops")
  render()
end
