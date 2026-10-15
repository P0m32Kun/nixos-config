--!nonstrict
-- sysops 运维面板 v2.1（紧凑专业风）。
-- 首屏布局（Q5）：待审批框 → 对话（流在上、输入框在下）→ 体检问题（前 3 条）
-- → 工具折叠行（深报告/已忽略/系统操作）→ 已处理历史（Q1：折叠不占位）。
-- 即时反馈（Q2）：动作的 runAsync 完成回调里 render()，1 秒内卡片变状态；
-- 批准/拒绝/发起弹 noctalia 通知。执行串行化（Q3）见 sysops-ctl dispatch-next。
-- 面板能力边界同先例：layer-shell 表面，大小固定，宿主管理位置。

local SYSOPS_BIN = noctalia.getConfig("sysops_bin") or "/etc/profiles/per-user/kun/bin/sysops-ctl"
local REPORT = "~/.local/state/sysops/report.json"
local QUEUE = "~/.local/state/sysops/queue.json"
local CHAT = "~/.local/state/sysops/chat.json"
local DEEP_REPORT = "~/.local/state/sysops/deep-report.md"

local showLogs = nil -- 展开执行日志的方案 id
local showHistory = false -- 已处理历史是否展开（Q1）
local showAllIssues = false -- 体检问题是否展开全部（Q5）
local showHandled = false -- 修复中/已修复的问题是否展开
local showEarly = false -- 更早的对话消息是否展开（Q5）
local showDeep = false -- 深度报告是否展开
local showIgnored = false -- 已忽略问题是否展开
local showOps = false -- 系统操作是否展开
local rollbackOpen = false -- 回滚代际列表是否展开
local chatText = "" -- 对话输入框当前文本（非受控输入的镜像）
local collecting = false -- 体检进行中（Q2 同款过程态）
local diagnosing = {} -- issue_id → true：诊断进行中（方案产出后清除）
local fixState = {} -- issue_id → 最新修复状态（render 时由方案/任务联接重建）

local RISK_LABEL = { low = "低", medium = "中", high = "高" }
local STATUS_LABEL = {
  pending = "待审批",
  approved = "已批准·排队中",
  queued = "排队中",
  dispatched = "已派发·启动中",
  running = "执行中",
  done = "已完成",
  failed = "已失败",
  rejected = "已拒绝",
}

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

-- 所有动作回 sysops-ctl；完成即重绘（Q2 即时反馈的关键）
local function ctl(...)
  noctalia.runAsync({ SYSOPS_BIN, ... }, function()
    render()
  end)
end

-- 体检：点击即进过程态（按钮置灰 + 摘要行显示进行中），完成通知带结果
local function collectNow()
  if collecting then
    return
  end
  collecting = true
  render()
  noctalia.runAsync({ SYSOPS_BIN, "collect", "--full" }, function()
    collecting = false
    local rr = readJson(REPORT)
    local ss = (rr or {}).summary or {}
    noctalia.notify(
      "体检完成",
      ("crit %d / warn %d / info %d"):format(ss.crit or 0, ss.warn or 0, ss.info or 0))
    render()
  end)
end

-- 主题色 → 不透明 hex。实测 fill 的坑：`角色/alpha` 后缀与 8 位 hex 都被
-- 静默忽略，只有纯角色名或 6 位 hex 会真正涂色。
local function opaque(role, fallback)
  local hex = noctalia.getColor(role)
  if type(hex) == "string" and #hex >= 7 then
    return hex:sub(1, 7)
  end
  return fallback
end

local function sectionTitle(text, extra)
  return ui.row({ align = "center", justify = "space_between", gap = 6 }, {
    ui.label({ text = text, fontSize = 10, fontWeight = "bold", color = "on_surface_variant" }),
    ui.label({ text = extra or "", fontSize = 9, color = "on_surface_variant" }),
  })
end

local function card(children, gap)
  return ui.column({ gap = gap or 4, fill = opaque("surface_variant", "#2c2c3a"), radius = 8, padding = 8 }, children)
end

-- ============ 方案卡片（紧凑） ============

local function proposalCard(p, queuePos)
  local children = {}
  -- 状态以 job 进度为准（方案自身 status 停在 approved）
  local status = p.status or "pending"
  local job = p.job or {}
  if job.status == "queued" or job.status == "dispatched" or job.status == "running"
    or job.status == "done" or job.status == "failed" then
    status = job.status
  end
  local statusText = STATUS_LABEL[status] or status
  if job.status == "queued" and queuePos then
    statusText = ("排队中（%d/%d）"):format(queuePos.i, queuePos.n)
  end

  table.insert(children, ui.row({ align = "center", gap = 6 }, {
    ui.label({
      text = p.title or p.id,
      fontSize = 12,
      fontWeight = "bold",
      color = "on_surface",
      flexGrow = 1,
    }),
    ui.label({ text = RISK_LABEL[p.risk] or "", fontSize = 9, color = "primary" }),
    ui.label({ text = statusText, fontSize = 9, color = "primary" }),
  }))

  -- 将要执行的命令（审批即批这些，原样列出）
  local steps = {}
  for _, s in p.steps or {} do
    table.insert(steps, ui.label({ text = "› " .. (s.cmd or ""), fontSize = 10, color = "on_surface" }))
  end
  if #steps > 0 then
    table.insert(children, ui.column({ gap = 1 }, steps))
  end
  if p.diff and p.diff ~= "" then
    table.insert(children, ui.markdown({ text = "```diff\n" .. p.diff .. "\n```" }))
  end

  if status == "pending" then
    local pid = p.id -- 每次迭代新局部，闭包不共享循环变量
    local title = p.title or p.id
    table.insert(children, ui.row({ gap = 6, align = "center" }, {
      ui.button({ text = "批准执行", variant = "primary", controlSize = "sm", onClick = function()
        noctalia.notify("已批准，进入执行队列", title)
        ctl("decide", pid, "--approve")
      end }),
      ui.button({ text = "拒绝", controlSize = "sm", onClick = function()
        noctalia.notify("已拒绝", title)
        ctl("decide", pid, "--reject")
      end }),
    }))
  elseif status == "done" or status == "failed" then
    if job.result and job.result ~= "" then
      table.insert(children, ui.label({ text = "结果：" .. job.result, fontSize = 10, color = "on_surface" }))
    end
    local pid = p.id
    table.insert(children, ui.button({
      text = showLogs == pid and "收起日志" or "执行日志",
      controlSize = "sm",
      onClick = function()
        showLogs = showLogs == pid and nil or pid
        render()
      end,
    }))
    if showLogs == pid and p.log_tail and p.log_tail ~= "" then
      table.insert(children, ui.label({ text = p.log_tail, fontSize = 9, color = "on_surface_variant" }))
    end
  end
  return card(children)
end

-- ============ 问题卡片（紧凑） ============

local function issueCard(it)
  local children = {
    ui.row({ align = "center", gap = 6 }, {
      ui.label({ text = "[" .. (it.severity or "?") .. "]", fontSize = 10, color = "primary" }),
      ui.label({ text = it.title or it.id, fontSize = 12, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
    }),
  }
  if it.detail and it.detail ~= "" then
    table.insert(children, ui.label({ text = it.detail, fontSize = 10, color = "on_surface_variant" }))
  end
  -- 修复状态可见性（v2.1 反馈）：修过的问题必须显示进展，避免"看起来没人管"
  local fix = fixState[it.id]
  if diagnosing[it.id] then
    table.insert(children, ui.label({ text = "修复状态：诊断中…（hermes 正在产出方案）", fontSize = 10, color = "primary" }))
  elseif fix then
    table.insert(children, ui.label({ text = "修复状态：" .. fix, fontSize = 10, color = "primary" }))
  end
  local iid = it.id -- 每次迭代新局部
  local mainBtn
  if it.quick_fix and type(it.quick_fix.commands) == "table" then
    for _, c in it.quick_fix.commands do
      table.insert(children, ui.label({ text = "› " .. c, fontSize = 10, color = "on_surface" }))
    end
    mainBtn = ui.button({ text = "修复", controlSize = "sm", onClick = function()
      noctalia.notify("已生成方案", it.title or iid)
      ctl("propose", "--from-issue", iid)
    end })
  else
    mainBtn = ui.button({
      text = diagnosing[iid] and "诊断中…" or "发起修复",
      controlSize = "sm",
      enabled = not diagnosing[iid],
      tooltip = "hermes 诊断出方案进待审批框",
      onClick = function()
        diagnosing[iid] = true
        noctalia.notify("已发起诊断", it.title or iid)
        ctl("diagnose", iid)
      end,
    })
  end
  table.insert(children, ui.row({ gap = 6, align = "center" }, {
    mainBtn,
    ui.button({ text = "本轮忽略", controlSize = "sm", onClick = function()
      ctl("ignore", iid, "--round")
    end }),
    ui.button({ text = "永久忽略", controlSize = "sm", onClick = function()
      ctl("ignore", iid, "--permanent")
    end }),
  }))
  return card(children)
end

-- ============ 主渲染 ============

function render()
  local r = readJson(REPORT)
  local q = readJson(QUEUE)
  local s = (r or {}).summary or {}
  local proposals = (q or {}).proposals or {}

  -- 队列位置（Q3：排队 N/M）
  local nonTerminal = {}
  for _, p in proposals do
    local st = (p.job or {}).status
    if st == "queued" or st == "dispatched" or st == "running" then
      table.insert(nonTerminal, p)
    end
  end
  table.sort(nonTerminal, function(a, b)
    return ((a.job or {}).created_at or "") < ((b.job or {}).created_at or "")
  end)
  local queuePos = {}
  for i, p in nonTerminal do
    queuePos[p.id] = { i = i, n = #nonTerminal }
  end

  local pending, processed = {}, {}
  for _, p in proposals do
    if p.status == "pending" then
      table.insert(pending, p)
    else
      table.insert(processed, p)
    end
    -- 诊断产出的方案已到 → 清除该问题的"诊断中"过程态
    if p.issue_id and diagnosing[p.issue_id] then
      diagnosing[p.issue_id] = nil
    end
  end

  -- 修复状态图谱：issue_id → 最新方案/执行状态（问题卡显示进展用）
  fixState = {}
  local fixAt = {}
  for _, p in proposals do
    if p.issue_id then
      local at = p.created_at or ""
      if not fixAt[p.issue_id] or at >= fixAt[p.issue_id] then
        local label
        local job = p.job or {}
        if job.status == "done" then
          label = "已修复 · 待下轮体检复核"
        elseif job.status == "failed" then
          label = "上次修复失败，可重新发起"
        elseif job.status == "queued" or job.status == "dispatched" or job.status == "running" then
          label = "修复执行中…"
        elseif p.status == "pending" then
          label = "修复方案已在待审批框"
        elseif p.status == "rejected" then
          label = "方案已拒绝，可重新发起"
        end
        if label then
          fixState[p.issue_id] = label
          fixAt[p.issue_id] = at
        end
      end
    end
  end

  local header = ui.row({ align = "center", justify = "space_between", gap = 6 }, {
    ui.label({ text = "系统运维", fontSize = 15, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
    ui.button({
      text = collecting and "体检中…" or "立即体检",
      controlSize = "sm",
      enabled = not collecting,
      tooltip = "深检查（含网络类检查）",
      onClick = function()
        collectNow()
      end,
    }),
    ui.button({ glyph = "close", controlSize = "sm", onClick = function()
      panel.close()
    end }),
  })

  local summaryText
  if collecting then
    summaryText = "⟳ 体检采集中…（深检查约十几秒，完成后弹通知）"
  elseif r then
    summaryText = ("%s（%s）· crit %d / warn %d / info %d · 执行队列 %d"):format(
      r.collected_at or "?", r.full and "深" or "浅", s.crit or 0, s.warn or 0, s.info or 0, #nonTerminal)
  else
    summaryText = "暂无体检数据——点「立即体检」或等每小时定时采集"
  end

  -- ① 待审批框：只放 pending（Q1）
  local pendingNodes = {}
  for _, p in pending do
    table.insert(pendingNodes, proposalCard(p, nil))
  end
  if #pendingNodes == 0 then
    table.insert(pendingNodes, ui.label({
      text = "（空）问题卡片上的「修复」或「发起修复」会把方案送到这里",
      fontSize = 10,
      color = "on_surface_variant",
    }))
  end

  -- ② 对话：流在上（最近 4 条，Q5），输入框在下
  local chat = readJson(CHAT)
  local msgs = (chat and chat.messages) or {}
  local chatNodes = {}
  local startIdx = showEarly and 1 or math.max(1, #msgs - 3)
  if #msgs > 4 then
    table.insert(chatNodes, ui.button({
      text = showEarly and "收起更早" or ("更早 (%d)"):format(#msgs - 4),
      controlSize = "sm",
      onClick = function()
        showEarly = not showEarly
        render()
      end,
    }))
  end
  for i = startIdx, #msgs do
    local m = msgs[i]
    if m.role == "assistant" then
      table.insert(chatNodes, ui.markdown({ text = m.text or "" }))
    else
      table.insert(chatNodes, ui.row({ justify = "end" }, {
        ui.column({ fill = opaque("surface", "#1e1e2e"), radius = 6, padding = 6, maxWidth = 400 }, {
          ui.label({ text = m.text or "", fontSize = 11, color = "on_surface", maxWidth = 390 }),
        }),
      }))
    end
  end
  if #msgs == 0 then
    table.insert(chatNodes, ui.label({
      text = "自由提问系统问题（只读诊断；修复会以方案进入待审批框）",
      fontSize = 10,
      color = "on_surface_variant",
    }))
  end
  if #msgs > 0 and msgs[#msgs].role == "user" then
    table.insert(chatNodes, ui.label({ text = "助手思考中…", fontSize = 10, color = "primary" }))
  end
  table.insert(chatNodes, ui.row({ align = "center", gap = 6 }, {
    ui.input({
      key = "sysops-chat-input",
      placeholder = "向运维助手提问（Enter 发送）…",
      fontSize = 11,
      flexGrow = 1,
      submitOnEnter = true,
      onChange = function(text)
        chatText = text
      end,
      onSubmit = function(text)
        if text and text ~= "" then
          ctl("chat", text)
        end
      end,
    }),
    ui.button({ text = "发送", variant = "primary", controlSize = "sm", onClick = function()
      if chatText ~= "" then
        ctl("chat", chatText)
      end
    end }),
  }))

  -- ③ 体检问题：主列表只放"需要行动"的问题（未处理 + 修复失败/被拒）；
  --    诊断中/方案就绪/执行中/已修复待复核的收进折叠区（Q1 同款哲学：
  --    处理中的不占待办位，但可追溯）
  local allIssues = (r and r.issues) or {}
  local actionable, handled = {}, {}
  for _, it in allIssues do
    local fix = fixState[it.id]
    local inFlight = diagnosing[it.id]
      or fix == "修复方案已在待审批框"
      or fix == "修复执行中…"
      or fix == "已修复 · 待下轮体检复核"
    if inFlight then
      table.insert(handled, it)
    else
      table.insert(actionable, it) -- 未处理，或上次修复失败/方案被拒（带状态行）
    end
  end
  local issueNodes = {}
  local limit = showAllIssues and #actionable or math.min(3, #actionable)
  for i = 1, limit do
    table.insert(issueNodes, issueCard(actionable[i]))
  end
  if #actionable == 0 then
    table.insert(issueNodes, ui.label({
      text = #handled > 0 and ("（无待处理问题，%d 项修复中/已修复见下方）"):format(#handled)
        or (r and "未发现问题" or "等待首次体检"),
      fontSize = 10,
      color = "on_surface_variant",
    }))
  elseif #actionable > 3 then
    table.insert(issueNodes, ui.button({
      text = showAllIssues and "收起" or ("更多 (%d)"):format(#actionable - 3),
      controlSize = "sm",
      onClick = function()
        showAllIssues = not showAllIssues
        render()
      end,
    }))
  end
  if #handled > 0 then
    table.insert(issueNodes, ui.button({
      text = showHandled and "收起" or ("修复中/已修复 (%d)"):format(#handled),
      controlSize = "sm",
      onClick = function()
        showHandled = not showHandled
        render()
      end,
    }))
    if showHandled then
      for _, it in handled do
        table.insert(issueNodes, issueCard(it))
      end
    end
  end

  -- ④ 工具折叠行：深报告 / 已忽略 / 系统操作（Q5）
  local ignoredList = (r and r.ignored) or {}
  local foldRow = ui.row({ gap = 6, align = "center" }, {
    ui.button({ text = showDeep and "收起深报告" or "深报告", controlSize = "sm", onClick = function()
      showDeep = not showDeep
      render()
    end }),
    ui.button({ text = showIgnored and "收起已忽略" or ("已忽略 (%d)"):format(#ignoredList), controlSize = "sm", onClick = function()
      showIgnored = not showIgnored
      render()
    end }),
    ui.button({ text = showOps and "收起系统操作" or "系统操作", controlSize = "sm", onClick = function()
      showOps = not showOps
      render()
    end }),
  })

  local foldNodes = {}
  if showDeep then
    local deepRaw = noctalia.readFile(DEEP_REPORT)
    table.insert(foldNodes, card({
      ui.markdown({ text = deepRaw or "（暂无深度报告——每周一早自动产出，或 sysops-ctl deep 手动跑）" }),
    }))
  end
  if showIgnored then
    local igRows = {}
    if #ignoredList == 0 then
      table.insert(igRows, ui.label({ text = "（空）", fontSize = 10, color = "on_surface_variant" }))
    end
    for _, ig in ignoredList do
      local gid = ig.id -- 每次迭代新局部
      table.insert(igRows, ui.row({ align = "center", gap = 6 }, {
        ui.label({ text = ("%s  [%s]"):format(ig.id, ig.mode or "?"), fontSize = 10, color = "on_surface_variant", flexGrow = 1 }),
        ui.button({ text = "恢复", controlSize = "sm", onClick = function()
          ctl("unignore", gid)
        end }),
      }))
    end
    table.insert(foldNodes, card(igRows))
  end
  if showOps then
    local opsNodes = {
      ui.row({ gap = 6, align = "center" }, {
        ui.button({ text = "系统更新", controlSize = "sm", onClick = function()
          noctalia.notify("已生成方案", "系统更新（flake update + rebuild）")
          ctl("propose", "--update")
        end }),
        ui.button({ text = rollbackOpen and "收起回滚列表" or "回滚…", controlSize = "sm", onClick = function()
          rollbackOpen = not rollbackOpen
          render()
        end }),
      }),
    }
    if rollbackOpen then
      local gens = ((r or {}).system or {}).generations or {}
      for _, g in gens do
        local gn = g.number -- 每次迭代新局部
        table.insert(opsNodes, ui.row({ align = "center", gap = 6 }, {
          ui.label({
            text = ("第 %d 代  %s%s"):format(gn, g.date or "", g.current and "（当前）" or ""),
            fontSize = 10,
            color = "on_surface",
            flexGrow = 1,
          }),
          ui.button({ text = "回滚到此", controlSize = "sm", onClick = g.current and nil or function()
            noctalia.notify("已生成方案", ("回滚到第 %d 代"):format(gn))
            ctl("propose", "--rollback", tostring(gn))
          end }),
        }))
      end
    end
    table.insert(foldNodes, card(opsNodes))
  end

  -- ⑤ 已处理历史（Q1：折叠不占位）
  local historyNodes = {}
  if showHistory then
    if #processed == 0 then
      table.insert(historyNodes, ui.label({ text = "（空）", fontSize = 10, color = "on_surface_variant" }))
    end
    for _, p in processed do
      table.insert(historyNodes, proposalCard(p, nil))
    end
  end

  panel.render(ui.column({ flexGrow = 1, gap = 8, fill = opaque("surface", "#1e1e2e"), radius = 16, padding = 10 }, {
    header,
    ui.label({ text = summaryText, fontSize = 10, color = "on_surface_variant" }),
    ui.scroll({ flexGrow = 1, gap = 6 }, {
      sectionTitle("待审批框", #pending > 0 and ("%d 项待批"):format(#pending) or ""),
      ui.column({ gap = 5 }, pendingNodes),
      sectionTitle("对话"),
      card(chatNodes, 5),
      sectionTitle("体检问题", #actionable > 0 and ("%d 项待处理"):format(#actionable) or ""),
      ui.column({ gap = 5 }, issueNodes),
      sectionTitle("工具"),
      foldRow,
      ui.column({ gap = 5 }, foldNodes),
      sectionTitle("已处理", #processed > 0 and ("%d 项"):format(#processed) or ""),
      ui.row({ gap = 6, align = "center" }, {
        ui.button({ text = showHistory and "收起历史" or "查看历史", controlSize = "sm", onClick = function()
          showHistory = not showHistory
          render()
        end }),
      }),
      ui.column({ gap = 5 }, historyNodes),
    }),
    ui.label({
      text = "批准 → 串行执行（队列接力）→ 卡片更新状态 · 失败即停不自动重试 · push 永不自动",
      fontSize = 9,
      color = "on_surface_variant",
    }),
  }))
end

function onOpen(_context)
  render()
end

function update()
  noctalia.setUpdateInterval(5000)
  render()
end
