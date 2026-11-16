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

    local function Scale(v) return ("%.1f"):format(v) end

    Section("Bar")
    Add(W.Check(P, "Lock bar", function() return ns.db.locked end, function(v) ns.db.locked = v end))
    local LAYOUTS = { "compact", "row", "wrap", "column" }
    local LAYOUT_NAMES = { "Compact", "Row", "Wrap", "Column" }
    Add(W.Stepper(P, "Layout", function()
            for i, k in ipairs(LAYOUTS) do if k == ns.db.barLayout then return i end end
            return 1
        end,
        function(v) ns.db.barLayout = LAYOUTS[v] or "compact"; ns.dirty = true end,
        1, 1, 4, function(v) return LAYOUT_NAMES[v] or "Compact" end))
    Add(W.Check(P, "Fade when idle", function() return ns.db.fadeIdle end,
        function(v) ns.db.fadeIdle = v; ns.ApplyBarFade() end))
    Add(W.Check(P, "Aura button", function() return ns.db.auraButton ~= false end,
        function(v) ns.db.auraButton = v; ns.dirty = true end))
    Add(W.Check(P, "Seal button", function() return ns.db.sealButton end,
        function(v) ns.db.sealButton = v; ns.dirty = true end, "Click: cast. Wheel: change seal."))
    Add(W.Check(P, "Status text", function() return ns.db.barText end,
        function(v) ns.db.barText = v; ns.dirty = true end, "Row, Wrap and Column layouts."))
    Add(W.Check(P, "Minimap button", function() return ns.db.showMinimap end,
        function(v) ns.db.showMinimap = v; if ns.UpdateMinimap then ns.UpdateMinimap() end end))
    Add(W.Stepper(P, "Bar scale", function() return ns.db.scale end, function(v) ns.db.scale = v; ns.ApplyScale() end,
        0.1, 0.5, 2.0, Scale))
    Add(W.Stepper(P, "Window scale", function() return ns.WinScale() end, function(v) ns.db.winScale = v; ns.ApplyScale() end,
        0.1, 0.6, 1.5, Scale))
    Add(W.Stepper(P, "Row width", function() return ns.db.rowWidth or 76 end,
        function(v) ns.db.rowWidth = v; ns.dirty = true end, 8, 60, 140, function(v) return ("%d"):format(v) end,
        "Compact layout."))
    Add(W.Check(P, "Grow upward", function() return ns.db.growUp end,
        function(v) ns.db.growUp = v; ns.dirty = true end, "Compact layout."))
    Add(W.Check(P, "Timers", function() return ns.db.rowTimers ~= false end,
        function(v) ns.db.rowTimers = v; ns.dirty = true end, "Compact layout."))

    Section("Raid frames")
    Add(W.Check(P, "Blessing icons", function() return ns.db.frameIcons end,
        function(v) ns.db.frameIcons = v; if ns.RefreshFrameIcons then ns.RefreshFrameIcons() end end))
    Add(W.Stepper(P, "Icon size", function() return ns.db.frameIconSize or 22 end,
        function(v) ns.db.frameIconSize = v; if ns.RefreshFrameIcons then ns.RefreshFrameIcons() end end,
        2, 14, 40, function(v) return ("%d"):format(v) end))

    Section("Key Bindings")
    Add(W.KeyBind(P, "Smart Buff", "CLICK PallyPulseSmartButton:LeftButton", "Alt: bless yourself."))
    Add(W.KeyBind(P, "Oath of Light", "CLICK PallyPulseOathTarget:LeftButton", "Mouseover, target, then self."))
    Add(W.KeyBind(P, "Toggle window", "PALLYPULSE_TOGGLE"))

    Section("Smart Buff")
    Add(W.Stepper(P, "Refresh below (min)", function() return ns.db.refresh / 60 end,
        function(v) ns.db.refresh = v * 60; ns.dirty = true end, 1, 0, 30, function(v) return ("%d"):format(v) end))
    Add(W.Stepper(P, "Greater Blessing at", function() return ns.db.greaterMin or 2 end,
        function(v) ns.db.greaterMin = v; ns.dirty = true end, 1, 1, 10, function(v) return ("%d+"):format(v) end,
        "Players of one class."))
    Add(W.Stepper(P, "Symbol warning", function() return ns.db.reagentWarn or 0 end,
        function(v) ns.db.reagentWarn = v; ns.dirty = true end, 5, 0, 100, function(v) return v == 0 and "Off" or ("%d"):format(v) end,
        "Symbol of Kings."))
    Add(W.Check(P, "Righteous Fury as tank", function() return ns.db.rfReminder end,
        function(v) ns.db.rfReminder = v; ns.dirty = true end))
    Add(W.Check(P, "Auto Oath on tanks", function() return ns.db.autoOath end,
        function(v) ns.db.autoOath = v; if v then ns.AutoOathSelf() end end))

    Section("Group")
    Add(W.Check(P, "Accept !bless requests", function() return ns.db.chatRequests end,
        function(v) ns.db.chatRequests = v end, "!bless want might"))
    Add(W.Check(P, "PallyPower sync", function() return ns.db.compat end, function(v) ns.db.compat = v end))
    Add(W.Check(P, "Test mode", function() return ns.preview end,
        function(v) if ns.SetPreview then ns.SetPreview(v) end end, "Adds a fake 13-player raid."))

    Section("Ready Check")
    Add(W.Check(P, "Show on ready check", function() return ns.db.readyCheck ~= false end,
        function(v) ns.db.readyCheck = v end))
    Add(W.Check(P, "Raid buffs", function() return ns.db.readyCheckRaid end,
        function(v) ns.db.readyCheckRaid = v; if ns.RefreshReadyCheck then ns.RefreshReadyCheck() end end,
        "Fortitude, Mark, Intellect, Spirit, food, flask."))
    Add(W.Stepper(P, "Scale", function() return ns.RCScale() end,
        function(v)
            ns.db.rcScale = v; ns.ApplyScale()
            local rc = _G.PallyPulseReadyCheck     -- open it so the change is visible
            if not (rc and rc:IsShown()) and ns.ShowReadyCheck then ns.ShowReadyCheck() end
        end, 0.1, 0.6, 1.5, Scale))

    Section("Sounds")
    Add(W.Check(P, "Oath expiring", function() return ns.db.oathSound end,
        function(v) ns.db.oathSound = v end, "30 seconds left."))
    Add(W.Check(P, "Ready check: missing blessings", function() return ns.db.readyCheckSound end,
        function(v) ns.db.readyCheckSound = v end))
    Add(W.Dropdown(P, "Sound", function() return ns.SoundList() end,
        function() return ns.CurrentSound().name end,
        function(item) ns.db.alertSoundName = item.name; ns.Alert() end))
    Add(W.Button(P, "Test", 80, 22, function() ns.Alert() end))

    -- two columns
    local colX, y0 = { 16, 270 }, -(top or 60)
    -- column 1: Bar, Raid frames, Key Bindings; column 2: Smart Buff and the rest
    local headings = {}
    for i, r in ipairs(rows) do if r.heading then headings[#headings + 1] = i end end
    local split = headings[4] or math.ceil(#rows / 2)    -- column 2 starts at "Smart Buff"
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
