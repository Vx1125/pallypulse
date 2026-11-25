local ADDON, ns = ...
local S, W = ns.STYLE, ns.W

-- Ready check window: opens on a ready check (or /pulse check). A blessing report:
--   header       buffed / missing / unavailable, and a bar split the same way
--   Your Responsibilities   who still needs a blessing from you, by blessing
--   Needs Attention  players short a blessing (open by default)
--   Fully Buffed, Unavailable (dead or offline), Other Paladins (closed by default)
-- Each player row keeps the blessing matrix; with "Raid buffs" on it also shows the main raid
-- buffs, food and flask. A gap that's yours gets a red outline, another paladin's a muted
-- amber one; buffs nobody owes stay neutral. Dead and offline players never count as missing.
-- Ready checks happen out of combat, when group members' buffs can be read.

local ICON = "Interface\\Icons\\"
local ROW_H, NAME_W, CELL, GAP, PAD = 18, 100, 16, 3, 10
local COUNT_W = 34        -- the "3/3" blessing count column
local SEC_H, LINE_H = 18, 17
local MAXROWS = 40
local MINW = 228          -- sized to its content; this is the floor
local SB_W = 20            -- room for the scrollbar when the list scrolls

-- Columns. "match" maps a buff name to the column; "from" = classes that provide it (column
-- only shown when one is in the group; nil = always shown).
local COLS = {}
for _, b in ipairs(ns.BLESSINGS) do
    COLS[#COLS + 1] = { key = b.key, label = b.single:gsub("^Blessing of ", ""), icon = b.icon,
                        names = { [b.single] = true, [b.greater] = true }, from = { PALADIN = true }, blessing = true }
end
local function Col(key, label, icon, names, from)
    local set = {}
    for _, n in ipairs(names) do set[n] = true end
    COLS[#COLS + 1] = { key = key, label = label, icon = ICON .. icon, names = set, from = from, raid = true }
end
Col("FORT",   "Fortitude",   "Spell_Holy_WordFortitude",  { "Power Word: Fortitude", "Prayer of Fortitude" }, { PRIEST = true })
Col("MOTW",   "Mark of the Wild",      "Spell_Nature_Regeneration", { "Mark of the Wild", "Gift of the Wild" }, { DRUID = true })
Col("INT",    "Intellect", "Spell_Holy_MagicalSentry",  { "Arcane Intellect", "Arcane Brilliance" }, { MAGE = true })
Col("SPIRIT", "Spirit",    "Spell_Holy_DivineSpirit",   { "Divine Spirit", "Prayer of Spirit" }, { PRIEST = true })
Col("FOOD",   "Food",      "INV_Misc_Food_14",          { "Well Fed" })
Col("FLASK",  "Flask",     "INV_Potion_97",
    { "Flask of the Titans", "Supreme Power", "Distilled Wisdom", "Chromatic Resistance", "Petrification" })

local win
local shownCols = {}
local closeAt
local lastStatus = {}     -- [name] = ready status, kept after the check ends
local checking = false    -- a ready check is running; after it ends the statuses are frozen

-- every buff name on a unit (with its icon)
local function BuffsOn(unit)
    local have = {}
    local modern = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    for i = 1, 40 do
        local n, ic, fin = nil, nil, false
        if modern then
            local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
            if ok and not d then fin = true
            elseif ok then pcall(function() n, ic = d.name, d.icon end) end
        else
            local ok, nn, ii = pcall(UnitBuff, unit, i)
            if ok and not nn then fin = true elseif ok then n, ic = nn, ii end
        end
        if fin then break end
        if n and ns.Readable(n) then have[n] = ns.Readable(ic) and ic or true end
    end
    return have
end

local function HasCol(have, col)
    for n in pairs(col.names) do
        if have[n] then return have[n] end
    end
    if col.key == "FLASK" then
        for n, ic in pairs(have) do
            if n:find("^Flask of ") then return ic end
        end
    end
    return nil
end

local function ReadyTexture(st)
    if st == "ready" then return READY_CHECK_READY_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-Ready" end
    if st == "notready" then return READY_CHECK_NOT_READY_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-NotReady" end
    if st == "waiting" then return READY_CHECK_WAITING_TEXTURE or "Interface\\RaidFrame\\ReadyCheck-Waiting" end
    return nil
end

-- sections: which are open (the player's own choice is remembered)
local SECTIONS = {
    { key = "need",   label = "Needs Attention", open = true },
    { key = "ok",     label = "Fully Buffed",    open = false },
    { key = "off",    label = "Unavailable",     open = false },
    { key = "others", label = "Other Paladins",  open = false },
}
local function IsOpen(sec)
    local v = ns.db.rcOpen and ns.db.rcOpen[sec.key]
    if v == nil then return sec.open end
    return v
end

local function BindingText()
    local key = GetBindingKey and GetBindingKey("CLICK PallyPulseSmartButton:LeftButton")
    return key and (GetBindingText and GetBindingText(key, "KEY_") or key) or nil
end

local function Build()
    win = W.Panel(UIParent, MINW, 200, "PallyPulseReadyCheck")
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:Hide()
    tinsert(UISpecialFrames, "PallyPulseReadyCheck")
    W.MakeDraggable(win, win, "ready")
    W.RestorePos(win, "ready", { "TOP", "TOP", 0, -140 })
    win:SetScale(ns.RCScale())

    -- title bar: "Ready Check" left, buffed / eligible right (hover: ready answers)
    win.bar = win:CreateTexture(nil, "BACKGROUND", nil, 1)
    win.bar:SetPoint("TOPLEFT", 1, -1); win.bar:SetPoint("TOPRIGHT", -1, -1); win.bar:SetHeight(24)
    win.bar:SetColorTexture(unpack(S.header))
    win.barLine = win:CreateTexture(nil, "ARTWORK")
    win.barLine:SetPoint("TOPLEFT", win.bar, "BOTTOMLEFT"); win.barLine:SetPoint("TOPRIGHT", win.bar, "BOTTOMRIGHT")
    win.barLine:SetHeight(1); win.barLine:SetColorTexture(unpack(S.border))
    win.title = W.Text(win, 13, S.gold, "LEFT", S.head)
    win.title:SetPoint("TOPLEFT", PAD, -6)
    win.title:SetText("Ready Check")
    local close = W.CloseButton(win, function()
        -- closing the preview window ends the preview
        if ns.preview and ns.SetPreview then ns.SetPreview(false) else win:Hide() end
    end)
    close:SetPoint("TOPRIGHT", -4, -3)
    win.countBtn = CreateFrame("Frame", nil, win)
    win.countBtn:SetSize(90, 18); win.countBtn:SetPoint("RIGHT", close, "LEFT", -4, 0)
    win.countBtn:EnableMouse(true)
    win.count = W.Text(win.countBtn, 11, S.text, "RIGHT")
    win.count:SetPoint("RIGHT")
    W.Tip(win.countBtn, function(t)
        t:AddLine("Buffed / eligible", 1, 1, 1)
        t:AddLine("Dead and offline players aren't counted.", unpack(S.dim))
        if win.answers then t:AddDoubleLine("Clicked Ready", win.answers, 0.8, 0.8, 0.8, 1, 1, 1) end
    end)

    -- totals, and a bar split the same way: buffed / missing / unavailable
    win.summary = W.Text(win, 11, S.text, "LEFT")
    win.summary:SetPoint("TOPLEFT", PAD, -31)
    win.seg = {}
    for i, c in ipairs({ S.good, S.bad, S.off }) do
        local t = win:CreateTexture(nil, "ARTWORK")
        t:SetHeight(4); t:SetColorTexture(c[1], c[2], c[3], 1)
        win.seg[i] = t
    end
    win.segBg = win:CreateTexture(nil, "BACKGROUND", nil, 2)
    win.segBg:SetHeight(4); win.segBg:SetColorTexture(0, 0, 0, 0.5)

    -- Your Responsibilities (stays above the scrolling list)
    win.mineHead = W.Text(win, 11, S.gold, "LEFT", S.head)
    win.mineHead:SetText("Your Responsibilities")
    win.mineKey = W.Text(win, 10, S.dim, "LEFT", S.num)
    win.mineCount = W.Text(win, 11, S.bad, "RIGHT")
    win.mineDone = W.Text(win, 11, S.good, "LEFT")
    win.mine = {}
    for i = 1, #ns.BLESSINGS do
        local l = CreateFrame("Frame", nil, win)
        l:SetHeight(LINE_H - 1)
        l:EnableMouse(true)
        l.icon = l:CreateTexture(nil, "ARTWORK")
        l.icon:SetSize(14, 14); l.icon:SetPoint("LEFT", 2, 0); l.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        l.name = W.Text(l, 11, S.text, "LEFT"); l.name:SetWidth(52); l.name:SetWordWrap(false)
        l.name:SetPoint("LEFT", l.icon, "RIGHT", 5, 0)
        l.who = W.Text(l, 11, S.text, "LEFT"); l.who:SetWordWrap(false)
        l.who:SetPoint("LEFT", l.name, "RIGHT", 4, 0); l.who:SetPoint("RIGHT", 0, 0)
        W.Tip(l, function(t)
            if not l.all then return end
            t:AddLine(l.name:GetText(), 1, 1, 1)
            for _, n in ipairs(l.all) do t:AddLine(n, unpack(S.text)) end
        end)
        win.mine[i] = l
    end

    -- one shared column header over the matrix: Player, Status, blessing (and buff) icons
    win.colHead = CreateFrame("Frame", nil, win)
    win.colHead:SetHeight(CELL + 2)
    win.colHead.player = W.Text(win.colHead, 10, S.dim, "LEFT", S.head)
    win.colHead.player:SetPoint("LEFT", 22, 0); win.colHead.player:SetText("Player")
    win.colHead.status = W.Text(win.colHead, 10, S.dim, "RIGHT", S.head)
    win.colHead.status:SetPoint("RIGHT", win.colHead, "LEFT", NAME_W + COUNT_W - 4, 0); win.colHead.status:SetText("Status")
    win.heads = {}
    for i, col in ipairs(COLS) do
        local c = CreateFrame("Frame", nil, win.colHead)
        c:SetSize(CELL, CELL)
        c.tex = c:CreateTexture(nil, "ARTWORK")
        c.tex:SetAllPoints(); c.tex:SetTexture(col.icon); c.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        c:EnableMouse(true)
        W.Tip(c, function(t)
            t:AddLine(col.label, 1, 1, 1)
            if col.blessing then
                t:AddLine("Icon: active", unpack(S.good))
                t:AddLine("Red edge: yours, missing", unpack(S.bad))
                t:AddLine("Tan edge: another paladin's, missing", unpack(S.other))
                t:AddLine("Empty: not assigned", unpack(S.dim))
            end
        end)
        c:Hide()
        win.heads[i] = c
    end

    -- the list scrolls when it's taller than the screen allows
    win.scroll = CreateFrame("ScrollFrame", "PallyPulseReadyScroll", win, "UIPanelScrollFrameTemplate")
    win.scroll.scrollBarHideable = true
    win.list = CreateFrame("Frame", nil, win.scroll)
    win.list:SetSize(MINW, 10)
    win.scroll:SetScrollChild(win.list)
    W.SkinScroll(win.scroll)
    local L = win.list

    -- section headers: click to open or close
    win.secs = {}
    for _, sec in ipairs(SECTIONS) do
        local h = CreateFrame("Button", nil, L)
        h:SetHeight(SEC_H)
        h.bg = h:CreateTexture(nil, "BACKGROUND")
        h.bg:SetAllPoints(); h.bg:SetColorTexture(unpack(S.header))
        h.mark = h:CreateTexture(nil, "ARTWORK")
        h.mark:SetSize(12, 12); h.mark:SetPoint("LEFT", 4, 0)
        h.text = W.Text(h, 11, S.text, "LEFT", S.head)
        h.text:SetPoint("LEFT", h.mark, "RIGHT", 5, 0)
        h.num = W.Text(h, 11, S.text, "RIGHT", S.num)
        h.num:SetPoint("RIGHT", -6, 0)
        h.hl = h:CreateTexture(nil, "HIGHLIGHT"); h.hl:SetAllPoints(); h.hl:SetColorTexture(S.gold[1], S.gold[2], S.gold[3], 0.06)
        h.sec = sec
        h:SetScript("OnClick", function(self)
            ns.db.rcOpen = ns.db.rcOpen or {}
            ns.db.rcOpen[self.sec.key] = not IsOpen(self.sec)
            ns.RefreshReadyCheck()
        end)
        h:Hide()
        win.secs[sec.key] = h
    end

    win.rows = {}
    for r = 1, MAXROWS do
        local row = CreateFrame("Frame", nil, L)
        row:SetHeight(ROW_H)
        row:EnableMouse(true)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.stripe = row:CreateTexture(nil, "BORDER")
        row.stripe:SetPoint("TOPLEFT"); row.stripe:SetPoint("BOTTOMLEFT"); row.stripe:SetWidth(2)
        row.ready = row:CreateTexture(nil, "ARTWORK")
        row.ready:SetSize(12, 12); row.ready:SetPoint("LEFT", 6, 0)
        row.name = W.Text(row, 11, S.text, "LEFT")
        row.name:SetPoint("LEFT", 22, 0); row.name:SetWidth(NAME_W - 24); row.name:SetWordWrap(false)
        -- right-aligned "2/3" (or Dead / Offline)
        row.bcount = W.Text(row, 11, S.text, "RIGHT", S.num, "OUTLINE")
        row.bcount:SetPoint("RIGHT", row, "LEFT", NAME_W + COUNT_W - 4, 0); row.bcount:SetWidth(COUNT_W + 10)
        -- full name and status on hover (names can be cut short)
        row:SetScript("OnEnter", function(self)
            if not self.e then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.e.name, W.ClassColor(self.e.class))
            if self.statusText then GameTooltip:AddLine(self.statusText, 0.8, 0.8, 0.8) end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.cells = {}
        for i = 1, #COLS do
            local c = CreateFrame("Frame", nil, row, BackdropTemplateMixin and "BackdropTemplate" or nil)
            c:SetSize(CELL, CELL)
            if c.SetBackdrop then
                c:SetBackdrop({ bgFile = W.WHITE, edgeFile = W.WHITE, edgeSize = 1 })
            end
            c.tex = c:CreateTexture(nil, "ARTWORK")
            c.tex:SetPoint("TOPLEFT", 1, -1); c.tex:SetPoint("BOTTOMRIGHT", -1, 1)
            c.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            c:EnableMouse(true)
            c:SetScript("OnEnter", function(self)
                if not self.tip then return end
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(self.tip, 1, 1, 1)
                if self.tip2 then GameTooltip:AddLine(self.tip2, unpack(self.tip2c or S.dim)) end
                GameTooltip:Show()
            end)
            c:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.cells[i] = c
        end
        row:Hide()
        win.rows[r] = row
    end

    -- Other Paladins: a name line (click: whisper), then one line per blessing
    win.lines = {}
    for i = 1, 24 do
        local l = CreateFrame("Button", nil, L)
        l:SetHeight(LINE_H - 1)
        l.icon = l:CreateTexture(nil, "ARTWORK")
        l.icon:SetSize(14, 14); l.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        l.text = W.Text(l, 11, S.text, "LEFT")
        l.text:SetJustifyV("TOP")
        l.right = W.Text(l, 10, S.dim, "RIGHT")
        l.right:SetPoint("TOPRIGHT", 0, -2)
        l.hl = l:CreateTexture(nil, "HIGHLIGHT")
        l.hl:SetAllPoints(); l.hl:SetColorTexture(S.gold[1], S.gold[2], S.gold[3], 0.06)
        l:SetScript("OnClick", function(self)
            if self.whisper and self.pal then
                pcall(SendChatMessage, self.whisper, "WHISPER", nil, self.pal)
            end
        end)
        l:SetScript("OnEnter", function(self)
            if not self.tip and not self.all then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if self.all then
                for _, n in ipairs(self.all) do GameTooltip:AddLine(n, 1, 1, 1) end
            end
            if self.tip then GameTooltip:AddLine(self.tip, 0.6, 0.6, 0.6) end
            GameTooltip:Show()
        end)
        l:SetScript("OnLeave", function() GameTooltip:Hide() end)
        l:Hide()
        win.lines[i] = l
    end

    local elapsed = 0
    win:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 1 then return end      -- answers also refresh on READY_CHECK_CONFIRM
        elapsed = 0
        if closeAt and GetTime() >= closeAt and not self:IsMouseOver() then
            closeAt = nil; self:Hide(); return
        end
        -- the check is over and the pull started (maybe without you): done with it
        if closeAt and ns.GroupInCombat and ns.GroupInCombat() then
            closeAt = nil; self:Hide(); return
        end
        if not InCombatLockdown() then ns.RefreshReadyCheck() end
    end)
end

-- What a player has and should have: the shared readiness (ns.Readiness), plus every buff on
-- them for the matrix.
local function Evaluate(e, rd)
    rd = rd or ns.Readiness(e)
    if e.fake then
        rd.alive, rd.online, rd.have = not e.dead, true, ns.PreviewBuffs(e)
    else
        rd.alive = not ns.SafeUnit(UnitIsDeadOrGhost, e.unit, false)
        rd.online = ns.SafeUnit(UnitIsConnected, e.unit, true) and true or false
        rd.have = BuffsOn(e.unit)
    end
    rd.short = rd.state == "need"
    return rd
end

local function SortedRoster()
    local list = {}
    for _, e in ipairs(ns.roster or {}) do list[#list + 1] = e end
    local order = {}
    for i, c in ipairs(ns.CLASSES) do order[c] = i end
    table.sort(list, function(a, b)
        local oa, ob = order[a.class] or 99, order[b.class] or 99
        if oa ~= ob then return oa < ob end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

-- One player row: ready icon, name, blessing count and the buff matrix. Adds what's owed to
-- todo[paladin][KEY] = { names }.
local function FillPlayer(row, e, inf, me, x0, todo, todoOrder)
    local cr, cg, cb = W.ClassColor(e.class)
    row.stripe:SetColorTexture(cr, cg, cb, 1)
    row.name:SetText(ns.FirstName(e.name))
    row.name:SetTextColor(cr, cg, cb)

    local st
    if e.fake then st = e.ready
    elseif checking then pcall(function() st = GetReadyCheckStatus and GetReadyCheckStatus(e.unit) end) end
    if not ns.Readable(st) then st = nil end
    -- a "ready" answer can't be taken back, so a later read never downgrades it
    if st and lastStatus[e.name] ~= "ready" then lastStatus[e.name] = st end
    st = lastStatus[e.name]
    local rt = ReadyTexture(st)
    row.ready:SetTexture(rt); row.ready:SetShown(rt ~= nil)

    local have, owe, expect, got = inf.have, inf.owe, inf.expect, inf.got
    row.e = e
    row:SetAlpha(inf.here and 1 or 0.55)
    if not inf.online then
        row.bcount:SetText("Offline"); row.bcount:SetTextColor(unpack(S.off)); row.statusText = "Offline"
    elseif not inf.alive then
        row.bcount:SetText("Dead"); row.bcount:SetTextColor(unpack(S.off)); row.statusText = "Dead"
    elseif expect > 0 then
        row.bcount:SetText(("%d/%d"):format(math.min(got, expect), expect))
        row.bcount:SetTextColor(unpack(got >= expect and S.good or (inf.mine == "missing" and S.bad or S.other)))
        row.statusText = ("%d of %d blessings"):format(math.min(got, expect), expect)
    else
        row.bcount:SetText(""); row.statusText = nil
    end
    -- red row only when it's your blessing that's missing
    row.bg:SetColorTexture(unpack(inf.mine == "missing" and S.rowMiss or { 0, 0, 0, 0 }))
    for _, c in ipairs(row.cells) do c:Hide() end
    for k, ci in ipairs(shownCols) do
        local col, c = COLS[ci], row.cells[ci]
        c:ClearAllPoints(); c:SetPoint("LEFT", row, "LEFT", x0 + (k - 1) * (CELL + GAP), 0)
        local ic
        if col.blessing then
            ic = inf.left[col.key] and (HasCol(have, col) or true)
        else
            ic = HasCol(have, col)
        end
        local owner = col.blessing and owe[col.key]
        c.tip, c.tip2, c.tip2c = col.label, nil, nil
        if ic then
            c.tex:SetTexture(type(ic) ~= "boolean" and ic or col.icon); c.tex:Show()
            if c.SetBackdrop then c:SetBackdropColor(0, 0, 0, 0.6); c:SetBackdropBorderColor(0, 0, 0, 1) end
            c.tip2, c.tip2c = "Active", S.good
        else
            c.tex:Hide()
            if c.SetBackdrop then
                c:SetBackdropColor(0, 0, 0, 0.3)
                if owner and inf.here then
                    local col2 = (owner == me) and S.bad or S.other
                    c:SetBackdropBorderColor(col2[1], col2[2], col2[3], 1)
                    c.tip2 = (owner == me) and "Missing: yours" or ("Missing: " .. ns.FirstName(owner) .. "'s")
                    c.tip2c = col2
                    if not todo[owner] then todo[owner] = {}; todoOrder[#todoOrder + 1] = owner end
                    todo[owner][col.key] = todo[owner][col.key] or {}
                    table.insert(todo[owner][col.key], ns.FirstName(e.name))
                else
                    -- not required: neutral, unlike a missing blessing
                    c:SetBackdropBorderColor(S.border[1], S.border[2], S.border[3], 0.35)
                    c.tip2 = inf.here and (col.blessing and "Not assigned" or "Missing") or "Unavailable"
                end
            end
        end
        c:Show()
    end
end

local function Names(names, max)
    local shown = {}
    for i = 1, math.min(#names, max) do shown[i] = names[i] end
    local txt = table.concat(shown, ", ")
    if #names > max then txt = txt .. " +" .. (#names - max) end
    return txt
end

-- Keep a window inside the screen (after it grows, or the resolution or UI scale changes).
function ns.KeepOnScreen(f, key)
    if not f or not f:GetLeft() or (InCombatLockdown() and f:IsProtected()) then return end
    local k = UIParent:GetEffectiveScale() / f:GetEffectiveScale()
    local sw, sh = UIParent:GetWidth() * k, UIParent:GetHeight() * k
    local l, t, w, h = f:GetLeft(), f:GetTop(), f:GetWidth(), f:GetHeight()
    local nl = math.max(0, math.min(l, sw - w))
    local nt = math.max(math.min(h, sh), math.min(t, sh))
    if math.abs(nl - l) > 0.5 or math.abs(nt - t) > 0.5 then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", nl, nt)
        if key then W.SavePos(f, key) end
    end
end

function ns.RefreshReadyCheck()
    if not win or not win:IsShown() then return end
    local list = SortedRoster()
    local me = ns.Me()
    local sum = ns.ReadinessSummary()
    local info = {}
    for _, e in ipairs(list) do info[e] = Evaluate(e, sum.players[e]) end

    -- which columns: the blessings (if any paladin), raid buffs whose class is present, food
    -- and flask
    local present = {}
    for _, e in ipairs(list) do present[e.class] = true end
    wipe(shownCols)
    for i, col in ipairs(COLS) do
        local show = not col.raid or ns.db.readyCheckRaid
        if show and col.from then
            show = false
            for c in pairs(col.from) do if present[c] then show = true break end end
        end
        if show then shownCols[#shownCols + 1] = i end
    end
    local x0 = NAME_W + COUNT_W
    local contentW = math.max(MINW, x0 + #shownCols * (CELL + GAP) - GAP + PAD)
    -- the tallest the window may get on this screen at this scale
    local k = UIParent:GetEffectiveScale() / win:GetEffectiveScale()
    local maxH = math.max(220, UIParent:GetHeight() * k * 0.85)

    local groups = { need = {}, ok = {}, off = {} }
    for _, e in ipairs(list) do table.insert(groups[info[e].state] or groups.ok, e) end

    -- fill every row first (placed later), so todo is known before drawing responsibilities
    local todo, todoOrder = {}, {}
    local r = 0
    for _, g in ipairs({ "need", "ok", "off" }) do
        for _, e in ipairs(groups[g]) do
            r = r + 1
            local row = win.rows[r]
            if row then FillPlayer(row, e, info[e], me, x0, todo, todoOrder); row:Hide() end
        end
    end
    for i = r + 1, MAXROWS do win.rows[i]:Hide() end

    -- header: buffed / eligible (dead and offline left out); ready answers in the tooltip
    local readyN = 0
    for _, e in ipairs(list) do
        local st = e.fake and e.ready or lastStatus[e.name]
        if st == "ready" then readyN = readyN + 1 end
    end
    win.answers = ("%d/%d"):format(readyN, #list)
    win.count:SetText(("%d/%d Buffed"):format(sum.buffed, sum.eligible))
    win.count:SetTextColor(unpack(sum.buffed == sum.eligible and S.good or S.text))
    win.summary:SetText(("%s%d|r Buffed  ·  %s%d|r Missing  ·  %s%d|r Unavailable"):format(
        W.Hex(unpack(S.good)), sum.buffed, W.Hex(unpack(sum.missing > 0 and S.bad or S.dim)), sum.missing,
        W.Hex(unpack(S.off)), sum.unavailable))

    -- the fixed top part
    local width = contentW      -- grows by the scrollbar below if needed
    local y = 47

    local function Seg(width)
        local barW = width - PAD * 2
        win.segBg:ClearAllPoints(); win.segBg:SetPoint("TOPLEFT", PAD, -47); win.segBg:SetWidth(barW)
        local x, total = PAD, math.max(1, sum.total)
        for i, n in ipairs({ sum.buffed, sum.missing, sum.unavailable }) do
            local seg, w = win.seg[i], barW * n / total
            if n > 0 then
                seg:ClearAllPoints(); seg:SetPoint("TOPLEFT", win, "TOPLEFT", x, -47); seg:SetWidth(math.max(1, w)); seg:Show()
            else
                seg:Hide()
            end
            x = x + w
        end
    end
    y = y + 11

    -- Your Responsibilities: by blessing; a single green line once they're all up
    win.mineMissing = 0
    local mine = todo[me]
    local isPal = false
    for _, p in ipairs(ns.paladins or {}) do if p == me then isPal = true break end end
    for _, l in ipairs(win.mine) do l:Hide() end
    win.mineHead:Hide(); win.mineKey:Hide(); win.mineCount:Hide(); win.mineDone:Hide()
    local mineLines = {}
    if isPal then
        local n = 0
        for _, b in ipairs(ns.BLESSINGS) do
            if mine and mine[b.key] then n = n + 1; win.mineMissing = win.mineMissing + #mine[b.key] end
        end
        if n == 0 then
            win.mineDone:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t All your blessings active")
            win.mineDone:ClearAllPoints(); win.mineDone:SetPoint("TOPLEFT", PAD, -y); win.mineDone:Show()
            y = y + LINE_H + 2
        else
            win.mineHead:ClearAllPoints(); win.mineHead:SetPoint("TOPLEFT", PAD, -y); win.mineHead:Show()
            local key = BindingText()
            if key then
                win.mineKey:SetText("[" .. key .. "]")
                win.mineKey:ClearAllPoints(); win.mineKey:SetPoint("LEFT", win.mineHead, "RIGHT", 6, 0); win.mineKey:Show()
            end
            win.mineCount:SetText(win.mineMissing .. " Missing")
            win.mineCount:ClearAllPoints(); win.mineCount:SetPoint("TOPRIGHT", win, "TOPRIGHT", -PAD, -y); win.mineCount:Show()
            y = y + 16
            local i = 0
            for _, b in ipairs(ns.BLESSINGS) do
                local names = mine[b.key]
                if names then
                    i = i + 1
                    local l = win.mine[i]
                    l.icon:SetTexture(b.icon)
                    l.name:SetText((b.single:gsub("^Blessing of ", "")))
                    l.who:SetText(Names(names, 5))
                    l.all = #names > 5 and names or nil
                    l:ClearAllPoints(); l:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y)
                    mineLines[#mineLines + 1] = l
                    l:Show()
                    y = y + LINE_H
                end
            end
            y = y + 4
        end
    end

    -- sections (in the scrolling list); one shared column header above it
    local matrixOpen = (#groups.need > 0 and IsOpen(SECTIONS[1])) or (#groups.ok > 0 and IsOpen(SECTIONS[2]))
    win.colHead:SetShown(matrixOpen and true or false)
    if matrixOpen then
        win.colHead:ClearAllPoints(); win.colHead:SetPoint("TOPLEFT", win, "TOPLEFT", 1, -y)
        for _, c in ipairs(win.heads) do c:Hide() end
        for n, ci in ipairs(shownCols) do
            local c = win.heads[ci]
            c:ClearAllPoints(); c:SetPoint("LEFT", win.colHead, "LEFT", x0 + (n - 1) * (CELL + GAP), 0)
            c:Show()
        end
        y = y + CELL + 3
    end
    local topH = y

    for _, h in pairs(win.secs) do h:Hide() end
    local ly = 0
    local function Header(key, n)
        local h = win.secs[key]
        local open = IsOpen(h.sec)
        h.mark:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
        h.text:SetText(h.sec.label)
        local cc = (key == "need") and S.bad or (key == "ok" and S.good or (key == "others" and S.other or S.off))
        h.num:SetText(n); h.num:SetTextColor(unpack(cc))
        h:ClearAllPoints(); h:SetPoint("TOPLEFT", win.list, "TOPLEFT", 0, -ly); h:SetWidth(contentW - 2)
        h:Show()
        ly = ly + SEC_H + 1
        return open
    end
    r = 0
    for _, key in ipairs({ "need", "ok", "off" }) do
        local g = groups[key]
        if #g > 0 then
            local open = Header(key, #g)
            for idx, e in ipairs(g) do
                r = r + 1
                local row = win.rows[r]
                if row and open then
                    if info[e].mine ~= "missing" then
                        row.bg:SetColorTexture(unpack(idx % 2 == 0 and S.rowAlt or { 0, 0, 0, 0 }))
                    end
                    row:ClearAllPoints(); row:SetPoint("TOPLEFT", win.list, "TOPLEFT", 0, -ly)
                    row:SetWidth(contentW - 2); row:Show()
                    ly = ly + ROW_H
                end
            end
            if open then ly = ly + 1 end
        end
    end

    -- Other Paladins: paladin name and how many are pending, then one line per blessing with
    -- its players (wrapping onto more lines when needed; the full list on hover)
    table.sort(todoOrder)
    for _, l in ipairs(win.lines) do l:Hide() end
    local others = {}
    for _, pal in ipairs(todoOrder) do if pal ~= me then others[#others + 1] = pal end end
    if #others > 0 then
        local open = Header("others", #others)
        if open then
            local i = 0
            local lineW = contentW - PAD * 2
            local function Line(indent, text, wrap)
                i = i + 1
                local l = win.lines[i]
                if not l then return nil end
                l.pal, l.whisper, l.tip, l.all = nil, nil, nil, nil
                l.right:SetText("")
                l.icon:ClearAllPoints(); l.icon:SetPoint("TOPLEFT", indent, -1)
                l.text:ClearAllPoints()
                l.text:SetPoint("TOPLEFT", indent + (indent > 0 and 19 or 0), -2)
                l.text:SetWidth(lineW - indent - (indent > 0 and 19 or 0) - (indent > 0 and 0 or 60))
                l.text:SetWordWrap(wrap and true or false)
                l.text:SetText(text)
                local h = math.max(LINE_H - 1, math.ceil((l.text:GetStringHeight() or 12) + 4))
                l:SetHeight(h)
                l:ClearAllPoints(); l:SetPoint("TOPLEFT", win.list, "TOPLEFT", PAD, -ly); l:SetWidth(lineW)
                l:Show()
                ly = ly + h
                return l
            end
            local pr, pg, pb = W.ClassColor("PALADIN")
            for _, pal in ipairs(others) do
                local pending, wparts = 0, {}
                for _, b in ipairs(ns.BLESSINGS) do
                    local names = todo[pal][b.key]
                    if names then
                        pending = pending + #names
                        wparts[#wparts + 1] = b.single:gsub("^Blessing of ", "") .. ": " .. table.concat(names, ", ")
                    end
                end
                if i > 0 then ly = ly + 3 end
                local l = Line(0, W.Hex(pr, pg, pb) .. ns.FirstName(pal) .. "|r", false)
                if not l then break end
                l.icon:Hide()
                l.right:SetText(pending .. " pending")
                local real = ns.UnitForName and ns.UnitForName(pal) and not (ns.IsFakeName and ns.IsFakeName(pal))
                if real then
                    l.pal = pal
                    l.whisper = "[PallyPulse] Missing your " .. table.concat(wparts, "; ")
                    l.tip = "Click: whisper " .. ns.FirstName(pal)
                end
                for _, b in ipairs(ns.BLESSINGS) do
                    local names = todo[pal][b.key]
                    if names then
                        -- up to 12 names, wrapped; the rest on hover
                        local bl = Line(4, Names(names, 12), true)
                        if not bl then break end
                        bl.icon:SetTexture(b.icon); bl.icon:Show()
                        bl.all = #names > 12 and names or nil
                    end
                end
            end
        end
    end
    local contentH = ly + 2

    -- size: scroll the list only when it doesn't fit
    local room = math.max(SEC_H * 2, maxH - topH - 6)
    local needScroll = contentH > room
    local listH = needScroll and room or contentH
    if needScroll then width = contentW + SB_W end
    win.list:SetSize(contentW, math.max(1, contentH))
    win.scroll:ClearAllPoints()
    win.scroll:SetPoint("TOPLEFT", win, "TOPLEFT", 1, -topH)
    win.scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -(needScroll and SB_W or 1), 5)
    local bar = win.scroll.ScrollBar or _G["PallyPulseReadyScrollScrollBar"]
    if bar then bar:SetShown(needScroll) end
    if not needScroll then win.scroll:SetVerticalScroll(0) end
    win.colHead:SetWidth(contentW - 2)
    for _, l in ipairs(mineLines) do l:SetWidth(width - PAD * 2) end
    Seg(width)
    win:SetSize(width, topH + listH + 6)
    ns.KeepOnScreen(win, "ready")
end

function ns.ShowReadyCheck(auto)
    if not win then Build() end
    if InCombatLockdown() then return end
    closeAt = nil
    win:SetScale(ns.RCScale())
    win:Show()
    ns.RefreshReadyCheck()
    ns.dirty = true   -- the bar refreshes too
end

function ns.ToggleReadyCheck()
    if win and win:IsShown() then win:Hide() else ns.ShowReadyCheck() end
end

function ns.GroupInCombat()
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    local raid = IsInRaid and IsInRaid()
    for i = 1, n do
        local u = raid and ("raid" .. i) or (i == n and "player" or ("party" .. i))
        local ok, c = pcall(UnitAffectingCombat, u)
        if ok and c == true then return true end
    end
    return false
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("READY_CHECK")
ev:RegisterEvent("READY_CHECK_CONFIRM")
ev:RegisterEvent("READY_CHECK_FINISHED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
local reopen = false       -- it was open when combat started: bring it back afterwards
ev:SetScript("OnEvent", function(_, event)
    if not ns.db then return end
    if event == "READY_CHECK" then
        wipe(lastStatus)
        checking = true
        if ns.db.readyCheck ~= false then
            ns.ShowReadyCheck(true)
            if ns.db.readyCheckSound and win and (win.mineMissing or 0) > 0 and ns.Alert then ns.Alert() end
        end
    elseif event == "READY_CHECK_CONFIRM" then
        ns.RefreshReadyCheck()
    elseif event == "READY_CHECK_FINISHED" then
        ns.RefreshReadyCheck()     -- last live read, then frozen
        checking = false
        if win and win:IsShown() then closeAt = GetTime() + 15 end   -- stays open while you hover it
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- only a check still running comes back after combat; a finished one was the pull
        reopen = win and win:IsShown() and checking or false
        if win then win:Hide() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if reopen then
            reopen = false
            local keepClose = closeAt
            ns.ShowReadyCheck()
            closeAt = keepClose        -- a finished ready check still closes on its timer
        end
    end
end)
