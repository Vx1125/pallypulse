local ADDON, ns = ...
local S, W = ns.STYLE, ns.W

-- Ready check window: opens on a ready check (or /pulse check) and shows, for everyone in
-- the group, their ready status and which blessings they have. With "show raid buffs" on it
-- also shows the main raid buffs, food and flask. Gaps that are yours to fill get a red outline.
-- Ready checks happen out of combat, when group members' buffs can be read.

local ICON = "Interface\\Icons\\"
local ROW_H, NAME_W, CELL, GAP, PAD = 18, 104, 18, 3, 10
local COUNT_W = 44        -- the "3/3" blessing count column
local TOP = 52            -- title + column headers
local FOOT = 26
local MAXROWS = 40

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
Col("FORT",   "Stamina",   "Spell_Holy_WordFortitude",  { "Power Word: Fortitude", "Prayer of Fortitude" }, { PRIEST = true })
Col("MOTW",   "Mark",      "Spell_Nature_Regeneration", { "Mark of the Wild", "Gift of the Wild" }, { DRUID = true })
Col("INT",    "Intellect", "Spell_Holy_MagicalSentry",  { "Arcane Intellect", "Arcane Brilliance" }, { MAGE = true })
Col("SPIRIT", "Spirit",    "Spell_Holy_DivineSpirit",   { "Divine Spirit", "Prayer of Spirit" }, { PRIEST = true })
Col("FOOD",   "Food",      "INV_Misc_Food_14",          { "Well Fed" })
Col("FLASK",  "Flask",     "INV_Potion_97",
    { "Flask of the Titans", "Supreme Power", "Distilled Wisdom", "Chromatic Resistance", "Petrification" })

local win
local shownCols = {}
local closeAt
local lastStatus = {}     -- [name] = ready status, kept after the check ends

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

local function Build()
    win = W.Panel(UIParent, 400, 200, "PallyPulseReadyCheck")
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:Hide()
    W.MakeDraggable(win, win, "ready")
    W.RestorePos(win, "ready", { "TOP", "TOP", 0, -140 })
    win:SetScale(ns.db.scale or 1)

    win.title = W.Text(win, 14, S.gold, "LEFT", S.head)
    win.title:SetPoint("TOPLEFT", PAD, -9)
    win.count = W.Text(win, 12, S.text, "LEFT", S.head)
    win.count:SetPoint("LEFT", win.title, "RIGHT", 10, 0)
    win.summary = W.Text(win, 11, S.text, "LEFT")
    win.summary:SetPoint("LEFT", win.count, "RIGHT", 12, 0)

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() win:Hide() end)

    win.heads = {}
    for i, col in ipairs(COLS) do
        local h = CreateFrame("Frame", nil, win)
        h:SetSize(CELL, CELL)
        h.tex = h:CreateTexture(nil, "ARTWORK")
        h.tex:SetAllPoints(); h.tex:SetTexture(col.icon); h.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        h:EnableMouse(true)
        W.Tip(h, function(t)
            t:AddLine(col.label, 1, 1, 1)
            if col.blessing then t:AddLine("Red outline: yours to give", unpack(S.dim)) end
        end)
        win.heads[i] = h
    end

    win.rows = {}
    for r = 1, MAXROWS do
        local row = CreateFrame("Frame", nil, win)
        row:SetHeight(ROW_H)
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.ready = row:CreateTexture(nil, "ARTWORK")
        row.ready:SetSize(14, 14); row.ready:SetPoint("LEFT", 2, 0)
        row.name = W.Text(row, 12, S.text, "LEFT", S.head)
        row.name:SetPoint("LEFT", 20, 0); row.name:SetWidth(NAME_W - 22); row.name:SetWordWrap(false)
        row.bcount = W.Text(row, 12, S.text, "CENTER", S.num, "OUTLINE")
        row.bcount:SetPoint("LEFT", NAME_W - 6, 0); row.bcount:SetWidth(COUNT_W - 4)
        row.cells = {}
        for i = 1, #COLS do
            local c = CreateFrame("Frame", nil, row, BackdropTemplateMixin and "BackdropTemplate" or nil)
            c:SetSize(CELL, CELL)
            if c.SetBackdrop then
                c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
            end
            c.tex = c:CreateTexture(nil, "ARTWORK")
            c.tex:SetPoint("TOPLEFT", 1, -1); c.tex:SetPoint("BOTTOMRIGHT", -1, 1)
            c.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row.cells[i] = c
        end
        row:Hide()
        win.rows[r] = row
    end

    win.foot = W.Text(win, 11, S.dim, "LEFT")
    win.foot:SetPoint("BOTTOMLEFT", PAD, 9)

    local elapsed = 0
    win:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed < 0.5 then return end
        elapsed = 0
        if closeAt and GetTime() >= closeAt and not self:IsMouseOver() then
            closeAt = nil; self:Hide(); return
        end
        if not InCombatLockdown() then ns.RefreshReadyCheck() end
    end)
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

function ns.RefreshReadyCheck()
    if not win or not win:IsShown() then return end
    local list = SortedRoster()
    local me = ns.Me()

    -- which columns: the four blessings (if any paladin), raid buffs whose class is present,
    -- food and flask always
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

    local x0 = PAD + NAME_W + COUNT_W
    for i, h in ipairs(win.heads) do h:Hide() end
    for n, ci in ipairs(shownCols) do
        local h = win.heads[ci]
        h:ClearAllPoints(); h:SetPoint("TOPLEFT", win, "TOPLEFT", x0 + (n - 1) * (CELL + GAP), -30)
        h:Show()
    end
    local width = x0 + #shownCols * (CELL + GAP) - GAP + PAD

    local ready, total, mine = 0, 0, 0
    local short, checked = 0, 0
    local npal = #(ns.paladins or {})
    local n = math.min(#list, MAXROWS)
    for r = 1, MAXROWS do
        local row = win.rows[r]
        local e = list[r]
        if r <= n and e then
            total = total + 1
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", win, "TOPLEFT", 6, -(TOP + (r - 1) * (ROW_H + 1)))
            row:SetWidth(width - 12)
            local cr, cg, cb = W.ClassColor(e.class)
            row.bg:SetColorTexture(cr, cg, cb, 0.18)
            row.name:SetText(ns.FirstName(e.name))
            row.name:SetTextColor(cr, cg, cb)

            local st
            if e.fake then st = e.ready
            else pcall(function() st = GetReadyCheckStatus and GetReadyCheckStatus(e.unit) end) end
            if not ns.Readable(st) then st = nil end
            if st then lastStatus[e.name] = st else st = lastStatus[e.name] end
            if st == "ready" then ready = ready + 1 end
            local rt = ReadyTexture(st)
            row.ready:SetTexture(rt); row.ready:SetShown(rt ~= nil)

            local alive = not ns.SafeUnit(UnitIsDeadOrGhost, e.unit, false)
            local have
            if e.fake then alive, have = not e.dead, ns.PreviewBuffs(e) else have = BuffsOn(e.unit) end
            local myKey = ns.KeyFor(me, e)

            -- how many blessings they should have (one from each paladin, distinct) vs have
            local expect, want = 0, {}
            for _, pal in ipairs(ns.paladins or {}) do
                local k = ns.KeyFor(pal, e)
                if k and not want[k] then want[k] = true; expect = expect + 1 end
            end
            if expect == 0 then expect = math.min(npal, 4) end
            if ns.preview and e.fake then expect = 3 end          -- pretend 3 paladins
            local got = 0
            for _, col in ipairs(COLS) do
                if col.blessing and HasCol(have, col) then got = got + 1 end
            end
            if not alive then
                row.bcount:SetText("dead"); row.bcount:SetTextColor(unpack(S.dim))
            elseif expect > 0 then
                checked = checked + 1
                local okb = got >= expect
                if not okb then short = short + 1 end
                row.bcount:SetText(("%d/%d"):format(math.min(got, expect), expect))
                row.bcount:SetTextColor(unpack(okb and S.good or S.bad))
            else
                row.bcount:SetText("")
            end
            for i, c in ipairs(row.cells) do c:Hide() end
            for k, ci in ipairs(shownCols) do
                local col, c = COLS[ci], row.cells[ci]
                c:ClearAllPoints(); c:SetPoint("LEFT", row, "LEFT", x0 - 6 + (k - 1) * (CELL + GAP), 0)
                local ic = HasCol(have, col)
                local yours = col.blessing and myKey == col.key
                if ic then
                    c.tex:SetTexture(type(ic) ~= "boolean" and ic or col.icon); c.tex:Show()
                    if c.SetBackdrop then c:SetBackdropColor(0, 0, 0, 0.6); c:SetBackdropBorderColor(0, 0, 0, 1) end
                else
                    c.tex:Hide()
                    if c.SetBackdrop then
                        c:SetBackdropColor(0, 0, 0, 0.35)
                        if yours and alive then
                            c:SetBackdropBorderColor(S.bad[1], S.bad[2], S.bad[3], 1); mine = mine + 1
                        else
                            c:SetBackdropBorderColor(S.border[1], S.border[2], S.border[3], 0.6)
                        end
                    end
                end
                c:Show()
            end
            row:Show()
        else
            row:Hide()
        end
    end

    win.title:SetText("Ready check")
    win.count:SetText(("%d/%d ready"):format(ready, total))
    if checked == 0 then
        win.summary:SetText("")
    elseif short == 0 then
        win.summary:SetText(W.Hex(unpack(S.good)) .. "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t Everyone has all their blessings|r")
    else
        win.summary:SetText(W.Hex(unpack(S.bad)) .. short .. (short == 1 and " player is" or " players are") .. " short a blessing|r")
    end
    if mine > 0 then
        local key = GetBindingKey and GetBindingKey("CLICK PallyPulseSmartButton:LeftButton")
        win.foot:SetText(W.Hex(unpack(S.bad)) .. mine .. " of your blessings missing|r" ..
            (key and ("  -  press " .. (GetBindingText and GetBindingText(key, "KEY_") or key) .. " (Smart Buff)") or "  -  use Smart Buff"))
    else
        win.foot:SetText(W.Hex(unpack(S.good)) .. "All your blessings are up|r")
    end
    win:SetSize(math.max(width, 390), TOP + n * (ROW_H + 1) + FOOT + 4)
end

function ns.ShowReadyCheck(auto)
    if not win then Build() end
    if InCombatLockdown() then return end
    closeAt = nil
    win:SetScale(ns.db.scale or 1)
    win:Show()
    ns.RefreshReadyCheck()
    ns.dirty = true   -- the bar refreshes too
end

function ns.ToggleReadyCheck()
    if win and win:IsShown() then win:Hide() else ns.ShowReadyCheck() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("READY_CHECK")
ev:RegisterEvent("READY_CHECK_CONFIRM")
ev:RegisterEvent("READY_CHECK_FINISHED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:SetScript("OnEvent", function(_, event)
    if not ns.db then return end
    if event == "READY_CHECK" then
        wipe(lastStatus)
        if ns.db.readyCheck ~= false then ns.ShowReadyCheck(true) end
    elseif event == "READY_CHECK_CONFIRM" then
        ns.RefreshReadyCheck()
    elseif event == "READY_CHECK_FINISHED" then
        ns.RefreshReadyCheck()
        if win and win:IsShown() then closeAt = GetTime() + 15 end   -- stays open while you hover it
    elseif event == "PLAYER_REGEN_DISABLED" then
        if win then win:Hide() end
    end
end)
