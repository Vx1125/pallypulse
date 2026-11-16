local ADDON, ns = ...

-- Test mode: adds a fake 13-player raid with two fake paladins, so the bar, the tabs and the
-- ready check window can be tried while solo. The fake paladins are real rows on the
-- Blessings tab: change their assignments (or anyone's) and every view updates. Each fake
-- player's buffs come from the current assignments, with a few deliberate gaps. Nothing is
-- cast on fake players, nothing about them is sent to the group, and it's all removed when
-- test mode ends.

local PREFIX = "pulsepreview"

-- Fake paladins and what they start with
local PALS = {
    { name = "Liadra", blessing = "KINGS", aura = "DEVOTION" },
    { name = "Tomas",  blessing = "LIGHT", aura = "CONCENTRATION", oath = "Brannock" },
}

-- name, class, role, your blessing ("ok" / "low" / "missing"), fake paladins whose blessing
-- they're missing, raid buffs, ready status, dead
local FAKES = {
    { "Brannock",  "WARRIOR", "TANK",   "ok",      {},           { "FORT", "MOTW", "FOOD", "FLASK" }, "ready" },
    { "Hrodgar",   "WARRIOR", "MELEE",  "missing", { "Liadra" }, { "FORT", "MOTW", "FOOD" },          "ready" },
    { "Vexa",      "ROGUE",   "MELEE",  "low",     {},           { "FORT", "MOTW", "FOOD" },          "waiting" },
    { "Talonis",   "HUNTER",  "MELEE",  "ok",      { "Tomas" },  { "FORT", "INT" },                   "ready" },
    { "Ilyndra",   "MAGE",    "CASTER", "missing", {},           { "FORT", "MOTW", "INT", "FLASK" },  "ready" },
    { "Corvin",    "MAGE",    "CASTER", "ok",      { "Liadra" }, { "FORT", "INT", "FOOD" },           "notready" },
    { "Morwen",    "WARLOCK", "CASTER", "low",     {},           { "FORT", "MOTW", "INT" },           "waiting" },
    { "Sorrel",    "PRIEST",  "HEALER", "ok",      {},           { "FORT", "MOTW", "INT", "SPIRIT", "FOOD" }, "ready" },
    { "Ansel",     "PRIEST",  "HEALER", "missing", {},           { "FORT", "INT", "SPIRIT" },         "ready", true },
    { "Mirelle",   "DRUID",   "HEALER", "ok",      { "Tomas" },  { "FORT", "MOTW", "INT", "FLASK" },  "ready" },
    { "Thrallbek", "SHAMAN",  "HEALER", "missing", {},           { "FORT", "MOTW", "INT" },           "waiting" },
    { "Grokka",    "SHAMAN",  "MELEE",  "ok",      {},           { "FORT", "MOTW", "FOOD" },          "ready" },
}

local RAID_NAMES = {
    FORT = "Prayer of Fortitude", MOTW = "Gift of the Wild", INT = "Arcane Brilliance",
    SPIRIT = "Prayer of Spirit", FOOD = "Well Fed", FLASK = "Flask of the Titans",
}

local fakeNames = {}
for _, p in ipairs(PALS) do fakeNames[p.name] = true end
for _, f in ipairs(FAKES) do fakeNames[f[1]] = true end

function ns.IsFake(unit)
    return type(unit) == "string" and unit:sub(1, #PREFIX) == PREFIX
end
function ns.IsFakeName(name) return name and fakeNames[name] or false end

local byName = {}

local function AddFakes()
    wipe(byName)
    local i = 0
    local function add(e)
        i = i + 1
        e.unit, e.fake = PREFIX .. i, true
        ns.roster[#ns.roster + 1] = e
        ns.byClass[e.class] = ns.byClass[e.class] or {}
        table.insert(ns.byClass[e.class], e)
        byName[e.name] = e
    end
    for _, p in ipairs(PALS) do
        add({ name = p.name, class = "PALADIN", role = "HEALER", mine = "ok", gaps = {}, raid = { "FORT", "MOTW" }, ready = "ready" })
        ns.paladins[#ns.paladins + 1] = p.name
        local all = {}
        for _, b in ipairs(ns.BLESSINGS) do all[b.key] = true end
        ns.caps[p.name] = all
        ns.oathCap[p.name] = true
        local auras = {}
        for k in pairs(ns.AURA_BY_KEY) do auras[k] = true end
        ns.auraCaps[p.name] = auras
    end
    for _, f in ipairs(FAKES) do
        local gaps = {}
        for _, pal in ipairs(f[5]) do gaps[pal] = true end
        add({ name = f[1], class = f[2], role = f[3], mine = f[4], gaps = gaps, raid = f[6], ready = f[7], dead = f[8] })
    end
end

-- Give the fake paladins a starting setup (only if they have none yet)
local function Seed()
    for _, p in ipairs(PALS) do
        if not ns.assign[p.name] then
            ns.assign[p.name] = {}
            for _, c in ipairs(ns.CLASSES) do ns.assign[p.name][c] = p.blessing end
        end
        if ns.db.auraAssign[p.name] == nil then ns.db.auraAssign[p.name] = p.aura end
        if p.oath and ns.oath[p.name] == nil then ns.oath[p.name] = p.oath end
    end
end

-- Remove everything test mode left behind
local function Cleanup()
    for name in pairs(fakeNames) do
        ns.assign[name] = nil
        ns.db.auraAssign[name] = nil
        ns.oath[name] = nil
        ns.caps[name], ns.oathCap[name], ns.auraCaps[name] = nil, nil, nil
        ns.db.roleOverride[name] = nil
        ns.db.requests[name] = nil
        ns.db.override[name], ns.db.autoOverride[name] = nil, nil
    end
    for _, t in pairs(ns.db.override) do for name in pairs(fakeNames) do t[name] = nil end end
    for _, t in pairs(ns.db.autoOverride) do for name in pairs(fakeNames) do t[name] = nil end end
end

-- Time left on a fake player's blessing, from whoever is assigned to give it
local function FakeRemaining(e, key)
    if e.dead or not key then return nil end
    local me, best = ns.Me(), nil
    for _, pal in ipairs(ns.paladins) do
        if ns.KeyFor(pal, e) == key then
            local t
            if pal == me then
                t = (e.mine == "ok" and 50 * 60) or (e.mine == "low" and 2 * 60) or nil
            elseif not e.gaps[pal] then
                t = 45 * 60
            end
            if t and (not best or t > best) then best = t end
        end
    end
    return best
end

-- Buff names on a fake player, the way the ready check window reads them
function ns.PreviewBuffs(e)
    local have = {}
    for _, b in ipairs(ns.BLESSINGS) do
        if FakeRemaining(e, b.key) then have[b.single] = b.icon end
    end
    for _, r in ipairs(e.raid or {}) do have[RAID_NAMES[r]] = true end
    return have
end

-- wrap the roster, status and edit functions
local origScan = ns.ScanRoster
local cleaned = false
function ns.ScanRoster(...)
    origScan(...)
    if ns.preview then
        AddFakes()
    elseif not cleaned and ns.db then
        cleaned = true; Cleanup()          -- leftovers from a /reload during test mode
    end
end

local origEligible = ns.Eligible
function ns.Eligible(e)
    if e and e.fake then return not e.dead end
    return origEligible(e)
end

local origRemaining = ns.MemberRemaining
function ns.MemberRemaining(e, key)
    if e and e.fake then return FakeRemaining(e, key) end
    return origRemaining(e, key)
end

local origRole = ns.GuessRole
function ns.GuessRole(e)
    if e and e.fake and not ns.db.roleOverride[e.name] then return e.role, "test" end
    return origRole(e)
end

local origCanEdit = ns.CanEditRow
function ns.CanEditRow(pal)
    if ns.preview and ns.IsFakeName(pal) then return true end
    return origCanEdit(pal)
end

-- nothing about fake players goes out to the group
local function Quiet(fn, nameArgs, bIdx)          -- bIdx = position of the "broadcast" argument
    return function(...)
        local args = { ... }
        local n = math.max(select("#", ...), bIdx)
        if ns.preview then
            for _, i in ipairs(nameArgs) do
                if ns.IsFakeName(args[i]) then args[bIdx] = false end
            end
        end
        return fn(unpack(args, 1, n))
    end
end
ns.SetAssignment = Quiet(ns.SetAssignment, { 1 }, 4)    -- (pal, class, key, broadcast)
ns.SetAura = Quiet(ns.SetAura, { 1 }, 3)                -- (pal, key, broadcast)
ns.SetOath = Quiet(ns.SetOath, { 1, 2 }, 3)             -- (pal, target, broadcast)
ns.SetOverride = Quiet(ns.SetOverride, { 1, 2 }, 4)     -- (pal, player, key, broadcast)

-- never cast on a fake player: clear any click that would
local function Disarm(b)
    if not b or InCombatLockdown() then return end
    for _, sfx in ipairs({ "1", "2" }) do
        if ns.IsFake(b:GetAttribute("unit" .. sfx)) then
            b:SetAttribute("type" .. sfx, nil)
        end
    end
end

local origQueue = ns.QueueSmart
function ns.QueueSmart(...)
    origQueue(...)
    if ns.preview then Disarm(ns.smartBtn) end
end

local origRefresh
local function HookBar()
    if origRefresh or not ns.RefreshBar then return end
    origRefresh = ns.RefreshBar
    ns.RefreshBar = function(...)
        origRefresh(...)
        if ns.preview and ns.bar then
            for _, b in ipairs(ns.bar.buttons or {}) do Disarm(b) end
            Disarm(ns.smartBtn)
        end
    end
end

function ns.SetPreview(on)
    if InCombatLockdown() then return end
    HookBar()
    ns.preview = on and true or false
    if ns.preview then Seed() else Cleanup() end
    ns.ScanRoster()
    if ns.AutoOverrides then ns.AutoOverrides() end
    ns.dirty = true
    if ns.RefreshWindow then pcall(ns.RefreshWindow) end
    if ns.RefreshOptions then pcall(ns.RefreshOptions) end
    if ns.preview then
        if ns.ShowReadyCheck then ns.ShowReadyCheck() end
    else
        local rc = _G.PallyPulseReadyCheck
        if rc then rc:Hide() end
    end
end

function ns.TogglePreview() ns.SetPreview(not ns.preview) end
