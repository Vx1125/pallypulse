local ADDON, ns = ...
local S, W = ns.STYLE, ns.W

-- Options tab (built into the main window).

local rows = {}
local depsUpdate      -- set by BuildOptions: re-checks settings that depend on another

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
    "barMode", "rowHeight", "iconSize", "barAlpha", "barClassNames", "hideEmptyClasses",
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
    ns.ApplySettings()
    return true
end

-- After settings change all at once (import, restore defaults): apply them everywhere.
function ns.ApplySettings()
    if ns.db.barLayout ~= "horizontal" then ns.db.barLayout = "compact" end
    if ns.db.barMode ~= "compact" and ns.db.barMode ~= "action" then ns.db.barMode = "standard" end
    ns.ApplyScale()
    ns.W.ApplyStyle()
    if ns.ApplyBarFade then ns.ApplyBarFade() end
    if ns.UpdateMinimap then ns.UpdateMinimap() end
    if ns.RefreshFrameIcons then ns.RefreshFrameIcons() end
    ns.RefreshOptions()
    if ns.RefreshWindow then ns.RefreshWindow() end
    ns.dirty = true
end

-- Restore defaults: only the options above (the profile keys). Assignments, presets, priorities,
-- auras, Oath targets, specs, window positions and key bindings are kept.
function ns.RestoreDefaults()
    for _, k in ipairs(PROFILE_KEYS) do
        local v = ns.DEFAULTS[k]
        if type(v) == "table" then v = nil end
        ns.db[k] = v
    end
    ns.ApplySettings()
end

StaticPopupDialogs["PALLYPULSE_DEFAULTS"] = {
    text = "Restore default options?\n\nAssignments, presets, priorities and key bindings are kept.",
    button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function() ns.RestoreDefaults() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

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
    local function Choice(label, key, keys, names, default, onSet, tip)
        Add(W.Stepper(current, label, function()
                for i, k in ipairs(keys) do if k == ns.db[key] then return i end end
                return 1
            end,
            function(v) ns.db[key] = keys[v] or default; ns.dirty = true; if onSet then onSet() end end,
            1, 1, #keys, function(v) return names[v] or names[1] end, tip, 80))
    end

    local function Mins(v) return ("%d min"):format(v) end
    local function Px(v) return ("%d px"):format(v) end
    -- dependent settings: { widget, available(), why }
    local deps = {}
    local function Dep(widget, fn, why) deps[#deps + 1] = { widget, fn, why } end

    -- ---- page 1: General (how PallyPulse behaves) ----
    Page()
    Section("Key Bindings")
    Add(W.KeyBind(current, "Smart Buff", "CLICK PallyPulseSmartButton:LeftButton",
        "Press it again and again: each press casts the next blessing you owe. Alt: on yourself."))
    Add(W.KeyBind(current, "Oath of Light", "CLICK PallyPulseOathTarget:LeftButton",
        "Casts Oath of Light on your mouseover, then target, then yourself."))
    Add(W.KeyBind(current, "Toggle window", "PALLYPULSE_TOGGLE", "Opens and closes this window."))

    Section("Smart Buff")
    Add(W.Stepper(current, "Refresh before expiry", function() return ns.db.refresh / 60 end,
        function(v) ns.db.refresh = v * 60; ns.dirty = true end, 1, 0, 30, Mins,
        "A blessing with less time left counts as expiring: Smart Buff renews it and the bar marks it."))
    Add(W.Stepper(current, "Greater Blessings from", function() return ns.db.greaterMin or 2 end,
        function(v) ns.db.greaterMin = v; ns.dirty = true end, 1, 1, 10,
        function(v) return v == 1 and "1 player" or ("%d players"):format(v) end,
        "Players of one class needed before the Greater Blessing is used instead of single ones."))
    Add(W.Stepper(current, "Low symbol warning", function() return ns.db.reagentWarn or 0 end,
        function(v) ns.db.reagentWarn = v; ns.dirty = true end, 5, 0, 100, function(v) return v == 0 and "Off" or Int(v) end,
        "Warns on the bar when you carry fewer Symbols of Kings than this."))
    Add(W.Check(current, "Righteous Fury when tanking", function() return ns.db.rfReminder end,
        function(v) ns.db.rfReminder = v; ns.dirty = true end,
        "Smart Buff adds Righteous Fury while you're marked as a tank."))
    Add(W.Check(current, "Auto-assign Oath to tanks", function() return ns.db.autoOath end,
        function(v) ns.db.autoOath = v; if v then ns.AutoOathSelf() end end,
        "Your Oath of Light target follows the tank. Smart Buff and the Oath key cast it."))

    Column()
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
        function(v) ns.db.chatRequests = v end, "Group members can type !bless want might (and more) in chat."))

    Section("Ready Check")
    Add(W.Check(current, "Show on ready check", function() return ns.db.readyCheck ~= false end,
        function(v) ns.db.readyCheck = v end, "Opens the Ready Check window with every ready check."))
    Add(W.Check(current, "Raid buff columns", function() return ns.db.readyCheckRaid end,
        function(v) ns.db.readyCheckRaid = v; if ns.RefreshReadyCheck then ns.RefreshReadyCheck() end end,
        "Adds Fortitude, Mark, Intellect, Spirit, food and flask to the Ready Check."))

    Section("Sound Alerts")
    Add(W.Check(current, "Oath expiring", function() return ns.db.oathSound end,
        function(v) ns.db.oathSound = v end, "30 seconds left."))
    Add(W.Check(current, "Ready check: your blessings missing", function() return ns.db.readyCheckSound end,
        function(v) ns.db.readyCheckSound = v end, "When the Ready Check opens and you still owe blessings."))
    local snd = W.Dropdown(current, "Alert sound", function() return ns.SoundList() end,
        function() return ns.CurrentSound().name end,
        function(item) ns.db.alertSoundName = item.name; ns.Alert() end,
        "Game sounds, plus sounds from other addons (LibSharedMedia).", 110)
    snd.button:ClearAllPoints(); snd.button:SetPoint("RIGHT", -60, 0)
    local preview = W.Button(snd, "Preview", 56, 20, function() ns.Alert() end)
    preview:SetPoint("RIGHT")
    Add(snd)
    local function SoundOn() return ns.db.oathSound or ns.db.readyCheckSound end
    Dep(snd, SoundOn, "Turn on an alert above.")
    Dep(preview, SoundOn)

    -- ---- page 2: Appearance (how it looks) ----
    Page()
    Section("Blessing Bar")
    Add(W.Check(current, "Lock bar", function() return ns.db.locked end, function(v) ns.db.locked = v end,
        "Stops the bar being dragged."))
    Choice("Display", "barMode", { "standard", "compact", "action" }, { "Standard", "Compact", "Action only" }, "standard", nil,
        "Standard: a row per class. Compact: icons only. Action only: just the rows you still owe (fixed at the pull in combat).")
    Choice("Orientation", "barLayout", { "compact", "horizontal" }, { "Vertical", "Horizontal" }, "compact")
    local grow = W.Check(current, "Grow upward", function() return ns.db.growUp end,
        function(v) ns.db.growUp = v; ns.dirty = true end, "New rows are added above.")
    Add(grow)
    Dep(grow, function() return ns.db.barLayout ~= "horizontal" end, "Vertical only.")
    Add(W.Check(current, "Fade when idle", function() return ns.db.fadeIdle end,
        function(v) ns.db.fadeIdle = v; ns.ApplyBarFade() end, "Dims the bar when there's nothing to cast."))
    Add(W.Check(current, "Timers", function() return ns.db.rowTimers ~= false end,
        function(v) ns.db.rowTimers = v; ns.dirty = true end, "Time left on each row."))
    local cn = W.Check(current, "Class names", function() return ns.db.barClassNames end,
        function(v) ns.db.barClassNames = v; ns.dirty = true end, "Makes the rows wider.")
    Add(cn)
    Add(W.Check(current, "Aura button", function() return ns.db.auraButton ~= false end,
        function(v) ns.db.auraButton = v; ns.dirty = true end, "Your assigned aura. Click: turn it on."))
    Add(W.Check(current, "Seal button", function() return ns.db.sealButton end,
        function(v) ns.db.sealButton = v; ns.dirty = true end, "Click: cast. Wheel: change seal."))

    Section("Bar Position")
    Add(W.NumberBox(current, "Bar X", function() return (BarOffset()) end,
        function(v) local _, y = BarOffset(); SetBarOffset(v, y) end, "From the middle of the screen. Enter to apply."))
    Add(W.NumberBox(current, "Bar Y", function() return select(2, BarOffset()) end,
        function(v) local x = BarOffset(); SetBarOffset(x, v) end, "From the middle of the screen. Enter to apply."))
    Add(W.Button(current, "Center", 80, 22, function() SetBarOffset(0, 0); ns.RefreshOptions() end))

    Column()
    Section("Bar Size")
    Add(W.Stepper(current, "Bar scale", function() return ns.db.scale end, function(v) ns.db.scale = v; ns.ApplyScale() end,
        0.1, 0.5, 2.0, Scale))
    local rw = W.Stepper(current, "Row width", function() return ns.db.rowWidth or 76 end,
        function(v) ns.db.rowWidth = v; ns.dirty = true end, 8, 60, 140, Px)
    Add(rw)
    Add(W.Stepper(current, "Row height", function() return ns.db.rowHeight or 22 end,
        function(v) ns.db.rowHeight = v; ns.dirty = true end, 2, 16, 32, Px, "Also the cell size in Compact."))
    local isz = W.Stepper(current, "Icon size", function() return ns.db.iconSize or 18 end,
        function(v) ns.db.iconSize = v; ns.dirty = true end, 2, 10, 30, Px, "Up to the row height.")
    Add(isz)
    Add(W.Stepper(current, "Background", function() return ns.db.barAlpha or 0.85 end,
        function(v) ns.db.barAlpha = v; ns.dirty = true end, 0.05, 0, 1,
        function(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end, "Row background opacity. Icons and text stay solid."))
    local function Rows() return ns.db.barMode ~= "compact" end
    Dep(rw, Rows, "Not used in Compact.")
    Dep(isz, Rows, "Not used in Compact.")
    Dep(cn, Rows, "Not used in Compact.")

    Section("Raid Frames")
    Add(W.Check(current, "Show blessing icons", function() return ns.db.frameIcons end,
        function(v) ns.db.frameIcons = v; if ns.RefreshFrameIcons then ns.RefreshFrameIcons() end end,
        "Your blessing on each party and raid frame, with time left."))
    local fc = W.Check(current, "Click icon to bless", function() return ns.db.frameIconClick ~= false end,
        function(v) ns.db.frameIconClick = v; if ns.RefreshFrameIcons then ns.RefreshFrameIcons() end end,
        "Casts your blessing on that player. Works in combat.")
    Add(fc)
    local fs = W.Stepper(current, "Raid icon size", function() return ns.db.frameIconSize or 22 end,
        function(v) ns.db.frameIconSize = v; if ns.RefreshFrameIcons then ns.RefreshFrameIcons() end end,
        2, 14, 40, Px)
    Add(fs)
    local function Icons() return ns.db.frameIcons end
    Dep(fc, Icons, "Turn on Show blessing icons.")
    Dep(fs, Icons, "Turn on Show blessing icons.")

    Section("Windows")
    Add(W.Stepper(current, "Main window scale", function() return ns.WinScale() end,
        function(v) ns.db.winScale = v; ns.ApplyScale() end, 0.1, 0.6, 1.5, Scale))
    Add(W.Stepper(current, "Ready Check scale", function() return ns.RCScale() end,
        function(v)
            ns.db.rcScale = v; ns.ApplyScale()
            local rc = _G.PallyPulseReadyCheck     -- open it so the change is visible
            if not (rc and rc:IsShown()) and ns.ShowReadyCheck then ns.ShowReadyCheck() end
        end, 0.1, 0.6, 1.5, Scale))
    Add(W.Check(current, "Show minimap button", function() return ns.db.showMinimap end,
        function(v) ns.db.showMinimap = v; if ns.UpdateMinimap then ns.UpdateMinimap() end end))
    Add(W.Check(current, "Hide empty classes", function() return ns.db.hideEmptyClasses end,
        function(v) ns.db.hideEmptyClasses = v; if ns.RefreshWindow then ns.RefreshWindow() end end,
        "Blessings tab: hides classes with nobody in the group. Their assignments are kept."))
    Add(W.Dropdown(current, "Font", W.FontList, function() return ns.db.font or "Default" end,
        function(item) ns.db.font = item.name; W.ApplyStyle() end, "Fonts from LibSharedMedia, when another addon has loaded it."))

    -- ---- page 3: Advanced ----
    Page()
    Section("Compatibility")
    Add(W.Check(current, "PallyPower sync", function() return ns.db.compat end, function(v) ns.db.compat = v end,
        "Also sends and reads PallyPower's assignment messages, so paladins using PallyPower see yours and you see theirs."))

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
    local rd = W.Button(current, "Restore defaults", 120, 22, function() StaticPopup_Show("PALLYPULSE_DEFAULTS") end)
    W.Tip(rd, function(t)
        t:AddLine("Restore defaults", 1, 1, 1)
        t:AddLine("Options only. Assignments, presets, priorities and key bindings are kept.", S.dim[1], S.dim[2], S.dim[3], true)
    end)
    Add(rd)

    Section("Diagnostics")
    local cpu = W.Button(current, "CPU report", 120, 22, function() if ns.ProfileReport then ns.ProfileReport() end end)
    W.Tip(cpu, function(t) t:AddLine("CPU report", 1, 1, 1); t:AddLine("Time and memory used, in chat. Same as /pulse debug cpu.", S.dim[1], S.dim[2], S.dim[3], true) end)
    Add(cpu)
    local sp = W.Button(current, "Spec report", 120, 22, function() if ns.DebugSpecs then ns.DebugSpecs() end end)
    W.Tip(sp, function(t) t:AddLine("Spec report", 1, 1, 1); t:AddLine("Detected specs, in chat. Same as /pulse debug specs.", S.dim[1], S.dim[2], S.dim[3], true) end)
    Add(sp)

    Column()
    -- Priorities: pick a class, then set the blessing order for each of its specs
    Section("Blessing Priorities")
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

    -- dependent settings follow their parent at once
    local function UpdateDeps()
        for _, d in ipairs(deps) do
            local w, on = d[1], d[2]() and true or false
            if w.SetAvailable then w:SetAvailable(on, d[3])
            elseif w.Enable then if on then w:Enable() else w:Disable() end end
        end
    end
    W.onChange = UpdateDeps
    depsUpdate = UpdateDeps

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
    for i, name in ipairs({ "General", "Appearance", "Advanced" }) do
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
    local colX, y0 = { 14, 264 }, -(top + 28)
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
                if r.widget.SetWidth and not r.heading and r.widget:GetObjectType() == "Frame" then r.widget:SetWidth(240) end
                if r.heading and r.widget.rule then r.widget.rule:SetWidth(240) end
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
    if depsUpdate then depsUpdate() end
end

function ns.HideSettings() end
