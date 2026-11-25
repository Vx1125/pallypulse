local ADDON, ns = ...
local S, W = ns.STYLE, ns.W

-- Main window, four tabs:
--   Blessings  paladin x class grid, plus each paladin's Aura and Oath of Light
--   Players    everyone in the group: guessed role, the blessing you give them (click to set
--              an exception), requests, and whether it's up
--   Group      who runs PallyPulse (which version), PallyPower, or nothing
--   Options    settings

local CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local PAD, CELL, GAP, NAME_W, ROW_H = 10, 26, 3, 108, 30
local MAX_ROWS = 10
local COL_W = CELL + GAP
local GRID_X = PAD + NAME_W
local AURA_X = GRID_X + #ns.CLASSES * COL_W - GAP + 12
local OATH_X = AURA_X + CELL + 10
local OATH_W = 84
local WIDTH = OATH_X + OATH_W + PAD
local TITLE_H, TABS_H = 28, 24
local TOP = TITLE_H + TABS_H + 6          -- where tab content starts
local HEADS_Y = TOP
local ROWS_Y = HEADS_Y + 36
local BOTTOM = 62
local LIST_ROW, LIST_MAX_VISIBLE = 22, 12

local win, picker
local panels, tabs = {}, {}
local current = "blessings"

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function CanEdit(pal)
    if ns.CanEditRow(pal) then return true end
    ns.Print("Requires leader or assist.")
    return false
end

local function BlessingOptions(pal)
    if pal == ns.Me() then ns.ComputeOwnCaps() end     -- your spellbook, fresh
    local caps = ns.caps[pal]
    local list = { { key = "NONE", icon = W.NOTREADY, label = "No blessing" } }
    for _, b in ipairs(ns.BLESSINGS) do
        if not caps or caps[b.key] then list[#list + 1] = { key = b.key, icon = b.icon, label = b.single } end
    end
    return list
end

local function AuraOptions(pal)
    local caps = ns.auraCaps[pal]
    local list = { { key = "NONE", icon = W.NOTREADY, label = "No aura" } }
    for _, a in ipairs(ns.AURAS) do
        if not caps or next(caps) == nil or caps[a.key] then list[#list + 1] = { key = a.key, icon = a.icon, label = a.name } end
    end
    return list
end

local function Cycle(pal, class, dir)
    local list = BlessingOptions(pal)
    local cur = (ns.assign[pal] and ns.assign[pal][class]) or "NONE"
    local idx = 1
    for i, o in ipairs(list) do if o.key == cur then idx = i break end end
    idx = ((idx - 1 + dir) % #list) + 1
    ns.SetAssignment(pal, class, list[idx].key, true)
end

local function Analyze()
    local dup, uncovered, ncon = {}, {}, 0
    for _, class in ipairs(ns.CLASSES) do
        local members = ns.byClass[class]
        if members and #members > 0 and #ns.paladins > 0 then
            local seen, any = {}, false
            for _, pal in ipairs(ns.paladins) do
                local key = ns.assign[pal] and ns.assign[pal][class]
                if key then
                    any = true
                    if seen[key] then
                        dup[pal .. "|" .. class] = true
                        dup[seen[key] .. "|" .. class] = true
                        ncon = ncon + 1
                    else
                        seen[key] = pal
                    end
                end
            end
            if not any then uncovered[#uncovered + 1] = class end
        end
    end
    return dup, uncovered, ncon
end

-- "Bob (Kings, Might)" for each player of a class with a request
local function ClassRequests(class)
    local out = {}
    for _, e in ipairs(ns.byClass[class] or {}) do
        local req = ns.db.requests[e.name]
        if req and #req > 0 then
            local t = {}
            for _, k in ipairs(req) do if ns.BY_KEY[k] then t[#t + 1] = ns.BY_KEY[k].single:gsub("^Blessing of ", "") end end
            out[#out + 1] = ns.FirstName(e.name) .. " (" .. table.concat(t, ", ") .. ")"
        end
    end
    return out
end

local function ClassNames(list, max)
    local names = {}
    for i, class in ipairs(list) do
        if i > max then names[#names + 1] = ("+%d more"):format(#list - max) break end
        names[#names + 1] = LOCALIZED_CLASS_NAMES_MALE[class] or class
    end
    return table.concat(names, ", ")
end

-- ---------------------------------------------------------------------------
-- Icon picker flyout (blessings, auras)
-- ---------------------------------------------------------------------------
local function OpenPicker(anchor, options, cur, onPick)
    if not picker then
        picker = W.Panel(UIParent, 10, 10)
        picker:SetFrameStrata("FULLSCREEN_DIALOG")
        picker:Hide()
        picker.btns = {}
        W.AutoClose(picker)
    end
    for _, b in ipairs(picker.btns) do b:Hide() end
    for i, o in ipairs(options) do
        local b = picker.btns[i]
        if not b then
            b = CreateFrame("Button", nil, picker, BackdropTemplateMixin and "BackdropTemplate" or nil)
            W.IconSlot(b, 26)
            b.check:Hide(); b.count:Hide()
            b.strip:SetColorTexture(0, 0, 0, 0)
            b:SetScript("OnClick", function(self) picker.onPick(self.opt.key); picker:Hide() end)
            b:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(unpack(S.gold))
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(self.opt.label, 1, 1, 1)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(self.baseBorder or S.border)); GameTooltip:Hide() end)
            picker.btns[i] = b
        end
        b.opt = o
        b.icon:SetTexture(o.icon)
        if o.icon == W.NOTREADY or o.plain then b.icon:SetTexCoord(0, 1, 0, 1) else b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        b.baseBorder = (o.key == cur) and S.gold or S.border
        b:SetBackdropBorderColor(unpack(b.baseBorder))
        b:ClearAllPoints()
        b:SetPoint("LEFT", picker, "LEFT", 6 + (i - 1) * 29, 0)
        b:Show()
    end
    picker:SetSize(12 + #options * 29 - 3, 38)
    picker.onPick, picker.anchor = onPick, anchor
    picker:ClearAllPoints()
    picker:SetPoint("BOTTOM", anchor, "TOP", 0, 2)
    picker:SetScale(ns.WinScale and ns.WinScale() or ns.db.scale)
    picker:Show()
end

local function Cell(parent, w, h)
    local c = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    c:SetSize(w, h)
    c:SetBackdrop({ bgFile = W.WHITE, edgeFile = W.WHITE, edgeSize = 1 })
    c:SetBackdropColor(unpack(S.cell))
    c:SetBackdropBorderColor(unpack(S.border))
    c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    c.baseBorder = S.border
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("TOPLEFT", 1, -1); c.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.plus = W.Text(c, 14, S.dim, "CENTER", S.num)
    c.plus:SetAllPoints(); c.plus:SetText("+")
    c:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(self.baseBorder)); if self.row then self.row.hl:Hide() end; GameTooltip:Hide()
    end)
    return c
end

local function Tip(self, title, value, hint)
    self:SetBackdropBorderColor(unpack(S.gold))
    if self.row then self.row.hl:Show() end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title)
    if value then GameTooltip:AddLine(value, 1, 1, 1, true) end
    if hint then GameTooltip:AddLine(hint, 0.6, 0.6, 0.6, true) end
    GameTooltip:Show()
end

-- Scrolling list used by the Players and Group tabs.
local function MakeList(name, parent, top, height, rowBuilder)
    -- named: older versions of the scroll template build their scrollbar from the frame's name
    local sf = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 6, -top)
    sf:SetPoint("RIGHT", parent, "RIGHT", -28, 0)
    sf:SetHeight(height)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(WIDTH - 40, 10)
    sf:SetScrollChild(child)
    sf.rows = {}
    for i = 1, 40 do
        local r = CreateFrame("Frame", nil, child)
        r:SetSize(WIDTH - 40, LIST_ROW)
        r:SetPoint("TOPLEFT", 0, -(i - 1) * LIST_ROW)
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.alt = i % 2 == 0
        r.bg:SetColorTexture(unpack(r.alt and S.rowAlt or { 0, 0, 0, 0 }))
        r.hl = r:CreateTexture(nil, "BACKGROUND", nil, 2)
        r.hl:SetAllPoints(); r.hl:SetColorTexture(S.rowHover[1], S.rowHover[2], S.rowHover[3], 0.9); r.hl:Hide()
        rowBuilder(r)
        r:Hide()
        sf.rows[i] = r
    end
    sf.child = child
    W.SkinScroll(sf)
    return sf
end

local function SizeList(sf, n)
    local vis = math.max(1, math.min(n, LIST_MAX_VISIBLE))
    sf:SetHeight(vis * LIST_ROW)
    sf.child:SetHeight(math.max(n, 1) * LIST_ROW)
    if n <= LIST_MAX_VISIBLE then sf:SetVerticalScroll(0) end
    return vis * LIST_ROW
end

-- ---------------------------------------------------------------------------
-- Title and tabs
-- ---------------------------------------------------------------------------
local function ShowTab(name)
    current = name
    for k, p in pairs(panels) do p:SetShown(k == name) end
    for k, t in pairs(tabs) do
        local on = k == name
        t.text:SetTextColor(unpack(on and S.gold or S.dim))
        t.line:SetShown(on)
    end
    if picker then picker:Hide() end
    ns.RefreshWindow()
end
ns.ShowTab = ShowTab

local function BuildTitle()
    local band = win:CreateTexture(nil, "BACKGROUND", nil, 1)
    band:SetPoint("TOPLEFT", 1, -1); band:SetPoint("TOPRIGHT", -1, -1); band:SetHeight(TITLE_H - 2)
    band:SetColorTexture(unpack(S.header))
    local tb = CreateFrame("Frame", nil, win)
    tb:SetPoint("TOPLEFT", 4, -2); tb:SetPoint("TOPRIGHT", -4, -2); tb:SetHeight(TITLE_H - 4)
    local title = W.Heading(tb, 14)
    title:SetPoint("LEFT", PAD - 4, 0); title:SetText("PallyPulse")
    win.sub = W.Text(tb, 11, S.dim)
    win.sub:SetPoint("LEFT", title, "RIGHT", 8, -1)
    local close = W.CloseButton(tb, function() win:Hide() end)
    close:SetPoint("RIGHT", 0, 0)
    win.testBtn = W.Button(tb, "Test mode", 80, 18, function() if ns.TogglePreview then ns.TogglePreview() end end)
    win.testBtn:SetPoint("RIGHT", close, "LEFT", -6, 0)
    win.testBtn.keepColor = true
    W.Tip(win.testBtn, function(t)
        t:AddLine("Test mode", 1, 1, 1)
        t:AddLine("Fake 13-player raid with two fake paladins. Edit anything; nothing is cast or sent.", 0.7, 0.7, 0.7, true)
    end)
    W.MakeDraggable(win, tb, "win", false)

    local x = PAD
    for _, t in ipairs({ { "blessings", "Blessings" }, { "players", "Players" }, { "group", "Versions" }, { "options", "Options" } }) do
        local b = CreateFrame("Button", nil, win)
        b.text = W.Text(b, 12, S.dim, "CENTER", S.head)
        b.text:SetPoint("CENTER", 0, 1)
        b.text:SetText(t[2])
        b:SetSize(b.text:GetStringWidth() + 20, TABS_H)
        b:SetPoint("TOPLEFT", x, -TITLE_H)
        b.line = b:CreateTexture(nil, "ARTWORK")
        b.line:SetPoint("BOTTOMLEFT", 6, 1); b.line:SetPoint("BOTTOMRIGHT", -6, 1); b.line:SetHeight(2)
        b.line:SetColorTexture(S.gold[1], S.gold[2], S.gold[3], 1)
        b:SetScript("OnClick", function() ShowTab(t[1]) end)
        b:SetScript("OnEnter", function(self) if current ~= t[1] then self.text:SetTextColor(unpack(S.text)) end end)
        b:SetScript("OnLeave", function(self) if current ~= t[1] then self.text:SetTextColor(unpack(S.dim)) end end)
        tabs[t[1]] = b
        x = x + b:GetWidth() + 2
    end
    local tl = win:CreateTexture(nil, "ARTWORK")
    tl:SetPoint("TOPLEFT", band, "BOTTOMLEFT"); tl:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT"); tl:SetHeight(1)
    tl:SetColorTexture(S.border[1], S.border[2], S.border[3], 1)
    local line = win:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 8, -(TITLE_H + TABS_H)); line:SetPoint("TOPRIGHT", -8, -(TITLE_H + TABS_H)); line:SetHeight(1)
    line:SetColorTexture(S.border[1], S.border[2], S.border[3], 0.7)
end

-- ---------------------------------------------------------------------------
-- Blessings tab
-- ---------------------------------------------------------------------------
local function BuildBlessings(P)
    P.heads = {}
    for i, class in ipairs(ns.CLASSES) do
        local h = CreateFrame("Frame", nil, P)
        h:SetSize(CELL, 34)
        h:SetPoint("TOPLEFT", P, "TOPLEFT", GRID_X + (i - 1) * COL_W, -HEADS_Y)
        h:EnableMouse(true)
        h.icon = h:CreateTexture(nil, "ARTWORK")
        h.icon:SetSize(20, 20); h.icon:SetPoint("TOP")
        h.icon:SetTexture(CLASS_ICONS)
        local c = CLASS_ICON_TCOORDS[class]
        h.icon:SetTexCoord(c[1], c[2], c[3], c[4])
        h.count = W.Text(h, 10, S.dim, "CENTER", S.num)
        h.count:SetPoint("BOTTOM", 0, 2); h.count:SetWidth(CELL)
        -- gold dot: someone in this class asked for a blessing
        h.req = h:CreateTexture(nil, "OVERLAY")
        h.req:SetSize(5, 5); h.req:SetPoint("TOPRIGHT", h.icon, "TOPRIGHT", 2, 2)
        h.req:SetColorTexture(S.gold[1], S.gold[2], S.gold[3], 1)
        h.req:Hide()
        h.class = class
        h:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local n = ns.byClass[self.class] and #ns.byClass[self.class] or 0
            GameTooltip:AddLine(LOCALIZED_CLASS_NAMES_MALE[self.class] or self.class, W.ClassColor(self.class))
            GameTooltip:AddLine(("%d in group"):format(n), unpack(S.dim))
            local req = ClassRequests(self.class)
            if #req > 0 then
                GameTooltip:AddLine("Requests", unpack(S.gold))
                for _, t in ipairs(req) do GameTooltip:AddLine(t, 1, 1, 1) end
            end
            GameTooltip:Show()
        end)
        h:SetScript("OnLeave", function() GameTooltip:Hide() end)
        P.heads[i] = h
    end
    local function Head(x, w, label, color, tip)
        local h = CreateFrame("Frame", nil, P)
        h:SetSize(w, 34); h:SetPoint("TOPLEFT", P, "TOPLEFT", x, -HEADS_Y)
        h:EnableMouse(true)
        h.icon = h:CreateTexture(nil, "ARTWORK")
        h.icon:SetSize(20, 20); h.icon:SetPoint("TOP")
        h.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local l = W.Text(h, 10, color, "CENTER", S.head)
        l:SetPoint("BOTTOM", 0, 2); l:SetWidth(w + 10); l:SetText(label)
        h:SetScript("OnEnter", function(self)
            if not tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(label, unpack(color))
            GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true); GameTooltip:Show()
        end)
        h:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return h
    end
    P.auraHead = Head(AURA_X, CELL, "Aura", S.gold)
    P.auraHead.icon:SetTexture(ns.AURA_BY_KEY.DEVOTION.icon)
    P.oathHead = Head(OATH_X, OATH_W, "Oath", S.paladin)

    for _, x in ipairs({ AURA_X - 6, OATH_X - 5 }) do
        local div = P:CreateTexture(nil, "ARTWORK")
        div:SetWidth(1)
        div:SetPoint("TOPLEFT", P, "TOPLEFT", x, -HEADS_Y)
        div:SetPoint("BOTTOMLEFT", P, "BOTTOMLEFT", x, BOTTOM - 4)
        div:SetColorTexture(S.frame[1], S.frame[2], S.frame[3], 0.3)
    end

    P.rows = {}
    for r = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, P)
        row:SetSize(WIDTH - 12, ROW_H)
        row:SetPoint("TOPLEFT", 6, -(ROWS_Y + (r - 1) * ROW_H))
        row.bg = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.bg:SetAllPoints()
        row.alt = r % 2 == 0
        row.hl = row:CreateTexture(nil, "BACKGROUND", nil, 2)
        row.hl:SetAllPoints(); row.hl:SetColorTexture(S.rowHover[1], S.rowHover[2], S.rowHover[3], 0.9); row.hl:Hide()
        -- paladin-pink edge: one row per paladin
        row.edge = row:CreateTexture(nil, "BORDER")
        row.edge:SetPoint("TOPLEFT"); row.edge:SetPoint("BOTTOMLEFT"); row.edge:SetWidth(2)
        row.edge:SetColorTexture(S.paladin[1], S.paladin[2], S.paladin[3], 0.8)
        row.status = row:CreateTexture(nil, "ARTWORK")
        row.status:SetSize(10, 10); row.status:SetPoint("LEFT", PAD - 6, 0)
        row.name = W.Text(row, 12, S.text)
        row.name:SetPoint("LEFT", row.status, "RIGHT", 4, 0)
        row.name:SetWidth(NAME_W - 18); row.name:SetWordWrap(false)

        row.cells = {}
        for i, class in ipairs(ns.CLASSES) do
            local cell = Cell(row, CELL, CELL)
            cell:SetPoint("LEFT", row, "LEFT", GRID_X - 6 + (i - 1) * COL_W, 0)
            cell:EnableMouseWheel(true)
            cell.class, cell.row = class, row
            cell:SetScript("OnClick", function(self, btn)
                if not CanEdit(self.pal) then return end
                if btn == "RightButton" or IsShiftKeyDown() then
                    ns.SetAssignment(self.pal, self.class, "NONE", true)
                else
                    local cur = (ns.assign[self.pal] and ns.assign[self.pal][self.class]) or "NONE"
                    local pal, class = self.pal, self.class
                    OpenPicker(self, BlessingOptions(pal), cur, function(key) ns.SetAssignment(pal, class, key, true) end)
                end
            end)
            cell:SetScript("OnMouseWheel", function(self, delta)
                if ns.CanEditRow(self.pal) then Cycle(self.pal, self.class, delta > 0 and -1 or 1) end
            end)
            cell:SetScript("OnEnter", function(self)
                local key = ns.assign[self.pal] and ns.assign[self.pal][self.class]
                local r, g, b = W.ClassColor(self.class)
                local lines = {}
                if key and ns.BY_KEY[key] then
                    local greater, single = ns.CastNames(key, self.class)
                    lines[#lines + 1] = greater or ns.BY_KEY[key].single
                    -- your own row: who is still missing it
                    if self.pal == ns.Me() and ns.byClass[self.class] then
                        local need, total = ns.ClassStatus(self.class, key)
                        if total > 0 then
                            lines[#lines + 1] = need == 0 and (W.Hex(unpack(S.good)) .. "All buffed|r")
                                or (W.Hex(unpack(S.bad)) .. ("%d/%d missing"):format(need, total) .. "|r")
                        end
                    end
                else
                    lines[#lines + 1] = W.Hex(unpack(S.dim)) .. "None|r"
                end
                local same = ns.SameBlessing(self.pal, self.class)
                if same then lines[#lines + 1] = W.Hex(unpack(S.bad)) .. "Also from " .. table.concat(same, ", ") .. "|r" end
                local req = ClassRequests(self.class)
                if #req > 0 then lines[#lines + 1] = W.Hex(unpack(S.gold)) .. "Requests:|r " .. table.concat(req, ", ") end
                Tip(self, W.Hex(r, g, b) .. (LOCALIZED_CLASS_NAMES_MALE[self.class] or self.class) .. "|r - " .. ns.FirstName(self.pal),
                    table.concat(lines, "\n"),
                    ns.CanEditRow(self.pal) and "Click: choose   Wheel: cycle   Right-click: clear" or nil)
            end)
            row.cells[i] = cell
        end

        local ac = Cell(row, CELL, CELL)
        ac:SetPoint("LEFT", row, "LEFT", AURA_X - 6, 0)
        ac.row = row
        ac:SetScript("OnClick", function(self, btn)
            if not CanEdit(self.pal) then return end
            if btn == "RightButton" then ns.SetAura(self.pal, nil, true) return end
            local pal = self.pal
            OpenPicker(self, AuraOptions(pal), ns.AuraFor(pal) or "NONE", function(key) ns.SetAura(pal, key, true) end)
        end)
        ac:SetScript("OnEnter", function(self)
            local k = ns.AuraFor(self.pal)
            Tip(self, W.Hex(unpack(S.gold)) .. "Aura|r - " .. ns.FirstName(self.pal),
                k and ns.AURA_BY_KEY[k].name or "None",
                ns.CanEditRow(self.pal) and "Click: choose   Right-click: clear" or nil)
        end)
        row.aura = ac

        local oc = Cell(row, OATH_W, CELL)
        oc:SetPoint("LEFT", row, "LEFT", OATH_X - 6, 0)
        oc.row = row
        oc.icon:Hide()
        oc.text = W.Text(oc, 11, S.text, "CENTER")
        oc.text:SetPoint("LEFT", 3, 0); oc.text:SetPoint("RIGHT", -3, 0); oc.text:SetWordWrap(false)
        oc:SetScript("OnClick", function(self, btn)
            if not CanEdit(self.pal) then return end
            if btn == "RightButton" or IsShiftKeyDown() then
                ns.SetOath(self.pal, nil, true)
            else
                local ok, why = ns.SetOathToTarget(self.pal)
                if not ok then ns.Print(why) end
            end
        end)
        oc:SetScript("OnEnter", function(self)
            Tip(self, W.Hex(unpack(S.paladin)) .. "Oath of Light|r - " .. ns.FirstName(self.pal),
                ns.oath[self.pal] or "None",
                ns.CanEditRow(self.pal) and "Click: set to target   Right-click: clear" or nil)
        end)
        row.oath = oc

        row:Hide()
        P.rows[r] = row
    end

    P.empty = W.Text(P, 12, S.dim, "CENTER")
    P.empty:SetPoint("TOP", 0, -(ROWS_Y + 8)); P.empty:SetWidth(WIDTH - 40)
    P.empty:SetText("No paladins in group")

    P.status = W.Text(P, 11, S.dim)
    P.status:SetPoint("BOTTOMLEFT", PAD, 40); P.status:SetWidth(WIDTH - PAD * 2)

    local auto = W.Button(P, "Auto-assign", 96, 22, function() ns.AutoAssign() end)
    auto:SetPoint("BOTTOMLEFT", PAD - 2, 10)
    local presets = W.Button(P, "Presets", 72, 22, function(self) ns.TogglePresetMenu(self) end)
    presets:SetPoint("LEFT", auto, "RIGHT", 2, 0)
    StaticPopupDialogs["PALLYPULSE_CLEAR"] = {
        text = "Clear all assignments?", button1 = YES or "Yes", button2 = NO or "No",
        OnAccept = function() ns.ClearAll() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    local clear = W.Button(P, "Clear", 60, 22, function() StaticPopup_Show("PALLYPULSE_CLEAR") end)
    clear:SetPoint("LEFT", presets, "RIGHT", 2, 0)
    P.preset = W.Text(P, 11, S.gold, "LEFT")
    P.preset:SetPoint("LEFT", clear, "RIGHT", 8, 0); P.preset:SetWidth(108); P.preset:SetWordWrap(false)
    local announce = W.Button(P, "Announce", 84, 22, function() ns.Announce() end)
    announce:SetPoint("BOTTOMRIGHT", -PAD + 2, 10)
    local sync = W.Button(P, "Sync", 56, 22, function() ns.RequestSync() end)
    sync:SetPoint("RIGHT", announce, "LEFT", -2, 0)
    W.Tip(auto, function(t)
        t:AddLine("Auto-assign", 1, 1, 1)
        t:AddLine("Blessings, auras and Oaths by class and role", 0.7, 0.7, 0.7, true)
    end)
end

local function RefreshBlessings(P)
    local dup, uncovered, ncon = Analyze()
    local npal = math.min(#ns.paladins, MAX_ROWS)
    P.oathHead.icon:SetTexture(ns.OathIcon())
    for _, h in ipairs(P.heads) do
        local n = ns.byClass[h.class] and #ns.byClass[h.class] or 0
        h.count:SetText(n)
        h.count:SetTextColor(unpack(n > 0 and S.text or S.dim))
        h.icon:SetDesaturated(n == 0)
        h.icon:SetAlpha(n == 0 and 0.35 or 1)
        h.req:SetShown(n > 0 and #ClassRequests(h.class) > 0)
    end
    local pname, same = ns.ActivePreset and ns.ActivePreset()
    if pname then
        P.preset:SetText(same and pname or (pname .. " (changed)"))
        P.preset:SetTextColor(unpack(same and S.gold or S.dim))
    else
        P.preset:SetText("")
    end
    local me = ns.Me()
    for r = 1, MAX_ROWS do
        local row, pal = P.rows[r], ns.paladins[r]
        if pal and r <= npal then
            row:Show()
            row.bg:SetColorTexture(unpack(pal == me and S.rowSel or (row.alt and S.rowAlt or { 0, 0, 0, 0 })))
            row.name:SetText(pal == me and (ns.FirstName(pal) .. W.Hex(unpack(S.dim)) .. " (you)|r") or ns.FirstName(pal))
            row.name:SetTextColor(W.ClassColor("PALADIN"))
            local heard = (pal == me) or ns.caps[pal] ~= nil
            row.status:SetTexture(heard and W.READY or W.WAITING)
            row.name:SetAlpha(heard and 1 or 0.65)
            local editable = ns.CanEditRow(pal)
            for _, cell in ipairs(row.cells) do
                cell.pal = pal
                local key = ns.assign[pal] and ns.assign[pal][cell.class]
                local has = ns.byClass[cell.class] and #ns.byClass[cell.class] > 0
                if key and ns.BY_KEY[key] then
                    cell.icon:SetTexture(ns.BY_KEY[key].icon); cell.icon:SetAlpha(has and 1 or 0.35); cell.plus:Hide()
                else
                    cell.icon:SetTexture(nil); cell.plus:Show(); cell.plus:SetAlpha(has and 0.6 or 0.2)
                end
                cell.baseBorder = dup[pal .. "|" .. cell.class] and S.bad or S.border
                cell:SetBackdropBorderColor(unpack(cell.baseBorder))
                cell:SetAlpha(editable and 1 or 0.6)
            end
            local ac = row.aura
            ac.pal = pal
            local ak = ns.AuraFor(pal)
            if ak then ac.icon:SetTexture(ns.AURA_BY_KEY[ak].icon); ac.plus:Hide()
            else ac.icon:SetTexture(nil); ac.plus:Show(); ac.plus:SetAlpha(0.6) end
            ac:SetAlpha(editable and 1 or 0.6)

            local oc = row.oath
            oc.pal = pal
            local tgt = ns.oath[pal]
            oc.plus:Hide()
            if ns.oathCap[pal] == false then
                oc.text:SetText("No talent"); oc.text:SetTextColor(S.dim[1], S.dim[2], S.dim[3], 0.6); oc.baseBorder = S.border
            elseif tgt then
                local unit = ns.UnitForName(tgt)
                if unit then
                    local _, cls = UnitClass(unit)
                    oc.text:SetText(ns.FirstName(tgt)); oc.text:SetTextColor(W.ClassColor(cls or "PALADIN")); oc.baseBorder = S.border
                else
                    oc.text:SetText(ns.FirstName(tgt) .. " (left)"); oc.text:SetTextColor(unpack(S.dim)); oc.baseBorder = S.warn
                end
            else
                oc.text:SetText("+"); oc.text:SetTextColor(unpack(S.dim)); oc.baseBorder = S.border
            end
            oc:SetBackdropBorderColor(unpack(oc.baseBorder))
            oc:SetAlpha(editable and 1 or 0.6)
        else
            row:Hide()
        end
    end
    P.empty:SetShown(npal == 0)
    local text, color
    if #ns.paladins == 0 then
        text, color = "", S.dim
    elseif ncon > 0 then
        text = ("|T%s:12|t  %d duplicate%s"):format(W.NOTREADY, ncon, ncon == 1 and "" or "s"); color = S.bad
    elseif #uncovered > 0 then
        text = ("|T%s:12|t  Unassigned: %s"):format(W.WAITING, ClassNames(uncovered, 3)); color = S.warn
    else
        text = ("|T%s:12|t  All classes covered"):format(W.READY); color = S.good
    end
    P.status:SetText(text); P.status:SetTextColor(unpack(color))
    return ROWS_Y + math.max(npal, 1) * ROW_H + BOTTOM + 4
end

-- ---------------------------------------------------------------------------
-- Players tab
-- ---------------------------------------------------------------------------
local ROLE_CYCLE = { false, "TANK", "MELEE", "RANGED", "CASTER", "HEALER" }

local LIST_TOP = TOP + 40          -- summary line + column headers
local sortBy = "status"            -- "status", "name", "class", "role"
local ROLE_ORDER = { TANK = 1, HEALER = 2, MELEE = 3, RANGED = 4, CASTER = 5 }

local function BuildPlayers(P)
    -- totals for the whole group (every paladin's blessings, not only yours)
    P.summary = W.Text(P, 11, S.text, "LEFT")
    P.summary:SetPoint("TOPLEFT", PAD, -(TOP + 4))

    -- column headers; Player, Role and Status sort (Player again: by class)
    P.heads = {}
    local hdr = {
        { 28, "Player", "name" }, { 126, "Role", "role" }, { 186, "Yours" }, { 218, "Wants" },
        { 284, "Your Status", "status" }, { 366, "Raid Status", "raid" },
    }
    for _, h in ipairs(hdr) do
        local b = CreateFrame("Button", nil, P)
        b.text = W.Text(b, 11, S.gold, "LEFT", S.head); b.text:SetPoint("LEFT")
        b.text:SetText(h[2])
        b:SetSize(70, 16)
        b:SetPoint("TOPLEFT", h[1], -(TOP + 22))
        b.sort = h[3]
        if b.sort then
            b:SetScript("OnClick", function(self)
                if self.sort == "name" then sortBy = (sortBy == "name") and "class" or "name"
                else sortBy = self.sort end
                ns.RefreshWindow()
            end)
            W.Tip(b, function(t)
                t:AddLine(h[2], 1, 1, 1)
                if h[3] == "status" then t:AddLine("Your blessing on them.", unpack(S.dim))
                elseif h[3] == "raid" then t:AddLine("Every paladin's blessings.", unpack(S.dim)) end
                t:AddLine("Click: sort", 0.6, 0.6, 0.6)
            end)
        else
            b:EnableMouse(false)
        end
        P.heads[#P.heads + 1] = b
    end
    P.rule = P:CreateTexture(nil, "ARTWORK")
    P.rule:SetPoint("TOPLEFT", 8, -(LIST_TOP - 2)); P.rule:SetPoint("TOPRIGHT", -8, -(LIST_TOP - 2)); P.rule:SetHeight(1)
    P.rule:SetColorTexture(S.border[1], S.border[2], S.border[3], 0.5)

    P.list = MakeList("PallyPulsePlayerList", P, LIST_TOP, LIST_ROW * LIST_MAX_VISIBLE, function(r)
        -- status strip: red = your blessing missing, gold = yours expiring, tan = another paladin's missing
        r.strip = r:CreateTexture(nil, "BORDER")
        r.strip:SetPoint("TOPLEFT"); r.strip:SetPoint("BOTTOMLEFT"); r.strip:SetWidth(2)
        r.cicon = r:CreateTexture(nil, "ARTWORK")
        r.cicon:SetSize(14, 14); r.cicon:SetPoint("LEFT", 4, 0)
        r.cicon:SetTexture(CLASS_ICONS)
        r.name = W.Text(r, 12, S.text); r.name:SetPoint("LEFT", 22, 0); r.name:SetWidth(96); r.name:SetWordWrap(false)

        r.role = CreateFrame("Button", nil, r)
        r.role:SetSize(58, LIST_ROW); r.role:SetPoint("LEFT", 120, 0)
        r.role:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        r.role.text = W.Text(r.role, 11, S.dim); r.role.text:SetPoint("LEFT")
        r.role:SetScript("OnClick", function(self, btn)
            local e = self:GetParent().e
            local cur = ns.db.roleOverride[e.name] or false
            if btn == "RightButton" then ns.db.roleOverride[e.name] = nil
            else
                local idx = 1
                for i, v in ipairs(ROLE_CYCLE) do if v == cur then idx = i break end end
                ns.db.roleOverride[e.name] = ROLE_CYCLE[(idx % #ROLE_CYCLE) + 1] or nil
            end
            if ns.AutoOverrides then ns.AutoOverrides() end   -- re-plan exceptions for the new role
            ns.dirty = true
            ns.RefreshWindow()
        end)
        r.role:SetScript("OnEnter", function(self)
            local e = self:GetParent().e
            local role, why, specName = ns.GuessRole(e)
            self:GetParent().hl:Show()
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Role: " .. (role and ns.ROLE_LABEL[role] or "Unknown"), 1, 1, 1)
            GameTooltip:AddLine(why == "set by hand" and "Manual" or (why == "spec" and tostring(specName)) or "Auto",
                unpack(S.dim))
            GameTooltip:AddLine("Click: set   Right-click: auto", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        r.role:SetScript("OnLeave", function(self) self:GetParent().hl:Hide(); GameTooltip:Hide() end)

        r.cell = Cell(r, 20, 20)
        r.cell:SetPoint("LEFT", 180, 0)
        r.cell.plus:SetFont(S.num, 12, "")
        r.cell.badge = W.Text(r.cell, 9, S.gold, "RIGHT", S.num, "OUTLINE")
        r.cell.badge:SetPoint("BOTTOMRIGHT", 2, -2)
        r.cell:SetScript("OnClick", function(self, btn)
            local e = self:GetParent().e
            local me = ns.Me()
            if btn == "RightButton" then ns.SetOverride(me, e.name, nil, true) return end
            local opts = { { key = "DEFAULT", icon = "Interface\\Buttons\\UI-RefreshButton", label = "Class default", plain = true } }
            for _, o in ipairs(BlessingOptions(me)) do opts[#opts + 1] = o end
            local cur = ns.db.override[me] and ns.db.override[me][e.name] or "DEFAULT"
            OpenPicker(self, opts, cur, function(key) ns.SetOverride(me, e.name, key, true) end)
        end)
        r.cell:SetScript("OnEnter", function(self)
            local e = self:GetParent().e
            local me = ns.Me()
            local key = ns.KeyFor(me, e)
            local _, kind = ns.IsException(me, e)
            local req = ns.db.requests[e.name]
            local value = (key and ns.BY_KEY[key].single or "None") .. (kind == "hand" and " (manual)" or kind == "auto" and " (auto)" or "")
            if req and req[1] and ns.BY_KEY[req[1]] then
                value = value .. "\n" .. W.Hex(unpack(S.gold)) .. "Wants " .. ns.BY_KEY[req[1]].single:gsub("^Blessing of ", "") .. "|r"
            end
            Tip(self, ns.FirstName(e.name), value, "Click: override   Right-click: reset")
        end)
        r.cell.row = r

        r.wants = W.Text(r, 11, S.dim); r.wants:SetPoint("LEFT", 212, 0); r.wants:SetWidth(62); r.wants:SetWordWrap(false)
        r.stat = W.Text(r, 11, S.text); r.stat:SetPoint("LEFT", 278, 0); r.stat:SetWidth(78); r.stat:SetWordWrap(false)
        r.raid = W.Text(r, 11, S.text); r.raid:SetPoint("LEFT", 360, 0); r.raid:SetWidth(100); r.raid:SetWordWrap(false)
    end)
    P.note = W.Text(P, 11, S.dim)
    P.note:SetWidth(WIDTH - PAD * 2)
    P.note:SetText("")
end

-- Sort rank: what you need to do first.
--   1 your blessing missing, 2 yours expiring, 3 another paladin's missing, 4 buffed, 5 dead / offline
local function Rank(rd)
    if rd.state == "off" then return 5 end
    if rd.mine == "missing" then return 1 end
    if rd.mine == "expiring" then return 2 end
    if rd.state == "need" then return 3 end
    return 4
end

local function RefreshPlayers(P)
    local me = ns.Me()
    local items = {}
    local nOk, nNeed, nOff = 0, 0, 0
    for i, e in ipairs(ns.roster) do
        if i > 40 then break end
        local rd = ns.Readiness(e)
        if rd.state == "ok" then nOk = nOk + 1 elseif rd.state == "need" then nNeed = nNeed + 1 else nOff = nOff + 1 end
        items[#items + 1] = { e = e, rd = rd, rank = Rank(rd) }
    end
    local classOrder = {}
    for i, c in ipairs(ns.CLASSES) do classOrder[c] = i end
    -- ties go by name, never by time left, so rows don't shuffle as timers tick
    table.sort(items, function(a, b)
        local ea, eb = a.e, b.e
        if sortBy == "status" then
            if a.rank ~= b.rank then return a.rank < b.rank end
        elseif sortBy == "raid" then
            local ra, rb = (a.rd.state == "need" and 1) or (a.rd.state == "ok" and 2) or 3, (b.rd.state == "need" and 1) or (b.rd.state == "ok" and 2) or 3
            if ra ~= rb then return ra < rb end
        elseif sortBy == "class" then
            local ca, cb = classOrder[ea.class] or 99, classOrder[eb.class] or 99
            if ca ~= cb then return ca < cb end
        elseif sortBy == "role" then
            local ra, rb = ROLE_ORDER[ns.GuessRole(ea) or ""] or 9, ROLE_ORDER[ns.GuessRole(eb) or ""] or 9
            if ra ~= rb then return ra < rb end
        end
        return (ea.name or "") < (eb.name or "")
    end)

    -- same counts as the Ready Check
    P.summary:SetText(("%d players  ·  %s%d|r Buffed  ·  %s%d|r Missing  ·  %s%d|r Unavailable"):format(
        #items, W.Hex(unpack(S.good)), nOk, W.Hex(unpack(nNeed > 0 and S.bad or S.dim)), nNeed, W.Hex(unpack(S.off)), nOff))
    for _, h in ipairs(P.heads) do
        if h.sort then
            local on = (h.sort == sortBy) or (h.sort == "name" and sortBy == "class")
            if h.sort == "name" then h.text:SetText(sortBy == "class" and "Class" or "Player") end
            h.text:SetTextColor(unpack(on and S.gold or S.dim))
        end
    end

    local n = 0
    for i, it in ipairs(items) do
        n = i
        local e, rd = it.e, it.rd
        local key = rd.myKey
        local r = P.list.rows[i]
        r.e = e
        r:Show()
        r:SetAlpha(rd.here and 1 or 0.5)
        r.bg:SetColorTexture(unpack(rd.mine == "missing" and S.rowMiss or (r.alt and S.rowAlt or { 0, 0, 0, 0 })))
        local sc = (rd.mine == "missing" and S.bad) or (rd.mine == "expiring" and S.warn) or (rd.state == "need" and S.other) or nil
        r.strip:SetShown(sc ~= nil)
        if sc then r.strip:SetColorTexture(sc[1], sc[2], sc[3], 1) end
        local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[e.class]
        if tc then r.cicon:SetTexCoord(tc[1] + 0.02, tc[2] - 0.02, tc[3] + 0.02, tc[4] - 0.02); r.cicon:Show() else r.cicon:Hide() end
        r.name:SetText(ns.FirstName(e.name)); r.name:SetTextColor(W.ClassColor(e.class))
        local role, why = ns.GuessRole(e)
        local spec = why ~= "set by hand" and ns.SpecLabel(e)
        r.role.text:SetText(spec or ((role and ns.ROLE_LABEL[role] or "?") .. (why == "set by hand" and "*" or "")))
        r.role.text:SetTextColor(unpack(role and S.text or S.dim))
        local isEx = ns.IsException(me, e)
        if key then r.cell.icon:SetTexture(ns.BY_KEY[key].icon); r.cell.plus:Hide()
        else r.cell.icon:SetTexture(nil); r.cell.plus:Show() end
        r.cell.badge:SetText(isEx and "*" or "")
        r.cell.baseBorder = (rd.mine == "missing" and S.bad) or (isEx and S.gold) or S.border
        r.cell:SetBackdropBorderColor(unpack(r.cell.baseBorder))
        local req = ns.db.requests[e.name]
        if req then
            local t = {}
            for _, k in ipairs(req) do t[#t + 1] = ns.BY_KEY[k].single:gsub("^Blessing of ", "") end
            r.wants:SetText(table.concat(t, ", ")); r.wants:SetTextColor(unpack(S.gold))
        else
            r.wants:SetText("-"); r.wants:SetTextColor(unpack(S.dim))
        end
        -- Your Status: your blessing on them
        if not rd.here then
            r.stat:SetText((e.dead or ns.SafeUnit(UnitIsDeadOrGhost, e.unit, false)) and "Dead" or "Offline"); r.stat:SetTextColor(unpack(S.off))
        elseif key then
            local left = rd.left[key]
            local far = e.name ~= me and ns.InRange(ns.BY_KEY[key].single, e.unit) == false
            if not left then r.stat:SetText(far and "Out of range" or "Missing"); r.stat:SetTextColor(unpack(S.bad))
            else
                r.stat:SetText(W.FormatTime(left) ~= "" and W.FormatTime(left) or "Active")
                r.stat:SetTextColor(unpack(rd.mine == "expiring" and S.warn or S.good))
            end
        else
            r.stat:SetText("-"); r.stat:SetTextColor(unpack(S.dim))
        end
        -- Raid Status: every paladin's blessings
        if not rd.here then r.raid:SetText("-"); r.raid:SetTextColor(unpack(S.off))
        elseif rd.state == "need" then
            r.raid:SetText("Incomplete"); r.raid:SetTextColor(unpack(rd.others and S.other or S.bad))
        else
            r.raid:SetText("Ready"); r.raid:SetTextColor(unpack(S.good))
        end
    end
    for i = n + 1, 40 do P.list.rows[i]:Hide() end
    local h = SizeList(P.list, n)
    P.note:ClearAllPoints()
    P.note:SetPoint("TOPLEFT", PAD, -(LIST_TOP + h + 8))
    return LIST_TOP + h + 8 + 30
end

-- ---------------------------------------------------------------------------
-- Group tab (versions)
-- ---------------------------------------------------------------------------
local function BuildGroup(P)
    P.summary = W.Text(P, 11, S.text, "LEFT")
    P.summary:SetPoint("TOPLEFT", PAD, -(TOP + 4))
    for _, h in ipairs({ { 28, "Player" }, { 190, "Addon" }, { 300, "Version" }, { 390, "Status" } }) do
        local t = W.Text(P, 11, S.gold, "LEFT", S.head)
        t:SetPoint("TOPLEFT", h[1], -(TOP + 22)); t:SetText(h[2])
    end
    local rule = P:CreateTexture(nil, "ARTWORK")
    rule:SetPoint("TOPLEFT", 8, -(LIST_TOP - 2)); rule:SetPoint("TOPRIGHT", -8, -(LIST_TOP - 2)); rule:SetHeight(1)
    rule:SetColorTexture(S.border[1], S.border[2], S.border[3], 0.5)
    P.list = MakeList("PallyPulseGroupList", P, LIST_TOP, LIST_ROW * LIST_MAX_VISIBLE, function(r)
        r.dot = r:CreateTexture(nil, "ARTWORK")
        r.dot:SetSize(6, 6); r.dot:SetPoint("LEFT", 8, 0)
        r.name = W.Text(r, 12, S.text); r.name:SetPoint("LEFT", 22, 0); r.name:SetWidth(160); r.name:SetWordWrap(false)
        r.addon = W.Text(r, 11, S.text); r.addon:SetPoint("LEFT", 184, 0); r.addon:SetWidth(104)
        r.ver = W.Text(r, 11, S.text); r.ver:SetPoint("LEFT", 294, 0); r.ver:SetWidth(90); r.ver:SetWordWrap(false)
        r.stat = W.Text(r, 11, S.dim); r.stat:SetPoint("LEFT", 384, 0); r.stat:SetWidth(100); r.stat:SetWordWrap(false)
    end)
    P.footer = W.Text(P, 11, S.dim)
    P.refresh = W.Button(P, "Refresh", 80, 22, function() ns.RequestVersions() end)
end

local function RefreshGroup(P)
    local rows = ns.VersionRows()
    local Parse = ns.ParseVersion or function() return 0 end
    -- newest release seen in the group, to spot old copies
    local newest = Parse(ns.VERSION)
    for _, v in ipairs(rows) do
        if v.addon == "PallyPulse" then newest = math.max(newest, Parse(v.ver)) end
    end
    local n, pp, pulse, none, old = 0, 0, 0, 0, 0
    for i, v in ipairs(rows) do
        if i > 40 then break end
        n = i
        local r = P.list.rows[i]
        r:Show()
        r.name:SetText(ns.FirstName(v.name) .. (v.name == ns.Me() and W.Hex(unpack(S.dim)) .. " (you)|r" or ""))
        r.name:SetTextColor(W.ClassColor(v.class))
        local dot
        if v.addon == "PallyPulse" then
            pulse = pulse + 1
            r.addon:SetText("PallyPulse"); r.addon:SetTextColor(unpack(S.text))
            r.ver:SetText(v.ver or "?"); r.ver:SetTextColor(unpack(S.text))
            local pv = Parse(v.ver)
            if pv > 0 and pv < newest then
                old = old + 1
                r.stat:SetText("Out of date"); r.stat:SetTextColor(unpack(S.warn)); dot = S.warn
            else
                r.stat:SetText("Synced"); r.stat:SetTextColor(unpack(S.good)); dot = S.good
            end
        elseif v.addon == "PallyPower" then
            pp = pp + 1
            r.addon:SetText("PallyPower"); r.addon:SetTextColor(unpack(S.text))
            r.ver:SetText("-"); r.ver:SetTextColor(unpack(S.dim))
            r.stat:SetText("Synced"); r.stat:SetTextColor(unpack(S.good)); dot = S.good
        else
            local pal = v.class == "PALADIN"
            if pal then none = none + 1 end
            r.addon:SetText(pal and "None" or "-"); r.addon:SetTextColor(unpack(S.dim))
            r.ver:SetText("")
            r.stat:SetText(pal and "No sync" or ""); r.stat:SetTextColor(unpack(pal and S.bad or S.dim))
            dot = pal and S.bad or nil
        end
        r.dot:SetShown(dot ~= nil)
        if dot then r.dot:SetColorTexture(dot[1], dot[2], dot[3], 1) end
    end
    for i = n + 1, 40 do P.list.rows[i]:Hide() end
    P.summary:SetText(("%s%d|r PallyPulse   %s%d|r PallyPower   %s%d|r out of date   %s%d|r no sync"):format(
        W.Hex(unpack(S.good)), pulse, W.Hex(unpack(S.good)), pp, W.Hex(unpack(old > 0 and S.warn or S.dim)), old,
        W.Hex(unpack(none > 0 and S.bad or S.dim)), none))
    local h = SizeList(P.list, n)
    P.footer:ClearAllPoints()
    P.footer:SetPoint("TOPLEFT", PAD, -(LIST_TOP + h + 10))
    P.footer:SetText(("You: v%s"):format(ns.VERSION))
    P.refresh:ClearAllPoints()
    P.refresh:SetPoint("TOPRIGHT", P, "TOPRIGHT", -PAD, -(LIST_TOP + h + 5))
    return LIST_TOP + h + 40
end

-- ---------------------------------------------------------------------------
-- Build / refresh
-- ---------------------------------------------------------------------------
local function Build()
    win = W.Panel(UIParent, WIDTH, 200, "PallyPulseWindow")
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:Hide()
    ns.win = win
    tinsert(UISpecialFrames, "PallyPulseWindow")
    BuildTitle()
    for _, name in ipairs({ "blessings", "players", "group", "options" }) do
        local p = CreateFrame("Frame", nil, win)
        p:SetAllPoints(win)
        p:Hide()
        panels[name] = p
    end
    BuildBlessings(panels.blessings)
    BuildPlayers(panels.players)
    BuildGroup(panels.group)
    panels.options.height = ns.BuildOptions(panels.options, TOP + 6)

    win:SetScript("OnShow", function() ShowTab(current) end)
    local tick = 0
    win:SetScript("OnUpdate", function(_, dt)
        tick = tick + dt
        if tick < 2 then return end
        tick = 0
        if current == "players" or current == "group" then ns.RefreshWindow() end
    end)
    win:SetScript("OnHide", function() ns.HideMenus() end)
    W.RestorePos(win, "win", { "CENTER", "CENTER", 0, 60 })
    win:SetScale(ns.WinScale and ns.WinScale() or ns.db.scale)
end

function ns.RefreshWindow()
    if not win or not win:IsShown() then return end
    local grp = IsInRaid() and "Raid" or (IsInGroup() and "Party" or "Solo")
    if ns.preview then grp = W.Hex(unpack(S.warn)) .. "Test mode|r" end
    win.sub:SetText(("%s  |  %d paladin%s"):format(grp, #ns.paladins, #ns.paladins == 1 and "" or "s"))
    if win.testBtn then
        win.testBtn:SetText(ns.preview and "Exit test" or "Test mode")
        if win.testBtn.label then win.testBtn.label:SetTextColor(unpack(ns.preview and S.warn or S.text)) end
    end
    local h
    if current == "blessings" then h = RefreshBlessings(panels.blessings)
    elseif current == "players" then h = RefreshPlayers(panels.players)
    elseif current == "group" then h = RefreshGroup(panels.group)
    else
        if ns.RefreshOptions then ns.RefreshOptions() end
        h = panels.options.height or 300
    end
    win:SetHeight(math.max(h, 180))
end

function ns.OnAssignmentsChanged()
    ns.dirty = true
    ns.RefreshWindow()
end

function ns.ToggleWindow()
    if not win then return end
    if win:IsShown() then win:Hide() else win:Show() end
end

function ns.ToggleSettings()
    if not win then return end
    if not win:IsShown() then win:Show() end
    ShowTab("options")
end

function ns.BuildWindow() Build() end

function ns.HideMenus()
    if picker then picker:Hide() end
    if ns.HidePresetMenu then ns.HidePresetMenu() end
end
