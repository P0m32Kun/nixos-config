--!nonstrict
-- agent-usage 明细面板：每家 harness 一张卡片。只读采集层 JSON，30 秒重渲染。

local STATE_DIR = "~/.local/state/agent-usage"
local AGENTS = { "zcode", "pi", "codex", "hermes" }

-- 格式化工具必须定义在展示配置之前：STAT_DEFS 的闭包按词法作用域
-- 捕获，挪到后面会捕获到 nil 的全局名（实测报 attempt to call a nil value）
local function fmt(n)
  if n >= 1e9 then
    return string.format("%.1fB", n / 1e9)
  elseif n >= 1e6 then
    return string.format("%.1fM", n / 1e6)
  elseif n >= 1e3 then
    return string.format("%.0fK", n / 1e3)
  end
  return tostring(math.floor(n))
end

local function fmtCost(c)
  if c and c > 0 then
    return ("¥%.2f"):format(c)
  end
  return "-"
end

-- ===== 展示配置（改这里即热重载，无需 rebuild）=====
-- 卡片上显示哪些统计、按什么顺序排列。可用键：
--   today       今日 in / out
--   cache       今日 cache 读
--   week        7 天 input
--   month_in    本月 input
--   month_cost  本月成本（¥）
--   total_in    累计 input
--   cost_today  今日成本（¥）
--   cost_total  累计成本（¥）
local CARD_STATS = { "today", "cache", "month_in", "month_cost", "cost_total" }
local SHOW_MODELS = true -- 卡片底部的模型分布行
local SHOW_SPARKLINE = true -- 卡片底部的 30 天趋势线

local STAT_DEFS = {
  today = { b = "today", label = "今日 in/out", v = function(x)
    return ("%s / %s"):format(fmt(x.input), fmt(x.output))
  end },
  cache = { b = "today", label = "今日 cache 读", v = function(x)
    return fmt(x.cache_read)
  end },
  week = { b = "week", label = "7 天 input", v = function(x)
    return fmt(x.input)
  end },
  month_in = { b = "month", label = "本月 input", v = function(x)
    return fmt(x.input)
  end },
  month_cost = { b = "month", label = "本月成本", v = function(x)
    return fmtCost(x.cost_cny)
  end },
  total_in = { b = "total", label = "累计 input", v = function(x)
    return fmt(x.input)
  end },
  cost_today = { b = "today", label = "今日成本", v = function(x)
    return fmtCost(x.cost_cny)
  end },
  cost_total = { b = "total", label = "累计成本", v = function(x)
    return fmtCost(x.cost_cny)
  end },
}

local function readAgent(name)
  local raw = noctalia.readFile(("%s/%s.json"):format(STATE_DIR, name))
  if not raw then
    return nil
  end
  return noctalia.json.decode(raw)
end

-- by_day 是新→旧排序，sparkline 要旧→新；归一化到 0-1
local function sparkline(r)
  local days = r.by_day or {}
  if #days < 2 then
    return nil
  end
  local asc, max = {}, 0
  for i = #days, 1, -1 do
    local v = days[i].input or 0
    max = math.max(max, v)
    table.insert(asc, v)
  end
  if max <= 0 then
    return nil
  end
  local values = {}
  for _, v in asc do
    table.insert(values, v / max)
  end
  return values
end

local function modelLine(r)
  local parts = {}
  for i, m in r.by_model or {} do
    if i > 3 then
      break
    end
    table.insert(parts, ("%s(%s)"):format(m.model, fmt(m.input)))
  end
  return table.concat(parts, " · ")
end

local function stat(label, value, color)
  return ui.column({ gap = 2 }, {
    ui.label({ text = label, fontSize = 11, color = "on_surface_variant" }),
    ui.label({ text = value, fontSize = 14, fontWeight = "medium", color = color or "on_surface" }),
  })
end

local function agentCard(name, r)
  if not r.available then
    return ui.column({ gap = 6, fill = "surface", radius = 10, padding = 12 }, {
      ui.row({ align = "center", justify = "space_between" }, {
        ui.label({ text = name, fontSize = 15, fontWeight = "bold", color = "on_surface" }),
        ui.label({ text = "不可用", fontSize = 12, color = "on_surface_variant" }),
      }),
      ui.label({ text = r.reason or "无数据", fontSize = 12, color = "on_surface_variant" }),
    })
  end
  local stats = {}
  for _, key in CARD_STATS do
    local def = STAT_DEFS[key]
    if def then
      local bucket = r[def.b] or {}
      table.insert(stats, stat(def.label, def.v(bucket)))
    end
  end
  local children = {
    ui.row({ align = "center", justify = "space_between", gap = 8 }, {
      ui.label({ text = name, fontSize = 15, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
      ui.label({ text = ("%d 次请求/今日"):format((r.today or {}).requests or 0), fontSize = 11, color = "primary" }),
    }),
  }
  if #stats > 0 then
    table.insert(children, ui.row({ gap = 20, align = "start" }, stats))
  end
  if SHOW_MODELS and #(r.by_model or {}) > 0 then
    table.insert(children, ui.label({ text = modelLine(r), fontSize = 11, color = "on_surface_variant" }))
  end
  if SHOW_SPARKLINE then
    local line = sparkline(r)
    if line then
      table.insert(children, ui.graph({ values = line, width = 400, height = 36, color = "primary" }))
    end
  end
  return ui.column({ gap = 10, fill = "surface", radius = 10, padding = 12 }, children)
end

local function render()
  local cards = {}
  local collected = ""
  local notes = {}
  for _, name in AGENTS do
    local r = readAgent(name)
    if r then
      collected = r.collected_at or ""
      if r.cost_note then
        table.insert(notes, name .. "：" .. r.cost_note)
      end
      table.insert(cards, agentCard(name, r))
    end
  end
  if #cards == 0 then
    table.insert(cards, ui.label({ text = "暂无数据：先跑 agent-usage-collect", color = "on_surface_variant" }))
  end
  panel.render(ui.column({ flexGrow = 1, gap = 12 }, {
    ui.row({ align = "center", justify = "space_between", gap = 8 }, {
      ui.label({ text = "Agent 用量", fontSize = 16, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
      ui.button({ glyph = "close", onClick = "onCloseClicked" }),
    }),
    ui.scroll({ flexGrow = 1, gap = 12 }, cards),
    ui.label({
      text = "采集于 " .. collected .. " · timer 每 15 分钟刷新 · " .. table.concat(notes, "；"),
      fontSize = 10,
      color = "on_surface_variant",
    }),
  }))
end

function onOpen(_context)
  render()
end

function update()
  noctalia.setUpdateInterval(30000)
  render()
end

function onCloseClicked()
  panel.close()
end
