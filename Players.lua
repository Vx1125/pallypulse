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
-- Roles
-- ---------------------------------------------------------------------------
local FIXED = { WARRIOR = "MELEE", ROGUE = "MELEE", HUNTER = "MELEE", MAGE = "CASTER", WARLOCK = "CASTER", PRIEST = "HEALER" }

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
    if FIXED[e.class] then return FIXED[e.class], "class" end
    -- hybrids
    local ptype
    pcall(function() ptype = UnitPowerType(u) end)
    if not ns.Readable(ptype) then ptype = nil end
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
        local prefs = (role and ns.ROLE_PREFS[role]) or ns.PREFS[e.class]
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
--   !bless want might kings   ask for these blessings (in order)
--   !bless clear              back to normal
--   !bless missing            whispers back which of your blessings are down
--   !bless help
-- Also answers to "!pulse". Only one PallyPulse paladin replies, so the group isn't spammed.
-- ---------------------------------------------------------------------------
local ALIASES = {
    might = "MIGHT", bom = "MIGHT", ap = "MIGHT",
    wisdom = "WISDOM", wis = "WISDOM", bow = "WISDOM", mana = "WISDOM",
    kings = "KINGS", king = "KINGS", bok = "KINGS",
}

local function ParseBlessing(word)
    word = (word or ""):lower():gsub("[^%a]", "")
    if word == "" then return nil end
    if ALIASES[word] then return ALIASES[word] end
    for alias, key in pairs(ALIASES) do
        if #word >= 3 and alias:sub(1, #word) == word then return key end
    end
end

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

local function MissingFor(e)
    local out = {}
    for _, pal in ipairs(ns.paladins) do
        local key = ns.KeyFor(pal, e)
        if key and not ns.MemberRemaining(e, key) then
            out[#out + 1] = ns.BY_KEY[key].single:gsub("^Blessing of ", "") .. " (" .. ns.FirstName(pal) .. ")"
        end
    end
    return out
end

local function OnChat(msg, author)
    if not ns.db or not ns.db.chatRequests then return end
    if select(2, UnitClass("player")) ~= "PALADIN" then return end
    local cmd, rest = (msg or ""):lower():match("^%s*!%s*(%a+)%s*(.-)%s*$")
    if cmd ~= "bless" and cmd ~= "pulse" then return end
    author = ns.StripRealm(Ambiguate(author or "", "none"))
    local e
    for _, r in ipairs(ns.roster) do if r.name == author or ns.FirstName(r.name) == author then e = r break end end
    if not e then return end
    local sub, args = rest:match("^(%a*)%s*(.-)$")

    if sub == "want" then
        local keys = {}
        for word in args:gmatch("%S+") do
            local k = ParseBlessing(word)
            if k then keys[#keys + 1] = k end
        end
        if #keys == 0 then
            if IAnswer() then Whisper(author, "Usage: !bless want might|wisdom|kings") end
            return
        end
        ns.SetRequest(e.name, keys, false)
        if IAnswer() then
            local names = {}
            for _, k in ipairs(keys) do names[#names + 1] = ns.BY_KEY[k].single:gsub("^Blessing of ", "") end
            Whisper(author, table.concat(names, ", ") .. " set.")
        end
    elseif sub == "clear" then
        ns.SetRequest(e.name, nil, false)
        if IAnswer() then Whisper(author, "Cleared.") end
    elseif sub == "missing" then
        if IAnswer() then
            local m = MissingFor(e)
            Whisper(author, #m == 0 and "Nothing missing." or ("Missing: " .. table.concat(m, ", ")))
        end
    else
        if IAnswer() then Whisper(author, "!bless want might|wisdom|kings, !bless clear, !bless missing") end
    end
end

local chat = CreateFrame("Frame")
for _, ev in ipairs({ "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
                      "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_WHISPER" }) do
    pcall(chat.RegisterEvent, chat, ev)
end
chat:SetScript("OnEvent", function(_, _, msg, author)
    if not ns.Readable(msg) or not ns.Readable(author) then return end
    pcall(OnChat, msg, author)
end)
