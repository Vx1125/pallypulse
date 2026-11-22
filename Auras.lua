local ADDON, ns = ...

-- Aura assignments (one aura per paladin, synced with PallyPulse and PallyPower users) and the
-- Righteous Fury reminder for tanking paladins. Both feed into Smart Buff, ahead of blessings.

ns.auraCaps = {}   -- paladin -> { AURA KEY = true }

function ns.ComputeAuraCaps()
    local me = ns.Me()
    local caps = {}
    for _, a in ipairs(ns.AURAS) do
        if ns.KnownSpell(a.name, a.id) then caps[a.key] = true end
    end
    ns.auraCaps[me] = caps
    return caps
end

function ns.AuraFor(pal)
    local k = ns.db and ns.db.auraAssign[pal]
    return k and ns.AURA_BY_KEY[k] and k or nil
end

function ns.SetAura(pal, key, broadcast)
    if key == "NONE" or key == "" then key = nil end
    ns.db.auraAssign[pal] = key
    ns.dirty = true
    if ns.OnAssignmentsChanged then ns.OnAssignmentsChanged() end
    if broadcast then
        ns.Send(("U|%s|%s"):format(pal, key or "NONE"))
        if ns.CompatSendAura then ns.CompatSendAura(pal, key) end
    end
end

ns.comm["U"] = function(sender, pal, key)
    if not (pal and key) then return end
    if sender ~= pal and not ns.HasAuthority(ns.UnitForName(sender)) then return end
    if key ~= "NONE" and not ns.AURA_BY_KEY[key] then return end
    ns.SetAura(pal, key, false)
end

table.insert(ns.syncHooks, function()
    local me = ns.Me()
    if select(2, UnitClass("player")) == "PALADIN" then
        ns.Send(("U|%s|%s"):format(me, ns.AuraFor(me) or "NONE"))
    end
end)

-- One different aura per paladin, best first. Keeps auras already set where they're unique.
function ns.AutoAuras()
    local pals = {}
    for i, p in ipairs(ns.paladins) do pals[i] = p end
    table.sort(pals)
    -- your own preferred aura goes first, so the alphabet doesn't hand it to someone else
    local me, prefer = ns.Me(), ns.db.auraPrefer
    if prefer and not ns.AURA_BY_KEY[prefer] then prefer = nil end
    if prefer then
        for i, p in ipairs(pals) do if p == me then table.remove(pals, i); table.insert(pals, 1, me) break end end
    end
    local used = {}
    for _, pal in ipairs(pals) do
        if not ns.CanEditRow(pal) then
            local k = ns.AuraFor(pal)
            if k then used[k] = true end
        end
    end
    for _, pal in ipairs(pals) do
        if ns.CanEditRow(pal) then
            local caps = ns.auraCaps[pal]
            local pick
            local function ok(k) return not used[k] and (not caps or next(caps) == nil or caps[k]) end
            if pal == me and prefer and ok(prefer) then pick = prefer end
            if not pick then
                for _, k in ipairs(ns.AURA_PREFS) do if ok(k) then pick = k break end end
            end
            if pick then used[pick] = true end
            ns.db.auraAssign[pal] = pick
            ns.Send(("U|%s|%s"):format(pal, pick or "NONE"))
            if ns.CompatSendAura then ns.CompatSendAura(pal, pick) end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Is a buff of yours on a unit? Returns expiration (0 = no duration) or nil.
-- ---------------------------------------------------------------------------
local function ScanAura(unit, name, filter)
    local modern = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    for i = 1, 40 do
        local n, e, fin = nil, nil, false
        if modern then
            local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
            if ok and not d then fin = true
            elseif ok then pcall(function() n, e = d.name, d.expirationTime end) end
        else
            local fn = (filter and filter:find("HARMFUL")) and UnitDebuff or UnitBuff
            local f2 = filter and filter:find("PLAYER") and "PLAYER" or nil
            local ok, nn, _, _, _, _, ee = pcall(fn, unit, i, f2)
            if ok and not nn then fin = true elseif ok then n, e = nn, ee end
        end
        if fin then break end
        if n and ns.Readable(n) and n == name then
            if not ns.Readable(e) then e = 0 end
            return e or 0
        end
    end
    return nil
end

function ns.FindAura(unit, name, filter)
    local r = ScanAura(unit, name, filter)
    if r then return r end
    -- On yourself the client may not flag your own paladin aura as "cast by player", so the
    -- PLAYER filter misses it. Anything with this name on you counts.
    if unit == "player" and filter and filter:find("PLAYER") then
        r = ScanAura(unit, name, (filter:gsub("|PLAYER", "")))
        if r then return r end
        if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
            local ok, d = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
            if ok and d then
                local e = 0
                pcall(function() if ns.Readable(d.expirationTime) then e = d.expirationTime or 0 end end)
                return e
            end
        end
    end
    return nil
end

-- /pulse auras: what the client says is on you, to track down aura-detection problems.
function ns.DebugAuras()
    local me = ns.Me()
    local key = ns.AuraFor(me)
    local a = key and ns.AURA_BY_KEY[key]
    ns.Print(("assigned aura = %s, known = %s, FindAura(PLAYER filter) = %s, any caster = %s"):format(
        tostring(key), tostring(ns.auraCaps[me] and ns.auraCaps[me][key]),
        tostring(a and ScanAura("player", a.name, "HELPFUL|PLAYER")),
        tostring(a and ScanAura("player", a.name, "HELPFUL"))))
    local modern = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    for i = 1, 40 do
        local line
        if modern then
            local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok then line = "(unreadable)"
            elseif not d then break
            else
                pcall(function()
                    line = ("%s  id=%s  source=%s"):format(tostring(d.name), tostring(d.spellId), tostring(d.sourceUnit))
                end)
            end
        else
            local ok, n, _, _, _, _, _, caster, _, _, id = pcall(UnitBuff, "player", i)
            if not ok then line = "(unreadable)" elseif not n then break
            else line = ("%s  id=%s  source=%s"):format(tostring(n), tostring(id), tostring(caster)) end
        end
        ns.Print("  " .. i .. ". " .. tostring(line))
    end
end

-- Your assigned aura: key, whether it's on, whether you know it.
-- Paladin auras are also stances. The stance bar still says which one is active in combat,
-- when your buffs are hidden from addons. true/false if the aura is on the stance bar, nil if not.
local function StanceActive(auraName)
    if not (GetNumShapeshiftForms and GetShapeshiftFormInfo) then return nil end
    local found
    pcall(function()
        for i = 1, GetNumShapeshiftForms() or 0 do
            local a1, a2, a3, a4 = GetShapeshiftFormInfo(i)
            local name, active
            if type(a2) == "string" then          -- older clients: texture, name, active, castable
                name, active = a2, a3
            else                                  -- icon, active, castable, spellID
                active = a2
                if a4 then
                    if C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(a4)
                    elseif GetSpellInfo then name = GetSpellInfo(a4) end
                end
            end
            if name and ns.Readable(name) and name == auraName then
                found = (ns.Readable(active) and active) and true or false
                return
            end
        end
    end)
    return found
end

local lastAuraOn = {}   -- [aura key] = on, from the last out-of-combat read

function ns.AuraStatus()
    local me = ns.Me()
    local key = ns.AuraFor(me)
    if not key then return nil end
    local a = ns.AURA_BY_KEY[key]
    local known = ns.auraCaps[me] and ns.auraCaps[me][key]
    local on = StanceActive(a.name)
    if on == nil then
        on = ns.FindAura("player", a.name, "HELPFUL|PLAYER") ~= nil
        -- buffs can be hidden in combat: trust what we saw before the pull
        if not on and InCombatLockdown() and lastAuraOn[key] then on = true end
    end
    if not InCombatLockdown() then lastAuraOn = { [key] = on } end
    return key, on, known
end

-- Non-English clients: replace the English spell names with the client's own, looked up by id.
-- English clients keep the names as written (safer if Forever renumbered any spells).
function ns.LocalizeSpells()
    local loc = GetLocale and GetLocale() or "enUS"
    if loc == "enUS" or loc == "enGB" then return end
    local function N(id)
        local n
        pcall(function()
            if C_Spell and C_Spell.GetSpellName then n = C_Spell.GetSpellName(id)
            elseif GetSpellInfo then n = GetSpellInfo(id) end
        end)
        return n
    end
    for _, b in ipairs(ns.BLESSINGS) do
        local s, g = N(b.singleId), N(b.greaterId)
        if s then ns.NAME2KEY[s] = b.key; b.single = s end
        if g then ns.NAME2KEY[g] = b.key; b.greater = g end
    end
    for _, a in ipairs(ns.AURAS) do local n = N(a.id); if n then a.name = n end end
    local rf = N(ns.RF.id); if rf then ns.RF.name = rf end
end

-- Should you have Righteous Fury up, and is it? (only while you're marked as tank)
function ns.RFStatus()
    if not ns.db.rfReminder then return false end
    local me = ns.Me()
    local tank = false
    for _, t in ipairs(ns.FindTanks()) do if t == me then tank = true break end end
    if not tank or not ns.KnownSpell(ns.RF.name, ns.RF.id) then return false end
    local on = ns.FindAura("player", ns.RF.name, "HELPFUL|PLAYER") ~= nil
    return true, on
end
