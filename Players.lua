local ADDON, ns = ...

-- Per-player blessings ("exceptions"), role guessing and "!bless" chat requests.
--
-- A paladin normally gives each class one blessing. An exception gives one player something
-- else from that paladin (the druid tank gets Kings, the other druids get Wisdom).
--   db.override[pal][player]     set by hand (Players tab, a request, or PallyPower)
--   db.autoOverride[pal][player] set by auto-assign from guessed roles; recomputed each time
-- The effective blessing pal owes a player: hand > auto > the class assignment.

local function Me() return ns.Me() end

function ns.KeyFor(pal, e)
    if not pal or not e then return nil end
    local db = ns.db
    local o = db and db.override[pal] and db.override[pal][e.name]
    if o == "NONE" then return nil end
    if o and ns.BY_KEY[o] then return o end
    local a = db and db.autoOverride[pal] and db.autoOverride[pal][e.name]
    if a and ns.BY_KEY[a] then return a end
    return ns.assign[pal] and ns.assign[pal][e.class]
end

-- Is the player's blessing from pal an exception (not the class one)?
function ns.IsException(pal, e)
    local db = ns.db
    local o = db and db.override[pal] and db.override[pal][e.name]
    local a = db and db.autoOverride[pal] and db.autoOverride[pal][e.name]
    return (o or a) and true or false, o and "hand" or (a and "auto") or nil
end

function ns.SetOverride(pal, player, key, broadcast)
    ns.db.override[pal] = ns.db.override[pal] or {}
    if key == "DEFAULT" or key == "" then key = nil end
    ns.db.override[pal][player] = key
    ns.dirty = true
    if ns.OnAssignmentsChanged then ns.OnAssignmentsChanged() end
    if broadcast then
        ns.Send(("P|%s|%s|%s"):format(pal, player, key or "DEFAULT"))
        if ns.CompatSendOverride then ns.CompatSendOverride(pal, player, key) end
    end
end

-- ---------------------------------------------------------------------------
-- Specs: inspect hybrids (and warriors, for Protection) out of combat, one at a time, and
-- remember the main talent tree for 60 days. Works with talent trees (classic clients) or
-- specializations (modern), whichever this client has.
-- ---------------------------------------------------------------------------
local SPEC_CLASSES = { WARRIOR = true, DRUID = true, SHAMAN = true, PALADIN = true, PRIEST = true }
local SPEC_AGE = 60 * 86400

-- tree / spec name (or its art file) -> role; casters before melee ("ShamanElementalCombat")
local TREE_ROLES = {
    { "TANK",   { "protection" } },
    { "HEALER", { "holy", "restoration", "discipline" } },
    { "CASTER", { "balance", "elemental", "shadow", "arcane", "fire", "frost", "affliction", "demonology", "destruction" } },
    { "MELEE",  { "retribution", "enhancement", "feral", "arms", "fury", "combat", "assassination", "subtlety" } },
    { "RANGED", { "beast", "marksman", "survival" } },
}
local function TreeRole(text)
    text = (text or ""):lower()
    for _, r in ipairs(TREE_ROLES) do
        for _, w in ipairs(r[2]) do if text:find(w, 1, true) then return r[1] end end
    end
end

-- Main spec of the inspected unit (isInspect) or yourself: name, role.
local function ReadSpec(isInspect, unit)
    local name, role
    pcall(function()
        local id
        if isInspect and GetInspectSpecialization then id = GetInspectSpecialization(unit)
        elseif not isInspect and GetSpecialization and GetSpecializationInfo then
            local i = GetSpecialization()
            if i then id = (GetSpecializationInfo(i)) end
        end
        if id and id > 0 and GetSpecializationInfoByID then
            local _, n, _, _, r = GetSpecializationInfoByID(id)
            if n then name, role = n, (r == "TANK" or r == "HEALER") and r or TreeRole(n) end
        end
    end)
    if name then return name, role end
    pcall(function()
        if not (GetNumTalentTabs and GetTalentTabInfo) then return end
        local bestPts, best, bestFile = 0, nil, nil
        for t = 1, GetNumTalentTabs(isInspect) or 0 do
            local r = { GetTalentTabInfo(t, isInspect) }
            local n, pts, file
            if type(r[1]) == "number" then n, pts, file = r[2], r[5], r[6] else n, pts, file = r[1], r[3], r[4] end
            if type(pts) == "number" and pts > bestPts then bestPts, best, bestFile = pts, n, file end
        end
        if best then name, role = best, TreeRole(tostring(bestFile or "") .. " " .. best) end
    end)
    return name, role
end

-- /pulse debug specs: what the game returns for your own talents, and each player's spec
function ns.DebugSpecs()
    local P = ns.Print
    P(("API: GetSpecialization=%s GetInspectSpecialization=%s GetNumTalentTabs=%s GetTalentTabInfo=%s"):format(
        tostring(GetSpecialization ~= nil), tostring(GetInspectSpecialization ~= nil),
        tostring(GetNumTalentTabs ~= nil), tostring(GetTalentTabInfo ~= nil)))
    if GetSpecialization then
        local ok, i = pcall(GetSpecialization)
        P("GetSpecialization() = " .. tostring(ok and i))
    end
    if GetNumTalentTabs and GetTalentTabInfo then
        local ok, n = pcall(GetNumTalentTabs, false)
        P("GetNumTalentTabs() = " .. tostring(ok and n))
        for t = 1, (ok and n or 0) do
            local r = { pcall(GetTalentTabInfo, t, false) }
            local parts = {}
            for i = 2, math.min(#r, 9) do parts[#parts + 1] = tostring(r[i]) end
            P(("  tab %d: %s"):format(t, table.concat(parts, ", ")))
        end
    end
    local name, role = ReadSpec(false)
    P(("You read as: %s (%s)"):format(tostring(name), tostring(role)))
    for _, e in ipairs(ns.roster) do
        local s = ns.db.specs[e.name]
        local r, why = ns.GuessRole(e)
        P(("  %s %s: spec=%s role=%s (%s)"):format(ns.FirstName(e.name), e.class, s and tostring(s.name) or "-",
            tostring(r), tostring(why)))
    end
end

local specTried = {}      -- [name] = GetTime() of the last inspect this session
local inspecting          -- { name, unit, guid, t }
local replan = false

-- Specs are shared with the other PallyPulse paladins, so each player is only inspected
-- once per group: "S|name,ROLE,Spec,time;name,..." (batched to stay under the message size).
local function SpecEntry(name, s)
    return ("%s,%s,%s,%d"):format(name, s.role, (tostring(s.name):gsub("[,;|]", "")), s.t or 0)
end

local function SendSpecs(names)
    local buf = {}
    local len = 2
    local function flush()
        if #buf > 0 then ns.Send("S|" .. table.concat(buf, ";")) end
        wipe(buf); len = 2
    end
    for _, name in ipairs(names) do
        local s = ns.db.specs[name]
        if s and s.role then
            local item = SpecEntry(name, s)
            if len + #item + 1 > 240 then flush() end
            buf[#buf + 1] = item
            len = len + #item + 1
        end
    end
    flush()
end

local function StoreSpec(name, specName, role, when, shared)
    if not (specName and role and ns.Readable(specName)) then return end
    local old = ns.db.specs[name]
    if not old or old.role ~= role then replan = true end
    ns.db.specs[name] = { name = specName, role = role, t = when or time() }
    ns.dirty = true
    if not shared then SendSpecs({ name }) end
end

ns.comm.S = function(sender, data)
    if not ns.db or not data then return end
    local inGroup = {}
    for _, e in ipairs(ns.roster) do inGroup[e.name] = true end
    for item in data:gmatch("[^;]+") do
        local name, role, specName, t = item:match("^([^,]+),(%u+),([^,]*),(%d+)$")
        t = tonumber(t)
        if name and inGroup[name] and ns.ROLE_LABEL[role] and t and t <= time() + 60 then
            local cur = ns.db.specs[name]
            if not cur or (cur.t or 0) < t then
                StoreSpec(name, specName, role, t, true)
                specTried[name] = GetTime()        -- no need to inspect them ourselves
            end
        end
    end
end

-- when someone asks for sync (joins, reloads): send the specs we know for this group,
-- at most every 30 seconds
local lastSpecSync = 0
table.insert(ns.syncHooks, function()
    if GetTime() - lastSpecSync < 30 then return end
    lastSpecSync = GetTime()
    local names = {}
    for _, e in ipairs(ns.roster) do if not e.fake and ns.db.specs[e.name] then names[#names + 1] = e.name end end
    SendSpecs(names)
end)

local function InspectNext()
    if not ns.db or InCombatLockdown() then return end
    if inspecting then
        if GetTime() - inspecting.t < 5 then return end
        pcall(ClearInspectPlayer)
        inspecting = nil
    end
    if InspectFrame and InspectFrame:IsShown() then return end   -- you're inspecting someone
    local now = GetTime()
    for _, e in ipairs(ns.roster) do
        if not e.fake and SPEC_CLASSES[e.class] and not (specTried[e.name] and now - specTried[e.name] < 600)
            and not (specTried[e.name] and ns.db.specs[e.name]) then
            if e.name == ns.Me() then
                specTried[e.name] = now
                StoreSpec(e.name, ReadSpec(false))
            else
                local ok = false
                pcall(function()
                    ok = UnitIsConnected(e.unit) and CanInspect(e.unit) and CheckInteractDistance(e.unit, 1) and true or false
                end)
                if ok then
                    specTried[e.name] = now
                    inspecting = { name = e.name, unit = e.unit, guid = UnitGUID(e.unit), t = now }
                    pcall(NotifyInspect, e.unit)
                    return
                end
            end
        end
    end
    -- queue done: re-plan exceptions once if anyone's role changed
    if replan then
        replan = false
        if ns.AutoOverrides then ns.AutoOverrides() end
    end
end

local specEv = CreateFrame("Frame")
specEv:RegisterEvent("INSPECT_READY")
pcall(specEv.RegisterEvent, specEv, "INSPECT_TALENT_READY")
specEv:RegisterEvent("PLAYER_TALENT_UPDATE")
specEv:SetScript("OnEvent", function(_, event, guid)
    if not ns.db then return end
    if event == "PLAYER_TALENT_UPDATE" then
        specTried[ns.Me()] = nil
        return
    end
    if not inspecting then return end
    if guid and inspecting.guid and guid ~= inspecting.guid then return end
    StoreSpec(inspecting.name, ReadSpec(true, inspecting.unit))
    pcall(ClearInspectPlayer)
    inspecting = nil
end)

local pruned = false
local specTicker = CreateFrame("Frame")
local specElapsed = 0
specTicker:SetScript("OnUpdate", function(_, dt)
    specElapsed = specElapsed + dt
    if specElapsed < 2 then return end
    specElapsed = 0
    if not ns.db then return end
    if not pruned then
        pruned = true
        for name, s in pairs(ns.db.specs) do
            if type(s) ~= "table" or time() - (s.t or 0) > SPEC_AGE then ns.db.specs[name] = nil end
        end
    end
    InspectNext()
end)

-- tree / spec name -> the spec keys in Data.lua's ns.SPECS
local TREE_KEYS = {
    { "PROTECTION", "protection" }, { "DISCIPLINE", "discipline" }, { "HOLY", "holy" },
    { "RESTORATION", "restoration" }, { "BALANCE", "balance" }, { "ELEMENTAL", "elemental" },
    { "ENHANCEMENT", "enhancement" }, { "FERAL", "feral" }, { "ARMS", "arms" }, { "FURY", "fury" },
    { "RETRIBUTION", "retribution" }, { "SHADOW", "shadow" },
}
local function TreeKey(text)
    text = (text or ""):lower()
    for _, t in ipairs(TREE_KEYS) do if text:find(t[2], 1, true) then return t[1] end end
end

-- Which Priorities row a player uses: their inspected spec, or the first spec of their
-- class that fits their role.
function ns.SpecKey(e)
    local specs = ns.SPECS[e.class]
    if not specs or #specs == 1 then return specs and specs[1].key or "" end
    if e.class == "PALADIN" and ns.oathCap and ns.oathCap[e.name] then return "HOLY" end
    local role = ns.GuessRole(e)
    local s = ns.db.specs and ns.db.specs[e.name]
    local key = s and TreeKey(s.name)
    if key == "FERAL" then key = (role == "TANK") and "BEAR" or "CAT" end
    if key then
        for _, sp in ipairs(specs) do if sp.key == key then return key end end
    end
    for _, sp in ipairs(specs) do if sp.role == role then return sp.key end end
    return specs[1].key
end

-- Short spec name for the Players tab, only when the spec is known (inspected, shared by
-- another PallyPulse, or a paladin with Oath of Light). nil otherwise.
local SHORT = {
    ARMS = "Arms", FURY = "Fury", PROTECTION = "Prot", DISCIPLINE = "Disc", HOLY = "Holy", SHADOW = "Shadow",
    BALANCE = "Balance", CAT = "Feral", BEAR = "Bear", RESTORATION = "Resto", ELEMENTAL = "Elemental",
    ENHANCEMENT = "Enhance", RETRIBUTION = "Ret",
}
function ns.SpecLabel(e)
    local specs = ns.SPECS[e.class]
    if not specs or #specs == 1 then return nil end
    local known = (ns.db.specs and ns.db.specs[e.name]) or (e.class == "PALADIN" and ns.oathCap and ns.oathCap[e.name])
    if not known then return nil end
    return SHORT[ns.SpecKey(e)]
end

-- ---------------------------------------------------------------------------
-- Roles
-- ---------------------------------------------------------------------------
local FIXED = { WARRIOR = "MELEE", ROGUE = "MELEE", HUNTER = "RANGED", MAGE = "CASTER", WARLOCK = "CASTER", PRIEST = "HEALER" }

-- Best guess at what kind of player this is: TANK / MELEE / CASTER / HEALER, or nil if unsure.
-- Second value says where the guess came from.
function ns.GuessRole(e)
    local set = ns.db.roleOverride[e.name]
    if set then return set, "set by hand" end
    local u = e.unit
    for _, t in ipairs(ns.FindTanks()) do if t == e.name then return "TANK", "tank marker / role" end end
    local role
    pcall(function() role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(u) end)
    if not ns.Readable(role) then role = nil end
    if role == "HEALER" then return "HEALER", "group role" end
    local ptype
    pcall(function() ptype = UnitPowerType(u) end)
    if not ns.Readable(ptype) then ptype = nil end
    -- Oath of Light is a Holy talent: a paladin who has it is Holy
    if e.class == "PALADIN" and ns.oathCap and ns.oathCap[e.name] then return "HEALER", "spec", "Holy" end
    local spec = ns.db.specs and ns.db.specs[e.name]
    if spec and spec.role then
        if spec.role == "MELEE" and e.class == "DRUID" and ptype == 1 then return "TANK", "spec", spec.name end
        return spec.role, "spec", spec.name
    end
    if FIXED[e.class] then return FIXED[e.class], "class" end
    -- hybrids
    if e.class == "DRUID" then
        if ptype == 1 then return "TANK", "bear form" end
        if ptype == 3 then return "MELEE", "cat form" end
        if role == "DAMAGER" then return "CASTER", "group role" end
    elseif e.class == "PALADIN" then
        if role == "DAMAGER" then return "MELEE", "group role" end
    elseif e.class == "SHAMAN" then
        -- elemental and enhancement both say "damage"; leave it to the class default
    end
    return nil, "unknown"
end

-- ---------------------------------------------------------------------------
-- Spec-aware auto-assign: exceptions where a player's role wants something the class
-- assignment doesn't give them. Requests ("!bless want") always win.
-- ---------------------------------------------------------------------------
local function Sorted(t) local c = {} for i, v in ipairs(t) do c[i] = v end table.sort(c) return c end

function ns.AutoOverrides()
    local db = ns.db
    -- alphabetical, so every PallyPulse copy in the group reaches the same answer
    local pals = Sorted(ns.paladins)
    for _, pal in ipairs(pals) do
        if ns.CanEditRow(pal) then db.autoOverride[pal] = {} end
    end
    for _, e in ipairs(ns.roster) do
        local req = db.requests[e.name]
        local role = ns.GuessRole(e)
        local prefs = ns.PrefsFor(e)
        local list, seen = {}, {}
        for _, k in ipairs(req or {}) do if not seen[k] then seen[k] = true; list[#list + 1] = k end end
        for _, k in ipairs(prefs or {}) do if not seen[k] then seen[k] = true; list[#list + 1] = k end end

        -- what each paladin gives this player now (class assignment or hand exception)
        local give, n = {}, 0
        for _, pal in ipairs(pals) do
            local o = db.override[pal] and db.override[pal][e.name]
            local k = (o and o ~= "NONE" and o) or (ns.assign[pal] and ns.assign[pal][e.class])
            if k then give[pal] = k; n = n + 1 end
        end
        if n > 0 then
            -- the n blessings this player should end up with
            local want, wantSet = {}, {}
            for _, k in ipairs(list) do
                if #want >= n then break end
                local someone = false
                for _, pal in ipairs(pals) do
                    local caps = ns.caps[pal]
                    if give[pal] and (not caps or caps[k]) then someone = true break end
                end
                if someone then want[#want + 1] = k; wantSet[k] = true end
            end
            local have = {}
            for _, k in pairs(give) do have[k] = true end
            local missing = {}
            for _, k in ipairs(want) do if not have[k] then missing[#missing + 1] = k end end
            -- swap: a paladin giving something unwanted (and not hand-set) gives a wanted one instead
            for _, pal in ipairs(pals) do
                if #missing == 0 then break end
                local hand = db.override[pal] and db.override[pal][e.name]
                local k = give[pal]
                if k and not wantSet[k] and not hand and ns.CanEditRow(pal) then
                    local caps = ns.caps[pal]
                    for i, m in ipairs(missing) do
                        if not caps or caps[m] then
                            db.autoOverride[pal][e.name] = m
                            give[pal] = m
                            table.remove(missing, i)
                            break
                        end
                    end
                end
            end
        end
    end
    -- share the result
    for _, pal in ipairs(pals) do
        if ns.CanEditRow(pal) then ns.BroadcastOverrides(pal) end
    end
end

function ns.BroadcastOverrides(pal)
    pal = pal or Me()
    local db = ns.db
    local seen = {}
    for player, key in pairs(db.override[pal] or {}) do
        seen[player] = true
        ns.Send(("P|%s|%s|%s"):format(pal, player, key))
        if ns.CompatSendOverride then ns.CompatSendOverride(pal, player, key) end
    end
    for player, key in pairs(db.autoOverride[pal] or {}) do
        if not seen[player] then
            ns.Send(("P|%s|%s|%s|auto"):format(pal, player, key))
            if ns.CompatSendOverride then ns.CompatSendOverride(pal, player, key) end
        end
    end
end

ns.comm["P"] = function(sender, pal, player, key, kind)
    if not (pal and player and key) then return end
    if sender ~= pal and not ns.HasAuthority(ns.UnitForName(sender)) then return end
    if key ~= "DEFAULT" and key ~= "NONE" and not ns.BY_KEY[key] then return end
    if kind == "auto" then
        ns.db.autoOverride[pal] = ns.db.autoOverride[pal] or {}
        ns.db.autoOverride[pal][player] = (key ~= "DEFAULT") and key or nil
    else
        ns.db.override[pal] = ns.db.override[pal] or {}
        ns.db.override[pal][player] = (key ~= "DEFAULT") and key or nil
    end
    ns.dirty = true
    if ns.OnAssignmentsChanged then ns.OnAssignmentsChanged() end
end

-- requests sync between PallyPulse copies, so everyone plans with the same wishes
ns.comm["R"] = function(sender, player, list)
    if not player then return end
    if sender ~= player and not ns.HasAuthority(ns.UnitForName(sender)) and not ns.paladinsSet()[sender] then return end
    local t = {}
    for k in (list or ""):gmatch("[^,]+") do if ns.BY_KEY[k] then t[#t + 1] = k end end
    ns.db.requests[player] = #t > 0 and t or nil
    ns.dirty = true
    if ns.OnAssignmentsChanged then ns.OnAssignmentsChanged() end
end

function ns.paladinsSet()
    local s = {}
    for _, p in ipairs(ns.paladins) do s[p] = true end
    return s
end

function ns.SetRequest(player, keys, broadcast)
    ns.db.requests[player] = (keys and #keys > 0) and keys or nil
    if broadcast then ns.Send(("R|%s|%s"):format(player, table.concat(keys or {}, ","))) end
    ns.AutoOverrides()
    ns.dirty = true
    if ns.OnAssignmentsChanged then ns.OnAssignmentsChanged() end
end

table.insert(ns.syncHooks, function()
    ns.BroadcastOverrides(Me())
    for player, keys in pairs(ns.db.requests) do
        if ns.UnitForName(player) then ns.Send(("R|%s|%s"):format(player, table.concat(keys, ","))) end
    end
end)

-- ---------------------------------------------------------------------------
-- "!bless" chat commands (anyone in the group, addon or not)
--   !bless want might kings          ask for these blessings (in order)
--   !bless want <name> kings         leader / assistant: set it for someone else
--   !bless clear                     back to normal
--   !bless missing                   your blessings that are down
--   !bless missing all               everyone's
--   !bless report                    which paladin blesses which class
--   !bless assign                    leader / assistant: run Auto-assign
--   !bless help
-- Also answers to "!pulse". Blessing names may have a typo or two. Only one PallyPulse
-- paladin replies, so the group isn't spammed. Personal answers are whispered; report and
-- "missing all" answer in the channel they were asked in.
-- ---------------------------------------------------------------------------
local ALIASES = {
    might = "MIGHT", bom = "MIGHT", ap = "MIGHT", gbom = "MIGHT",
    wisdom = "WISDOM", wis = "WISDOM", bow = "WISDOM", mana = "WISDOM", gbow = "WISDOM",
    kings = "KINGS", king = "KINGS", bok = "KINGS", gbok = "KINGS",
}
local FULL = { might = "MIGHT", wisdom = "WISDOM", kings = "KINGS" }

local function Distance(a, b)
    local la, lb = #a, #b
    local prev = {}
    for j = 0, lb do prev[j] = j end
    for i = 1, la do
        local cur = { [0] = i }
        for j = 1, lb do
            local cost = (a:sub(i, i) == b:sub(j, j)) and 0 or 1
            cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        end
        prev = cur
    end
    return prev[lb]
end

local function ParseBlessing(word)
    word = (word or ""):lower():gsub("[^%a]", "")
    if word == "" then return nil end
    if ALIASES[word] then return ALIASES[word] end
    for alias, key in pairs(ALIASES) do
        if #word >= 3 and alias:sub(1, #word) == word then return key end
    end
    -- typos: "wisodm", "mihgt", "kigns"
    if #word >= 4 then
        local best, bestD, tie = nil, 3, false
        for name, key in pairs(FULL) do
            local d = Distance(word, name)
            if d < bestD then best, bestD, tie = key, d, false elseif d == bestD then tie = true end
        end
        if best and not tie and bestD <= (#word >= 6 and 2 or 1) then return best end
    end
end

local function Short(key) return (ns.BY_KEY[key].single:gsub("^Blessing of ", "")) end

local CLASS_SHORT = { WARRIOR = "War", ROGUE = "Rog", HUNTER = "Hun", MAGE = "Mage", WARLOCK = "Lock",
                      PRIEST = "Pri", DRUID = "Dru", SHAMAN = "Sham", PALADIN = "Pal" }

-- The PallyPulse paladin who answers chat (alphabetically first that we know runs it).
local function IAnswer()
    local me = Me()
    local first = me
    for _, pal in ipairs(ns.paladins) do
        local v = ns.versions and ns.versions[pal]
        if v and v.addon == "PallyPulse" and pal < first then first = pal end
    end
    return first == me
end

local function Whisper(to, msg)
    pcall(SendChatMessage, "[PallyPulse] " .. msg, "WHISPER", nil, to)
end

local CHANNEL = {
    CHAT_MSG_PARTY = "PARTY", CHAT_MSG_PARTY_LEADER = "PARTY",
    CHAT_MSG_RAID = "RAID", CHAT_MSG_RAID_LEADER = "RAID",
    CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT", CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE_CHAT",
}
-- answer in the channel the question came from (a whisper gets a whisper)
local function Reply(event, author, msg)
    local ch = CHANNEL[event]
    if ch then pcall(SendChatMessage, "[PallyPulse] " .. msg, ch) else Whisper(author, msg) end
end

local function MissingFor(e)
    local out = {}
    for _, pal in ipairs(ns.paladins) do
        local key = ns.KeyFor(pal, e)
        if key and ns.BY_KEY[key] and not ns.MemberRemaining(e, key) then
            out[#out + 1] = Short(key) .. " (" .. ns.FirstName(pal) .. ")"
        end
    end
    return out
end

-- "Tomas: Might War/Rog/Hun, Wisdom rest (+1 single)"
local function ReportLine(pal)
    local row = ns.assign[pal] or {}
    local count, classes = {}, {}
    for _, class in ipairs(ns.CLASSES) do
        local k = row[class]
        if k and ns.BY_KEY[k] and ns.byClass[class] then
            count[k] = (count[k] or 0) + 1
            classes[k] = classes[k] or {}
            table.insert(classes[k], CLASS_SHORT[class] or class)
        end
    end
    local main, mainN = nil, 0
    for k, n in pairs(count) do if n > mainN then main, mainN = k, n end end
    if not main then return nil end
    local parts = {}
    for _, b in ipairs(ns.BLESSINGS) do
        local k = b.key
        if count[k] and k ~= main then parts[#parts + 1] = Short(k) .. " " .. table.concat(classes[k], "/") end
    end
    local text = #parts == 0 and Short(main) or (table.concat(parts, ", ") .. ", " .. Short(main) .. " rest")
    local singles = 0
    for _, e in ipairs(ns.roster) do if ns.IsException(pal, e) then singles = singles + 1 end end
    if singles > 0 then text = text .. (" (+%d single)"):format(singles) end
    return ns.FirstName(pal) .. ": " .. text
end

-- find a group member by name (full, first name, or the start of it)
local function FindPlayer(word)
    word = (word or ""):lower()
    if #word < 3 then return nil end
    local hit
    for _, r in ipairs(ns.roster) do
        local n = ns.FirstName(r.name):lower()
        if n == word or r.name:lower() == word then return r end
        if n:sub(1, #word) == word then
            if hit then return nil end   -- ambiguous
            hit = r
        end
    end
    return hit
end

local function OnChat(event, msg, author)
    if not ns.db or not ns.db.chatRequests then return end
    if select(2, UnitClass("player")) ~= "PALADIN" then return end
    local cmd, rest = (msg or ""):lower():match("^%s*!%s*(%a+)%s*(.-)%s*$")
    if cmd ~= "bless" and cmd ~= "pulse" then return end
    author = ns.StripRealm(Ambiguate(author or "", "none"))
    local e
    for _, r in ipairs(ns.roster) do if r.name == author or ns.FirstName(r.name) == author then e = r break end end
    if not e then return end
    local lead = ns.HasAuthority(e.unit)
    local sub, args = rest:match("^(%a*)%s*(.-)$")

    if sub == "want" then
        local who, words = e, {}
        for word in args:gmatch("[^%s,;/]+") do words[#words + 1] = word end
        if words[1] and not ParseBlessing(words[1]) and lead then
            local other = FindPlayer(words[1])
            if other then who = other; table.remove(words, 1) end
        end
        local keys, seen = {}, {}
        for _, word in ipairs(words) do
            local k = ParseBlessing(word)
            if k and not seen[k] then seen[k] = true; keys[#keys + 1] = k end
        end
        if #keys == 0 then
            if IAnswer() then Whisper(author, "!bless want might, wisdom, kings") end
            return
        end
        ns.SetRequest(who.name, keys, false)
        if IAnswer() then
            local names = {}
            for _, k in ipairs(keys) do names[#names + 1] = Short(k) end
            Whisper(author, (who ~= e and (ns.FirstName(who.name) .. ": ") or "") .. table.concat(names, ", "))
        end
    elseif sub == "clear" then
        local who = e
        if lead and args ~= "" then who = FindPlayer(args) or e end
        ns.SetRequest(who.name, nil, false)
        if IAnswer() then Whisper(author, (who ~= e and (ns.FirstName(who.name) .. ": ") or "") .. "Cleared") end
    elseif sub == "missing" then
        if not IAnswer() then return end
        if args == "all" or args == "raid" or args == "group" then
            local out, extra, len = {}, 0, 0
            for _, r in ipairs(ns.roster) do
                if not r.fake and ns.Eligible(r) then
                    local m = {}
                    for _, pal in ipairs(ns.paladins) do
                        local key = ns.KeyFor(pal, r)
                        if key and ns.BY_KEY[key] and not ns.MemberRemaining(r, key) then m[#m + 1] = Short(key) end
                    end
                    if #m > 0 then
                        local item = ns.FirstName(r.name) .. " " .. table.concat(m, "/")
                        if len + #item > 200 then extra = extra + 1
                        else out[#out + 1] = item; len = len + #item + 2 end
                    end
                end
            end
            if #out == 0 then Reply(event, author, "All buffed")
            else Reply(event, author, "Missing: " .. table.concat(out, ", ") .. (extra > 0 and (" +" .. extra) or "")) end
        else
            local m = MissingFor(e)
            Whisper(author, #m == 0 and "All buffed" or ("Missing: " .. table.concat(m, ", ")))
        end
    elseif sub == "report" then
        if not IAnswer() then return end
        local any = false
        for _, pal in ipairs(ns.paladins) do
            local line = not ns.IsFakeName(pal) and ReportLine(pal)
            if line then any = true; Reply(event, author, line) end
        end
        if not any then Reply(event, author, "No assignments") end
    elseif sub == "assign" then
        if not lead or not IAnswer() then return end
        if InCombatLockdown() then Whisper(author, "In combat") return end
        ns.AutoAssign()
        Reply(event, author, "Assigned")
    else
        if IAnswer() then
            Whisper(author, "!bless want might, wisdom, kings | clear | missing [all] | report" .. (lead and " | assign" or ""))
        end
    end
end

local chat = CreateFrame("Frame")
for _, ev in ipairs({ "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
                      "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_WHISPER" }) do
    pcall(chat.RegisterEvent, chat, ev)
end
chat:SetScript("OnEvent", function(_, event, msg, author)
    if not ns.Readable(msg) or not ns.Readable(author) then return end
    pcall(OnChat, event, msg, author)
end)
