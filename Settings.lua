local ADDON, ns = ...
local S, W = ns.STYLE, ns.W

-- Options tab (built into the main window).

local rows = {}

function ns.BuildOptions(P, top)
    local function Section(text)
        local h = W.Heading(P, 12)
        h:SetText(text)
        rows[#rows + 1] = { widget = h, gap = 6, heading = true }
    end
    local function Add(widget) rows[#rows + 1] = { widget = widget } end

    Section("Buff bar")
    Add(W.Check(P, "Lock buff bar position", function() return ns.db.locked end, function(v) ns.db.locked = v end))
    local LAYOUTS = { "compact", "row", "wrap", "column" }
    local LAYOUT_NAMES = { "Compact", "Row", "Wrap", "Column" }
    Add(W.Stepper(P, "Bar layout", function()
            for i, k in ipairs(LAYOUTS) do if k == ns.db.barLayout then return i end end
            return 1
        end,
        function(v) ns.db.barLayout = LAYOUTS[v] or "compact"; ns.dirty = true end,
        1, 1, 4, function(v) return LAYOUT_NAMES[v] or "Compact" end))
    Add(W.Check(P, "Show text beside Smart Buff", function() return ns.db.barText end,
        function(v) ns.db.barText = v; ns.dirty = true end))
    Add(W.Check(P, "Show minimap button", function() return ns.db.showMinimap end,
        function(v) ns.db.showMinimap = v; if ns.UpdateMinimap then ns.UpdateMinimap() end end))
    Add(W.Stepper(P, "UI scale", function() return ns.db.scale end, function(v) ns.db.scale = v; ns.ApplyScale() end,
        0.1, 0.7, 1.5, function(v) return ("%.1f"):format(v) end))

    Section("Smart Buff")
    Add(W.Stepper(P, "Refresh at (min left)", function() return ns.db.refresh / 60 end,
        function(v) ns.db.refresh = v * 60; ns.dirty = true end, 1, 0, 30, function(v) return ("%d"):format(v) end))
    Add(W.Stepper(P, "Greater at class size", function() return ns.db.greaterMin or 2 end,
        function(v) ns.db.greaterMin = v; ns.dirty = true end, 1, 1, 10, function(v) return ("%d+"):format(v) end))
    Add(W.Stepper(P, "Symbol warning under", function() return ns.db.reagentWarn or 0 end,
        function(v) ns.db.reagentWarn = v; ns.dirty = true end, 5, 0, 100, function(v) return v == 0 and "off" or ("%d"):format(v) end))
    Add(W.Check(P, "Righteous Fury when I tank", function() return ns.db.rfReminder end,
        function(v) ns.db.rfReminder = v; ns.dirty = true end))
    Add(W.Check(P, "Auto Oath of Light on tanks", function() return ns.db.autoOath end,
        function(v) ns.db.autoOath = v; if v then ns.AutoOathSelf() end end))

    Section("Party and raid frames")
    Add(W.Check(P, "Blessing icons on frames", function() return ns.db.frameIcons end,
        function(v) ns.db.frameIcons = v; if ns.RefreshFrameIcons then ns.RefreshFrameIcons() end end))
    Add(W.Stepper(P, "Frame icon size", function() return ns.db.frameIconSize or 22 end,
        function(v) ns.db.frameIconSize = v; if ns.RefreshFrameIcons then ns.RefreshFrameIcons() end end,
        2, 14, 40, function(v) return ("%d"):format(v) end))

    Section("Group")
    Add(W.Check(P, "Preview a raid (test while solo)", function() return ns.preview end,
        function(v) if ns.SetPreview then ns.SetPreview(v) end end))
    Add(W.Check(P, "Answer \"!bless\" chat requests", function() return ns.db.chatRequests end,
        function(v) ns.db.chatRequests = v end))
    Add(W.Check(P, "Sync with PallyPower users", function() return ns.db.compat end, function(v) ns.db.compat = v end))
    Add(W.Check(P, "Open window on ready check", function() return ns.db.readyCheck ~= false end,
        function(v) ns.db.readyCheck = v end))
    Add(W.Check(P, "Ready check: show raid buffs too", function() return ns.db.readyCheckRaid end,
        function(v) ns.db.readyCheckRaid = v; if ns.RefreshReadyCheck then ns.RefreshReadyCheck() end end))

    -- two columns
    local colX, y0 = { 16, 270 }, -(top or 60)
    -- column 1: Buff bar + Smart Buff, column 2: the rest
    local headings = {}
    for i, r in ipairs(rows) do if r.heading then headings[#headings + 1] = i end end
    local split = headings[3] or math.ceil(#rows / 2)
    local maxY = 0
    local y, col = y0, 1
    for i, r in ipairs(rows) do
        if i == split then col, y = 2, y0 end
        if r.heading and y ~= y0 then y = y - 6 end
        r.widget:ClearAllPoints()
        r.widget:SetPoint("TOPLEFT", P, "TOPLEFT", colX[col] + (r.heading and 0 or 2), y)
        if r.widget.SetWidth and not r.heading and r.widget:GetObjectType() == "Frame" then r.widget:SetWidth(232) end
        y = y - (r.heading and 20 or 27)
        maxY = math.max(maxY, -y)
    end
    return maxY + 14
end

function ns.RefreshOptions()
    for _, r in ipairs(rows) do if r.widget.Refresh then r.widget:Refresh() end end
end

function ns.HideSettings() end
