local ADDON, ns = ...
local S, W = ns.STYLE, ns.W

-- Compact buff bar:
--   [ SMART ]  Might > Thrall          [W][R][M][P] ... [Oath]
--   [ 46px  ]  5 missing  2 expiring
-- The smart button (or its keybind) casts the next buff you owe. The small class slots
-- still cast by hand: left-click greater (or normal), right-click normal blessing.

local SMART, MINI, GAP, PAD = 44, 22, 2, 7
local TEXT_W = 128
-- Bar (PallyPower style): rows tinted by status, stacked (Vertical) or side by side
-- (Horizontal), with a small drag dot on the left and no panel behind them.
local ROW_GAP, HANDLE = 1, 14
-- rows get wider when class names are shown beside the icons
local CNAME_W = 50
local function RowW() return (ns.db.rowWidth or 76) + (ns.db.barClassNames and CNAME_W or 0) end
-- Tracker settings: row height, icon size, display mode
local function RH() return math.max(16, math.min(32, ns.db.rowHeight or 22)) end
local function ISZ() return math.max(10, math.min(RH() - 2, ns.db.iconSize or (RH() - 4))) end
local function Mode()
    local m = ns.db.barMode
    return (m == "compact" or m == "action") and m or "standard"
end
local function Square() return Mode() == "compact" end      -- icon cells instead of rows
local function CellW() return Square() and RH() or RowW() end
-- thin status strip on each row (left edge; bottom edge on icon cells)
local function AddStat(b)
    b.stat = b:CreateTexture(nil, "OVERLAY", nil, 1)
    b.stat:SetColorTexture(S.good[1], S.good[2], S.good[3], 1)
end

-- Seals (optional seal button, like PallyPower's). Click casts the chosen one; mouse wheel
-- picks another (out of combat).
local ICON = "Interface\\Icons\\"
local SEALS = {
    { name = "Seal of Righteousness", id = 21084, icon = ICON .. "Ability_ThunderBolt" },
    { name = "Seal of the Crusader",  id = 21082, icon = ICON .. "Spell_Holy_HolySmite" },
    { name = "Seal of Command",       id = 20375, icon = ICON .. "Ability_Warrior_InnerRage" },
    { name = "Seal of Justice",       id = 20164, icon = ICON .. "Spell_Holy_SealOfWrath" },
    { name = "Seal of Light",         id = 20165, icon = ICON .. "Spell_Holy_HealingAura" },
    { name = "Seal of Wisdom",        id = 20166, icon = ICON .. "Spell_Holy_RighteousnessAura" },
}
local function KnownSeals()
    local list = {}
    for _, sl in ipairs(SEALS) do
        if ns.KnownSpell(sl.name, sl.id) then list[#list + 1] = sl end
    end
    return list
end
local function CurrentSeal()
    local list = KnownSeals()
    for _, sl in ipairs(list) do if sl.name == ns.db.seal then return sl, list end end
    return list[1], list
end

-- Oath of Light on whoever you're pointing at: mouseover, else your target, else yourself.
-- Works in combat (the macro never changes). Afterwards that player becomes your Oath target.
local function OathMacro()
    local n = ns.OATH.name
    return "/cast [@mouseover,help,nodead][@target,help,nodead][@player] " .. n
end

function ns.PickOathFromCast()
    local me = ns.Me()
    local function ok(u)
        local r = false
        pcall(function()
            r = UnitExists(u) and UnitCanAssist("player", u) and not UnitIsDeadOrGhost(u)
                and (UnitIsUnit(u, "player") or UnitInParty(u) or UnitInRaid(u)) and true or false
        end)
        return r
    end
    local unit = (ok("mouseover") and "mouseover") or (ok("target") and "target") or "player"
    local name = ns.FullName(unit)
    if not name or not ns.Readable(name) then return end
    ns.db.oathAutoPick = nil          -- hand-picked: automatic Oath leaves it alone
    if name ~= ns.oath[me] then ns.SetOath(me, name, true) end
end

-- Alert sounds to pick from in Options: six game sounds, plus any sounds other installed
-- addons share through LibSharedMedia (Details, WeakAuras, DBM, BigWigs...). PallyPulse
-- doesn't ship the library; it only uses it when another addon has loaded it.
ns.SOUNDS = {
    { name = "Raid warning",   id = 8959 },
    { name = "Ready check",    id = 8960 },
    { name = "Whisper",        id = 3081 },
    { name = "Quest complete", id = 878 },
    { name = "Level up",       id = 888 },
    { name = "Map ping",       id = 3175 },
    { name = "Radiation ticker", file = "Interface\\AddOns\\PallyPulse\\Sounds\\RadiationTicker.ogg" },
}

function ns.SoundList()
    local list = {}
    for _, snd in ipairs(ns.SOUNDS) do list[#list + 1] = snd end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local seen = {}
        for _, snd in ipairs(ns.SOUNDS) do seen[snd.name] = true end
        local ok, names = pcall(LSM.List, LSM, "sound")
        for _, name in ipairs(ok and names or {}) do
            if name ~= "None" and not seen[name] then
                local file = LSM:Fetch("sound", name, true)
                if file then seen[name] = true; list[#list + 1] = { name = name, file = file } end
            end
        end
    end
    return list
end

-- The chosen sound (saved by name, so the list can grow without changing your pick)
function ns.CurrentSound()
    local list = ns.SoundList()
    local want = ns.db.alertSoundName or (ns.SOUNDS[ns.db.alertSound or 1] or ns.SOUNDS[1]).name
    for i, snd in ipairs(list) do if snd.name == want then return snd, i, list end end
    return list[1], 1, list
end

function ns.Alert()
    local snd = ns.CurrentSound()
    if snd.file then pcall(PlaySoundFile, snd.file, "Master")
    else pcall(PlaySound, snd.id, "Master") end
end
-- status colours: strip and text only; the rows themselves stay dark
local STATE_COLOR = { ok = S.good, low = S.warn, need = S.bad }
local bar

-- Two layouts, both made of the same class rows: Vertical ("compact", rows stacked) and
-- Horizontal (rows side by side).
local function Horizontal() return ns.db.barLayout == "horizontal" end
-- Horizontal: tooltips and the player list open below the bar in the top half of the
-- screen, above it in the bottom half.
local function SideDown()
    local _, cy = bar:GetCenter()
    if not cy then return true end
    return cy * bar:GetEffectiveScale() > (UIParent:GetHeight() * UIParent:GetEffectiveScale()) / 2
end
-- width taken by the two text lines beside Smart Buff (off unless "Show text" is on)
-- Tooltips and the player list open beside the bar, on the side facing the middle of the
-- screen, so they never cover the bar's own buttons.
local function SideRight()
    local cx = bar:GetCenter()
    if not cx then return true end
    return cx * bar:GetEffectiveScale() < (UIParent:GetWidth() * UIParent:GetEffectiveScale()) / 2
end

local function PlaceTip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    if Horizontal() then
        if SideDown() then GameTooltip:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
        else GameTooltip:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 4) end
    elseif SideRight() then
        GameTooltip:SetPoint("TOPLEFT", bar, "TOPRIGHT", 4, 0)
    else
        GameTooltip:SetPoint("TOPRIGHT", bar, "TOPLEFT", -4, 0)
    end
end

local function TextW() return ns.db.barText and (TEXT_W + 8) or 0 end
local ShowFlyout   -- defined below; the class buttons call it

local SECURE = "SecureActionButtonTemplate" .. (BackdropTemplateMixin and ",BackdropTemplate" or "")

local function BindingText()
    local key = GetBindingKey and GetBindingKey("CLICK PallyPulseSmartButton:LeftButton")
    return key and (GetBindingText and GetBindingText(key, "KEY_") or key) or nil
end

local function SmallIconButton(parent, kind)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(14, 14)
    if kind == "menu" then
        -- three gold lines; drawn, so it exists on every client
        b.lines = {}
        for i = 1, 3 do
            local t = b:CreateTexture(nil, "ARTWORK")
            t:SetSize(11, 2)
            t:SetPoint("TOP", 0, -2 - (i - 1) * 4)
            t:SetColorTexture(S.dim[1], S.dim[2], S.dim[3], 1)
            b.lines[i] = t
        end
        b:SetScript("OnEnter", function(self) for _, t in ipairs(self.lines) do t:SetColorTexture(S.gold[1], S.gold[2], S.gold[3], 1) end end)
        b:SetScript("OnLeave", function(self) for _, t in ipairs(self.lines) do t:SetColorTexture(S.dim[1], S.dim[2], S.dim[3], 1) end end)
    else
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        t:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
        b.tex = t
        b:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    end
    return b
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------
local function BuildSmart()
    local s = CreateFrame("Button", "PallyPulseSmartButton", bar, SECURE)
    W.IconSlot(s, SMART)
    s:RegisterForClicks("AnyDown", "AnyUp")
    s:SetPoint("TOPLEFT", PAD, -PAD)
    s.strip:SetColorTexture(S.gold[1], S.gold[2], S.gold[3], 1)
    s.count:SetFont(S.num, 18, "OUTLINE")
    s.isSmart = true
    AddStat(s)

    -- soft gold pulse while there is something to cast
    s.glow = s:CreateTexture(nil, "OVERLAY", nil, 3)
    s.glow:SetPoint("TOPLEFT", -13, 13); s.glow:SetPoint("BOTTOMRIGHT", 13, -13)
    s.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    s.glow:SetBlendMode("ADD")
    s.glow:SetVertexColor(S.gold[1], S.gold[2], S.gold[3])
    s.glow:Hide()
    local ag = s.glow:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(0.25); a:SetToAlpha(0.9); a:SetDuration(0.8)
    s.pulse = ag

    s.key = W.Text(s, 9, S.dim, "LEFT", S.num, "OUTLINE")
    s.key:SetPoint("TOPLEFT", 2, -2)
    -- what the next press casts ("Kings"), from the same job the key casts
    s.what = W.Text(s, 10, S.text, "LEFT", S.head)
    s.what:SetWordWrap(false)
    s.what:Hide()

    s:SetScript("OnEnter", function(self)
        PlaceTip(self)
        local key = BindingText()
        GameTooltip:AddDoubleLine("Next Blessing", key or "", S.gold[1], S.gold[2], S.gold[3], 0.6, 0.6, 0.6)
        local job, me = self.job, ns.Me()
        if InCombatLockdown() then
            local cn = self.cnext
            if type(cn) == "table" then
                local r, g, b = 1, 1, 1
                local _, c = UnitClass(cn.unit or ""); if c then r, g, b = W.ClassColor(c) end
                GameTooltip:AddDoubleLine(cn.spell, cn.name, 1, 1, 1, r, g, b)
                if not cn.combatRebless then
                    GameTooltip:AddDoubleLine("Queue", self.cleft or 0, 0.8, 0.8, 0.8, 1, 1, 1)
                end
            elseif cn == "oath" then
                GameTooltip:AddDoubleLine("Oath of Light", tostring(ns.oath[me]), 1, 1, 1, 1, 1, 1)
            else
                GameTooltip:AddLine("Queue empty", unpack(S.dim))
            end
        elseif job then
            local r, g, b = 1, 1, 1
            if job.unit then local _, c = UnitClass(job.unit); if c then r, g, b = W.ClassColor(c) end end
            GameTooltip:AddDoubleLine(job.spell, job.greater and (LOCALIZED_CLASS_NAMES_MALE[job.class] or job.class) or job.name, 1, 1, 1, r, g, b)
            if job.rebless then GameTooltip:AddLine("Re-bless", unpack(S.good)) end
        else
            GameTooltip:AddLine("All buffed", unpack(S.good))
        end
        local st = self.stats
        if st and not InCombatLockdown() then
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Missing", st.missing, 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine("Expiring", st.expiring, 0.8, 0.8, 0.8, 1, 1, 1)
            if st.far > 0 then GameTooltip:AddDoubleLine("Out of range", st.far, 0.8, 0.8, 0.8, 1, 1, 1) end
            if #ns.paladins > 0 and ns.ReadinessSummary then
                local sum = ns.ReadinessSummary()     -- same counts as the Ready Check
                GameTooltip:AddDoubleLine("Raid buffed", ("%d/%d"):format(sum.buffed, sum.eligible), 0.8, 0.8, 0.8, 1, 1, 1)
            end
            if (st.held or 0) > 0 then GameTooltip:AddDoubleLine("Hand active", st.held, 0.8, 0.8, 0.8, 1, 1, 1) end
            local warn = ns.db.reagentWarn or 0
            if warn > 0 and ns.KnowsAnyGreater() then
                local n = ns.ReagentCount()
                if n and n < warn then GameTooltip:AddDoubleLine("Symbol of Kings", n, 0.8, 0.8, 0.8, unpack(S.bad)) end
            end
        end
        GameTooltip:AddLine(" ")
        if ns.oathCap[me] then GameTooltip:AddLine("Right-click: Oath of Light", 0.6, 0.6, 0.6) end
        if ns.selfSpell then GameTooltip:AddLine("Alt: " .. ns.selfSpell .. " (self)", 0.6, 0.6, 0.6) end
        if not key then GameTooltip:AddLine("Not bound", 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    s:SetScript("OnLeave", function() GameTooltip:Hide() end)

    ns.WireSmart(s)
    bar.smart = s
end

local function BuildMinis()
    bar.buttons = {}
    for i, class in ipairs(ns.CLASSES) do
        local b = CreateFrame("Button", "PallyPulseBtn" .. i, bar, SECURE)
        W.IconSlot(b, MINI)
        b:RegisterForClicks("AnyDown", "AnyUp")
        b.strip:SetColorTexture(W.ClassColor(class))
        b.class = class
        AddStat(b)
        -- class icon, shown only in the Compact layout (left of the blessing icon)
        local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if tc then
            b.cicon = b:CreateTexture(nil, "ARTWORK")
            b.cicon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
            b.cicon:SetTexCoord(tc[1] + 0.02, tc[2] - 0.02, tc[3] + 0.02, tc[4] - 0.02)
            b.cicon:Hide()
        end
        -- class name (option), beside the icons
        b.cname = W.Text(b, 10, S.text, "LEFT")
        b.cname:SetWordWrap(false)
        b.cname:SetText(LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class)
        b.cname:SetTextColor(W.ClassColor(class))
        b.cname:Hide()
        -- another paladin gives this class the same blessing
        b.dupMark = W.Text(b, 9, S.bad, "CENTER", S.num, "OUTLINE")
        b.dupMark:SetPoint("TOPRIGHT", b.icon, "TOPRIGHT", 3, 2)
        b.dupMark:SetText("x2")
        b.dupMark:Hide()
        b:SetScript("OnEnter", function(self)
            PlaceTip(self)
            if self.key then
                local bl = ns.BY_KEY[self.key].single
                local cname = LOCALIZED_CLASS_NAMES_MALE[self.class] or self.class
                GameTooltip:AddDoubleLine(bl, cname, 1, 1, 1, W.ClassColor(self.class))
                if (self.need or 0) == 0 then
                    GameTooltip:AddLine("All buffed", unpack(S.good))
                else
                    -- the count on the row: players without it, or under the Expiring time
                    GameTooltip:AddLine(("%d/%d missing or expiring"):format(self.need, self.total or 0), unpack(S.bad))
                    for n, name in ipairs(self.missing or {}) do
                        if n > 8 then GameTooltip:AddLine("...", unpack(S.dim)) break end
                        GameTooltip:AddLine("  " .. ns.FirstName(name), unpack(S.text))
                    end
                end
                if self.lowest and self.lowest ~= math.huge then
                    GameTooltip:AddDoubleLine("Shortest", W.FormatTime(self.lowest), 0.8, 0.8, 0.8, unpack(self.soon and S.warn or S.good))
                end
                if self.dup then GameTooltip:AddLine("x2: also from " .. table.concat(self.dup, ", "), unpack(S.bad)) end
                GameTooltip:AddLine(" ")
                local left, right = ns.CastNames(self.key, self.class)
                GameTooltip:AddLine("Click: " .. tostring(left), 0.6, 0.6, 0.6)
                if right and right ~= left then GameTooltip:AddLine("Right-click: single", 0.6, 0.6, 0.6) end
                GameTooltip:AddLine("Shift-click: single on target", 0.6, 0.6, 0.6)
            end
            GameTooltip:Show()
            ShowFlyout(self)
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        bar.buttons[i] = b
    end

    local o = CreateFrame("Button", "PallyPulseOathBtn", bar, SECURE)
    W.IconSlot(o, MINI)
    o:RegisterForClicks("AnyDown", "AnyUp")
    o:HookScript("PostClick", function(_, button, down)
        if IsShiftKeyDown() and (down == nil or down == (GetCVarBool and GetCVarBool("ActionButtonUseKeyDown"))) then
            ns.PickOathFromCast()
        end
    end)
    o.strip:SetColorTexture(S.paladin[1], S.paladin[2], S.paladin[3], 1)
    AddStat(o)
    o:SetScript("OnEnter", function(self)
        PlaceTip(self)
        GameTooltip:AddDoubleLine("Oath of Light", tostring(ns.oath[ns.Me()]), S.paladin[1], S.paladin[2], S.paladin[3], 1, 1, 1)
        if self.left then
            GameTooltip:AddLine(W.FormatTime(self.left), unpack(self.left < ns.OATH.warn and S.warn or S.good))
        else
            GameTooltip:AddLine("Expired", unpack(S.bad))
        end
        GameTooltip:AddLine("Click: cast", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Shift-click: cast on target", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    o:SetScript("OnLeave", function() GameTooltip:Hide() end)
    o:Hide()
    bar.oathBtn = o

    -- Your assigned aura: click to turn it on.
    local au = CreateFrame("Button", "PallyPulseAuraBtn", bar, SECURE)
    W.IconSlot(au, MINI)
    au:RegisterForClicks("AnyDown", "AnyUp")
    au.strip:SetColorTexture(S.gold[1], S.gold[2], S.gold[3], 1)
    AddStat(au)
    au:SetScript("OnEnter", function(self)
        PlaceTip(self)
        local a = self.aura and ns.AURA_BY_KEY[self.aura]
        GameTooltip:AddLine(a and a.name or "Aura", unpack(S.gold))
        GameTooltip:AddLine(self.on and "On" or "Off", unpack(self.on and S.good or S.bad))
        GameTooltip:Show()
    end)
    au:SetScript("OnLeave", function() GameTooltip:Hide() end)
    au:Hide()
    bar.auraBtn = au

    local se = CreateFrame("Button", "PallyPulseSealBtn", bar, SECURE)
    W.IconSlot(se, MINI)
    se:RegisterForClicks("AnyDown", "AnyUp")
    se.strip:SetColorTexture(S.gold[1], S.gold[2], S.gold[3], 1)
    AddStat(se)
    se:EnableMouseWheel(true)
    se:SetScript("OnMouseWheel", function(self, delta)
        if InCombatLockdown() then return end
        local cur, list = CurrentSeal()
        if not cur or #list < 2 then return end
        local idx = 1
        for i, sl in ipairs(list) do if sl == cur then idx = i end end
        idx = ((idx - 1 - delta) % #list) + 1
        ns.db.seal = list[idx].name
        ns.dirty = true
        ns.RefreshBar()
        if self:IsMouseOver() then self:GetScript("OnEnter")(self) end
    end)
    se:SetScript("OnEnter", function(self)
        PlaceTip(self)
        local cur = CurrentSeal()
        GameTooltip:AddLine(cur and cur.name or "Seal", unpack(S.gold))
        GameTooltip:AddLine("Click: cast", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Wheel: change", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    se:SetScript("OnLeave", function() GameTooltip:Hide() end)
    se:Hide()
    bar.sealBtn = se
end

-- ---------------------------------------------------------------------------
-- Player flyout: hover a class button to see everyone in that class and click one to buff
-- just them. Out of combat it's filled live. In combat the game only lets protected code
-- show it, so at the pull each class button gets its player list (ArmFlyout) and a secure
-- OnEnter snippet shows the flyout from that.
-- ---------------------------------------------------------------------------
local fly
local FLY_MAX, FLY_H, FLY_W = 12, 20, 168

local flyHeader

-- shown by protected code in combat
local FLY_SNIPPET = [=[
    if not owner:GetAttribute("on") then return end
    local fly = owner:GetFrameRef("fly")
    local n = self:GetAttribute("fn") or 0
    for i = 1, 12 do
        local r = owner:GetFrameRef("row" .. i)
        if i <= n then
            local u, sp = self:GetAttribute("fu" .. i), self:GetAttribute("fs" .. i)
            r:SetAttribute("type1", sp and "spell" or nil); r:SetAttribute("spell1", sp); r:SetAttribute("unit1", u)
            r:SetAttribute("type2", sp and "spell" or nil); r:SetAttribute("spell2", sp); r:SetAttribute("unit2", u)
            r:Show()
        else
            r:Hide()
        end
    end
    if n == 0 then fly:Hide() return end
    fly:SetHeight(10 + n * 20)
    fly:ClearAllPoints()
    fly:SetPoint(self:GetAttribute("fp"), self, self:GetAttribute("frp"), self:GetAttribute("fx") or 0, 0)
    fly:Show()
    fly:RegisterAutoHide(0.5)
    fly:AddToAutoHide(self)
]=]

local SetBars, RangeLevel     -- defined below

local function BuildFlyout()
    fly = CreateFrame("Frame", "PallyPulseFlyout", bar,
        "SecureHandlerBaseTemplate" .. (BackdropTemplateMixin and ",BackdropTemplate" or ""))
    fly:SetSize(FLY_W, 40)
    W.StylePanel(fly)
    fly:SetFrameStrata("DIALOG")
    fly:SetClampedToScreen(true)
    fly:Hide()
    fly.rows = {}
    for i = 1, FLY_MAX do
        local r = CreateFrame("Button", "PallyPulseFly" .. i, fly, SECURE)
        r:SetSize(FLY_W - 10, FLY_H)
        r:RegisterForClicks("AnyDown", "AnyUp")
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16); r.icon:SetPoint("LEFT", 2, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.name = W.Text(r, 11, S.text)
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0); r.name:SetWidth(86); r.name:SetWordWrap(false)
        r.time = W.Text(r, 10, S.dim, "RIGHT", S.num)
        r.time:SetPoint("RIGHT", -3, 0)
        -- range: three signal bars, left of the time
        r.bars = {}
        for b = 1, 3 do
            local t = r:CreateTexture(nil, "ARTWORK")
            t:SetSize(3, 3 + b * 3)
            t:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -36 - (3 - b) * 4, 5)
            r.bars[b] = t
        end
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.10)
        r:SetPoint("TOPLEFT", 5, -5 - (i - 1) * FLY_H)
        -- mouse wheel: change the blessing you give this player (a personal blessing)
        r:EnableMouseWheel(true)
        r:SetScript("OnMouseWheel", function(self, delta)
            local e = self.entry
            if InCombatLockdown() or not e then return end
            local me = ns.Me()
            local caps = ns.ComputeOwnCaps()
            local keys = {}
            for _, b in ipairs(ns.BLESSINGS) do
                if not caps or caps[b.key] then keys[#keys + 1] = b.key end
            end
            if #keys < 2 then return end
            local cur, idx = ns.KeyFor(me, e), 1
            for i2, k in ipairs(keys) do if k == cur then idx = i2 end end
            local new = keys[((idx - 1 - delta) % #keys) + 1]
            local classKey = ns.assign[me] and ns.assign[me][e.class]
            -- back to the class blessing: clear the exception, unless Auto-assign set one
            -- (then a hand-set class blessing is what overrides it)
            local auto = ns.db.autoOverride[me] and ns.db.autoOverride[me][e.name]
            local keep = new ~= classKey or (auto and auto ~= new)
            ns.SetOverride(me, e.name, keep and new or nil, not e.fake)
            ns.dirty = true
            ShowFlyout(fly.anchor)
            if self:IsMouseOver() then self:GetScript("OnEnter")(self) end
        end)
        r:SetScript("OnEnter", function(self)
            local e = self.entry
            if not e then return end
            GameTooltip:SetOwner(self, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("TOPLEFT", fly, "BOTTOMLEFT", 0, -4)
            GameTooltip:AddLine(ns.FirstName(e.name), W.ClassColor(e.class))
            if self.key then GameTooltip:AddLine("Click: " .. ns.BY_KEY[self.key].single, 1, 1, 1) end
            GameTooltip:AddLine("Wheel: change", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:HookScript("PostClick", function(self) if self.entry then ns.NoteFlyCast(self.entry.name) end end)
        r:Hide()
        fly.rows[i] = r
    end
    -- stays open while the mouse is on it, its button or the bar, with half a second of
    -- grace so crossing the gap between the bar and the list doesn't close it
    fly:SetScript("OnUpdate", function(self, dt)
        -- range bars, twice a second, in or out of combat
        self.rangeT = (self.rangeT or 0) + dt
        if self.rangeT > 0.5 then
            self.rangeT = 0
            for _, r in ipairs(self.rows) do
                if r:IsShown() and r.entry then SetBars(r, r.entry.fake and 3 or RangeLevel(r.entry, r.single)) end
            end
        end
        if InCombatLockdown() then return end
        if self:IsMouseOver() or (self.anchor and self.anchor:IsMouseOver()) or bar:IsMouseOver() then
            self.away = 0
            return
        end
        self.away = (self.away or 0) + dt
        if self.away > 0.5 then self:Hide() end
    end)
    -- combat: class buttons show the flyout through protected code
    flyHeader = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
    flyHeader:SetFrameRef("fly", fly)
    for i = 1, FLY_MAX do flyHeader:SetFrameRef("row" .. i, fly.rows[i]) end
    for _, b in ipairs(bar.buttons) do
        pcall(SecureHandlerWrapScript, b, "OnEnter", flyHeader, FLY_SNIPPET)
    end

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")     -- last chance to set things up before combat locks it
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            fly:Hide()
            ns.ArmFlyout()
        else
            flyHeader:SetAttribute("on", nil)
        end
    end)
end

-- The players a class button lists, in flyout order.
local function FlyEntries(class)
    local out, me = {}, ns.Me()
    for _, e in ipairs(ns.byClass[class] or {}) do
        if #out >= FLY_MAX then break end
        local key = ns.KeyFor(me, e)
        if key and ns.BY_KEY[key] then
            local _, single = ns.CastNames(key, e.class)
            out[#out + 1] = { e = e, key = key, single = single }
        end
    end
    return out
end

-- Where the flyout goes for a button: beside the bar, level with the button, on the side
-- facing the middle of the screen. As an anchor on the button itself, for protected code.
local function FlyAnchor(btn)
    if Horizontal() then
        if SideDown() then return "TOPLEFT", "BOTTOMLEFT", 0 end
        return "BOTTOMLEFT", "TOPLEFT", 0
    end
    if SideRight() then
        return "TOPLEFT", "TOPRIGHT", ((bar:GetRight() or 0) - (btn:GetRight() or 0)) + 2
    end
    return "TOPRIGHT", "TOPLEFT", -2
end

-- PLAYER_REGEN_DISABLED: give each class button its player list for the combat flyout.
function ns.ArmFlyout()
    if not flyHeader or InCombatLockdown() then return end
    for _, b in ipairs(bar.buttons) do
        local old = b:GetAttribute("fn") or 0
        for i = 1, old do b:SetAttribute("fu" .. i, nil); b:SetAttribute("fs" .. i, nil) end
        local n = 0
        if b:IsShown() and b.class then
            for i, it in ipairs(FlyEntries(b.class)) do
                n = i
                b:SetAttribute("fu" .. i, it.e.unit)
                b:SetAttribute("fs" .. i, (not it.e.fake) and it.single or nil)   -- never cast on test players
            end
            local p, rp, x = FlyAnchor(b)
            b:SetAttribute("fp", p); b:SetAttribute("frp", rp); b:SetAttribute("fx", x)
        end
        b:SetAttribute("fn", n)
    end
    flyHeader:SetAttribute("on", true)
end

-- 3 = in blessing range, 2 = within 40 yards, 1 = nearby, 0 = far or unknown
local RANGE_COLOR = { [3] = S.good, [2] = S.warn, [1] = S.bad }
function RangeLevel(e, spell)
    if e.name == ns.Me() then return 3 end
    if spell and ns.InRange(spell, e.unit) == true then return 3 end
    local inr
    pcall(function() inr = UnitInRange(e.unit) end)
    if ns.Readable(inr) and inr then return 2 end
    if ns.SafeUnit(UnitIsVisible, e.unit, false) then return 1 end
    return 0
end

function SetBars(r, level)
    local c = RANGE_COLOR[level]
    for b, t in ipairs(r.bars) do
        if c and b <= level then t:SetColorTexture(c[1], c[2], c[3], 1)
        else t:SetColorTexture(0.35, 0.35, 0.35, 0.6) end
    end
end

-- Names, icons, range and times on the rows (allowed in combat; the click setup is not).
local function FillRow(r, it)
    local e, key = it.e, it.key
    r.entry, r.key = e, key
    r.own = ns.IsException(ns.Me(), e) and true or false
    r.icon:SetTexture(ns.BY_KEY[key].icon)
    r.name:SetText(ns.FirstName(e.name) .. (r.own and " *" or ""))
    r.name:SetTextColor(W.ClassColor(e.class))
    local alive = ns.Eligible(e)
    local left = alive and ns.MemberRemaining(e, key)
    r.time:SetText(not alive and "Dead" or (left and W.FormatTime(left)) or "Missing")
    r.time:SetTextColor(unpack((alive and not left) and S.bad or S.dim))
    r.single = it.single
    SetBars(r, e.fake and 3 or RangeLevel(e, it.single))
end

function ShowFlyout(btn)
    if not fly or not btn.class then return end
    if InCombatLockdown() then
        -- the protected snippet has already shown it; just label the rows
        for i, it in ipairs(FlyEntries(btn.class)) do FillRow(fly.rows[i], it) end
        if fly:IsShown() and GameTooltip:IsOwned(btn) then
            GameTooltip:ClearAllPoints()
            if SideRight() then
                GameTooltip:SetPoint("TOPLEFT", fly, "BOTTOMLEFT", 0, -4)
            else
                GameTooltip:SetPoint("TOPRIGHT", fly, "BOTTOMRIGHT", 0, -4)
            end
        end
        return
    end
    local n = 0
    for i, it in ipairs(FlyEntries(btn.class)) do
        n = i
        local r, e, single = fly.rows[i], it.e, it.single
        r:SetAttribute("type1", "spell"); r:SetAttribute("spell1", single); r:SetAttribute("unit1", e.unit)
        r:SetAttribute("type2", "spell"); r:SetAttribute("spell2", single); r:SetAttribute("unit2", e.unit)
        if e.fake then r:SetAttribute("type1", nil); r:SetAttribute("type2", nil) end   -- preview player
        FillRow(r, it)
        r:SetAlpha(1)
        r:Show()
    end
    for i = n + 1, FLY_MAX do fly.rows[i]:Hide() end
    if n == 0 then fly:Hide() return end
    fly:SetSize(FLY_W, 10 + n * FLY_H)
    fly.anchor = btn
    fly:ClearAllPoints()
    -- beside the bar, level with the button; the button's tooltip moves under the list
    local yoff = (btn:GetTop() or 0) - (bar:GetTop() or 0)
    local right = SideRight()
    local horiz, down = Horizontal(), SideDown()
    if horiz then
        if down then fly:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
        else fly:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 2) end
    elseif right then
        fly:SetPoint("TOPLEFT", bar, "TOPRIGHT", 2, yoff)
    else
        fly:SetPoint("TOPRIGHT", btn, "TOPLEFT", -2, 0)    -- right next to the row, not past the drag dot
    end
    fly:SetScale(1)
    fly.away = 0
    fly:Show()
    if GameTooltip:IsOwned(btn) then
        GameTooltip:ClearAllPoints()
        if horiz then
            if down then GameTooltip:SetPoint("TOPLEFT", fly, "BOTTOMLEFT", 0, -4)
            else GameTooltip:SetPoint("BOTTOMLEFT", fly, "TOPLEFT", 0, 4) end
        elseif right then
            GameTooltip:SetPoint("TOPLEFT", fly, "BOTTOMLEFT", 0, -4)
        else
            GameTooltip:SetPoint("TOPRIGHT", fly, "BOTTOMRIGHT", 0, -4)
        end
    end
end

function ns.BuildBar()
    bar = W.Panel(UIParent, 200, SMART + PAD * 2, "PallyPulseBar")
    bar:SetFrameStrata("MEDIUM")
    ns.bar = bar

    -- drag by the panel itself; right-click the panel to open assignments
    W.MakeDraggable(bar, bar, "bar", true, true)
    bar:SetScript("OnMouseUp", function(_, btn) if btn == "RightButton" then ns.ToggleWindow() end end)

    BuildSmart()

    bar.line1 = W.Text(bar, 13, S.text, "LEFT", S.head)
    bar.line1:SetPoint("TOPLEFT", bar.smart, "TOPRIGHT", 8, -6)
    bar.line1:SetWidth(TEXT_W); bar.line1:SetWordWrap(false)
    bar.line2 = W.Text(bar, 11, S.dim)
    bar.line2:SetPoint("TOPLEFT", bar.line1, "BOTTOMLEFT", 0, -4)
    bar.line2:SetWidth(TEXT_W); bar.line2:SetWordWrap(false)

    BuildMinis()
    BuildFlyout()

    -- keybind "Oath of Light on target" (Key Bindings > AddOns > PallyPulse)
    local ot = CreateFrame("Button", "PallyPulseOathTarget", UIParent, SECURE)
    ot:SetSize(1, 1)
    local down = true
    pcall(function() if GetCVarBool then down = GetCVarBool("ActionButtonUseKeyDown") end end)
    ot:RegisterForClicks(down and "AnyDown" or "AnyUp")
    ot:SetAttribute("type", "macro")
    ot:SetAttribute("macrotext", OathMacro())
    ot:SetScript("PostClick", function() ns.PickOathFromCast() end)

    bar.menuBtn = SmallIconButton(bar, "menu")
    bar.menuBtn:SetPoint("TOPRIGHT", -5, -5)
    bar.menuBtn:SetScript("OnClick", function() ns.ToggleWindow() end)
    W.Tip(bar.menuBtn, function(t) t:AddLine("Assignments", 1, 1, 1) end)

    bar.foldBtn = SmallIconButton(bar, "fold")
    bar.foldBtn:SetPoint("TOP", bar.menuBtn, "BOTTOM", 0, -3)
    bar.foldBtn:SetScript("OnClick", function() ns.db.collapsed = not ns.db.collapsed; ns.dirty = true end)
    W.Tip(bar.foldBtn, function(t) t:AddLine(ns.db.collapsed and "Expand" or "Collapse", 1, 1, 1) end)

    -- Compact layout's drag dot: drag to move, click to fold the rows, right-click for assignments
    local hd = CreateFrame("Button", nil, bar)
    hd:SetSize(12, 12)
    hd:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    hd.tex = hd:CreateTexture(nil, "ARTWORK")
    hd.tex:SetAllPoints()
    hd.tex:SetTexture("Interface\\COMMON\\Indicator-Green")
    if not hd.tex:GetTexture() then hd.tex:SetColorTexture(S.good[1], S.good[2], S.good[3], 1) end
    hd:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    W.MakeDraggable(bar, hd, "bar", true, true)
    hd:SetScript("OnClick", function(_, btn)
        if btn == "RightButton" then ns.ToggleWindow()
        else ns.db.collapsed = not ns.db.collapsed; ns.dirty = true end
    end)
    W.Tip(hd, function(t)
        t:AddLine("PallyPulse", unpack(S.gold))
        t:AddLine(ns.db.collapsed and "Click: expand" or "Click: collapse", 0.8, 0.8, 0.8)
        t:AddLine("Right-click: assignments", 0.8, 0.8, 0.8)
    end)
    bar.handle = hd
    -- start in the row look straight away: after a /reload in combat the rows can't be laid
    -- out until combat ends, but the panel, text and old buttons needn't show meanwhile
    bar:SetBackdropColor(0, 0, 0, 0); bar:SetBackdropBorderColor(0, 0, 0, 0)
    bar.line1:Hide(); bar.line2:Hide()
    bar.menuBtn:Hide(); bar.foldBtn:Hide()
    hd:ClearAllPoints(); hd:SetPoint("RIGHT", bar.smart, "LEFT", -1, 0)
    hd:Show()

    local elapsed = 0
    bar:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.4 then return end
        if ns.ApplyBarFade then ns.ApplyBarFade() end
        if ns.dirty or elapsed > 5 then
            elapsed = 0
            ns.RefreshBar()
        end
    end)

    W.RestorePos(bar, "bar", { "CENTER", "CENTER", 0, -200 })
    bar:SetScale(ns.db.scale)
end

-- ---------------------------------------------------------------------------
-- Layout (out of combat only: moving or showing secure buttons is protected)
-- ---------------------------------------------------------------------------
-- Reshape a slot button for the Compact rows or back to a square icon.
-- after a font or style change, let every slot lay itself out again
function ns.OnStyleChanged()
    if not bar then return end
    for _, b in ipairs(bar.buttons or {}) do b.shaped = nil end
    for _, b in ipairs({ bar.smart, bar.auraBtn, bar.sealBtn, bar.oathBtn }) do if b then b.shaped = nil end end
end

local function SetNumFont(fs, size)
    local path = fs:GetFont()
    fs.ppSize = size
    if path then fs:SetFont(path, size, "OUTLINE") end
end

-- Lay a slot out as a row (Standard, Action only) or an icon cell (Compact).
local function Shape(b)
    local rh, isz, sq = RH(), ISZ(), Square()
    local want = (sq and "sq" or "row") .. RowW() .. ":" .. rh .. ":" .. isz
    if b.shaped == want then return end
    b.shaped = want
    b.icon:ClearAllPoints(); b.count:ClearAllPoints(); b.timer:ClearAllPoints(); b.check:ClearAllPoints()
    b.stat:ClearAllPoints()
    local fs = math.max(10, math.floor(rh * 0.5))
    if not sq then
        b:SetSize(RowW(), rh)
        b.stat:SetPoint("TOPLEFT", 1, -1); b.stat:SetPoint("BOTTOMLEFT", 1, 1); b.stat:SetWidth(3)
        local x = 6
        if b.cicon then
            b.cicon:ClearAllPoints(); b.cicon:SetSize(isz, isz); b.cicon:SetPoint("LEFT", x, 0); b.cicon:Show()
            x = x + isz + 2
        end
        b.icon:SetSize(isz, isz); b.icon:SetPoint("LEFT", x, 0)
        x = x + isz + 4
        if b.cname then
            b.cname:ClearAllPoints()
            b.cname:SetPoint("LEFT", x, 0); b.cname:SetWidth(CNAME_W - 4)
            b.cname:SetShown(ns.db.barClassNames and true or false)
        end
        if b.what then
            b.what:ClearAllPoints()
            b.what:SetPoint("LEFT", x, 0); b.what:SetPoint("RIGHT", -24, 0)
        end
        b.count:SetPoint("RIGHT", -6, 0)
        b.timer:SetPoint("RIGHT", -6, 0)
        b.check:SetPoint("BOTTOMRIGHT", 1, -1)
        b.strip:Hide()
        SetNumFont(b.count, b.isSmart and fs + 1 or fs)
        SetNumFont(b.timer, math.max(9, fs - 1))
    else
        b:SetSize(rh, rh)
        b.stat:SetPoint("BOTTOMLEFT", 1, 1); b.stat:SetPoint("BOTTOMRIGHT", -1, 1); b.stat:SetHeight(2)
        b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        if b.cicon then b.cicon:Hide() end
        if b.cname then b.cname:Hide() end
        if b.what then b.what:Hide() end
        b.count:SetPoint("CENTER", 0, 1)
        b.timer:SetPoint("TOPRIGHT", 0, -1)
        b.check:SetPoint("BOTTOMRIGHT", 1, -1)
        -- class colour along the top, so each cell still says whose it is
        b.strip:ClearAllPoints()
        b.strip:SetPoint("TOPLEFT", 1, -1); b.strip:SetPoint("TOPRIGHT", -1, -1); b.strip:SetHeight(2)
        b.strip:SetShown(b.class ~= nil)
        SetNumFont(b.count, fs)
        SetNumFont(b.timer, math.max(8, fs - 3))
    end
end

-- Dark row, thin status strip, coloured count. Cosmetic only, so it also runs in combat.
local function Paint(b, state)
    local c = STATE_COLOR[state] or S.bad
    local a = math.max(0, math.min(1, ns.db.barAlpha or 0.85))
    if b.SetBackdropColor then
        local bg = (state == "need" and not b.isSmart) and S.rowMiss or S.panel
        b:SetBackdropColor(bg[1], bg[2], bg[3], a)
        if b.isSmart and state ~= "ok" then b:SetBackdropBorderColor(S.gold[1], S.gold[2], S.gold[3], 1)
        elseif Square() and state ~= "ok" then b:SetBackdropBorderColor(c[1], c[2], c[3], 0.8)
        else b:SetBackdropBorderColor(0, 0, 0, math.max(0.35, a)) end
    end
    local sc = (b.isSmart and state ~= "ok") and S.gold or c
    b.stat:SetColorTexture(sc[1], sc[2], sc[3], 1)
    b.check:Hide()
    if not b.isSmart then
        b.icon:SetDesaturated(false)
        local v = state == "ok" and 0.85 or 1
        b.icon:SetVertexColor(v, v, v)
        b.count:SetTextColor(unpack(state == "need" and S.bad or S.warn))
    end
    b.timer:SetTextColor(unpack(state == "low" and S.warn or S.text))
    if b.count:IsShown() or ns.db.rowTimers == false then b.timer:SetText("") end
end

local function RowState(b)
    local st = b.slotState
    if st == "ok" then return b.soon and "low" or "ok" end
    if st == "low" then return "low" end
    return "need"
end

local function SetChrome(compact)
    if compact then
        bar:SetBackdropColor(0, 0, 0, 0); bar:SetBackdropBorderColor(0, 0, 0, 0)
    else
        bar:SetBackdropColor(unpack(S.bg)); bar:SetBackdropBorderColor(unpack(S.frame))
    end
    bar.line1:SetShown(not compact and ns.db.barText); bar.line2:SetShown(not compact and ns.db.barText)
    bar.menuBtn:SetShown(not compact); bar.foldBtn:SetShown(not compact)
    bar.handle:SetShown(compact)
end

local function Layout(minis)
    for _, b in ipairs(bar.buttons) do b:Hide() end
    bar.oathBtn:Hide()
    bar.auraBtn:Hide()
    bar.sealBtn:Hide()

    local s = bar.smart
    local n = #minis
    local rh, cw = RH(), CellW()
    SetChrome(true)
    local horiz = Horizontal()
    local up = ns.db.growUp and not horiz
    local cells = 1 + ((not ns.db.collapsed) and n or 0)
    -- keep the Smart row where it is: anchor the bar at its top (or bottom when growing up)
    local l, b0, t = bar:GetLeft(), bar:GetBottom(), bar:GetTop()
    if l then
        bar:ClearAllPoints()
        if up then bar:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b0)
        else bar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t) end
    end
    local function Pos(j)    -- j = 0 for the Smart row, 1.. for the others
        if horiz then return HANDLE + j * (cw + ROW_GAP), 0 end
        return HANDLE, -(((up and (cells - 1 - j)) or j) * (rh + ROW_GAP))
    end
    Shape(s)
    s:ClearAllPoints(); s:SetPoint("TOPLEFT", bar, "TOPLEFT", Pos(0))
    bar.handle:ClearAllPoints(); bar.handle:SetPoint("RIGHT", s, "LEFT", -1, 0)
    if not ns.db.collapsed then
        for i, b in ipairs(minis) do
            Shape(b)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", bar, "TOPLEFT", Pos(i))
            b:Show()
        end
    end
    if horiz then
        bar:SetSize(HANDLE + cells * (cw + ROW_GAP) - ROW_GAP, rh)
    else
        bar:SetSize(HANDLE + cw, cells * (rh + ROW_GAP) - ROW_GAP)
    end
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------
function ns.RefreshBar()
    if not bar then return end
    ns.dirty = false
    if ns.BeginScan then ns.BeginScan() end
    local me = ns.Me()
    local row = ns.assign[me] or {}
    local combat = InCombatLockdown()
    local minis, soonest = {}, nil

    -- Aura slot (first)
    local au = bar.auraBtn
    local akey, aon, aknown = ns.AuraStatus()
    if akey and aknown and ns.db.auraButton ~= false then
        local a = ns.AURA_BY_KEY[akey]
        au.aura, au.on = akey, aon
        au.icon:SetTexture(a.icon)
        W.SetSlotState(au, aon and "ok" or "all", not aon and "!" or nil, nil)
        if not combat then
            au:SetAttribute("type", "spell"); au:SetAttribute("spell", a.name); au:SetAttribute("unit", "player")
        end
        minis[#minis + 1] = au
    end

    -- Seal slot (optional): green while the seal is on you, tan when it isn't
    local se = bar.sealBtn
    if ns.db.sealButton then
        local cur = CurrentSeal()
        if cur then
            se.icon:SetTexture(cur.icon)
            local on = ns.FindAura("player", cur.name, "HELPFUL") ~= nil
            W.SetSlotState(se, on and "ok" or "low", nil, nil)
            if not combat then
                se:SetAttribute("type", "spell"); se:SetAttribute("spell", cur.name); se:SetAttribute("unit", "player")
            end
            minis[#minis + 1] = se
        end
    end

    for _, b in ipairs(bar.buttons) do
        local key = row[b.class]
        local list = ns.byClass[b.class]
        local active = key and ns.BY_KEY[key] and list and #list > 0
        b.key = active and key or nil
        b.dup = active and ns.SameBlessing(me, b.class) or nil
        b.dupMark:SetShown(b.dup ~= nil)
        if active then
            local need, total, target, lowest, missing = ns.ClassStatus(b.class, key)
            b.need, b.total, b.missing, b.lowest = need, total, missing, lowest
            b.icon:SetTexture(ns.BY_KEY[key].icon or W.QUESTION)
            local state = need == 0 and "ok" or (need == total and "all" or "need")
            W.SetSlotState(b, state, need, lowest)
            b.soon = lowest and lowest <= (ns.db.refresh or 0) or false
            if lowest and (not soonest or lowest < soonest) then soonest = lowest end
            if not combat then
                local greater, single = ns.CastNames(key, b.class)
                local unit = target or (list[1] and list[1].unit)
                b:SetAttribute("type1", "spell"); b:SetAttribute("spell1", greater)
                b:SetAttribute("type2", "spell"); b:SetAttribute("spell2", single)
                b:SetAttribute("unit1", unit);    b:SetAttribute("unit2", unit)
                -- Shift-click: this class's normal blessing on your current target. Works in
                -- combat, e.g. to re-bless someone after your Blessing of Freedom ends.
                b:SetAttribute("shift-type1", "spell"); b:SetAttribute("shift-spell1", single)
                b:SetAttribute("shift-unit1", "target")
                b:SetAttribute("shift-type2", "spell"); b:SetAttribute("shift-spell2", single)
                b:SetAttribute("shift-unit2", "target")
            end
            minis[#minis + 1] = b
        end
    end

    -- Oath of Light slot
    local o = bar.oathBtn
    local ounit, oleft = ns.OathStatus()
    if ns.db.oathSound and ounit and ns.oathCap[me] and oleft and oleft ~= math.huge then
        if oleft <= 30 and oleft > 0 then
            if not bar.oathWarned then bar.oathWarned = true; ns.Alert() end
        elseif oleft > 30 then
            bar.oathWarned = false
        end
    end
    if ounit and ns.oathCap[me] then
        o.left = oleft
        o.icon:SetTexture(ns.OathIcon())
        local state = (not oleft and "all") or (oleft < ns.OATH.warn and "low") or "ok"
        W.SetSlotState(o, state, not oleft and "!" or nil, oleft)
        if not combat then
            o:SetAttribute("type", "spell")
            o:SetAttribute("spell", ns.OATH.name)
            o:SetAttribute("unit", ounit)
            o:SetAttribute("shift-type1", "macro")
            o:SetAttribute("shift-macrotext1", OathMacro())
        end
        minis[#minis + 1] = o
    end

    -- Smart button
    local s = bar.smart
    local job, stats
    if combat then
        job, stats = nil, s.stats
    else
        ns.QueueSmart()
        job, stats = s.job, s.stats
    end
    s.stats = stats
    local todo = stats and (stats.missing + stats.expiring) or 0

    local cnext, cleft
    if combat then cnext, cleft = ns.CombatNext() end
    s.cnext, s.cleft = cnext, cleft

    if combat and type(cnext) == "table" then
        -- Working through the queue frozen at the pull.
        s.icon:SetTexture(cnext.icon or W.QUESTION)
        s.icon:SetDesaturated(false); s.icon:SetVertexColor(1, 1, 1)
        s.check:Hide()
        s.count:SetShown(cleft > 1); s.count:SetText(cleft); s.count:SetTextColor(unpack(S.gold))
        s.timer:SetText("")
        s:SetBackdropBorderColor(unpack(S.gold))
        s.glow:Show(); if not s.pulse:IsPlaying() then s.pulse:Play() end
        local r, g, b = 1, 1, 1
        local _, c = UnitClass(cnext.unit); if c then r, g, b = W.ClassColor(c) end
        bar.line1:SetText(("%s  %s%s|r"):format(cnext.label, W.Hex(r, g, b), ns.FirstName(cnext.name)))
        bar.line1:SetTextColor(unpack(S.gold))
        local otxt = ""
        if ounit and ns.oathCap[me] then
            otxt = "   " .. W.Hex(unpack(S.paladin)) .. "Oath " .. (oleft and W.FormatTime(oleft) or "Expired") .. "|r"
        end
        local far = ns.InRange(cnext.spell, cnext.unit) == false
        if far then
            -- protected code can't skip them; a press fails (or self-casts with Auto Self Cast on)
            bar.line2:SetText("Out of range" .. otxt)
            bar.line2:SetTextColor(unpack(S.bad))
            s.icon:SetDesaturated(true)
        elseif cnext.combatRebless then
            bar.line2:SetText("Re-bless target" .. otxt)
            bar.line2:SetTextColor(unpack(S.text))
        else
            bar.line2:SetText(("Queue: %d%s"):format(cleft, otxt))
            bar.line2:SetTextColor(unpack(S.text))
        end
    elseif combat and cnext == "oath" then
        -- Queue used up: the button casts Oath of Light on your Oath target.
        local urgent = (not oleft) or oleft < ns.OATH.warn
        s.icon:SetTexture(ns.OathIcon())
        s.icon:SetDesaturated(not urgent); s.icon:SetVertexColor(1, 1, 1)
        s.check:Hide(); s.count:Hide()
        s.timer:SetText(W.FormatTime(oleft))
        s:SetBackdropBorderColor(unpack(urgent and S.gold or S.border))
        if urgent then s.glow:Show(); if not s.pulse:IsPlaying() then s.pulse:Play() end
        else s.glow:Hide(); s.pulse:Stop() end
        local r, g, b = 1, 1, 1
        if ounit then local _, c = UnitClass(ounit); if c then r, g, b = W.ClassColor(c) end end
        bar.line1:SetText(("Oath  %s%s|r"):format(W.Hex(r, g, b), ns.FirstName(ns.oath[me] or "?")))
        bar.line1:SetTextColor(unpack(S.paladin))
        if not oleft then
            bar.line2:SetText("Expired"); bar.line2:SetTextColor(unpack(S.bad))
        elseif oleft < ns.OATH.warn then
            bar.line2:SetText(W.FormatTime(oleft)); bar.line2:SetTextColor(unpack(S.warn))
        else
            bar.line2:SetText(W.FormatTime(oleft)); bar.line2:SetTextColor(unpack(S.dim))
        end
    elseif combat then
        s.icon:SetDesaturated(true)
        s.check:Show(); s.count:Hide(); s.timer:SetText("")
        s:SetBackdropBorderColor(unpack(S.border))
        s.glow:Hide(); s.pulse:Stop()
        bar.line1:SetText("In combat"); bar.line1:SetTextColor(unpack(S.dim))
        bar.line2:SetText("Queue empty")
    elseif job then
        s.timer:SetText("")
        s.icon:SetTexture(job.icon or W.QUESTION)
        s.icon:SetDesaturated(false); s.icon:SetVertexColor(1, 1, 1)
        s.check:Hide()
        s.count:SetShown(todo > 1); s.count:SetText(todo); s.count:SetTextColor(unpack(S.gold))
        s:SetBackdropBorderColor(unpack(S.gold))
        s.glow:Show(); if not s.pulse:IsPlaying() then s.pulse:Play() end
        local r, g, b = 1, 1, 1
        local _, c = UnitClass(job.unit); if c then r, g, b = W.ClassColor(c) end
        bar.line1:SetText(("%s  %s%s|r"):format(job.label, W.Hex(r, g, b), ns.FirstName(job.name)))
        bar.line1:SetTextColor(unpack(S.gold))
        local parts = {}
        if stats.missing > 0 then parts[#parts + 1] = W.Hex(unpack(S.warn)) .. stats.missing .. " missing|r" end
        if stats.expiring > 0 then parts[#parts + 1] = stats.expiring .. " expiring" end
        if stats.far > 0 then parts[#parts + 1] = W.Hex(unpack(S.dim)) .. stats.far .. " far|r" end
        local warn = ns.db.reagentWarn or 0
        if warn > 0 and ns.KnowsAnyGreater() then
            local n = ns.ReagentCount()
            if n and n < warn then parts[#parts + 1] = W.Hex(unpack(S.bad)) .. n .. " Symbols|r" end
        end
        bar.line2:SetText(table.concat(parts, "  "))
        bar.line2:SetTextColor(unpack(S.text))
    else
        s.timer:SetText("")
        s.icon:SetTexture(ns.BY_KEY.KINGS.icon)
        s.icon:SetDesaturated(true); s.icon:SetVertexColor(0.55, 0.55, 0.55)
        s.check:Show(); s.count:Hide()
        s:SetBackdropBorderColor(unpack(S.border))
        s.glow:Hide(); s.pulse:Stop()
        if #minis == 0 then
            bar.line1:SetText("No assignments"); bar.line1:SetTextColor(unpack(S.dim))
            bar.line2:SetText("")
        elseif stats and stats.far > 0 then
            bar.line1:SetText("Out of range"); bar.line1:SetTextColor(unpack(S.warn))
            bar.line2:SetText(stats.far .. " out of range")
        else
            bar.line1:SetText("All buffed"); bar.line1:SetTextColor(unpack(S.good))
            bar.line2:SetText(soonest and ("Refresh in " .. W.FormatTime(math.max(0, soonest - ns.db.refresh))) or "")
        end
        bar.line2:SetTextColor(unpack(S.dim))
    end
    local key = BindingText()
    s.key:SetText(key or "")
    -- the next press, in words (rows only): same job the key casts, or the combat queue's next
    local what
    if combat and type(cnext) == "table" then what = cnext.label
    elseif combat and cnext == "oath" then what = "Oath"
    elseif not combat and job then what = job.label end
    if what then
        what = tostring(what):gsub("^Greater Blessing of ", ""):gsub("^Blessing of ", ""):gsub(" Aura$", "")
    end
    s.what:SetText(what or "")
    -- only when the row has room for it (wider rows or class names); the icon says it anyway
    local room = RowW() - (6 + ISZ() + 4) - 22
    s.what:SetShown(what ~= nil and not Square() and room >= 34)
    -- idle = nothing to cast (in combat: the combat queue is empty and Oath isn't urgent)
    bar.idle = not s.glow:IsShown() and not (not combat and stats and stats.far > 0)

    do
        -- smart row: red when there's something to cast, tan when only refreshes are due
        local st = "ok"
        if s.glow:IsShown() then
            st = (not combat and stats and stats.missing == 0 and stats.expiring > 0) and "low" or "need"
        elseif not combat and stats and stats.far > 0 then
            st = "low"
        end
        s.glow:Hide(); s.pulse:Stop()
        Paint(s, st)
        -- done: a small tick on the Smart row, nothing louder
        if st == "ok" and #minis > 0 then s.check:Show() end
        for _, b in ipairs(minis) do Paint(b, RowState(b)) end
    end

    if not combat and not bar.pulseMoving then   -- never re-lay out mid-drag: it fights the mouse
        -- Action only: just the rows that need you. Hiding secure buttons is only allowed out
        -- of combat, so the set shown at the pull stays until combat ends.
        if Mode() == "action" then
            local need = {}
            for _, b in ipairs(minis) do if RowState(b) ~= "ok" then need[#need + 1] = b end end
            minis = need
        end
        Layout(minis)
        ns.layoutDirty = false
    else
        ns.layoutDirty = true
    end
    ns.ApplyBarFade()
end

-- Fade the bar when there's nothing to cast (option), in or out of combat; full strength on
-- mouseover and while dragging.
function ns.ApplyBarFade()
    if not bar then return end
    local a = 1
    local hover = bar:IsMouseOver() or (fly and fly:IsShown() and fly:IsMouseOver())
    if ns.db.fadeIdle and bar.idle and not bar.pulseMoving and not hover then a = 0.3 end
    if bar:GetAlpha() ~= a then bar:SetAlpha(a) end
end

function ns.ToggleBar()
    if not bar then return end
    if bar:IsShown() then
        bar:Hide(); ns.Print("Bar hidden (/pulse bar)")
    else
        bar:Show(); ns.dirty = true
    end
end
