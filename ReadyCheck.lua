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
local ROW_H, NAME_W, CELL, GAP, PAD = 18, 104, 16, 3, 10
local COUNT_W = 40        -- the "3/3" blessing count column
local SEC_H, LINE_H = 18, 17
local MAXROWS = 40
local MINW = 300

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
    win = W.Panel(UIParent, 400, 200, "PallyPulseReadyCheck")
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:Hide()
    tinsert(UISpecialFrames, "PallyPulseReadyCheck")
    W.MakeDraggable(win, win, "ready")
    W.RestorePos(win, "ready", { "TOP", "TOP", 0, -140 })
    win:SetScale(ns.RCScale())

    -- title bar: "Ready Check" left, ready answers right
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
    win.count = W.Text(win, 11, S.text, "RIGHT")
    win.count:SetPoint("RIGHT", close, "LEFT", -6, 0)

    -- totals, and a bar split into buffed / missing / unavailable
    win.summary = W.Text(win, 11, S.text, "LEFT")
    win.summary:SetPoint("TOPLEFT", PAD, -32)
    win.seg = {}
    for i, c in ipairs({ S.good, S.bad, S.off }) do
        local t = win:CreateTexture(nil, "ARTWORK")
        t:SetHeight(4); t:SetColorTexture(c[1], c[2], c[3], 1)
        win.seg[i] = t
    end
    win.segBg = win:CreateTexture(nil, "BACKGROUND", nil, 2)
    win.segBg:SetHeight(4); win.segBg:SetColorTexture(0, 0, 0, 0.5)

    -- Your Responsibilities
    win.mineHead = W.Text(win, 11, S.gold, "LEFT", S.head)
    win.mineHead:SetText("Your Responsibilities")
    win.mineKey = W.Text(win, 10, S.dim, "LEFT", S.num)
    win.mineCount = W.Text(win, 11, S.bad, "RIGHT")
    win.mineDone = W.Text(win, 11, S.good, "LEFT")
    win.mine = {}
    for i = 1, #ns.BLESSINGS do
        local l = {}
        l.icon = win:CreateTexture(nil, "ARTWORK")
        l.icon:SetSize(14, 14); l.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        l.name = W.Text(win, 11, S.text, "LEFT"); l.name:SetWidth(54); l.name:SetWordWrap(false)
        l.who = W.Text(win, 11, S.text, "LEFT"); l.who:SetWordWrap(false)
        win.mine[i] = l
    end

    -- section headers: click to open or close
    win.secs = {}
    for _, sec in ipairs(SECTIONS) do
        local h = CreateFrame("Button", nil, win)
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
        -- column icons for the blessing matrix, shown only while the section is open
        h.heads = {}
        if sec.key ~= "others" then
            for i, col in ipairs(COLS) do
                local c = CreateFrame("Frame", nil, win)
                c:SetSize(CELL, CELL)
                c.tex = c:CreateTexture(nil, "ARTWORK")
                c.tex:SetAllPoints(); c.tex:SetTexture(col.icon); c.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                c:EnableMouse(true)
                W.Tip(c, function(t)
                    t:AddLine(col.label, 1, 1, 1)
                    if col.blessing then t:AddLine("Red: yours. Tan: another paladin's.", unpack(S.dim)) end
                end)
                c:Hide()
                h.heads[i] = c
            end
        end
        h.more = W.Text(win, 10, S.dim, "LEFT")
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
        local row = CreateFrame("Frame", nil, win)
        row:SetHeight(ROW_H)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.stripe = row:CreateTexture(nil, "BORDER")
        row.stripe:SetPoint("TOPLEFT"); row.stripe:SetPoint("BOTTOMLEFT"); row.stripe:SetWidth(2)
        row.ready = row:CreateTexture(nil, "ARTWORK")
        row.ready:SetSize(12, 12); row.ready:SetPoint("LEFT", 6, 0)
        row.name = W.Text(row, 11, S.text, "LEFT")
        row.name:SetPoint("LEFT", 22, 0); row.name:SetWidth(NAME_W - 24); row.name:SetWordWrap(false)
        row.bcount = W.Text(row, 11, S.text, "CENTER", S.num, "OUTLINE")
        row.bcount:SetPoint("LEFT", NAME_W - 6, 0); row.bcount:SetWidth(COUNT_W - 4)
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
                GameTooltip:Show()
            end)
            c:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.cells[i] = c
        end
        row:Hide()
        win.rows[r] = row
    end

    -- Other Paladins: one clickable line each (click = whisper them)
    win.lines = {}
    for i = 1, 10 do
        local l = CreateFrame("Button", nil, win)
        l:SetHeight(LINE_H - 1)
        l.text = W.Text(l, 11, S.text, "LEFT")
        l.text:SetPoint("LEFT"); l.text:SetPoint("RIGHT"); l.text:SetWordWrap(false)
        l.hl = l:CreateTexture(nil, "HIGHLIGHT")
        l.hl:SetAllPoints(); l.hl:SetColorTexture(S.gold[1], S.gold[2], S.gold[3], 0.06)
        l:SetScript("OnClick", function(self)
            if self.whisper and self.pal then
                pcall(SendChatMessage, self.whisper, "WHISPER", nil, self.pal)
            end
        end)
        l:SetScript("OnEnter", function(self)
            if not self.tip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.tip, 1, 1, 1)
            GameTooltip:Show()
        end)
        l:SetScript("OnLeave", function() GameTooltip:Hide() end)
        l:Hide()
        win.lines[i] = l
    end

    local elapsed = 0
    win:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 0.5 then return end
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
local function Evaluate(e)
    local rd = ns.Readiness(e)
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
    row:SetAlpha(inf.here and 1 or 0.55)
    if not inf.online then
        row.bcount:SetText("Offline"); row.bcount:SetTextColor(unpack(S.off))
    elseif not inf.alive then
        row.bcount:SetText("Dead"); row.bcount:SetTextColor(unpack(S.off))
    elseif expect > 0 then
        row.bcount:SetText(("%d/%d"):format(math.min(got, expect), expect))
        row.bcount:SetTextColor(unpack(got >= expect and S.good or (inf.mine == "missing" and S.bad or S.other)))
    else
        row.bcount:SetText("")
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
        c.tip = nil
        if ic then
            c.tex:SetTexture(type(ic) ~= "boolean" and ic or col.icon); c.tex:Show()
            if c.SetBackdrop then c:SetBackdropColor(0, 0, 0, 0.6); c:SetBackdropBorderColor(0, 0, 0, 1) end
        else
            c.tex:Hide()
            if c.SetBackdrop then
                c:SetBackdropColor(0, 0, 0, 0.3)
                if owner and inf.here then
                    local col2 = (owner == me) and S.bad or S.other
                    c:SetBackdropBorderColor(col2[1], col2[2], col2[3], 1)
                    c.tip = (owner == me) and "Yours" or ns.FirstName(owner)
                    if not todo[owner] then todo[owner] = {}; todoOrder[#todoOrder + 1] = owner end
                    todo[owner][col.key] = todo[owner][col.key] or {}
                    table.insert(todo[owner][col.key], ns.FirstName(e.name))
                else
                    -- not required: neutral, unlike a missing blessing
                    c:SetBackdropBorderColor(S.border[1], S.border[2], S.border[3], 0.35)
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

function ns.RefreshReadyCheck()
    if not win or not win:IsShown() then return end
    local list = SortedRoster()
    local me = ns.Me()
    local info = {}
    for _, e in ipairs(list) do info[e] = Evaluate(e) end

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
    local width = math.max(MINW, PAD + x0 + #shownCols * (CELL + GAP) - GAP + PAD)
    -- tallest the window may get (it never runs off screen; long sections end in "+N more")
    local maxH = math.max(260, (UIParent:GetHeight() * 0.85) / math.max(0.5, win:GetScale()))

    -- categories from the shared readiness; the counts always add up to the players listed
    local groups = { need = {}, ok = {}, off = {} }
    for _, e in ipairs(list) do
        table.insert(groups[info[e].state] or groups.ok, e)
    end
    local nNeed, nOk, nOff = #groups.need, #groups.ok, #groups.off

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

    -- header
    local readyN = 0
    for _, e in ipairs(list) do
        local st = e.fake and e.ready or lastStatus[e.name]
        if st == "ready" then readyN = readyN + 1 end
    end
    win.count:SetText(("%d/%d Ready"):format(readyN, #list))
    win.summary:SetText(("%s%d|r Buffed  ·  %s%d|r Missing  ·  %s%d|r Unavailable"):format(
        W.Hex(unpack(S.good)), nOk, W.Hex(unpack(nNeed > 0 and S.bad or S.dim)), nNeed, W.Hex(unpack(S.off)), nOff))
    local y = 48
    local barW = width - PAD * 2
    win.segBg:ClearAllPoints(); win.segBg:SetPoint("TOPLEFT", PAD, -y); win.segBg:SetWidth(barW)
    local x, total = PAD, math.max(1, #list)
    for i, n in ipairs({ nOk, nNeed, nOff }) do
        local seg = win.seg[i]
        local w = barW * n / total
        if n > 0 and #list > 0 then
            seg:ClearAllPoints(); seg:SetPoint("TOPLEFT", win, "TOPLEFT", x, -y); seg:SetWidth(math.max(1, w)); seg:Show()
        else
            seg:Hide()
        end
        x = x + w
    end
    y = y + 12

    -- Your Responsibilities: by blessing; a single green line once they're all up
    win.mineMissing = 0
    local mine = todo[me]
    local isPal = false
    for _, p in ipairs(ns.paladins or {}) do if p == me then isPal = true break end end
    for _, l in ipairs(win.mine) do l.icon:Hide(); l.name:Hide(); l.who:Hide() end
    win.mineHead:Hide(); win.mineKey:Hide(); win.mineCount:Hide(); win.mineDone:Hide()
    if isPal then
        local n = 0
        for _, b in ipairs(ns.BLESSINGS) do
            if mine and mine[b.key] then n = n + 1; win.mineMissing = win.mineMissing + #mine[b.key] end
        end
        if n == 0 then
            win.mineDone:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t All your blessings active")
            win.mineDone:ClearAllPoints(); win.mineDone:SetPoint("TOPLEFT", PAD, -y); win.mineDone:Show()
            y = y + LINE_H + 4
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
                    l.icon:ClearAllPoints(); l.icon:SetPoint("TOPLEFT", PAD + 2, -y - 1); l.icon:Show()
                    l.name:SetText((b.single:gsub("^Blessing of ", "")))
                    l.name:ClearAllPoints(); l.name:SetPoint("LEFT", l.icon, "RIGHT", 5, 0); l.name:Show()
                    l.who:SetText(Names(names, 6))
                    l.who:ClearAllPoints(); l.who:SetPoint("LEFT", l.name, "RIGHT", 4, 0)
                    l.who:SetWidth(width - PAD * 2 - 80); l.who:Show()
                    y = y + LINE_H
                end
            end
            y = y + 6
        end
    end

    -- sections; each open one gets its own column icons
    for _, h in pairs(win.secs) do
        h:Hide(); h.more:Hide()
        for _, c in pairs(h.heads) do c:Hide() end
    end
    local function Header(key, n)
        local h = win.secs[key]
        local open = IsOpen(h.sec)
        h.mark:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
        h.text:SetText(h.sec.label)
        local cc = (key == "need") and S.bad or (key == "ok" and S.good or (key == "others" and S.other or S.off))
        h.num:SetText(n); h.num:SetTextColor(unpack(cc))
        h:ClearAllPoints(); h:SetPoint("TOPLEFT", win, "TOPLEFT", 1, -y); h:SetWidth(width - 2)
        h:Show()
        y = y + SEC_H + 1
        if open and next(h.heads) then
            for k, ci in ipairs(shownCols) do
                local c = h.heads[ci]
                c:ClearAllPoints(); c:SetPoint("TOPLEFT", win, "TOPLEFT", 1 + x0 + (k - 1) * (CELL + GAP), -y - 1)
                c:Show()
            end
            y = y + CELL + 3
        end
        return open, h
    end
    r = 0
    local othersCount = 0
    for _, pal in ipairs(todoOrder) do if pal ~= me then othersCount = othersCount + 1 end end
    for _, key in ipairs({ "need", "ok", "off" }) do
        local g = groups[key]
        if #g > 0 then
            local open, h = Header(key, #g)
            local shown = 0
            for idx, e in ipairs(g) do
                r = r + 1
                local row = win.rows[r]
                -- keep room for the remaining headers and a "+N more" line
                local room = y + ROW_H + (SEC_H + 1) * 3 + LINE_H <= maxH
                if row and open and room then
                    if info[e].mine ~= "missing" then
                        row.bg:SetColorTexture(unpack(idx % 2 == 0 and S.rowAlt or { 0, 0, 0, 0 }))
                    end
                    row:ClearAllPoints(); row:SetPoint("TOPLEFT", win, "TOPLEFT", 1, -y)
                    row:SetWidth(width - 2); row:Show()
                    y = y + ROW_H
                    shown = shown + 1
                elseif row then
                    row:Hide()
                end
            end
            if open and shown < #g then
                h.more:SetText(("+%d more"):format(#g - shown))
                h.more:ClearAllPoints(); h.more:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + 12, -y - 1); h.more:Show()
                y = y + LINE_H
            end
            if open then y = y + 2 end
        end
    end

    -- Other Paladins: one line each, click to whisper
    table.sort(todoOrder)
    for _, l in ipairs(win.lines) do l:Hide() end
    if othersCount > 0 then
        local open = Header("others", othersCount)
        if open then
            local i = 0
            for _, pal in ipairs(todoOrder) do
                if pal ~= me and i < #win.lines and y + LINE_H <= maxH then
                    i = i + 1
                    local parts, wparts = {}, {}
                    for _, b in ipairs(ns.BLESSINGS) do
                        local names = todo[pal][b.key]
                        if names then
                            parts[#parts + 1] = ("|T%s:14|t %s"):format(b.icon, Names(names, 4))
                            wparts[#wparts + 1] = b.single:gsub("^Blessing of ", "") .. ": " .. table.concat(names, ", ")
                        end
                    end
                    local l = win.lines[i]
                    l.text:SetText(W.Hex(unpack(S.other)) .. ns.FirstName(pal) .. "|r  " .. table.concat(parts, "   "))
                    l.pal, l.whisper, l.tip = nil, nil, nil
                    local real = ns.UnitForName and ns.UnitForName(pal) and not (ns.IsFakeName and ns.IsFakeName(pal))
                    if real then
                        l.pal = pal
                        l.whisper = "[PallyPulse] Missing your " .. table.concat(wparts, "; ")
                        l.tip = "Click: whisper " .. ns.FirstName(pal)
                    end
                    l:ClearAllPoints(); l:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y); l:SetWidth(width - PAD * 2)
                    l:Show()
                    y = y + LINE_H
                end
            end
        end
    end
    win:SetSize(width, y + 6)
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
