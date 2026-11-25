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

-- A name lookup can match a spell the character cannot actually cast, so "known" is decided by spell id (same approach as PallyPower).
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
-- Is a spell with this name in your spellbook? Scans the book itself, so it doesn't depend on
-- spell ids (ranks differ between clients) or on name lookups that can fail while zoning.
local function InSpellbook(name)
    local found = false
    pcall(function()
        if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemName then
            for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
                local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
                local off, n = info.itemIndexOffset or 0, info.numSpellBookItems or 0
                for i = off + 1, off + n do
                    if C_SpellBook.GetSpellBookItemName(i, Enum.SpellBookSpellBank.Player) == name then found = true return end
                end
            end
        elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName then
            for tab = 1, GetNumSpellTabs() do
                local _, _, off, n = GetSpellTabInfo(tab)
                for i = off + 1, off + n do
                    if GetSpellBookItemName(i, BOOKTYPE_SPELL or "spell") == name then found = true return end
                end
            end
        end
    end)
    return found
end

function ns.KnownSpell(name, id, strict)
    if id and SpellKnownById(id) then return true end
    if not name or name == "" then return false end
    if InSpellbook(name) then return true end
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
    if ns.FillNewClasses then ns.FillNewClasses() end
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
-- remaining seconds (nil when the buff is missing, math.huge when it's there but the time
-- can't be read).
--
-- In combat the target's auras can be hidden or lose their caster, so the "cast by you"
-- scan can come back empty while the Oath is up. Then: any Oath of Light on them counts
-- (each holy paladin keeps theirs on a different tank), and if the auras can't be read at
-- all, the Oath is treated as still up rather than shown as missing.
local function ScanOath(unit, filter)
    local modern = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    local unsure = false
    for i = 1, 40 do
        local ok, name, e, fin = false, nil, nil, false
        if modern then
            local d
            ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
            if ok and not d then fin = true
            elseif ok then pcall(function() name, e = d.name, d.expirationTime end) end
        else
            local n, x, ee
            ok, n, x, x, x, x, ee = pcall(UnitBuff, unit, i, filter:find("PLAYER") and "PLAYER" or nil)
            if ok and not n then fin = true elseif ok then name, e = n, ee end
        end
        if fin then break end
        if not ok or not (name and Readable(name)) then
            unsure = true
        elseif name == ns.OATH.name then
            return true, (Readable(e) and e and e > 0) and e or nil, unsure
        end
    end
    return false, nil, unsure
end

function ns.OathStatus()
    local target = ns.oath[Me()]
    if not target then return nil, nil end
    local unit = UnitForName(target)
    if not unit then return nil, nil end
    local memKey = target .. "|OATH"
    local now, combat = GetTime(), InCombatLockdown()
    local mem = ns.auraMemory[memKey]
    if mem and mem <= now then mem = nil end

    local found, e, unsure = ScanOath(unit, "HELPFUL|PLAYER")
    if found then
        e = e or mem or (now + ns.OATH.duration)
        ns.auraMemory[memKey] = e
        return unit, e - now
    end
    if not combat and target ~= Me() then
        ns.auraMemory[memKey] = nil
        return unit, nil
    end
    if combat and mem then return unit, mem - now end
    local anyFound, anyE, anyUnsure = ScanOath(unit, "HELPFUL")
    if anyFound then return unit, anyE and (anyE - now) or mem and (mem - now) or math.huge end
    if not combat then ns.auraMemory[memKey] = nil; return unit, nil end
    if unsure or anyUnsure then return unit, math.huge end
    return unit, nil
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
-- Blessing order for a class: what most of its players want (by role and requests), ties
-- broken by the class default. Three shamans healing and one enhancement: Wisdom first.
local function ClassOrder(class)
    local score = {}
    for _, e in ipairs(ns.byClass[class] or {}) do
        local role = ns.GuessRole(e)
        local list = (ns.db.requests[e.name]) or ns.PrefsFor(e)
        for i, k in ipairs(list) do score[k] = (score[k] or 0) + (4 - math.min(i, 3)) end
    end
    local order = {}
    for i, k in ipairs(ns.PREFS[class]) do order[i] = k end
    local rank = {}
    for i, k in ipairs(order) do rank[k] = i end
    table.sort(order, function(a, b)
        local sa, sb = score[a] or 0, score[b] or 0
        if sa ~= sb then return sa > sb end
        return rank[a] < rank[b]
    end)
    return order
end

-- A class that joins the group after Auto-assign has no blessing from you, so it has no row
-- on the bar and no icon on its frames. Give it one: the first blessing in its order that
-- no other paladin gives it. Only your own empty cells, only for classes that just joined
-- (so Clear stays clear), and not on the first scan after login.
local seenClasses, pendingClasses, firstScan = {}, {}, true
function ns.FillNewClasses()
    if not ns.db then return end
    local present = {}
    for class in pairs(ns.byClass) do present[class] = true end
    if firstScan then
        firstScan = false
        seenClasses = present
        return
    end
    for class in pairs(present) do
        if not seenClasses[class] then pendingClasses[class] = true end
    end
    seenClasses = present
    if InCombatLockdown() or not IsInGroup() then return end
    local me = Me()
    local row = ns.assign[me]
    for class in pairs(pendingClasses) do
        pendingClasses[class] = nil
        if present[class] and not (row and row[class]) then
            local used = {}
            for _, pal in ipairs(ns.paladins) do
                local k = pal ~= me and ns.assign[pal] and ns.assign[pal][class]
                if k then used[k] = true end
            end
            local caps = ns.caps[me]
            -- your usual blessing first (the one you give most), if it's among this class's top picks
            local order, most, mostN, count = ClassOrder(class), nil, 0, {}
            for _, k in pairs(row or {}) do count[k] = (count[k] or 0) + 1 end
            for k, n in pairs(count) do if n > mostN then most, mostN = k, n end end
            if most then
                for i, k in ipairs(order) do
                    if k == most and i <= #ns.paladins then table.remove(order, i); table.insert(order, 1, most) break end
                end
            end
            for _, key in ipairs(order) do
                if not used[key] and (not caps or caps[key]) then
                    ns.SetAssignment(me, class, key, true)
                    break
                end
            end
            row = ns.assign[me]
        end
    end
end

-- Auto-assign. Each class gets its top blessings (one per paladin), and each paladin keeps
-- the same blessing everywhere it's wanted: with two paladins, one gives Kings to every class
-- and the other covers Might or Wisdom. The most wanted blessing goes first, to the paladin
-- who already gives it most, so pressing Auto-assign again doesn't swap paladins around.
-- Rows you can't edit keep what they have, and their blessings count as taken.
function ns.AutoAssign()
    local free, before = {}, {}
    for _, pal in ipairs(ns.paladins) do
        if ns.CanEditRow(pal) then
            free[#free + 1] = pal
            local c = {}
            for _, k in pairs(ns.assign[pal] or {}) do c[k] = (c[k] or 0) + 1 end
            before[pal] = c
            ns.assign[pal] = {}
        end
    end
    local function Can(pal, key) local caps = ns.caps[pal]; return not caps or caps[key] end
    local idx = {}
    for i, b in ipairs(ns.BLESSINGS) do idx[b.key] = i end

    -- what each class should get from the editable paladins, and how often each blessing is wanted
    local wants, freq = {}, {}
    for _, class in ipairs(ns.CLASSES) do
        if ns.byClass[class] then
            local used = {}
            for _, pal in ipairs(ns.paladins) do
                if not ns.CanEditRow(pal) then
                    local k = ns.assign[pal] and ns.assign[pal][class]
                    if k then used[k] = true end
                end
            end
            local list = {}
            for _, key in ipairs(ClassOrder(class)) do
                if #list >= #free then break end
                local castable = false
                for _, pal in ipairs(free) do if Can(pal, key) then castable = true break end end
                if not used[key] and castable then
                    list[#list + 1] = key
                    freq[key] = (freq[key] or 0) + 1
                end
            end
            wants[class] = list
        end
    end

    -- one blessing per paladin, most wanted first
    local keys = {}
    for k in pairs(freq) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if freq[a] ~= freq[b] then return freq[a] > freq[b] end
        return (idx[a] or 9) < (idx[b] or 9)
    end)
    local anchor, taken = {}, {}
    for _, key in ipairs(keys) do
        local best, bestN
        for _, pal in ipairs(free) do
            if not taken[pal] and Can(pal, key) then
                local n = before[pal][key] or 0
                if not best or n > bestN then best, bestN = pal, n end
            end
        end
        if best then anchor[best] = key; taken[best] = true end
    end

    -- each class: paladins give their own blessing where it's wanted, then the rest in order
    for _, class in ipairs(ns.CLASSES) do
        local list = wants[class]
        if list then
            local left = {}
            for _, k in ipairs(list) do left[k] = true end
            for _, pal in ipairs(free) do
                local k = anchor[pal]
                if k and left[k] then ns.assign[pal][class] = k; left[k] = nil end
            end
            for _, key in ipairs(list) do
                if left[key] then
                    for _, pal in ipairs(free) do
                        if not ns.assign[pal][class] and Can(pal, key) then
                            ns.assign[pal][class] = key; left[key] = nil
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
    if not chan then ns.Print("Not in a group."); return end
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
    if not sent then ns.Print("No assignments.") end
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

-- player, party1-4, raid1-40 (not pets, target, focus or nameplates)
function ns.IsGroupUnit(unit)
    if type(unit) ~= "string" then return false end
    return unit == "player" or unit:find("^party%d") ~= nil or unit:find("^raid%d") ~= nil
end

-- Other paladins giving the same blessing to this class as pal (a wasted cast).
-- Assignment conflicts: two paladins giving a class the same blessing. It only counts when at
-- least one player of that class would really get it from both; personal blessings (requests,
-- spec exceptions, hand-set) can make the same class blessing fine. Nothing is changed here.
-- Returns { { class, key, pals = { names }, players = { names } }, ... }
local function ClassConflicts(class)
    local out = {}
    local members = ns.byClass[class]
    if not members or #members == 0 then return out end
    local byKey, order = {}, {}
    for _, pal in ipairs(ns.paladins) do
        local key = ns.assign[pal] and ns.assign[pal][class]
        if key and ns.BY_KEY[key] then
            if not byKey[key] then byKey[key] = {}; order[#order + 1] = key end
            table.insert(byKey[key], pal)
        end
    end
    for _, key in ipairs(order) do
        local pals = byKey[key]
        if #pals > 1 then
            local hit, involved = {}, {}
            for _, e in ipairs(members) do
                local from = {}
                for _, pal in ipairs(pals) do if ns.KeyFor(pal, e) == key then from[#from + 1] = pal end end
                if #from > 1 then
                    hit[#hit + 1] = e.name
                    for _, pal in ipairs(from) do involved[pal] = true end
                end
            end
            if #hit > 0 then
                local who = {}
                for _, pal in ipairs(pals) do if involved[pal] then who[#who + 1] = pal end end
                out[#out + 1] = { class = class, key = key, pals = who, players = hit }
            end
        end
    end
    return out
end

-- Every conflict, plus a lookup by "paladin|CLASS" for highlighting cells.
function ns.AssignmentConflicts()
    local list, cells = {}, {}
    for _, class in ipairs(ns.CLASSES) do
        for _, c in ipairs(ClassConflicts(class)) do
            list[#list + 1] = c
            for _, pal in ipairs(c.pals) do cells[pal .. "|" .. class] = c end
        end
    end
    return list, cells
end

-- Coverage: does every player get as many different blessings as the paladins can give?
-- Each player should get min(paladins, blessings those paladins know between them), less one
-- for every paladin set to give that player nothing on purpose (a "None" personal blessing).
-- An empty class cell can't be told apart from a forgotten one, so it counts as unassigned.
-- Returns { { class, missing = n, players = { names } }, ... } and the total missing.
function ns.AssignmentGaps()
    local npal = #ns.paladins
    if npal == 0 then return {}, 0 end
    local known, nk = {}, 0
    for _, pal in ipairs(ns.paladins) do
        local caps = ns.caps[pal]
        for _, b in ipairs(ns.BLESSINGS) do
            if (not caps or caps[b.key]) and not known[b.key] then known[b.key] = true; nk = nk + 1 end
        end
    end
    local base = math.min(npal, nk)
    local out, total = {}, 0
    for _, class in ipairs(ns.CLASSES) do
        local worst, players = 0, {}
        for _, e in ipairs(ns.byClass[class] or {}) do
            local got, n, excluded = {}, 0, 0
            for _, pal in ipairs(ns.paladins) do
                local o = ns.db.override[pal] and ns.db.override[pal][e.name]
                if o == "NONE" then
                    excluded = excluded + 1
                else
                    local k = ns.KeyFor(pal, e)
                    if k and ns.BY_KEY[k] and not got[k] then got[k] = true; n = n + 1 end
                end
            end
            local short = math.max(0, base - excluded) - n
            if short > 0 then players[#players + 1] = e.name; if short > worst then worst = short end end
        end
        if worst > 0 then
            out[#out + 1] = { class = class, missing = worst, players = players }
            total = total + worst
        end
    end
    return out, total
end

-- Other paladins in a conflict with pal over this class (first names), or nil.
function ns.SameBlessing(pal, class)
    for _, c in ipairs(ClassConflicts(class)) do
        local mine, out = false, {}
        for _, p in ipairs(c.pals) do
            if p == pal then mine = true else out[#out + 1] = ns.FirstName(p) end
        end
        if mine and #out > 0 then return out end
    end
    return nil
end

-- Your blessing order per spec (Options > Advanced > Priorities). Unset specs use their
-- role's order from Data.lua.
local function ValidList(list)
    if type(list) ~= "table" or #list ~= #ns.BLESSINGS then return false end
    local seen = {}
    for _, k in ipairs(list) do
        if not ns.BY_KEY[k] or seen[k] then return false end
        seen[k] = true
    end
    return true
end

function ns.SpecDefault(class, spec)
    for _, s in ipairs(ns.SPECS[class] or {}) do
        if s.key == spec then return s.prefs or ns.ROLE_PREFS[s.role] end
    end
    return ns.PREFS[class]
end

function ns.SpecPrefs(class, spec)
    local mine = ns.db.specPrefs[class .. ":" .. (spec or "")]
    if ValidList(mine) then return mine end
    return ns.SpecDefault(class, spec)
end

function ns.SetSpecPrefs(class, spec, list)
    ns.db.specPrefs[class .. ":" .. (spec or "")] = ValidList(list) and list or nil
end

-- A group member's blessing order, from their spec (or best guess at it).
function ns.PrefsFor(e)
    return ns.SpecPrefs(e.class, ns.SpecKey(e))
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
        -- bar layout: "compact" (Vertical) | "horizontal"
        -- two layouts now: Vertical ("compact") and Horizontal; old Row/Wrap/Column map onto them
        local lay = ns.db.barLayout
        if lay == "row" or lay == "wrap" then ns.db.barLayout = "horizontal"
        elseif lay ~= "horizontal" then ns.db.barLayout = "compact" end
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
        for player, keys in pairs(ns.db.requests or {}) do
            if type(keys) == "table" then
                for i = #keys, 1, -1 do if not ns.BY_KEY[keys[i]] then table.remove(keys, i) end end
                if #keys == 0 then ns.db.requests[player] = nil end
            end
        end
        if ns.LocalizeSpells then ns.LocalizeSpells() end
    elseif event == "PLAYER_LOGIN" then
        ns.ComputeOwnCaps()
        ns.ScanRoster()
        if ns.BuildUI then ns.BuildUI() end
        -- fonts from LibSharedMedia are registered by the time everyone has loaded
        if ns.db.font and ns.db.font ~= "Default" then ns.W.ApplyStyle() end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED" then
        ns.ComputeOwnCaps()
        if event == "PLAYER_ENTERING_WORLD" then
            -- the spellbook can be incomplete right after a loading screen: check again shortly
            C_Timer.After(3, function() ns.ComputeOwnCaps(); ns.BroadcastCaps(); ns.dirty = true end)
        end
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
        -- only you and your group matter; target, focus and nameplate auras fire constantly
        local unit = ...
        if ns.IsGroupUnit(unit) then
            ns.InvalidateScan(unit)
            ns.dirty = true
        end
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
    if cmd == "" then
        if ns.ToggleWindow then ns.ToggleWindow() end
    elseif cmd == "bar" then
        if ns.ToggleBar then ns.ToggleBar() end
    elseif cmd == "options" then
        if ns.ToggleSettings then ns.ToggleSettings() end
    elseif cmd == "check" then
        if ns.ToggleReadyCheck then ns.ToggleReadyCheck() end
    elseif cmd == "announce" then
        ns.Announce()
    elseif cmd == "debug" then
        ns.Debug(arg)
    else
        ns.Print("/pulse  |  bar  |  options  |  check  |  announce")
    end
end

-- /pulse debug [test | trace | frames | auras]
function ns.Debug(arg)
    local me = ns.Me()
    if arg == "test" then
        -- what Smart Buff would do right now, without casting anything
        if ns.BeginScan then ns.BeginScan() end
        local jobs, st = ns.Candidates()
        ns.Print(("Missing %d, expiring %d, out of range %d"):format(st.missing, st.expiring, st.far))
        for i, j in ipairs(jobs) do
            if i > 12 then ns.Print("  ...") break end
            ns.Print(("  %d. %s -> %s%s%s"):format(i, j.spell, j.name or j.unit, j.near and "" or " (out of range)",
                j.rebless and " (re-bless)" or ""))
        end
        for _, e in ipairs(ns.roster) do
            local role, why = ns.GuessRole(e)
            ns.Print(("  %s: role=%s (%s), you give %s"):format(e.name, tostring(role), tostring(why), tostring(ns.KeyFor(me, e))))
        end
    elseif arg == "specs" then
        if ns.DebugSpecs then ns.DebugSpecs() end
    elseif arg == "cpu" then
        if ns.ProfileReport then ns.ProfileReport() end
    elseif arg == "trace" then
        ns.trace = not ns.trace
        ns.Print("Trace " .. (ns.trace and "on" or "off"))
    elseif arg == "frames" then
        if ns.DebugFrames then ns.DebugFrames() end
    elseif arg == "auras" then
        if ns.DebugAuras then ns.DebugAuras() end
    else
        ns.Print(("you = '%s', paladins in group = %d, combat = %s"):format(tostring(me), #ns.paladins, tostring(InCombatLockdown())))
        local known = {}
        for _, b in ipairs(ns.BLESSINGS) do
            known[#known + 1] = ("%s=%s/%s"):format(b.key, tostring(ns.KnownSpell(b.single, b.singleId)),
                tostring(ns.KnownSpell(b.greater, b.greaterId, true)))
        end
        ns.Print("Known (single/greater): " .. table.concat(known, " "))
        local any = false
        for class, key in pairs(ns.assign[me] or {}) do
            any = true
            local g, s = ns.CastNames(key, class)
            ns.Print(("%s: %s  left=%s  right=%s  members=%d"):format(class, key, tostring(g), tostring(s),
                ns.byClass[class] and #ns.byClass[class] or 0))
        end
        if not any then ns.Print("No assignments") end
        local ounit, oleft = ns.OathStatus()
        ns.Print(("Oath of Light: known=%s target=%s unit=%s remaining=%s"):format(tostring(ns.oathCap[me]),
            tostring(ns.oath[me]), tostring(ounit), (oleft == math.huge and "up") or (oleft and ("%ds"):format(oleft)) or "missing"))
        ns.Print(("Combat queue available=%s, re-bless target by=%s"):format(
            tostring(ns.combatQueueAvailable), tostring(ns.reblessHow)))
        if ns.bar then
            for _, b in ipairs(ns.bar.buttons) do
                if b:IsShown() then
                    ns.Print(("button %s: spell1=%s spell2=%s unit1=%s"):format(b.class,
                        tostring(b:GetAttribute("spell1")), tostring(b:GetAttribute("spell2")), tostring(b:GetAttribute("unit1"))))
                end
            end
        end
        ns.Print("/pulse debug test | trace | frames | auras | specs | cpu")
    end
end
