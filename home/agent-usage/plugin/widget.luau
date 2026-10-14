--!nonstrict
-- agent-usage 顶栏组件：Σ今日 input tokens + 悬浮明细，点击开面板。
-- 数据来自 ~/.local/state/agent-usage/<agent>.json（采集层 15 分钟一刷，
-- 这里 30 秒重读一次文件，两层刷新解耦——widget 自己不做任何聚合计算）。

local STATE_DIR = "~/.local/state/agent-usage"
local AGENTS = { "zcode", "pi", "codex", "hermes" }

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

local function readAgent(name)
  local raw = noctalia.readFile(("%s/%s.json"):format(STATE_DIR, name))
  if not raw then
    return nil
  end
  return noctalia.json.decode(raw)
end

local function render()
  barWidget.setGlyph(noctalia.getConfig("glyph"))
  local totalIn, any = 0, false
  local tooltip = {}
  for _, name in AGENTS do
    local r = readAgent(name)
    if r then
      any = true
      if r.available and r.today then
        totalIn += r.today.input or 0
        table.insert(
          tooltip,
          string.format("%s  今日 %s in / %s out / %s cache", name, fmt(r.today.input), fmt(r.today.output), fmt(r.today.cache_read))
        )
      else
        table.insert(tooltip, ("%s  %s"):format(name, r.reason or "不可用"))
      end
    end
  end
  if not any then
    barWidget.setText("--")
    barWidget.setTooltip("暂无用量数据：先跑 agent-usage-collect")
    return
  end
  barWidget.setText(fmt(totalIn))
  barWidget.setTooltip(table.concat(tooltip, "\n"))
end

function update()
  noctalia.setUpdateInterval(30000)
  render()
end

function onClick()
  noctalia.togglePanel("kun/agent-usage:detail")
  render()
end
