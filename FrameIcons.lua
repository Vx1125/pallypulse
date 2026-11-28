local ADDON, ns = ...
local S, W = ns.STYLE, ns.W

-- Big, readable blessing icons on Blizzard's party and raid frames, and on HealKit's frames.
--
-- On each frame, right side, inside the health bar:
--   [blessing]  the blessing you owe this player, with time left.
--               Missing it: red border, pulsing, "!".
--   [hand]      your Freedom / Protection / Sacrifice while it's on them (blue border).
--   [oath]      your Oath of Light, on your Oath target (pink border).
--
-- The icons are plain textures parented to Blizzard's frames and never take mouse input.
-- The one exception: a click spot over the blessing icon casts that player's blessing, in
-- combat too ("Click icon to bless"). It's a secure button set up out of combat, with a fixed
-- place (the blessing icon is always the rightmost), so nothing about it changes in combat.

local overlays = {}      -- blizzard frame -> overlay

local frameList = {}
local lastListBuild = 0

local function Enabled() return ns.db and ns.db.frameIcons end
local function Size() return (ns.db and ns.db.frameIconSize) or 22 end

-- Every Blizzard unit frame we know how to decorate, if it exists on this client.
local function BuildFrameList()
    wipe(frameList)
    local function add(f) if f and f.GetObjectType then frameList[#frameList + 1] = f end end
    for i = 1, 5 do add(_G["CompactPartyFrameMember" .. i]) end
    for i = 1, 40 do add(_G["CompactRaidFrame" .. i]) end
    for g = 1, 8 do for m = 1, 5 do add(_G["CompactRaidGroup" .. g .. "Member" .. m]) end end
    for i = 1, 4 do add(_G["PartyMemberFrame" .. i]) end                         -- classic portrait frames
    if PartyFrame then for i = 1, 4 do add(PartyFrame["MemberFrame" .. i]) end end  -- modern portrait frames
    -- HealKit (it hides Blizzard's group frames and keeps its own unit buttons in HealKit.cells;
    -- its preview cells are skipped)
    local hk = _G.HealKit
    if type(hk) == "table" and type(hk.cells) == "table" then
        for _, b in ipairs(hk.cells) do if type(b) == "table" and not b.fake then add(b) end end
    end
    lastListBuild = GetTime()
end

local function FrameUnit(f)
    local u = f.displayedUnit or f.unit
    if not u and f.GetAttribute then
        local ok, v = pcall(f.GetAttribute, f, "unit")
        if ok then u = v end
    end
    return u
end

-- ---------------------------------------------------------------------------
-- Overlay
-- ---------------------------------------------------------------------------
local function MakeSlot(parent, border)
    local s = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    W.IconSlot(s, Size())
    s:EnableMouse(false)
    s.check:Hide(); s.count:Hide()
    s.strip:SetColorTexture(0, 0, 0, 0)
    s.border = border
    s.bang = W.Text(s, 14, S.bad, "CENTER", S.num, "OUTLINE")
    s.bang:SetPoint("CENTER", 0, 0)
    s.bang:SetText("!")
    s.bang:Hide()
    local ag = s:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.35); a:SetDuration(0.6)
    s.pulse = ag
    s:Hide()
    return s
end

local function GetOverlay(f)
    local o = overlays[f]
    if o then return o end
    o = CreateFrame("Frame", nil, f)
    o:SetAllPoints(f)
    o:EnableMouse(false)
    o:SetFrameLevel((f:GetFrameLevel() or 1) + 8)
    o.bless = MakeSlot(o, S.border)
    o.hand = MakeSlot(o, { 0.30, 0.60, 1.00, 1 })
    o.oath = MakeSlot(o, S.paladin)
    overlays[f] = o
    return o
end

-- Out of combat only: point the click spot at this player and your blessing for them.
local function SetClick(o, f, unit, spell)
    if InCombatLockdown() then return end
    local b = o.click
    if not b then
        if not spell then return end
        -- parented to Blizzard's frame, not the overlay, so the overlay can still be shown
        -- and hidden in combat
        local ok
        ok, b = pcall(CreateFrame, "Button", nil, f, "SecureActionButtonTemplate")
        if not ok or not b then return end
        b:SetFrameLevel(o:GetFrameLevel() + 2)
        b:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
        b:EnableMouse(false)
        o.click = b
    end
    local on = spell and unit and ns.db.frameIconClick ~= false and true or false
    local sz = Size()
    if b.sz ~= sz then
        b:SetSize(sz, sz)
        b:ClearAllPoints()
        b:SetPoint("RIGHT", f, "RIGHT", -4, 0)
        b.sz = sz
    end
    if b.on ~= on or b.unit ~= unit or b.spell ~= spell then
        b:SetAttribute("type1", on and "spell" or nil)
        b:SetAttribute("spell1", on and spell or nil)
        b:SetAttribute("unit1", on and unit or nil)
        b:SetAttribute("unit", on and unit or nil)      -- keeps mouseover macros working here
        b:EnableMouse(on)
        b.on, b.unit, b.spell = on, unit, spell
    end
end

local function Resize(o)
    local sz = Size()
    for _, s in ipairs({ o.bless, o.hand, o.oath }) do
        s:SetSize(sz, sz)
        s.timer:SetFont(S.num, math.max(9, math.floor(sz * 0.42)), "OUTLINE")
        s.bang:SetFont(S.num, math.floor(sz * 0.7), "OUTLINE")
    end
    o.size = sz
end

-- Lay out the visible slots from the right edge inward, vertically centred.
local function Place(o, slots)
    local x = -4
    for _, s in ipairs(slots) do
        s:ClearAllPoints()
        s:SetPoint("RIGHT", o, "RIGHT", x, 0)
        x = x - (o.size + 2)
    end
end

-- far: out of range for your blessing. Shown dim and still, so it's clear a press won't reach.
local function SetSlot(s, icon, left, missing, far)
    s.icon:SetTexture(icon or W.QUESTION)
    s.icon:SetDesaturated((missing or far) and true or false)
    s.timer:SetText(missing and "" or W.FormatTime(left))
    s.bang:SetShown(missing and true or false)
    local c = (missing and not far) and S.bad or (far and S.dim) or s.border
    s:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    if missing and not far then
        if not s.pulse:IsPlaying() then s.pulse:Play() end
    else
        s.pulse:Stop()
    end
    s:SetAlpha(far and 0.4 or 1)
    s:Show()
end

local function SpellIcon(name)
    local icon
    pcall(function()
        if C_Spell and C_Spell.GetSpellTexture then icon = C_Spell.GetSpellTexture(name)
        elseif GetSpellTexture then icon = GetSpellTexture(name) end
    end)
    return icon
end

-- ---------------------------------------------------------------------------
-- Update
-- ---------------------------------------------------------------------------
local function EntryForUnit(unit)
    local name = ns.FullName(unit)
    if not name then return nil end
    for _, e in ipairs(ns.roster) do
        if e.name == name then return e end
    end
end

local function UpdateFrame(f)
    local o = overlays[f]
    local unit = f:IsVisible() and FrameUnit(f)
    local e = unit and ns.SafeUnit(UnitExists, unit, false) and EntryForUnit(unit)
    if not Enabled() or not e then
        if o then
            o:Hide()
            SetClick(o, f, nil, nil)
        end
        return
    end
    o = GetOverlay(f)
    if o.size ~= Size() then Resize(o) end
    o:Show()

    local me = ns.Me()
    local slots = {}
    local alive = ns.Eligible(e)

    -- your assigned blessing for this player's class
    local key = ns.KeyFor(me, e)
    if key and ns.BY_KEY[key] and alive then
        local left = ns.MemberRemaining(e, key)
        local far = e.name ~= me and ns.InRange and ns.InRange(ns.BY_KEY[key].single, e.unit) == false
        SetSlot(o.bless, ns.BY_KEY[key].icon, left, not left, far)
        slots[#slots + 1] = o.bless
        local _, single = ns.CastNames(key, e.class)
        SetClick(o, f, (not e.fake) and unit or nil, single)
    else
        o.bless:Hide()
        if alive or not key then SetClick(o, f, nil, nil) end   -- dead: keep it, they may be rezzed
    end

    -- your Freedom / Protection / Sacrifice
    local hand = alive and ns.HandActive(e.unit)
    if hand then
        SetSlot(o.hand, SpellIcon(hand), nil, false)
        slots[#slots + 1] = o.hand
    else
        o.hand:Hide()
    end

    -- your Oath of Light
    if ns.oathCap[me] and ns.oath[me] == e.name and alive then
        local _, oleft = ns.OathStatus()
        SetSlot(o.oath, ns.OathIcon(), oleft, not oleft)
        slots[#slots + 1] = o.oath
    else
        o.oath:Hide()
    end

    Place(o, slots)
end

-- units: optional set of unit tokens; only their frames are updated
function ns.RefreshFrameIcons(units)
    if GetTime() - lastListBuild > 5 then BuildFrameList() end
    for _, f in ipairs(frameList) do
        if not units or (f:IsVisible() and units[FrameUnit(f) or ""]) then
            local ok = pcall(UpdateFrame, f)
            if not ok and overlays[f] then overlays[f]:Hide() end
        end
    end
end

local driver = CreateFrame("Frame")
-- Every frame once a second (timers); between those, only the frames of players whose
-- auras changed. Auras on targets, nameplates and pets are ignored.
local elapsed, sinceFull, full = 0, 0, true
local changed = {}
driver:RegisterEvent("GROUP_ROSTER_UPDATE")
driver:RegisterEvent("UNIT_AURA")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" then
        if ns.IsGroupUnit(unit) then changed[unit] = true end
    else
        lastListBuild = 0                -- frames may have been created or reassigned
        full = true
    end
end)
driver:SetScript("OnUpdate", function(_, dt)
    elapsed, sinceFull = elapsed + dt, sinceFull + dt
    if elapsed < 0.25 or not ns.db then return end
    elapsed = 0
    if full or sinceFull >= 1 then
        full, sinceFull = false, 0
        wipe(changed)
        ns.RefreshFrameIcons()
    elseif next(changed) then
        ns.RefreshFrameIcons(changed)
        wipe(changed)
    end
end)

-- /pulse frames: list which Blizzard frames were found, for troubleshooting.
function ns.DebugFrames()
    BuildFrameList()
    local n = 0
    for _, f in ipairs(frameList) do
        if f:IsVisible() then
            n = n + 1
            ns.Print(("%s  unit=%s"):format(f:GetName() or "?", tostring(FrameUnit(f))))
        end
    end
    if n == 0 then ns.Print("No party/raid frames found.") end
end
