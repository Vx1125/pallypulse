local ADDON, ns = ...
local S, W = ns.STYLE, ns.W

-- Options tab (built into the main window).

local rows = {}

-- ---------------------------------------------------------------------------
-- Profiles: your options as one line of text, to copy to another character or share.
-- Only settings go in (no assignments, specs or positions), and import only accepts known
-- settings of the right type.
-- ---------------------------------------------------------------------------
local PROFILE_KEYS = {
    "locked", "barLayout", "fadeIdle", "auraButton", "sealButton", "showMinimap", "scale", "winScale",
    "rowWidth", "growUp", "rowTimers", "frameIcons", "frameIconSize", "frameIconClick", "refresh",
    "greaterMin", "reagentWarn", "rfReminder", "autoOath", "chatRequests", "compat", "readyCheck",
    "readyCheckRaid", "rcScale", "oathSound", "readyCheckSound", "alertSoundName", "font", "auraPrefer",
    "barMode", "rowHeight", "iconSize", "barAlpha",
}
local PREFIX = "PULSE1:"

local function Esc(v) return (tostring(v):gsub("[%%;=,]", function(c) return ("%%%02X"):format(c:byte()) end)) end
local function Unesc(v) return (v:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

function ns.ExportProfile()
    local parts = {}
    for _, k in ipairs(PROFILE_KEYS) do
        local v = ns.db[k]
        local t = type(v)
        if t == "boolean" then parts[#parts + 1] = k .. "=b" .. (v and 1 or 0)
        elseif t == "number" then parts[#parts + 1] = k .. "=n" .. v
        elseif t == "string" then parts[#parts + 1] = k .. "=s" .. Esc(v) end
    end
    for key, list in pairs(ns.db.specPrefs) do
        parts[#parts + 1] = "sp." .. key:gsub(":", ".") .. "=s" .. Esc(table.concat(list, ","))
    end
    return PREFIX .. table.concat(parts, ";")
end

function ns.ImportProfile(text)
    text = (text or ""):gsub("%s", "")
    if text:sub(1, #PREFIX) ~= PREFIX then return false end
    local allowed = {}
    for _, k in ipairs(PROFILE_KEYS) do allowed[k] = true end
    local got, prefs = {}, {}
    for pair in text:sub(#PREFIX + 1):gmatch("[^;]+") do
        local k, kind, v = pair:match("^([%w%.]+)=(%a)(.*)$")
        if k then
            local class, spec = k:match("^sp%.(%u+)%.(%u*)$")
            if class and kind == "s" and ns.SPECS[class] then
                local list = {}
                for key in Unesc(v):gmatch("[^,]+") do list[#list + 1] = key end
                prefs[class .. ":" .. spec] = list
            elseif allowed[k] then
                if kind == "b" then got[k] = (v == "1")
                elseif kind == "n" then got[k] = tonumber(v)
                elseif kind == "s" then got[k] = Unesc(v) end
            end
        end
    end
    if not next(got) and not next(prefs) then return false end
    for k, v in pairs(got) do
        local cur = ns.db[k]
        if v ~= nil and (cur == nil or type(cur) == type(v)) then ns.db[k] = v end
    end
    if ns.db.barLayout ~= "horizontal" then ns.db.barLayout = "compact" end
    if ns.db.barMode ~= "compact" and ns.db.barMode ~= "action" then ns.db.barMode = "standard" end
    for key, list in pairs(prefs) do
        local class, spec = key:match("^(%u+):(%u*)$")
        ns.SetSpecPrefs(class, spec, list)
    end
    ns.ApplyScale()
    ns.W.ApplyStyle()
    if ns.ApplyBarFade then ns.ApplyBarFade() end
    if ns.UpdateMinimap then ns.UpdateMinimap() end
    if ns.RefreshFrameIcons then ns.RefreshFrameIcons() end
    ns.RefreshOptions()
    ns.dirty = true
    return true
end

-- Bar position as the offset of its middle from the middle of the screen.
local function BarOffset()
    local bar = ns.bar
    if not bar or not bar:GetCenter() then return 0, 0 end
    local bx, by = bar:GetCenter()
    local k = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local ux, uy = UIParent:GetCenter()
    return math.floor(bx * k - ux + 0.5), math.floor(by * k - uy + 0.5)
end

local function SetBarOffset(x, y)
    local bar = ns.bar
    if not bar or InCombatLockdown() then return end
    local k = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", UIParent, "CENTER", x / k, y / k)
    -- store it the way the bar normally does (top left), so Layout keeps it in place
    local l, t = bar:GetLeft(), bar:GetTop()
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    ns.W.SavePos(bar, "bar")
    ns.dirty = true
end


function ns.BuildOptions(P, top)
    top = top or 60
    local pages, current = {}, nil
    local function Page()
        local pg = CreateFrame("Frame", nil, P)
        pg:SetAllPoints(P)
        pg.rows = {}
        pages[#pages + 1] = pg
        current = pg
        return pg
    end
    local function Section(text)
        local h = W.Section(current, text)
        current.rows[#current.rows + 1] = { widget = h, heading = true }
        rows[#rows + 1] = { widget = h }
    end
    local function Column() current.rows[#current.rows + 1] = { column = true } end
    local function Add(widget)
        widget:SetParent(current)
        current.rows[#current.rows + 1] = { widget = widget }
        rows[#rows + 1] = { widget = widget }
    end
    local function Scale(v) return ("%.1f"):format(v) end
    local function Int(v) return ("%d"):format(v) end
    local function Choice(label, key, keys, names, default, onSet)
        Add(W.Stepper(current, label, function()
                for i, k in ipairs(keys) do if k == ns.db[key] then return i end end
                return 1
            end,
            function(v) ns.db[key] = keys[v] or default; ns.dirty = true; if onSet then onSet() end end,
            1, 1, #keys, function(v) return names[v] or names[1] end, nil, 80))
    end

    -- page 1: General
    Page()
    Section("Raid frames")
    Add(W.Check(current, "Blessing icons", function() return ns.db.frameIcons end,
        function(v) ns.db.frameIcons = v; if ns.RefreshFrameIcons then ns.RefreshFrameIcons() end end))
    Add(W.Check(current, "Click icon to bless", function() return ns.db.frameIconClick ~= false end,
        function(v) ns.db.frameIconClick = v; if ns.RefreshFrameIcons then ns.RefreshFrameIcons() end end,
        "Works in combat."))
    Add(W.Stepper(current, "Icon size", function() return ns.db.frameIconSize or 22 end,
        function(v) ns.db.frameIconSize = v; if ns.RefreshFrameIcons then ns.RefreshFrameIcons() end end,
        2, 14, 40, Int))

    Section("Key Bindings")
    Add(W.KeyBind(current, "Smart Buff", "CLICK PallyPulseSmartButton:LeftButton", "Alt: bless yourself."))
    Add(W.KeyBind(current, "Oath of Light", "CLICK PallyPulseOathTarget:LeftButton", "Mouseover, target, then self."))
    Add(W.KeyBind(current, "Toggle window", "PALLYPULSE_TOGGLE"))

    Section("Window")
    Add(W.Stepper(current, "Window scale", function() return ns.WinScale() end, function(v) ns.db.winScale = v; ns.ApplyScale() end,
        0.1, 0.6, 1.5, Scale))
    Add(W.Check(current, "Minimap button", function() return ns.db.showMinimap end,
        function(v) ns.db.showMinimap = v; if ns.UpdateMinimap then ns.UpdateMinimap() end end))

    Section("Sounds")
    Add(W.Check(current, "Oath expiring", function() return ns.db.oathSound end,
        function(v) ns.db.oathSound = v end, "30 seconds left."))
    Add(W.Check(current, "Ready check: missing blessings", function() return ns.db.readyCheckSound end,
        function(v) ns.db.readyCheckSound = v end))
    Add(W.Dropdown(current, "Sound", function() return ns.SoundList() end,
        function() return ns.CurrentSound().name end,
        function(item) ns.db.alertSoundName = item.name; ns.Alert() end))
    Add(W.Button(current, "Test", 80, 22, function() ns.Alert() end))

    Column()
    Section("Smart Buff")
    Add(W.Stepper(current, "Expiring at (min)", function() return ns.db.refresh / 60 end,
        function(v) ns.db.refresh = v * 60; ns.dirty = true end, 1, 0, 30, Int, "Bar and Smart Buff."))
    Add(W.Stepper(current, "Greater Blessing at", function() return ns.db.greaterMin or 2 end,
        function(v) ns.db.greaterMin = v; ns.dirty = true end, 1, 1, 10, function(v) return ("%d+"):format(v) end,
        "Players of one class."))
    Add(W.Stepper(current, "Symbol warning", function() return ns.db.reagentWarn or 0 end,
        function(v) ns.db.reagentWarn = v; ns.dirty = true end, 5, 0, 100, function(v) return v == 0 and "Off" or Int(v) end,
        "Symbol of Kings."))
    Add(W.Check(current, "Righteous Fury as tank", function() return ns.db.rfReminder end,
        function(v) ns.db.rfReminder = v; ns.dirty = true end))
    Add(W.Check(current, "Auto Oath on tanks", function() return ns.db.autoOath end,
        function(v) ns.db.autoOath = v; if v then ns.AutoOathSelf() end end))

    Section("Group")
    local function AuraLabel(a) return (a.name:gsub(" Aura$", "")) end
    Add(W.Dropdown(current, "Your aura", function()
            local items = { { name = "Default" } }
            local caps = ns.auraCaps and ns.auraCaps[ns.Me()]
            for _, a in ipairs(ns.AURAS) do
                if not caps or next(caps) == nil or caps[a.key] then items[#items + 1] = { name = AuraLabel(a), key = a.key } end
            end
            return items
        end,
        function()
            local a = ns.db.auraPrefer and ns.AURA_BY_KEY[ns.db.auraPrefer]
            return a and AuraLabel(a) or "Default"
        end,
        function(item) ns.db.auraPrefer = item.key end, "Auto-assign gives you this aura first."))
    Add(W.Check(current, "Accept !bless requests", function() return ns.db.chatRequests end,
        function(v) ns.db.chatRequests = v end, "!bless want might"))
    Add(W.Check(current, "PallyPower sync", function() return ns.db.compat end, function(v) ns.db.compat = v end))

    Section("Ready Check")
    Add(W.Check(current, "Show on ready check", function() return ns.db.readyCheck ~= false end,
        function(v) ns.db.readyCheck = v end))
    Add(W.Check(current, "Raid buffs", function() return ns.db.readyCheckRaid end,
        function(v) ns.db.readyCheckRaid = v; if ns.RefreshReadyCheck then ns.RefreshReadyCheck() end end,
        "Fortitude, Mark, Intellect, Spirit, food, flask."))
    Add(W.Stepper(current, "Scale", function() return ns.RCScale() end,
        function(v)
            ns.db.rcScale = v; ns.ApplyScale()
            local rc = _G.PallyPulseReadyCheck     -- open it so the change is visible
            if not (rc and rc:IsShown()) and ns.ShowReadyCheck then ns.ShowReadyCheck() end
        end, 0.1, 0.6, 1.5, Scale))

    -- page 2: Bar
    Page()
    Section("Bar")
    Add(W.Check(current, "Lock bar", function() return ns.db.locked end, function(v) ns.db.locked = v end))
    Choice("Display", "barMode", { "standard", "compact", "action" }, { "Standard", "Compact", "Action only" }, "standard")
    Choice("Orientation", "barLayout", { "compact", "horizontal" }, { "Vertical", "Horizontal" }, "compact")
    Add(W.Check(current, "Fade when idle", function() return ns.db.fadeIdle end,
        function(v) ns.db.fadeIdle = v; ns.ApplyBarFade() end))
    Add(W.Check(current, "Grow upward", function() return ns.db.growUp end,
        function(v) ns.db.growUp = v; ns.dirty = true end, "Vertical."))
    Add(W.Check(current, "Timers", function() return ns.db.rowTimers ~= false end,
        function(v) ns.db.rowTimers = v; ns.dirty = true end))
    Add(W.Check(current, "Aura button", function() return ns.db.auraButton ~= false end,
        function(v) ns.db.auraButton = v; ns.dirty = true end))
    Add(W.Check(current, "Seal button", function() return ns.db.sealButton end,
        function(v) ns.db.sealButton = v; ns.dirty = true end, "Click: cast. Wheel: change seal."))

    Column()
    Section("Size")
    Add(W.Stepper(current, "Bar scale", function() return ns.db.scale end, function(v) ns.db.scale = v; ns.ApplyScale() end,
        0.1, 0.5, 2.0, Scale))
    Add(W.Stepper(current, "Row width", function() return ns.db.rowWidth or 76 end,
        function(v) ns.db.rowWidth = v; ns.dirty = true end, 8, 60, 140, Int, "Standard and Action only."))
    Add(W.Stepper(current, "Row height", function() return ns.db.rowHeight or 22 end,
        function(v) ns.db.rowHeight = v; ns.dirty = true end, 2, 16, 32, Int))
    Add(W.Stepper(current, "Icon size", function() return ns.db.iconSize or 18 end,
        function(v) ns.db.iconSize = v; ns.dirty = true end, 2, 10, 30, Int, "Standard and Action only."))
    Add(W.Stepper(current, "Background", function() return ns.db.barAlpha or 0.85 end,
        function(v) ns.db.barAlpha = v; ns.dirty = true end, 0.05, 0, 1,
        function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end))

    Section("Position")
    Add(W.NumberBox(current, "Bar X", function() return (BarOffset()) end,
        function(v) local _, y = BarOffset(); SetBarOffset(v, y) end, "From the middle of the screen."))
    Add(W.NumberBox(current, "Bar Y", function() return select(2, BarOffset()) end,
        function(v) local x = BarOffset(); SetBarOffset(x, v) end, "From the middle of the screen."))
    Add(W.Button(current, "Center", 80, 22, function() SetBarOffset(0, 0); ns.RefreshOptions() end))

    -- page 3: Advanced
    Page()
    Section("Look")
    Add(W.Dropdown(current, "Font", W.FontList, function() return ns.db.font or "Default" end,
        function(item) ns.db.font = item.name; W.ApplyStyle() end, "Fonts from LibSharedMedia."))

    Section("Profile")
    Add(W.Button(current, "Export", 80, 22, function()
        W.TextDialog("Export profile", ns.ExportProfile())
    end))
    Add(W.Button(current, "Import", 80, 22, function()
        W.TextDialog("Import profile", "", "Import", function(text)
            if ns.ImportProfile(text) then return true end
            return false
        end)
    end))

    Column()
    -- Priorities: pick a class, then set the blessing order for each of its specs
    Section("Priorities")
    local prioClass = "SHAMAN"
    local prioRows = {}
    Add(W.ClassPicker(current, ns.CLASSES, function() return prioClass end, function(c)
        prioClass = c
        for i, row in ipairs(prioRows) do row:Refresh() end
    end))
    for i = 1, 4 do
        local row = W.Priority(current, "",
            function()
                local sp = ns.SPECS[prioClass][i]
                return sp and ns.SpecPrefs(prioClass, sp.key) or {}
            end,
            function(list)
                local sp = ns.SPECS[prioClass][i]
                if sp then ns.SetSpecPrefs(prioClass, sp.key, list); ns.dirty = true end
            end,
            function(k) return ns.BY_KEY[k].icon end,
            function()
                local sp = ns.SPECS[prioClass][i]
                return sp and sp.label
            end)
        prioRows[i] = row
        Add(row)
    end
    Add(W.Button(current, "Reset", 80, 22, function()
        for _, sp in ipairs(ns.SPECS[prioClass]) do ns.SetSpecPrefs(prioClass, sp.key, nil) end
        for _, row in ipairs(prioRows) do row:Refresh() end
        ns.dirty = true
    end))

    -- page switch, under the window's tabs: small text tabs with a gold underline
    local tabs, heights = {}, {}
    local function Show(i)
        for j, pg in ipairs(pages) do pg:SetShown(j == i) end
        for j, t in ipairs(tabs) do
            t.text:SetTextColor(unpack(j == i and S.gold or S.dim))
            t.line:SetShown(j == i)
        end
        if heights[i] then P.height = heights[i] end      -- the window fits the page shown
        if ns.RefreshWindow then ns.RefreshWindow() end
    end
    local tx = 16
    for i, name in ipairs({ "General", "Bar", "Advanced" }) do
        local t = CreateFrame("Button", nil, P)
        t.text = W.Text(t, 11, S.dim, "LEFT", S.head); t.text:SetPoint("LEFT"); t.text:SetText(name)
        t:SetSize(t.text:GetStringWidth() + 4, 18)
        t:SetPoint("TOPLEFT", P, "TOPLEFT", tx, -top)
        t.line = t:CreateTexture(nil, "ARTWORK")
        t.line:SetPoint("BOTTOMLEFT", 0, 0); t.line:SetPoint("BOTTOMRIGHT", 0, 0); t.line:SetHeight(1)
        t.line:SetColorTexture(S.gold[1], S.gold[2], S.gold[3], 1)
        t:SetScript("OnClick", function() Show(i) end)
        tabs[i] = t
        tx = tx + t:GetWidth() + 16
    end

    -- two columns on each page; Column() starts the second
    local colX, y0 = { 16, 270 }, -(top + 28)
    for pi, pg in ipairs(pages) do
        local maxY = 0
        local y, col = y0, 1
        for _, r in ipairs(pg.rows) do
            if r.column then
                col, y = 2, y0
            else
                if r.heading and y ~= y0 then y = y - 8 end
                r.widget:ClearAllPoints()
                r.widget:SetPoint("TOPLEFT", pg, "TOPLEFT", colX[col] + (r.heading and 0 or 2), y)
                if r.widget.SetWidth and not r.heading and r.widget:GetObjectType() == "Frame" then r.widget:SetWidth(232) end
                y = y - (r.heading and 22 or 27)
                maxY = math.max(maxY, -y)
            end
        end
        heights[pi] = maxY + 14
    end
    Show(1)
    return heights[1]
end

function ns.RefreshOptions()
    for _, r in ipairs(rows) do if r.widget.Refresh then r.widget:Refresh() end end
end

function ns.HideSettings() end
