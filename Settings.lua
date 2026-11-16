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
    Add(W.Check(P, "Lock buff bar position", function() return ns.db.locked end, function(v) ns.db.locked = v end,
        "Stops the bar from being dragged."))
    local LAYOUTS = { "compact", "row", "wrap", "column" }
    local LAYOUT_NAMES = { "Compact", "Row", "Wrap", "Column" }
    Add(W.Stepper(P, "Bar layout", function()
            for i, k in ipairs(LAYOUTS) do if k == ns.db.barLayout then return i end end
            return 1
        end,
        function(v) ns.db.barLayout = LAYOUTS[v] or "compact"; ns.dirty = true end,
        1, 1, 4, function(v) return LAYOUT_NAMES[v] or "Compact" end,
        "Compact: PallyPower-style rows. Row, Wrap, Column: icon slots."))
    Add(W.Check(P, "Fade when all buffed", function() return ns.db.fadeIdle end,
        function(v) ns.db.fadeIdle = v; ns.ApplyBarFade() end,
        "The bar goes faint when there's nothing to cast, in or out of combat. Full strength on mouseover."))
    Add(W.Check(P, "Show aura button", function() return ns.db.auraButton ~= false end,
        function(v) ns.db.auraButton = v; ns.dirty = true end,
        "Your assigned aura on the bar. Smart Buff still turns it on either way."))
    Add(W.Check(P, "Show seal button", function() return ns.db.sealButton end,
        function(v) ns.db.sealButton = v; ns.dirty = true end,
        "Click to cast your seal, mouse wheel to change it."))
    Add(W.Check(P, "Show text beside Smart Buff", function() return ns.db.barText end,
        function(v) ns.db.barText = v; ns.dirty = true end,
        "Row, Wrap and Column only: the next buff and counts as text."))
    Add(W.Check(P, "Show minimap button", function() return ns.db.showMinimap end,
        function(v) ns.db.showMinimap = v; if ns.UpdateMinimap then ns.UpdateMinimap() end end))
    Add(W.Stepper(P, "Bar size", function() return ns.db.scale end, function(v) ns.db.scale = v; ns.ApplyScale() end,
        0.1, 0.5, 2.0, function(v) return ("%.1f"):format(v) end, "Size of the buff bar."))
    Add(W.Stepper(P, "Window size", function() return ns.WinScale() end, function(v) ns.db.winScale = v; ns.ApplyScale() end,
        0.1, 0.6, 1.5, function(v) return ("%.1f"):format(v) end, "Size of this window."))

    Section("Compact layout")
    Add(W.Stepper(P, "Row width", function() return ns.db.rowWidth or 76 end,
        function(v) ns.db.rowWidth = v; ns.dirty = true end, 8, 60, 140, function(v) return ("%d"):format(v) end))
    Add(W.Check(P, "Grow upward", function() return ns.db.growUp end,
        function(v) ns.db.growUp = v; ns.dirty = true end, "Rows stack above the Smart Buff row instead of below."))
    Add(W.Check(P, "Show timers", function() return ns.db.rowTimers ~= false end,
        function(v) ns.db.rowTimers = v; ns.dirty = true end, "Time left on rows where nobody is missing it."))

    Section("Party and raid frames")
    Add(W.Check(P, "Blessing icons on frames", function() return ns.db.frameIcons end,
        function(v) ns.db.frameIcons = v; if ns.RefreshFrameIcons then ns.RefreshFrameIcons() end end,
        "Shows your blessing and its timer on Blizzard's party and raid frames."))
    Add(W.Stepper(P, "Frame icon size", function() return ns.db.frameIconSize or 22 end,
        function(v) ns.db.frameIconSize = v; if ns.RefreshFrameIcons then ns.RefreshFrameIcons() end end,
        2, 14, 40, function(v) return ("%d"):format(v) end))

    Section("Keybinds")
    Add(W.KeyBind(P, "Smart Buff", "CLICK PallyPulseSmartButton:LeftButton",
        "Casts the next buff you owe. Alt + key blesses yourself."))
    Add(W.KeyBind(P, "Oath on mouseover", "CLICK PallyPulseOathTarget:LeftButton",
        "Oath of Light on your mouseover, else target, else you."))
    Add(W.KeyBind(P, "Open PallyPulse", "PALLYPULSE_TOGGLE", "Shows or hides the assignments window."))

    Section("Smart Buff")
    Add(W.Stepper(P, "Refresh at (min left)", function() return ns.db.refresh / 60 end,
        function(v) ns.db.refresh = v * 60; ns.dirty = true end, 1, 0, 30, function(v) return ("%d"):format(v) end,
        "Blessings with less time left than this count as needing a refresh."))
    Add(W.Stepper(P, "Greater at class size", function() return ns.db.greaterMin or 2 end,
        function(v) ns.db.greaterMin = v; ns.dirty = true end, 1, 1, 10, function(v) return ("%d+"):format(v) end,
        "Use a Greater Blessing when a class has at least this many players."))
    Add(W.Stepper(P, "Low Symbols alert", function() return ns.db.reagentWarn or 0 end,
        function(v) ns.db.reagentWarn = v; ns.dirty = true end, 5, 0, 100, function(v) return v == 0 and "off" or ("%d"):format(v) end,
        "Warn when you have fewer Symbols of Kings than this."))
    Add(W.Check(P, "Righteous Fury when I tank", function() return ns.db.rfReminder end,
        function(v) ns.db.rfReminder = v; ns.dirty = true end, "Smart Buff casts Righteous Fury when you're the tank."))
    Add(W.Check(P, "Auto Oath of Light on tanks", function() return ns.db.autoOath end,
        function(v) ns.db.autoOath = v; if v then ns.AutoOathSelf() end end,
        "Oath of Light goes on the group's tank, or on you when solo."))

    Section("Group")
    Add(W.Check(P, "Answer \"!bless\" chat requests", function() return ns.db.chatRequests end,
        function(v) ns.db.chatRequests = v end, "Players can type !bless want might to ask for a blessing."))
    Add(W.Check(P, "Sync with PallyPower users", function() return ns.db.compat end, function(v) ns.db.compat = v end,
        "Shares assignments with paladins using PallyPower."))

    Section("Ready check")
    Add(W.Check(P, "Open window on ready check", function() return ns.db.readyCheck ~= false end,
        function(v) ns.db.readyCheck = v end, "Opens when a ready check starts. /pulse check opens it any time."))
    Add(W.Check(P, "Show raid buffs too", function() return ns.db.readyCheckRaid end,
        function(v) ns.db.readyCheckRaid = v; if ns.RefreshReadyCheck then ns.RefreshReadyCheck() end end,
        "Adds Stamina, Mark, Intellect, Spirit, food and flask."))
    Add(W.Stepper(P, "Ready check size", function() return ns.RCScale() end,
        function(v)
            ns.db.rcScale = v; ns.ApplyScale()
            -- show the window so the change is visible
            local rc = _G.PallyPulseReadyCheck
            if not (rc and rc:IsShown()) and ns.ShowReadyCheck then ns.ShowReadyCheck() end
        end, 0.1, 0.6, 1.5, function(v) return ("%.1f"):format(v) end,
        "Size of the ready check window. Changing it opens the window so you can see."))

    Section("Sounds")
    Add(W.Check(P, "Oath about to expire", function() return ns.db.oathSound end,
        function(v) ns.db.oathSound = v end, "Plays when your Oath of Light has 30 seconds left."))
    Add(W.Check(P, "Ready check: I owe blessings", function() return ns.db.readyCheckSound end,
        function(v) ns.db.readyCheckSound = v end, "Plays when a ready check starts and you owe blessings."))
    Add(W.Stepper(P, "Sound", function() local _, i = ns.CurrentSound(); return i end,
        function(v)
            local list = ns.SoundList()
            if v > #list then v = #list end
            ns.db.alertSoundName = list[v].name
            ns.Alert()
        end, 1, 1, 500,
        function(v) local list = ns.SoundList(); return (list[math.min(v, #list)] or list[1]).name end,
        "Which sound both alerts use. Each one plays as you pick it. Sounds shared by your other addons are listed after PallyPulse's own.", 130))
    Add(W.Button(P, "Test sound", 110, 22, function() ns.Alert() end))

    Section("Testing")
    Add(W.Check(P, "Preview a raid", function() return ns.preview end,
        function(v) if ns.SetPreview then ns.SetPreview(v) end end,
        "Adds a pretend raid so you can see everything while solo. Nothing is cast on them."))

    -- two columns
    local colX, y0 = { 16, 270 }, -(top or 60)
    -- column 1: Buff bar, Compact layout, frames, keybinds; column 2: Smart Buff and the rest
    local headings = {}
    for i, r in ipairs(rows) do if r.heading then headings[#headings + 1] = i end end
    local split = headings[5] or math.ceil(#rows / 2)    -- column 2 starts at "Smart Buff"
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
