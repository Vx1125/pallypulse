local ADDON, ns = ...

-- PallyPower compatibility.
-- Speaks the "PLPWR" addon protocol used by PallyPower Forever (v10.10.26), so paladins
-- running the original addon and paladins running PallyPulse share one set of assignments.
--
-- Protocol facts (read from PallyPower.lua / PallyPowerValues.lua):
--   class ids    : 1 WARRIOR 2 ROGUE 3 PRIEST 4 DRUID 5 PALADIN 6 HUNTER 7 MAGE 8 WARLOCK 9 SHAMAN
--   blessing ids : 1 Wisdom 2 Might 3 Kings 4 Salvation 5 Light 6 Sanctuary   (0 / "n" = none)
--                  Salvation (4) and Sanctuary (6) no longer exist on Forever: never sent, ignored on receipt.
--   Oath of Light is not part of PallyPower's protocol, so it only syncs between PallyPulse users.
--   SELF  <6 x rank+talent hex pairs>@<9 chars: blessing id per class>
--   ASSIGN <name> <classId> <blessingId>   PASSIGN <name>@<9 chars>   MASSIGN <name> <blessingId>
--   REQ asks everyone to resend SELF.  CLEAR (leader only) wipes assignments.
--   NASSIGN <pal> <classId> <player> <blessingId>[@...]   per-player blessing (names: space -> "_")
--   ASELF <7 x hex pairs>@<auraId>   AASSIGN <name> <auraId>
--     aura ids: 1 Devotion 2 Retribution 3 Concentration 4 Shadow 5 Frost 6 Fire 7 Sanctity 8 Crusader
-- Not supported: seals, cooldown sync, symbol counts.

local PP = "PLPWR"
local RegisterPrefix = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
local SendAddon = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
if RegisterPrefix then RegisterPrefix(PP) end

local CLASS_ID = { WARRIOR = 1, ROGUE = 2, PRIEST = 3, DRUID = 4, PALADIN = 5, HUNTER = 6, MAGE = 7, WARLOCK = 8, SHAMAN = 9 }
local ID_CLASS = {}
for class, id in pairs(CLASS_ID) do ID_CLASS[id] = class end
local MAX_CLASSES = 9

local BLESS_ID = { WISDOM = 1, MIGHT = 2, KINGS = 3, LIGHT = 5 }
local ID_BLESS = {}
for key, id in pairs(BLESS_ID) do ID_BLESS[id] = key end

local function Enabled() return ns.db and ns.db.compat end

local function Out(msg)
    if not Enabled() then return end
    local chan = ns.GroupChannel()
    if chan and SendAddon then SendAddon(PP, msg, chan) end
end

local function IsPaladin()
    return select(2, UnitClass("player")) == "PALADIN"
end

-- ---------------------------------------------------------------------------
-- Outgoing
-- ---------------------------------------------------------------------------
local lastSelf, lastReq = 0, 0

function ns.CompatSendSelf()
    if not Enabled() or not IsPaladin() then return end
    local now = GetTime()
    if now - lastSelf < 2 then return end
    lastSelf = now

    local me = ns.Me()
    local caps = ns.caps[me] or ns.ComputeOwnCaps()
    local s = ""
    for id = 1, 6 do
        s = s .. (caps[ID_BLESS[id]] and "10" or "nn")
    end
    s = s .. "@"
    local row = ns.assign[me] or {}
    for id = 1, MAX_CLASSES do
        local key = row[ID_CLASS[id]]
        s = s .. (key and BLESS_ID[key] or "n")
    end
    Out("SELF " .. s)
    -- auras we know and the one we're assigned
    local ac = ns.auraCaps and ns.auraCaps[me] or {}
    local a = ""
    for id = 1, 7 do
        local aura = ns.AURA_BY_PP[id]
        a = a .. ((aura and ac[aura.key]) and "10" or "nn")
    end
    local mine = ns.AuraFor and ns.AuraFor(me)
    Out("ASELF " .. a .. "@" .. (mine and ns.AURA_BY_KEY[mine].pp or 0))
    local sym = ns.ReagentCount and ns.ReagentCount() or 0
    Out("FREEASSIGN NO | SYMCOUNT " .. (tonumber(sym) or 0) .. " | COOLDOWNS:n:n:n:n")
    -- per-player blessings
    local list = {}
    for _, t in ipairs({ ns.db.override[me] or {}, ns.db.autoOverride[me] or {} }) do
        for player, key in pairs(t) do
            local unit = ns.UnitForName(player)
            local class = unit and select(2, UnitClass(unit))
            if class and CLASS_ID[class] then
                list[#list + 1] = ("%s %d %s %d"):format(me:gsub(" ", "_"), CLASS_ID[class], player:gsub(" ", "_"),
                    BLESS_ID[key] or 0)
            end
        end
    end
    for i = 1, #list, 5 do
        Out("NASSIGN " .. table.concat(list, "@", i, math.min(i + 4, #list)))
    end
end

function ns.CompatSendAura(pal, key)
    if not Enabled() or not IsPaladin() then return end
    Out(("AASSIGN %s %d"):format(pal, (key and ns.AURA_BY_KEY[key] and ns.AURA_BY_KEY[key].pp) or 0))
end

function ns.CompatSendOverride(pal, player, key)
    if not Enabled() or not IsPaladin() then return end
    local unit = ns.UnitForName(player)
    local class = unit and select(2, UnitClass(unit))
    if not (class and CLASS_ID[class]) then return end
    Out(("NASSIGN %s %d %s %d"):format(pal:gsub(" ", "_"), CLASS_ID[class], player:gsub(" ", "_"),
        (key and BLESS_ID[key]) or 0))
end

function ns.CompatSendAssign(pal, class, key)
    if not Enabled() or not IsPaladin() then return end
    local classId = CLASS_ID[class]
    if not classId then return end
    Out(("ASSIGN %s %d %d"):format(pal, classId, (key and BLESS_ID[key]) or 0))
end

function ns.CompatRequest(force)
    if not Enabled() then return end
    local now = GetTime()
    if not force and now - lastReq < 10 then return end
    lastReq = now
    Out("REQ")
    ns.CompatSendSelf()
end

-- ---------------------------------------------------------------------------
-- Incoming
-- ---------------------------------------------------------------------------
local function MaySet(sender, name)
    if sender == name then return true end
    return ns.HasAuthority(ns.UnitForName(sender))
end

local function SetRowFromString(name, assign)
    ns.assign[name] = ns.assign[name] or {}
    for id = 1, MAX_CLASSES do
        local b = tonumber(assign:sub(id, id))
        local class = ID_CLASS[id]
        if class then
            ns.assign[name][class] = (b and ID_BLESS[b]) or nil
        end
    end
end

function ns.CompatReceive(prefix, text, channel, sender)
    if not Enabled() or prefix ~= PP or not text then return end
    sender = ns.StripRealm(Ambiguate(sender or "", "none"))
    if not sender or sender == ns.Me() then return end

    local cmd = text:match("^(%S+)")
    local changed = false
    if ns.NoteAddon then ns.NoteAddon(sender, "PallyPower") end

    if cmd == "REQ" then
        ns.CompatSendSelf()

    elseif cmd == "SELF" then
        local numbers, assign = text:match("^SELF ([0-9a-fn]*)@([0-9n]*)")
        if numbers then
            local caps = {}
            for id = 1, 6 do
                local rank = numbers:sub((id - 1) * 2 + 1, (id - 1) * 2 + 1)
                local key = ID_BLESS[id]
                if key and rank ~= "" and rank ~= "n" then caps[key] = true end
            end
            ns.caps[sender] = caps
            ns.assign[sender] = {}
            if assign then SetRowFromString(sender, assign) end
            changed = true
        end

    elseif cmd == "ASSIGN" then
        local name, classId, blessId = text:match("^ASSIGN (.*) (%d+) (%d+)$")
        if name then
            name = ns.StripRealm(name)
            local class = ID_CLASS[tonumber(classId)]
            if class and MaySet(sender, name) then
                ns.assign[name] = ns.assign[name] or {}
                ns.assign[name][class] = ID_BLESS[tonumber(blessId)]
                changed = true
            end
        end

    elseif cmd == "PASSIGN" then
        local name, assign = text:match("^PASSIGN (.*)@([0-9n]*)")
        if name and assign then
            name = ns.StripRealm(name)
            if MaySet(sender, name) then
                SetRowFromString(name, assign)
                changed = true
            end
        end

    elseif cmd == "MASSIGN" then
        local name, blessId = text:match("^MASSIGN (.*) (%d+)$")
        if name then
            name = ns.StripRealm(name)
            if MaySet(sender, name) then
                ns.assign[name] = ns.assign[name] or {}
                local key = ID_BLESS[tonumber(blessId)]
                for _, class in ipairs(ns.CLASSES) do
                    ns.assign[name][class] = key
                end
                changed = true
            end
        end

    elseif cmd == "NASSIGN" then
        for pname, _, tname, skill in text:sub(9):gmatch("([^@]*) ([^@]*) ([^@]*) ([^@]*)") do
            pname = ns.StripRealm((pname:gsub("_", " ")))
            tname = ns.StripRealm((tname:gsub("_", " ")))
            if MaySet(sender, pname) then
                local key = ID_BLESS[tonumber(skill) or 0]
                ns.db.override[pname] = ns.db.override[pname] or {}
                ns.db.override[pname][tname] = key   -- 0 / unknown clears it
                changed = true
            end
        end

    elseif cmd == "ASELF" then
        local numbers, assign = text:match("^ASELF ([0-9a-fn]*)@([0-9n]*)")
        if numbers and ns.auraCaps then
            local caps = {}
            for id = 1, 7 do
                local rank = numbers:sub((id - 1) * 2 + 1, (id - 1) * 2 + 1)
                local aura = ns.AURA_BY_PP[id]
                if aura and rank ~= "" and rank ~= "n" then caps[aura.key] = true end
            end
            ns.auraCaps[sender] = caps
            local a = ns.AURA_BY_PP[tonumber(assign or "") or 0]
            ns.db.auraAssign[sender] = a and a.key or nil
            changed = true
        end

    elseif cmd == "AASSIGN" then
        local name, auraId = text:match("^AASSIGN (.*) (%d+)$")
        if name then
            name = ns.StripRealm(name)
            if MaySet(sender, name) then
                local a = ns.AURA_BY_PP[tonumber(auraId)]
                ns.db.auraAssign[name] = a and a.key or nil
                changed = true
            end
        end

    elseif cmd == "CLEAR" then
        if ns.HasAuthority(ns.UnitForName(sender)) then
            for _, row in pairs(ns.assign) do wipe(row) end
            changed = true
        end
    end

    if changed then
        ns.dirty = true
        if ns.OnAssignmentsChanged then ns.OnAssignmentsChanged() end
    end
end
