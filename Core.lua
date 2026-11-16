local ADDON, ns = ...

local PREFIX = "PPULSE"
local core = CreateFrame("Frame")
ns.core = core

-- ---------------------------------------------------------------------------
-- Compat helpers
-- ---------------------------------------------------------------------------
local RegisterPrefix = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
local SendAddon = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
if RegisterPrefix then RegisterPrefix(PREFIX) end

local function SpellKnownByName(name)
    if not name or name == "" then return false end
    local ok, res = pcall(function()
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(name)
            return info and info.name ~= nil
        end
        return GetSpellInfo(name) ~= nil
    end)
    return ok and res and true or false
end

-- Forever has no Greater Blessings yet, and a name lookup can match a spell the character
-- cannot actually cast, so "known" is decided by spell id (same approach as PallyPower).
local function SpellKnownById(id)
    if not id then return false end
    local ok, res = pcall(function()
        if C_SpellBook and C_SpellBook.IsSpellKnown then return C_SpellBook.IsSpellKnown(id) end
        if IsSpellKnown then return IsSpellKnown(id) end
        if IsPlayerSpell then return IsPlayerSpell(id) end
    end)
    return ok and res and true or false
end

-- In combat the client can hide ("secret") values; never do arithmetic or tests on them.
local function Readable(v)
    local f = _G.issecretvalue or _G.issecret
    if f and f(v) then return false end
    return true
end
local function SafeUnit(fn, unit, default)
    local ok, v = pcall(fn, unit)
    if not ok or not Readable(v) then return default end
    return v
end

local function GroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

-- Forever characters can have surnames ("First Last"), which PallyPower keys by the full name.
local function StripRealm(name)
    if not name then return nil end
    return (name:gsub("%-[^%-]+$", ""))
end
local function FullName(unit)
    return StripRealm((GetUnitName and GetUnitName(unit, true)) or UnitName(unit))
end
local function Me() return FullName("player") end
ns.StripRealm, ns.FullName, ns.Me, ns.GroupChannel = StripRealm, FullName, Me, GroupChannel
ns.SpellKnownById, ns.SpellKnownByName = SpellKnownById, SpellKnownByName

-- Is this spell actually learned? strict = require a confirmed spell id (used for Greater
-- Blessings, where a name lookup alone can match a spell the character can't cast).
function ns.KnownSpell(name, id, strict)
    if id and SpellKnownById(id) then return true end
    if not name or name == "" then return false end
    local sid
    pcall(function()
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(name)
            sid = info and info.spellID
        elseif GetSpellInfo then
            sid = select(7, GetSpellInfo(name))
        end
    end)
    if sid then
        if SpellKnownById(sid) then return true end
        local ok, res = pcall(function() return IsPlayerSpell and IsPlayerSpell(sid) end)
        if ok and res then return true end
        if not strict then return true end   -- the client resolved the name from your spellbook
    end
    return false
end

-- Modules register extra message handlers here: ns.comm["X"] = function(sender, a, b, c, d) end
ns.comm = {}
-- ...and things to broadcast whenever a sync is requested.
ns.syncHooks = {}

function ns.Print(msg)
    print("|cfff58cbaPallyPulse|r: " .. tostring(msg))
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
ns.roster = {}      -- { {unit=, name=, class=}, ... }
ns.byClass = {}     -- CLASS -> { entry, ... }
ns.paladins = {}    -- sorted list of paladin names (player first)
ns.caps = {}        -- paladinName -> { KEY = true }
ns.assign = {}      -- set to DB.assign on load
ns.oath = {}        -- set to DB.oath on load
ns.oathCap = {}     -- paladinName -> true / false (knows Oath of Light); nil = unknown (e.g. PallyPower user)
ns.auraMemory = {}
ns.dirty = true     -- bar needs a refresh

-- ---------------------------------------------------------------------------
-- Roster
-- ---------------------------------------------------------------------------
function ns.ScanRoster()
    wipe(ns.roster); wipe(ns.byClass); wipe(ns.paladins)
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else
        units[1] = "player"
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local name = FullName(unit)
            local _, class = UnitClass(unit)
            if name and class then
                local e = { unit = unit, name = name, class = class }
                ns.roster[#ns.roster + 1] = e
                ns.byClass[class] = ns.byClass[class] or {}
                table.insert(ns.byClass[class], e)
                if class == "PALADIN" then ns.paladins[#ns.paladins + 1] = name end
            end
        end
    end
    local me = Me()
    table.sort(ns.paladins, function(a, b)
        if a == me then return true end
        if b == me then return false end
        return a < b
    end)
    ns.dirty = true
end

local function UnitForName(name)
    for _, e in ipairs(ns.roster) do
        if e.name == name then return e.unit end
    end
end

local function HasAuthority(unit)
    if not unit then return false end
    if not IsInGroup() then return unit == "player" end
    return UnitIsGroupLeader(unit) or UnitIsGroupAssistant(unit)
end

ns.UnitForName, ns.HasAuthority = UnitForName, HasAuthority

function ns.CanEditRow(pal)
    if pal == Me() then return true end
    return HasAuthority("player")
end

-- ---------------------------------------------------------------------------
-- Capabilities
-- ---------------------------------------------------------------------------
function ns.ComputeOwnCaps()
    local me = Me()
    local caps = {}
    for _, b in ipairs(ns.BLESSINGS) do
        if ns.KnownSpell(b.single, b.singleId) or ns.KnownSpell(b.greater, b.greaterId, true) then
            caps[b.key] = true
        end
    end
    ns.caps[me] = caps
    ns.oathCap[me] = ns.OathKnown()
    if ns.ComputeAuraCaps then ns.ComputeAuraCaps() end
    return caps
end

-- Oath of Light is a talent (Rank 1/1), so look it up by name, then confirm by spell id.
function ns.OathKnown()
    local id
    pcall(function()
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(ns.OATH.name)
            id = info and info.spellID
        elseif GetSpellInfo then
            id = select(7, GetSpellInfo(ns.OATH.name))
        end
    end)
    if not id then return false end
    if SpellKnownById(id) then return true end
    local ok, res = pcall(function() return IsPlayerSpell and IsPlayerSpell(id) end)
    return ok and res and true or false
end

local function CapsToString(caps)
    local t = {}
    for _, b in ipairs(ns.BLESSINGS) do if caps[b.key] then t[#t + 1] = b.key end end
    if ns.oathCap[Me()] then t[#t + 1] = "OATH" end
    local ac = ns.auraCaps and ns.auraCaps[Me()]
    if ac then for _, a in ipairs(ns.AURAS) do if ac[a.key] then t[#t + 1] = "A_" .. a.key end end end
    return table.concat(t, ",")
end

-- ---------------------------------------------------------------------------
-- Comm
-- ---------------------------------------------------------------------------
local function Send(msg, target)
    if target then
        if SendAddon then SendAddon(PREFIX, msg, "WHISPER", target) end
        return
    end
    local chan = GroupChannel()
    if chan and SendAddon then SendAddon(PREFIX, msg, chan) end
end
ns.Send = Send

function ns.BroadcastCaps()
    if UnitClass("player") and select(2, UnitClass("player")) == "PALADIN" then
        Send("C|" .. CapsToString(ns.ComputeOwnCaps()))
        if ns.CompatSendSelf then ns.CompatSendSelf() end
    end
end

function ns.BroadcastRow(pal)
    pal = pal or Me()
    for _, class in ipairs(ns.CLASSES) do
        local key = ns.assign[pal] and ns.assign[pal][class] or "NONE"
        Send(("A|%s|%s|%s"):format(pal, class, key))
        if ns.CompatSendAssign then ns.CompatSendAssign(pal, class, key) end
    end
    Send(("O|%s|%s"):format(pal, ns.oath[pal] or "NONE"))
end

-- ---------------------------------------------------------------------------
-- Oath of Light (one target per paladin, synced between PallyPulse users only)
-- ---------------------------------------------------------------------------
function ns.SetOath(pal, target, broadcast)
    if target == "NONE" or target == "" then target = nil end
    ns.oath[pal] = target
    ns.dirty = true
    if ns.OnAssignmentsChanged then ns.OnAssignmentsChanged() end
    if broadcast then Send(("O|%s|%s"):format(pal, target or "NONE")) end
end

-- Sets pal's Oath target to the player's current target. Returns false with a reason if it can't.
function ns.SetOathToTarget(pal)
    if ns.oathCap[pal] == false then
        return false, pal .. " doesn't have Oath of Light (it's a talent)."
    end
    if not UnitExists("target") then return false, "Target a group member first." end
    if not (UnitIsUnit("target", "player") or UnitInParty("target") or UnitInRaid("target")) then
        return false, "Your target is not in your group."
    end
    ns.SetOath(pal, FullName("target"), true)
    if pal == Me() then ns.db.oathAutoPick = nil end   -- hand-picked: automatic Oath leaves it alone
    return true
end

function ns.OathIcon()
    local icon
    pcall(function()
        if C_Spell and C_Spell.GetSpellTexture then icon = C_Spell.GetSpellTexture(ns.OATH.name)
        elseif GetSpellTexture then icon = GetSpellTexture(ns.OATH.name) end
    end)
    return icon or ns.OATH.icon
end

-- Status of the player's own Oath. Returns unit (or nil if the target isn't in the group),
-- remaining seconds (nil when the buff is missing).
function ns.OathStatus()
    local target = ns.oath[Me()]
    if not target then return nil, nil end
    local unit = UnitForName(target)
    if not unit then return nil, nil end
    local memKey = target .. "|OATH"
    local now, exp = GetTime(), nil
    local modern = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    -- "PLAYER" filter: only auras cast by us. Several holy paladins can each keep an Oath
    -- on the same tank, and theirs must not count as ours.
    for i = 1, 40 do
        local name, e, fin = nil, nil, false
        if modern then
            local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL|PLAYER")
            if ok and not d then fin = true
            elseif ok then pcall(function() name, e = d.name, d.expirationTime end) end
        else
            local ok, n, _, _, _, _, ee = pcall(UnitBuff, unit, i, "PLAYER")
            if ok and not n then fin = true elseif ok then name, e = n, ee end
        end
        if fin then break end
        if name and Readable(name) and name == ns.OATH.name then
            exp = (Readable(e) and e and e > 0) and e or (now + ns.OATH.duration)
            break
        end
    end
    if exp then
        ns.auraMemory[memKey] = exp
    elseif InCombatLockdown() and ns.auraMemory[memKey] and ns.auraMemory[memKey] > now then
        exp = ns.auraMemory[memKey]
    elseif not InCombatLockdown() then
        ns.auraMemory[memKey] = nil
    end
    return unit, exp and (exp - now) or nil
end

local function RunSyncHooks()
    for _, f in ipairs(ns.syncHooks) do pcall(f) end
end

function ns.RequestSync()
    if ns.CompatRequest then ns.CompatRequest() end
    Send("Q")
    ns.BroadcastCaps()
    ns.BroadcastRow()
    RunSyncHooks()
end

function ns.SetAssignment(pal, class, key, broadcast)
    if key == "NONE" then key = nil end
    ns.assign[pal] = ns.assign[pal] or {}
    ns.assign[pal][class] = key
    ns.dirty = true
    if ns.OnAssignmentsChanged then ns.OnAssignmentsChanged() end
    if broadcast then
        Send(("A|%s|%s|%s"):format(pal, class, key or "NONE"))
        if ns.CompatSendAssign then ns.CompatSendAssign(pal, class, key or "NONE") end
    end
end

local function OnAddonMessage(prefix, text, channel, sender)
    if prefix ~= PREFIX then return end
    sender = StripRealm(Ambiguate(sender or "", "none"))
    if sender == Me() then return end
    local cmd, a, b, c, d = strsplit("|", text)
    if cmd == "Q" then
        ns.BroadcastCaps()
        ns.BroadcastRow()
        RunSyncHooks()
    elseif cmd == "C" then
        local caps, oath, acaps = {}, false, {}
        for k in (a or ""):gmatch("[^,]+") do
            if ns.BY_KEY[k] then caps[k] = true end
            if k == "OATH" then oath = true end
            if k:sub(1, 2) == "A_" and ns.AURA_BY_KEY[k:sub(3)] then acaps[k:sub(3)] = true end
        end
        ns.caps[sender] = caps
        ns.oathCap[sender] = oath
        if ns.auraCaps then ns.auraCaps[sender] = acaps end
        if ns.OnAssignmentsChanged then ns.OnAssignmentsChanged() end
    elseif cmd == "A" then
        local pal, class, key = a, b, c
        if not (pal and class and key) then return end
        if not tContains(ns.CLASSES, class) then return end
        if key ~= "NONE" and not ns.BY_KEY[key] then return end
        -- Only the paladin themselves or a leader / assistant may change a row.
        if sender ~= pal and not HasAuthority(UnitForName(sender)) then return end
        ns.SetAssignment(pal, class, key, false)
    elseif cmd == "O" then
        local pal, target = a, b
        if not (pal and target) then return end
        if sender ~= pal and not HasAuthority(UnitForName(sender)) then return end
        ns.SetOath(pal, target, false)
    elseif ns.comm[cmd] then
        ns.comm[cmd](sender, a, b, c, d)
    end
end

-- ---------------------------------------------------------------------------
-- Auto-assign
-- ---------------------------------------------------------------------------
function ns.AutoAssign()
    local me = Me()
    for _, pal in ipairs(ns.paladins) do
        if ns.CanEditRow(pal) then
            ns.assign[pal] = {}
        end
    end
    for _, class in ipairs(ns.CLASSES) do
        if ns.byClass[class] then
            local used = {}
            for _, pal in ipairs(ns.paladins) do
                if ns.CanEditRow(pal) then
                    local caps = ns.caps[pal]
                    for _, key in ipairs(ns.PREFS[class]) do
                        if not used[key] and (not caps or caps[key]) then
                            used[key] = true
                            ns.assign[pal][class] = key
                            break
                        end
                    end
                end
            end
        end
    end
    ns.AutoOath()
    if ns.AutoOverrides then ns.AutoOverrides() end   -- spec-aware exceptions and requests
    if ns.AutoAuras then ns.AutoAuras() end
    for _, pal in ipairs(ns.paladins) do
        if ns.CanEditRow(pal) then ns.BroadcastRow(pal) end
    end
    RunSyncHooks()
    ns.dirty = true
    if ns.OnAssignmentsChanged then ns.OnAssignmentsChanged() end
end

-- Tanks in the group: raid Main Tank markers first, then group roles if the client has them.
function ns.FindTanks()
    local tanks, seen = {}, {}
    local function add(e) if not seen[e.name] then seen[e.name] = true; tanks[#tanks + 1] = e.name end end
    for _, e in ipairs(ns.roster) do
        local ok, mt = pcall(function() return GetPartyAssignment and GetPartyAssignment("MAINTANK", e.unit) end)
        if ok and mt and Readable(mt) then add(e) end
    end
    for _, e in ipairs(ns.roster) do
        local ok, role = pcall(function() return UnitGroupRolesAssigned and UnitGroupRolesAssigned(e.unit) end)
        if ok and Readable(role) and role == "TANK" then add(e) end
    end
    return tanks
end

-- Give each paladin known to have Oath of Light (and without a target in the group yet) a tank.
-- Holy paladins boost only their own heals, so several may share one tank; spread them when we can.
function ns.AutoOath()
    local tanks = ns.FindTanks()
    if #tanks == 0 then return end
    local n = 0
    for _, pal in ipairs(ns.paladins) do
        local current = ns.oath[pal]
        local valid = current and UnitForName(current)
        if ns.oathCap[pal] and ns.CanEditRow(pal) and not valid then
            n = n + 1
            ns.oath[pal] = tanks[((n - 1) % #tanks) + 1]
        end
    end
end

-- Automatic Oath for your own row, run whenever roles, Main Tank markers or the roster change.
-- It fills an empty Oath, replaces a target who left or died out of the group, and follows the
-- tank if the target it picked earlier stops being a tank. A target you picked by hand stays
-- while that player is in the group.
-- ns.db.oathAutoPick: the name this feature chose last (saved), so we know which picks are ours

function ns.AutoOathSelf()
    if not ns.db or not ns.db.autoOath then return end
    local me = Me()
    if not ns.oathCap[me] then return end
    local tanks = ns.FindTanks()
    if #tanks == 0 then
        -- No tank to follow. If the saved target isn't in the group (you went solo, or they
        -- left), put Oath on yourself so the button still works. A target who is still in
        -- the group is left alone.
        local cur = ns.oath[me]
        if not (cur and UnitForName(cur)) and cur ~= me then
            ns.db.oathAutoPick = me
            ns.SetOath(me, me, true)
        end
        return
    end

    local isTank = {}
    for _, t in ipairs(tanks) do isTank[t] = true end
    local current = ns.oath[me]
    local inGroup = current and UnitForName(current)
    if inGroup and isTank[current] then return end                       -- already on a tank
    if inGroup and current ~= ns.db.oathAutoPick then return end            -- hand-picked: leave it

    -- Prefer a tank no other paladin has an Oath on, so heals spread across tanks.
    local taken = {}
    for _, pal in ipairs(ns.paladins) do
        if pal ~= me and ns.oath[pal] then taken[ns.oath[pal]] = true end
    end
    local choice
    for _, t in ipairs(tanks) do if not taken[t] then choice = t break end end
    choice = choice or tanks[1]
    if choice == current then return end

    ns.db.oathAutoPick = choice
    ns.SetOath(me, choice, true)
    ns.Print(("Oath of Light target: %s (tank)%s"):format(choice,
        InCombatLockdown() and " - your Oath button switches to them after combat" or ""))
end

local pendingAuto
function ns.ScheduleAutoOath()
    if pendingAuto then return end
    pendingAuto = true
    local function run() pendingAuto = nil; ns.AutoOathSelf() end
    if C_Timer and C_Timer.After then C_Timer.After(0.5, run) else run() end
end

function ns.ClearAll()
    for _, pal in ipairs(ns.paladins) do
        if ns.CanEditRow(pal) then
            ns.assign[pal] = {}
            ns.oath[pal] = nil
            if ns.db.override then ns.db.override[pal] = nil end
            if ns.db.autoOverride then ns.db.autoOverride[pal] = nil end
            if ns.db.auraAssign then ns.db.auraAssign[pal] = nil end
            ns.BroadcastRow(pal)
        end
    end
    RunSyncHooks()
    ns.dirty = true
    if ns.OnAssignmentsChanged then ns.OnAssignmentsChanged() end
end

-- ---------------------------------------------------------------------------
-- Announce (only when the player clicks the button or types the command)
-- ---------------------------------------------------------------------------
function ns.Announce()
    local chan = GroupChannel()
    if not chan then ns.Print("You are not in a group."); return end
    local names = LOCALIZED_CLASS_NAMES_MALE or {}
    local sent = false
    for _, pal in ipairs(ns.paladins) do
        local row = ns.assign[pal]
        if row then
            local groups, order = {}, {}
            for _, class in ipairs(ns.CLASSES) do
                local key = row[class]
                if key and ns.byClass[class] then
                    if not groups[key] then groups[key] = {}; order[#order + 1] = key end
                    table.insert(groups[key], names[class] or class)
                end
            end
            local segs = {}
            for _, key in ipairs(order) do
                local short = ns.BY_KEY[key].single:gsub("^Blessing of ", "")
                segs[#segs + 1] = (" %s (%s)"):format(short, table.concat(groups[key], ", "))
            end
            if ns.oath[pal] then segs[#segs + 1] = (" Oath of Light (%s)"):format(ns.oath[pal]) end
            if #segs > 0 then
                local line = pal .. ":"
                for _, seg in ipairs(segs) do
                    if #line + #seg > 240 then
                        SendChatMessage(line, chan); line = pal .. ":"
                    end
                    line = line .. seg
                end
                SendChatMessage(line, chan)
                sent = true
            end
        end
    end
    if not sent then ns.Print("No assignments to announce.") end
end

-- ---------------------------------------------------------------------------
-- Buff scanning
-- ---------------------------------------------------------------------------
-- Per-refresh cache: the bar, the smart queue and the window all ask about the same units,
-- so each unit's auras are read once per refresh instead of several times.
local scanCache = {}
local handCache = {}
function ns.BeginScan() wipe(scanCache); wipe(handCache) end
function ns.InvalidateScan(unit) if unit then scanCache[unit] = nil; handCache[unit] = nil end end

-- Name of a hand blessing (Freedom / Protection / Sacrifice) that *you* have on unit, or false.
function ns.HandActive(unit)
    local c = handCache[unit]
    if c ~= nil then return c end
    local found = false
    local modern = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    for i = 1, 40 do
        local name, fin = nil, false
        if modern then
            local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL|PLAYER")
            if ok and not d then fin = true
            elseif ok then pcall(function() name = d.name end) end
        else
            local ok, n = pcall(UnitBuff, unit, i, "PLAYER")
            if ok and not n then fin = true elseif ok then name = n end
        end
        if fin then break end
        if name and Readable(name) and ns.HAND[name] then found = name break end
    end
    handCache[unit] = found
    return found
end

-- Players you put a hand blessing on recently: name -> GetTime() of the cast.
ns.handCast = {}
function ns.RecentlyFreed(name)
    local t = ns.handCast[name]
    return t and (GetTime() - t) < ns.REBLESS_WINDOW
end

-- Returns { KEY = expirationTime (0 when no duration) } for blessings on unit.
function ns.ScanBlessings(unit)
    local cached = scanCache[unit]
    if cached then return cached end
    local found = {}
    scanCache[unit] = found
    local modern = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    for i = 1, 40 do
        local name, exp
        local hidden, finished = false, false
        -- Every slot is read on its own inside pcall: a "secret" aura raises an error for
        -- addon code, and one hidden aura must not stop the scan or show an error popup.
        if modern then
            local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
            if not ok then
                hidden = true
            elseif not d then
                finished = true
            else
                local ok2, n, e = pcall(function() return d.name, d.expirationTime end)
                if ok2 then name, exp = n, e else hidden = true end
            end
        else
            local ok, n, _, _, _, _, e = pcall(UnitBuff, unit, i)
            if not ok then hidden = true
            elseif not n then finished = true
            else name, exp = n, e end
        end
        if finished then break end
        if hidden or not Readable(name) then
            -- hidden aura: could be anything, including one of our blessings. Note it, so a
            -- blessing we can't see isn't mistaken for a missing one.
            found._hidden = true
        else
            local key = ns.NAME2KEY[name]
            if key then
                if not Readable(exp) then exp = nil end
                exp = exp or 0
                if not found[key] or exp > found[key] then found[key] = exp end
            end
        end
    end
    return found
end

-- Last readable expiry per unit+blessing, so timers and "covered" status survive combat.
ns.auraMemory = {}

ns.SafeUnit, ns.Readable = SafeUnit, Readable

-- Can this roster entry receive a buff right now (exists, online, alive)?
-- Drop remembered blessings for a player whose buffs we know are gone (died, or got your
-- Freedom / Protection / Sacrifice, which replaces your blessing on them).
function ns.ForgetMember(name)
    if not name then return end
    local prefix = name .. "|"
    for k in pairs(ns.auraMemory) do
        if k:sub(1, #prefix) == prefix and k ~= prefix .. "OATH" then ns.auraMemory[k] = nil end
    end
end

function ns.Eligible(e)
    local u = e.unit
    if SafeUnit(UnitIsDeadOrGhost, u, false) then
        ns.ForgetMember(e.name)        -- dying removes buffs
        return false
    end
    return SafeUnit(UnitExists, u, false) and SafeUnit(UnitIsConnected, u, true)
end

-- Seconds left on blessing `key` for roster entry e; math.huge = no duration; nil = missing.
-- Remembers the last readable value so hidden ("secret") auras in combat don't read as missing.
function ns.MemberRemaining(e, key)
    local now = GetTime()
    local ok, buffs = pcall(ns.ScanBlessings, e.unit)
    local exp = ok and buffs[key] or nil
    -- "Unsure" when the read failed or some auras were hidden from us (Forever hides group
    -- members' auras around and during combat). Only a fully readable scan may declare a
    -- blessing missing; otherwise trust the last time we did see it.
    local unsure = (not ok) or buffs._hidden or InCombatLockdown()
    local memKey = e.name .. "|" .. key
    local mem = ns.auraMemory[memKey]
    if exp then
        ns.auraMemory[memKey] = exp
    elseif unsure and mem and (mem == 0 or mem > now) then
        exp = mem
    elseif not unsure then
        ns.auraMemory[memKey] = nil
    end
    -- a cast we just made counts as applied for a moment, until the aura shows up
    if not exp and ns.RecentlyCast and ns.RecentlyCast(e.name, key) then return math.huge end
    return exp and (exp == 0 and math.huge or exp - now) or nil
end

-- Status of the blessing the player owes a class.
-- Returns: needCount, totalCount, targetUnit, lowestRemaining(seconds or nil), missingNames
function ns.ClassStatus(class, key)
    local list = ns.byClass[class]
    if not list or not key then return 0, 0, nil, nil, {} end
    local thresh = ns.db.refresh
    local need, total, target, lowest = 0, 0, nil, nil
    local missing = {}
    for _, e in ipairs(list) do
        local u = e.unit
        -- players with their own exception (override) are tracked separately, not by class
        local own = ns.KeyFor and ns.KeyFor(Me(), e)
        if ns.Eligible(e) and (not own or own == key) then
            total = total + 1
            local remaining = ns.MemberRemaining(e, key)
            if not remaining or remaining < thresh then
                need = need + 1
                missing[#missing + 1] = e.name
                -- the class button aims at someone who needs it and is actually in range
                if not target and SafeUnit(UnitIsVisible, u, true)
                    and not (ns.InRange and ns.InRange(ns.BY_KEY[key].single, u) == false) then
                    target = u
                end
            end
            if remaining and remaining ~= math.huge and (not lowest or remaining < lowest) then
                lowest = remaining
            end
        end
    end
    return need, total, target, lowest, missing
end

-- Is the spell castable apart from mana? A Greater Blessing with no Symbol of Kings in your
-- bags reports "not usable" without "not enough mana", which is how we spot missing reagents.
-- Returns true when the client can't tell, so nothing is blocked by mistake.
local function NotBlockedByReagent(spell)
    local ok, usable, noMana = pcall(function()
        if C_Spell and C_Spell.IsSpellUsable then return C_Spell.IsSpellUsable(spell) end
        if IsUsableSpell then return IsUsableSpell(spell) end
        return true, false
    end)
    if not ok or not Readable(usable) or not Readable(noMana) then return true end
    return usable or noMana
end

-- Why the class gets a normal blessing instead of a greater one (for tooltips), or nil.
function ns.GreaterSkipReason(key, class)
    local b = ns.BY_KEY[key]
    if not b or not ns.KnownSpell(b.greater, b.greaterId, true) then return nil end
    local n = class and ns.byClass[class] and #ns.byClass[class] or 0
    local min = ns.db.greaterMin or 2
    if class and n < min then
        return ("only %d %s in group (greater used at %d+)"):format(n, n == 1 and "member" or "members", min)
    end
    if not NotBlockedByReagent(b.greater) then return "no Symbol of Kings" end
    return nil
end

-- Which spells to cast: (left-click spell, right-click spell).
-- Left is the greater blessing only when it's known, the class is big enough to be worth a
-- reagent, and it can actually be cast right now; otherwise the normal blessing.
function ns.CastNames(key, class)
    local b = ns.BY_KEY[key]
    if not b then return nil, nil end
    local greater = ns.KnownSpell(b.greater, b.greaterId, true) and b.greater or nil
    local single = (SpellKnownById(b.singleId) or SpellKnownByName(b.single)) and b.single or nil
    if greater and single and ns.GreaterSkipReason(key, class) then greater = nil end
    return greater or single, single or greater
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
core:RegisterEvent("ADDON_LOADED")
core:RegisterEvent("PLAYER_LOGIN")
core:RegisterEvent("PLAYER_ENTERING_WORLD")
core:RegisterEvent("GROUP_ROSTER_UPDATE")
core:RegisterEvent("CHAT_MSG_ADDON")
core:RegisterEvent("UNIT_AURA")
core:RegisterEvent("SPELLS_CHANGED")
core:RegisterEvent("PLAYER_REGEN_ENABLED")
core:RegisterEvent("PLAYER_REGEN_DISABLED")
-- Role events may not exist on every client; registering an unknown event raises an error.
for _, ev in ipairs({ "PLAYER_ROLES_ASSIGNED", "ROLE_CHANGED_INFORM" }) do
    pcall(core.RegisterEvent, core, ev)
end

core:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if (...) ~= ADDON then return end
        PallyPulseDB = PallyPulseDB or {}
        for k, v in pairs(ns.DEFAULTS) do
            if PallyPulseDB[k] == nil then
                PallyPulseDB[k] = (type(v) == "table") and CopyTable(v) or v
            end
        end
        ns.db = PallyPulseDB
        -- bar layout: "compact" | "row" | "wrap" | "column" (older versions had a yes/no "vertical")
        if ns.db.barLayout == nil then ns.db.barLayout = ns.db.vertical and "wrap" or "compact" end
        ns.assign = ns.db.assign
        ns.oath = ns.db.oath
        -- Drop blessings that no longer exist (e.g. Salvation, removed on Forever) from saved data.
        local function Clean(row)
            for class, key in pairs(row) do
                if not ns.BY_KEY[key] then row[class] = nil end
            end
        end
        for _, row in pairs(ns.assign) do Clean(row) end
        for _, rows in pairs(ns.db.presets) do
            for _, row in pairs(rows) do if type(row) == "table" then Clean(row) end end
        end
        for _, t in ipairs({ ns.db.override, ns.db.autoOverride }) do
            for _, row in pairs(t) do
                for player, key in pairs(row) do
                    if key ~= "NONE" and not ns.BY_KEY[key] then row[player] = nil end
                end
            end
        end
        if ns.LocalizeSpells then ns.LocalizeSpells() end
    elseif event == "PLAYER_LOGIN" then
        ns.ComputeOwnCaps()
        ns.ScanRoster()
        if ns.BuildUI then ns.BuildUI() end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED" then
        ns.ComputeOwnCaps()
        ns.ScanRoster()
        ns.RequestSync()
        ns.ScheduleAutoOath()
    elseif event == "PLAYER_ROLES_ASSIGNED" or event == "ROLE_CHANGED_INFORM" then
        ns.ScheduleAutoOath()
        ns.dirty = true
    elseif event == "GROUP_ROSTER_UPDATE" then
        ns.BeginScan()   -- unit tokens may now point at different players
        ns.ScanRoster()
        ns.RequestSync()
        ns.ScheduleAutoOath()   -- also fires when Main Tank markers change
        if ns.OnAssignmentsChanged then ns.OnAssignmentsChanged() end
    elseif event == "CHAT_MSG_ADDON" then
        if (...) == "PLPWR" then
            if ns.CompatReceive then ns.CompatReceive(...) end
        else
            OnAddonMessage(...)
        end
    elseif event == "UNIT_AURA" then
        ns.InvalidateScan((...))
        ns.dirty = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        ns.dirty = true
        ns.layoutDirty = true
        if ns.QueueSmart then ns.QueueSmart() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Last moment attributes can change: disarm the smart button so it can't fire a
        -- stale cast during combat (the queue can't be updated once combat starts).
        if ns.ArmCombatQueue then ns.ArmCombatQueue() end
        ns.dirty = true
    end
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------
SLASH_PALLYPULSE1 = "/pulse"
SLASH_PALLYPULSE2 = "/pallypulse"
SlashCmdList.PALLYPULSE = function(msg)
    msg = (msg or ""):lower()
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    if cmd == "" or cmd == "config" or cmd == "assign" then
        if ns.ToggleWindow then ns.ToggleWindow() end
    elseif cmd == "bar" then
        if ns.ToggleBar then ns.ToggleBar() end
    elseif cmd == "options" or cmd == "settings" then
        if ns.ToggleSettings then ns.ToggleSettings() end
    elseif cmd == "players" then
        if ns.win and not ns.win:IsShown() then ns.win:Show() end
        if ns.ShowTab then ns.ShowTab("players") end
    elseif cmd == "versions" or cmd == "version" or cmd == "group" then
        ns.RequestVersions()
        ns.PrintVersions()
        if ns.win and ns.win:IsShown() and ns.ShowTab then ns.ShowTab("group") end
    elseif cmd == "test" then
        -- Dry run: what Smart Buff would do right now, without casting anything.
        if ns.BeginScan then ns.BeginScan() end
        local jobs, st = ns.Candidates()
        ns.Print(("Dry run: %d missing, %d expiring, %d out of range."):format(st.missing, st.expiring, st.far))
        for i, j in ipairs(jobs) do
            if i > 12 then ns.Print("  ...") break end
            ns.Print(("  %d. %s -> %s%s%s"):format(i, j.spell, j.name or j.unit, j.near and "" or " (out of range)",
                j.rebless and " (re-bless)" or ""))
        end
        for _, e in ipairs(ns.roster) do
            local role, why = ns.GuessRole(e)
            local key = ns.KeyFor(Me(), e)
            ns.Print(("  %s: role=%s (%s), you give %s"):format(e.name, tostring(role), tostring(why), tostring(key)))
        end
    elseif cmd == "lock" then
        ns.db.locked = not ns.db.locked
        ns.Print(ns.db.locked and "Bar locked." or "Bar unlocked.")
    elseif cmd == "debug" then
        local me = ns.Me()
        ns.Print(("you = '%s', paladins in group = %d, combat = %s"):format(tostring(me), #ns.paladins, tostring(InCombatLockdown())))
        local any = false
        for class, key in pairs(ns.assign[me] or {}) do
            any = true
            local g, s = ns.CastNames(key, class)
            ns.Print(("%s: %s  left=%s  right=%s  members=%d"):format(class, key, tostring(g), tostring(s),
                ns.byClass[class] and #ns.byClass[class] or 0))
        end
        if not any then ns.Print("No blessings are assigned to you. Open /pulse and click your row.") end
        local ounit, oleft = ns.OathStatus()
        ns.Print(("Oath of Light: known=%s target=%s unit=%s remaining=%s"):format(tostring(ns.oathCap[me]),
            tostring(ns.oath[me]), tostring(ounit),
            oleft and ("%ds"):format(oleft) or "missing"))
        ns.Print(("Combat queue available=%s, exact re-bless matching=%s"):format(
            tostring(ns.combatQueueAvailable), tostring(ns.reblessExact)))
        if ns.bar then
            for _, b in ipairs(ns.bar.buttons) do
                if b:IsShown() then
                    ns.Print(("button %s: spell1=%s spell2=%s unit1=%s"):format(b.class,
                        tostring(b:GetAttribute("spell1")), tostring(b:GetAttribute("spell2")), tostring(b:GetAttribute("unit1"))))
                end
            end
        end
    elseif cmd == "trace" then
        ns.trace = not ns.trace
        ns.Print("Trace " .. (ns.trace and "ON: every Smart Buff press prints what it cast. /pulse trace again to stop." or "OFF."))
    elseif cmd == "frames" then
        if ns.DebugFrames then ns.DebugFrames() end
    elseif cmd == "auras" then
        if ns.DebugAuras then ns.DebugAuras() end
    elseif cmd == "check" then
        if ns.ToggleReadyCheck then ns.ToggleReadyCheck() end
    elseif cmd == "preview" then
        if ns.TogglePreview then ns.TogglePreview() end
    elseif cmd == "compat" then
        if arg == "on" or arg == "off" then ns.db.compat = (arg == "on") end
        ns.Print("PallyPower compatibility is " .. (ns.db.compat and "ON" or "OFF") .. ". Usage: /pulse compat on|off")
    elseif cmd == "announce" then
        ns.Announce()
    elseif cmd == "auto" then
        ns.AutoAssign()
    elseif cmd == "sync" then
        ns.RequestSync(); ns.Print("Sync requested.")
    elseif cmd == "refresh" then
        local n = tonumber(arg)
        if n and n >= 0 then
            ns.db.refresh = n * 60
            ns.dirty = true
            ns.Print(("Blessings count as missing under %d minute(s) remaining."):format(n))
        else
            ns.Print(("Refresh threshold is %d minute(s). Usage: /pulse refresh <minutes>"):format(ns.db.refresh / 60))
        end
    elseif cmd == "scale" then
        local n = tonumber(arg)
        if n and n >= 0.5 and n <= 2 then
            ns.db.scale = n
            if ns.ApplyScale then ns.ApplyScale() end
        else
            ns.Print("Usage: /pulse scale <0.5 - 2>")
        end
    else
        ns.Print("/pulse (window) | players | versions | options | bar | lock | auto | announce | sync | test | trace | debug | frames | auras | check | preview")
    end
end
