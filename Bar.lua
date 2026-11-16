local ADDON, ns = ...
local S, W = ns.STYLE, ns.W

-- Compact buff bar:
--   [ SMART ]  Might > Thrall          [W][R][M][P] ... [Oath]
--   [ 46px  ]  5 missing  2 expiring
-- The smart button (or its keybind) casts the next buff you owe. The small class slots
-- still cast by hand: left-click greater (or normal), right-click normal blessing.

local SMART, MINI, GAP, PAD = 44, 28, 3, 7
local TEXT_W = 128
local PER_ROW_STACKED = 5
local bar
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

    s:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("Smart Buff", unpack(S.gold))
        local job = self.job
        if InCombatLockdown() then
            local cn = self.cnext
            if type(cn) == "table" and cn.combatRebless then
                GameTooltip:AddDoubleLine(cn.spell, cn.name, 1, 1, 1, 1, 1, 1)
                GameTooltip:AddLine("Re-blesses your current target (e.g. after Freedom)", unpack(S.dim))
                GameTooltip:AddLine("Target a mob or nobody to use the pull queue, then Oath", unpack(S.dim))
            elseif type(cn) == "table" then
                GameTooltip:AddDoubleLine(cn.spell, cn.name, 1, 1, 1, 1, 1, 1)
                GameTooltip:AddLine(("Combat queue: %d left, frozen at the pull"):format(self.cleft or 0), unpack(S.dim))
            elseif cn == "oath" then
                GameTooltip:AddDoubleLine("Oath of Light", tostring(ns.oath[ns.Me()]), 1, 1, 1, 1, 1, 1)
                GameTooltip:AddLine("Combat queue done; presses recast your Oath", unpack(S.dim))
            else
                GameTooltip:AddLine("Nothing queued (everyone was buffed at the pull)", unpack(S.dim))
            end
            GameTooltip:AddLine("Right-click: Oath of Light", 0.6, 0.6, 0.6)
            if ns.selfSpell then GameTooltip:AddLine("Alt + key: " .. ns.selfSpell .. " on yourself", 0.6, 0.6, 0.6) end
        elseif job then
            local r, g, b = 1, 1, 1
            local unit = job.unit
            if unit then local _, c = UnitClass(unit); if c then r, g, b = W.ClassColor(c) end end
            GameTooltip:AddDoubleLine(job.spell, job.name, 1, 1, 1, r, g, b)
            if job.rebless then
                local h = job.unit and ns.HandActive(job.unit)
                GameTooltip:AddLine(h and ("Re-bless: this replaces your " .. h)
                    or "Re-bless after your Freedom / Protection / Sacrifice", 0.5, 0.75, 0.5, true)
            end
            if job.greater then
                GameTooltip:AddLine("Greater blessing: covers the whole class", unpack(S.dim))
            elseif job.class then
                local why = ns.GreaterSkipReason(job.key, job.class)
                if why then GameTooltip:AddLine("Normal blessing, no reagent: " .. why, 0.5, 0.75, 0.5, true) end
            end
        else
            GameTooltip:AddLine("Everyone you're assigned to is buffed", unpack(S.good))
        end
        local st = self.stats
        if st then
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Missing", st.missing, 0.8, 0.8, 0.8, 1, 1, 1)
            GameTooltip:AddDoubleLine("Expiring soon", st.expiring, 0.8, 0.8, 0.8, 1, 1, 1)
            if st.far > 0 then GameTooltip:AddDoubleLine("Out of range", st.far, 0.8, 0.8, 0.8, 1, 1, 1) end
            if (st.held or 0) > 0 then GameTooltip:AddDoubleLine("Under your Freedom / Protection", st.held, 0.8, 0.8, 0.8, 1, 1, 1) end
        end
        GameTooltip:AddLine(" ")
        if not InCombatLockdown() and ns.oathCap[ns.Me()] then
            GameTooltip:AddLine("Right-click: Oath of Light", 0.6, 0.6, 0.6)
            if ns.selfSpell then GameTooltip:AddLine("Alt + key: " .. ns.selfSpell .. " on yourself", 0.6, 0.6, 0.6) end
        end
        local key = BindingText()
        GameTooltip:AddLine(key and ("Keybind: " .. key) or "Set a keybind: Esc > Options > Keybindings > PallyPulse", 0.6, 0.6, 0.6, true)
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
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if self.key then
                local bl = ns.BY_KEY[self.key].single
                local cname = LOCALIZED_CLASS_NAMES_MALE[self.class] or self.class
                GameTooltip:AddDoubleLine(bl, cname, 1, 1, 1, W.ClassColor(self.class))
                if (self.need or 0) == 0 then
                    GameTooltip:AddLine("Everyone is covered", unpack(S.good))
                else
                    GameTooltip:AddLine(("%d of %d need it"):format(self.need, self.total or 0), unpack(S.warn))
                    for n, name in ipairs(self.missing or {}) do
                        if n > 8 then GameTooltip:AddLine("...", unpack(S.dim)) break end
                        GameTooltip:AddLine("  " .. name, unpack(S.text))
                    end
                end
                GameTooltip:AddLine(" ")
                local left = ns.CastNames(self.key, self.class)
                local why = ns.GreaterSkipReason(self.key, self.class)
                GameTooltip:AddLine("Left-click: " .. tostring(left), 0.6, 0.6, 0.6)
                if why then GameTooltip:AddLine("  Normal blessing: " .. why, 0.5, 0.75, 0.5) end
                GameTooltip:AddLine("Right-click: normal blessing", 0.6, 0.6, 0.6)
                GameTooltip:AddLine("Shift-click: normal blessing on your target (works in combat)", 0.6, 0.6, 0.6)
                if not InCombatLockdown() then GameTooltip:AddLine("Players are listed below: click one to buff just them", 0.6, 0.6, 0.6, true) end
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
    o.strip:SetColorTexture(S.paladin[1], S.paladin[2], S.paladin[3], 1)
    o:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddDoubleLine("Oath of Light", tostring(ns.oath[ns.Me()]), S.paladin[1], S.paladin[2], S.paladin[3], 1, 1, 1)
        if self.left then
            GameTooltip:AddLine(W.FormatTime(self.left) .. " remaining", unpack(self.left < ns.OATH.warn and S.warn or S.good))
        else
            GameTooltip:AddLine("Not active", unpack(S.bad))
        end
        GameTooltip:AddLine("Click: cast Oath of Light on your Oath target", 0.6, 0.6, 0.6)
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
    au:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        local a = self.aura and ns.AURA_BY_KEY[self.aura]
        GameTooltip:AddLine(a and a.name or "Aura", unpack(S.gold))
        GameTooltip:AddLine(self.on and "On" or "Off - click to turn it on", unpack(self.on and S.good or S.bad))
        GameTooltip:AddLine("Your assigned aura (change it on the Blessings tab)", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    au:SetScript("OnLeave", function() GameTooltip:Hide() end)
    au:Hide()
    bar.auraBtn = au
end

-- ---------------------------------------------------------------------------
-- Player flyout: hover a class button (out of combat) to see everyone in that class and
-- click one to buff just them. Out of combat only: the game blocks showing click-to-cast
-- buttons during combat.
-- ---------------------------------------------------------------------------
local fly
local FLY_MAX, FLY_H, FLY_W = 12, 20, 168

local function BuildFlyout()
    fly = W.Panel(bar, FLY_W, 40)
    fly:SetFrameStrata("DIALOG")
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
        r.name:SetPoint("LEFT", r.icon, "RIGHT", 5, 0); r.name:SetWidth(92); r.name:SetWordWrap(false)
        r.time = W.Text(r, 10, S.dim, "RIGHT", S.num)
        r.time:SetPoint("RIGHT", -3, 0)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.10)
        r:SetPoint("TOPLEFT", 5, -5 - (i - 1) * FLY_H)
        r:Hide()
        fly.rows[i] = r
    end
    fly:SetScript("OnUpdate", function(self)
        if InCombatLockdown() then return end
        if not self:IsMouseOver() and not (self.anchor and self.anchor:IsMouseOver()) then self:Hide() end
    end)
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")     -- last chance to hide it before combat locks it
    ev:SetScript("OnEvent", function() if fly then fly:Hide() end end)
end

function ShowFlyout(btn)
    if InCombatLockdown() or not fly or not btn.class then return end
    local list = ns.byClass[btn.class]
    if not list then return end
    local me, n = ns.Me(), 0
    for _, e in ipairs(list) do
        if n >= FLY_MAX then break end
        local key = ns.KeyFor(me, e)
        if key and ns.BY_KEY[key] then
            n = n + 1
            local r = fly.rows[n]
            local _, single = ns.CastNames(key, e.class)
            r:SetAttribute("type1", "spell"); r:SetAttribute("spell1", single); r:SetAttribute("unit1", e.unit)
            r:SetAttribute("type2", "spell"); r:SetAttribute("spell2", single); r:SetAttribute("unit2", e.unit)
            r.icon:SetTexture(ns.BY_KEY[key].icon)
            r.name:SetText(ns.FirstName(e.name))
            r.name:SetTextColor(W.ClassColor(e.class))
            local alive = ns.Eligible(e)
            local left = alive and ns.MemberRemaining(e, key)
            r.time:SetText(not alive and "dead" or (left and W.FormatTime(left)) or "missing")
            r.time:SetTextColor(unpack((alive and not left) and S.bad or S.dim))
            r:SetAlpha((single and ns.InRange(single, e.unit) == false) and 0.45 or 1)
            r:Show()
        end
    end
    for i = n + 1, FLY_MAX do fly.rows[i]:Hide() end
    if n == 0 then fly:Hide() return end
    fly:SetSize(FLY_W, 10 + n * FLY_H)
    fly.anchor = btn
    fly:ClearAllPoints()
    fly:SetPoint("TOP", btn, "BOTTOM", 0, -4)
    fly:SetScale(1)
    fly:Show()
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

    bar.menuBtn = SmallIconButton(bar, "menu")
    bar.menuBtn:SetPoint("TOPRIGHT", -5, -5)
    bar.menuBtn:SetScript("OnClick", function() ns.ToggleWindow() end)
    W.Tip(bar.menuBtn, function(t) t:AddLine("Assignments", 1, 1, 1); t:AddLine("Right-click the bar also opens them", 0.6, 0.6, 0.6) end)

    bar.foldBtn = SmallIconButton(bar, "fold")
    bar.foldBtn:SetPoint("TOP", bar.menuBtn, "BOTTOM", 0, -3)
    bar.foldBtn:SetScript("OnClick", function() ns.db.collapsed = not ns.db.collapsed; ns.dirty = true end)
    W.Tip(bar.foldBtn, function(t) t:AddLine(ns.db.collapsed and "Show class buttons" or "Hide class buttons", 1, 1, 1) end)

    local elapsed = 0
    bar:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.4 then return end
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
local function Layout(minis)
    for _, b in ipairs(bar.buttons) do b:Hide() end
    bar.oathBtn:Hide()
    bar.auraBtn:Hide()

    local headW = PAD + SMART + 8 + TEXT_W + 20       -- 20 = room for the two small buttons
    local w, h = headW, PAD * 2 + SMART
    local n = #minis
    if not ns.db.collapsed and n > 0 then
        if ns.db.vertical then
            -- stacked: rows of class slots under the smart button
            for i, b in ipairs(minis) do
                local col = (i - 1) % PER_ROW_STACKED
                local rowi = math.floor((i - 1) / PER_ROW_STACKED)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD + col * (MINI + GAP), -(PAD + SMART + 6 + rowi * (MINI + GAP)))
                b:Show()
            end
            local rows = math.ceil(n / PER_ROW_STACKED)
            h = PAD * 2 + SMART + 6 + rows * (MINI + GAP) - GAP
            w = math.max(headW, PAD * 2 + math.min(n, PER_ROW_STACKED) * (MINI + GAP) - GAP)
        else
            local x = PAD + SMART + 8 + TEXT_W + 4
            local y = -(PAD + (SMART - MINI) / 2)
            for i, b in ipairs(minis) do
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", bar, "TOPLEFT", x + (i - 1) * (MINI + GAP), y)
                b:Show()
            end
            w = x + n * (MINI + GAP) - GAP + 22
        end
    end
    bar:SetSize(w, h)
    bar.foldBtn.tex:SetTexture(ns.db.collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
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
    if akey and aknown then
        local a = ns.AURA_BY_KEY[akey]
        au.aura, au.on = akey, aon
        au.icon:SetTexture(a.icon)
        W.SetSlotState(au, aon and "ok" or "all", not aon and "!" or nil, nil)
        if not combat then
            au:SetAttribute("type", "spell"); au:SetAttribute("spell", a.name); au:SetAttribute("unit", "player")
        end
        minis[#minis + 1] = au
    end

    for _, b in ipairs(bar.buttons) do
        local key = row[b.class]
        local list = ns.byClass[b.class]
        local active = key and ns.BY_KEY[key] and list and #list > 0
        b.key = active and key or nil
        if active then
            local need, total, target, lowest, missing = ns.ClassStatus(b.class, key)
            b.need, b.total, b.missing = need, total, missing
            b.icon:SetTexture(ns.BY_KEY[key].icon or W.QUESTION)
            local state = need == 0 and "ok" or (need == total and "all" or "need")
            W.SetSlotState(b, state, need, lowest)
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
    if ounit and ns.oathCap[me] then
        o.left = oleft
        o.icon:SetTexture(ns.OathIcon())
        local state = (not oleft and "all") or (oleft < ns.OATH.warn and "low") or "ok"
        W.SetSlotState(o, state, not oleft and "!" or nil, oleft)
        if not combat then
            o:SetAttribute("type", "spell")
            o:SetAttribute("spell", ns.OATH.name)
            o:SetAttribute("unit", ounit)
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
        s.count:ClearAllPoints(); s.count:SetPoint("BOTTOMRIGHT", -2, 2)
        s.timer:SetText("")
        s:SetBackdropBorderColor(unpack(S.gold))
        s.glow:Show(); if not s.pulse:IsPlaying() then s.pulse:Play() end
        local r, g, b = 1, 1, 1
        local _, c = UnitClass(cnext.unit); if c then r, g, b = W.ClassColor(c) end
        bar.line1:SetText(("%s  %s%s|r"):format(cnext.label, W.Hex(r, g, b), ns.FirstName(cnext.name)))
        bar.line1:SetTextColor(unpack(S.gold))
        local otxt = ""
        if ounit and ns.oathCap[me] then
            otxt = "   " .. W.Hex(unpack(S.paladin)) .. "Oath " .. (oleft and W.FormatTime(oleft) or "down") .. "|r"
        end
        local far = ns.InRange(cnext.spell, cnext.unit) == false
        if far then
            -- protected code can't skip them; a press fails (or self-casts with Auto Self Cast on)
            bar.line2:SetText("Out of range - press skips them" .. otxt)
            bar.line2:SetTextColor(unpack(S.bad))
            s.icon:SetDesaturated(true)
        elseif cnext.combatRebless then
            bar.line2:SetText("Re-bless your target" .. otxt)
            bar.line2:SetTextColor(unpack(S.text))
        else
            bar.line2:SetText(("Combat queue: %d left%s"):format(cleft, otxt))
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
            bar.line2:SetText("Expired - press to recast"); bar.line2:SetTextColor(unpack(S.bad))
        elseif oleft < ns.OATH.warn then
            bar.line2:SetText(W.FormatTime(oleft) .. " left - recast soon"); bar.line2:SetTextColor(unpack(S.warn))
        else
            bar.line2:SetText(W.FormatTime(oleft) .. " left"); bar.line2:SetTextColor(unpack(S.dim))
        end
    elseif combat then
        s.icon:SetDesaturated(true)
        s.check:Show(); s.count:Hide(); s.timer:SetText("")
        s:SetBackdropBorderColor(unpack(S.border))
        s.glow:Hide(); s.pulse:Stop()
        bar.line1:SetText("In combat"); bar.line1:SetTextColor(unpack(S.dim))
        bar.line2:SetText("Everyone was buffed at the pull")
    elseif job then
        s.timer:SetText("")
        s.icon:SetTexture(job.icon or W.QUESTION)
        s.icon:SetDesaturated(false); s.icon:SetVertexColor(1, 1, 1)
        s.check:Hide()
        s.count:SetShown(todo > 1); s.count:SetText(todo); s.count:SetTextColor(unpack(S.gold))
        s.count:ClearAllPoints(); s.count:SetPoint("BOTTOMRIGHT", -2, 2)
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
            bar.line2:SetText("Right-click to assign")
        elseif stats and stats.far > 0 then
            bar.line1:SetText("Out of range"); bar.line1:SetTextColor(unpack(S.warn))
            bar.line2:SetText(stats.far .. " still need a buff")
        else
            bar.line1:SetText("All buffed"); bar.line1:SetTextColor(unpack(S.good))
            bar.line2:SetText(soonest and ("Next refresh in " .. W.FormatTime(math.max(0, soonest - ns.db.refresh))) or "")
        end
        bar.line2:SetTextColor(unpack(S.dim))
    end
    local key = BindingText()
    s.key:SetText(key or "")

    if not combat then
        Layout(minis)
        ns.layoutDirty = false
    else
        ns.layoutDirty = true
    end
end

function ns.ToggleBar()
    if not bar then return end
    if bar:IsShown() then
        bar:Hide(); ns.Print("Bar hidden. /pulse bar shows it again.")
    else
        bar:Show(); ns.dirty = true
    end
end
