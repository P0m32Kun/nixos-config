--!nonstrict
-- agent-usage 明细面板：每家 harness 一张卡片，只读采集层 JSON。
-- 展示页纯展示；右上角齿轮进入设置页（Agent 显隐 / 统计项勾选），
-- 卡片可拖拽排序。选择持久化在 ~/.local/state/agent-usage/panel-config.json
-- （放 state 目录而非插件目录：插件的 seed 部署每次 rebuild 会覆盖）。
--
-- 面板能力边界（noctalia 插件面板为 layer-shell 表面）：大小固定
-- （plugin.toml 声明，支持 "fill"），位置由宿主管理（center/auto），
-- 不支持鼠标拖动、自由缩放与窗口式吸附。

local STATE_DIR = "~/.local/state/agent-usage"
local CONFIG_PATH = "~/.local/state/agent-usage/panel-config.json"
local AGENTS = { "zcode", "pi", "codex", "hermes" }
local DRAG_TYPE = "agent-card"

-- 主题色 → 不透明 hex。实测 fill 的坑：`角色/alpha` 后缀与 8 位 hex 都被
-- 静默忽略（面板透出壁纸），只有纯角色名或 6 位 hex 会真正涂色——
-- noctalia.getColor 返回的正是 6 位 #RRGGBB，原样使用即为实心。
local function opaque(role, fallback)
  local hex = noctalia.getColor(role)
  if type(hex) == "string" and #hex >= 7 then
    return hex:sub(1, 7)
  end
  return fallback
end

-- 格式化工具必须定义在 STAT_DEFS 之前（词法作用域，靠后声明闭包会捕获 nil）
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

-- 可选统计项（设置页勾选）
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
local STAT_ORDER = { "today", "cache", "week", "month_in", "month_cost", "total_in", "cost_today", "cost_total" }

-- ============ 配置（持久化） ============

local function defaultConfig()
  return {
    stats = { "today", "cache", "month_in", "month_cost", "cost_total" },
    show_models = true,
    show_sparkline = true,
    enabled = { zcode = true, pi = true, codex = true, hermes = true },
    order = { "zcode", "pi", "codex", "hermes" },
  }
end

local config = defaultConfig()
local inSettings = false -- 面板当前页：false=展示页，true=设置页（不持久化）

local function loadConfig()
  local raw = noctalia.readFile(CONFIG_PATH)
  if not raw then
    return
  end
  local ok, decoded = pcall(noctalia.json.decode, raw)
  if not ok or type(decoded) ~= "table" then
    return
  end
  if type(decoded.stats) == "table" then
    config.stats = decoded.stats
  end
  if decoded.show_models ~= nil then
    config.show_models = decoded.show_models == true or decoded.show_models == "true"
  end
  if decoded.show_sparkline ~= nil then
    config.show_sparkline = decoded.show_sparkline == true or decoded.show_sparkline == "true"
  end
  if type(decoded.order) == "table" then
    config.order = decoded.order
  end
  if type(decoded.enabled) == "table" then
    for _, name in AGENTS do
      if decoded.enabled[name] ~= nil then
        config.enabled[name] = decoded.enabled[name] == true or decoded.enabled[name] == "true"
      end
    end
  end
end

local function saveConfig()
  noctalia.writeFile(CONFIG_PATH, noctalia.json.encode(config))
end

-- 全量顺序（含隐藏的 agent）；config.order 决定顺序，新 agent 追加尾部
local function agentOrder()
  local known = {}
  for _, a in AGENTS do
    known[a] = true
  end
  local seen, out = {}, {}
  for _, name in config.order do
    if known[name] and seen[name] == nil then
      seen[name] = true
      table.insert(out, name)
    end
  end
  for _, name in AGENTS do
    if seen[name] == nil then
      table.insert(out, name)
    end
  end
  return out
end

local function visibleAgents()
  local out = {}
  for _, name in agentOrder() do
    if config.enabled[name] ~= false then
      table.insert(out, name)
    end
  end
  return out
end

-- value 是 "agents:<index>"（插入区）或 "agents"（列表整体，追加尾部）
function onAgentDropped(payload, value)
  local indexText = string.match(value, "^agents:(%d+)$")
  local insertAt = indexText and tonumber(indexText) or #config.order + 1
  local fromIdx = nil
  for i, name in config.order do
    if name == payload then
      fromIdx = i
      break
    end
  end
  if fromIdx == nil then
    return
  end
  table.remove(config.order, fromIdx)
  if fromIdx < insertAt then
    insertAt -= 1
  end
  insertAt = math.max(1, math.min(insertAt, #config.order + 1))
  table.insert(config.order, insertAt, payload)
  saveConfig()
  render()
end

-- ============ 渲染 ============

local function readAgent(name)
  local raw = noctalia.readFile(("%s/%s.json"):format(STATE_DIR, name))
  if not raw then
    return nil
  end
  return noctalia.json.decode(raw)
end

-- by_day 新→旧，sparkline 要旧→新；归一化 0-1
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

local function grip(key)
  return ui.dragSource({
    key = "grip-" .. key,
    dragType = DRAG_TYPE,
    payload = key,
    previewAncestor = 2, -- 幽灵预览整张卡片（grip→header行→卡片列）
    liftFromLayout = true,
    width = 22,
    height = 22,
    align = "center",
    justify = "center",
    tooltip = "拖动调整顺序",
  }, {
    ui.glyph({ name = "menu-2", size = 14, color = "on_surface_variant" }),
  })
end

local function insertionZone(index)
  return ui.dropZone({
    key = "gap-" .. index,
    accepts = { DRAG_TYPE },
    value = "agents:" .. index,
    onDrop = "onAgentDropped",
    height = 3,
    radius = 6,
    expandOnDrag = true,
    hitSlop = 28,
  })
end

local function agentCard(name, r)
  local header = {
    grip(name),
    ui.label({ text = name, fontSize = 15, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
    ui.label({ text = ("%d 次请求/今日"):format((r.today or {}).requests or 0), fontSize = 11, color = "primary" }),
  }
  local children = { ui.row({ align = "center", justify = "space_between", gap = 8 }, header) }

  if not r.available then
    table.insert(children, ui.label({ text = r.reason or "无数据", fontSize = 12, color = "on_surface_variant" }))
    return ui.column({ gap = 6, fill = "surface", radius = 10, padding = 12 }, children)
  end

  local stats = {}
  for _, key in config.stats do
    local def = STAT_DEFS[key]
    if def then
      local bucket = r[def.b] or {}
      table.insert(stats, stat(def.label, def.v(bucket)))
    end
  end
  if #stats > 0 then
    table.insert(children, ui.row({ gap = 20, align = "start" }, stats))
  end
  if config.show_models and #(r.by_model or {}) > 0 then
    table.insert(children, ui.label({ text = modelLine(r), fontSize = 11, color = "on_surface_variant" }))
  end
  if config.show_sparkline then
    local line = sparkline(r)
    if line then
      table.insert(children, ui.graph({ values = line, width = 400, height = 36, color = "primary" }))
    end
  end
  return ui.column({ gap = 10, fill = opaque("surface_variant", "#2c2c3a"), radius = 10, padding = 12 }, children)
end

-- ============ 设置页 ============

local function toggleRow(label, checked, onChange, hint)
  local left = { ui.label({ text = label, fontSize = 12, color = "on_surface", flexGrow = 1 }) }
  if hint then
    table.insert(left, ui.label({ text = hint, fontSize = 10, color = "on_surface_variant" }))
  end
  return ui.row({ align = "center", justify = "space_between", gap = 8 }, {
    ui.row({ gap = 6, align = "center", flexGrow = 1 }, left),
    ui.toggle({ checked = checked, onChange = onChange, controlSize = "sm" }),
  })
end

local function setStat(key, v)
  local on = v == true or v == "true"
  local new = {}
  if on then
    -- 勾选：按 STAT_ORDER 的既有顺序插回
    local inList = {}
    for _, k in config.stats do
      inList[k] = true
    end
    inList[key] = true
    for _, k in STAT_ORDER do
      if inList[k] then
        table.insert(new, k)
      end
    end
  else
    for _, k in config.stats do
      if k ~= key then
        table.insert(new, k)
      end
    end
  end
  config.stats = new
  saveConfig()
  render()
end

local function sectionTitle(text)
  return ui.label({ text = text, fontSize = 12, fontWeight = "bold", color = "on_surface_variant" })
end

local function settingsView()
  local agentToggles = {}
  for _, name in agentOrder() do
    table.insert(agentToggles, toggleRow(name, config.enabled[name] ~= false, function(v)
      config.enabled[name] = v == true or v == "true"
      saveConfig()
      render()
    end))
  end

  local statToggles = {}
  for _, key in STAT_ORDER do
    table.insert(statToggles, toggleRow(STAT_DEFS[key].label, table.find(config.stats, key) ~= nil, function(v)
      setStat(key, v)
    end))
  end
  table.insert(statToggles, toggleRow("模型分布行", config.show_models, function(v)
    config.show_models = v == true or v == "true"
    saveConfig()
    render()
  end))
  table.insert(statToggles, toggleRow("30 天趋势线", config.show_sparkline, function(v)
    config.show_sparkline = v == true or v == "true"
    saveConfig()
    render()
  end))

  return ui.column({ gap = 12, flexGrow = 1 }, {
    sectionTitle("显示哪些 Agent"),
    ui.column({ gap = 6, fill = opaque("surface_variant", "#2c2c3a"), radius = 10, padding = 12 }, agentToggles),
    sectionTitle("卡片统计项"),
    ui.column({ gap = 6, fill = opaque("surface_variant", "#2c2c3a"), radius = 10, padding = 12 }, statToggles),
    ui.label({
      text = "顺序：回到展示页拖动卡片左侧把手调整",
      fontSize = 10,
      color = "on_surface_variant",
    }),
    ui.button({ text = "完成", variant = "primary", onClick = "onDoneClicked", controlSize = "md" }),
  })
end

-- ============ 主渲染 ============

function render()
  loadConfigOnce()
  local body
  local collected, notes = "", {}

  if inSettings then
    body = ui.scroll({ flexGrow = 1, gap = 4 }, { settingsView() })
  else
    local cards = {}
    for _, name in visibleAgents() do
      local r = readAgent(name)
      if r then
        collected = r.collected_at or ""
        if r.cost_note then
          table.insert(notes, name .. "：" .. r.cost_note)
        end
        cards[#cards + 1] = insertionZone(#cards + 1)
        cards[#cards + 1] = agentCard(name, r)
      end
    end
    cards[#cards + 1] = insertionZone(#cards + 1)
    if #cards == 1 then
      table.insert(cards, ui.label({ text = "暂无数据：先跑 agent-usage-collect", color = "on_surface_variant" }))
    end
    body = ui.scroll({ flexGrow = 1, gap = 8 }, {
      ui.dropZone({ accepts = { DRAG_TYPE }, value = "agents", onDrop = "onAgentDropped", gap = 8 }, cards),
    })
  end

  panel.render(ui.column({ flexGrow = 1, gap = 12, fill = opaque("surface", "#1e1e2e"), radius = 16, padding = 14 }, {
    ui.row({ align = "center", justify = "space_between", gap = 8 }, {
      ui.label({
        text = inSettings and "Agent 用量 · 设置" or "Agent 用量",
        fontSize = 16,
        fontWeight = "bold",
        color = "on_surface",
        flexGrow = 1,
      }),
      ui.button({
        glyph = inSettings and "arrow-left" or "settings",
        tooltip = inSettings and "返回展示" or "设置",
        onClick = "onToggleSettings",
      }),
      ui.button({ glyph = "close", onClick = "onCloseClicked" }),
    }),
    body,
    ui.label({
      text = "采集于 " .. collected .. " · timer 每 15 分钟刷新 · " .. table.concat(notes, "；"),
      fontSize = 10,
      color = "on_surface_variant",
    }),
  }))
end

local configLoaded = false
function loadConfigOnce()
  if not configLoaded then
    configLoaded = true
    loadConfig()
  end
end

function onToggleSettings()
  inSettings = not inSettings
  render()
end

function onDoneClicked()
  inSettings = false
  render()
end

function onOpen(_context)
  loadConfigOnce()
  render()
end

function update()
  noctalia.setUpdateInterval(30000)
  render()
end

function onCloseClicked()
  panel.close()
end
