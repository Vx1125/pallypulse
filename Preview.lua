local ADDON, ns = ...

-- Preview mode (/pulse preview, or Options): adds a pretend raid to the roster so the bar,
-- the Blessings and Players tabs and the ready check window can be checked while solo.
-- The pretend players have made-up buffs; nothing is ever cast on them. Not saved: a
-- /reload turns it off.

local PREFIX = "pulsepreview"

-- name, class, your blessing on them ("ok" / "low" / "missing"), other blessings they have,
-- raid buffs, ready status, dead
local FAKES = {
    { "Brannock",  "WARRIOR", "ok",      { "MIGHT", "LIGHT" },  { "FORT", "MOTW", "FOOD", "FLASK" }, "ready" },
    { "Hrodgar",   "WARRIOR", "missing", { "MIGHT" },           { "FORT", "MOTW", "FOOD" },          "ready" },
    { "Vexa",      "ROGUE",   "low",     { "MIGHT", "LIGHT" },  { "FORT", "MOTW", "FOOD" },          "waiting" },
    { "Talonis",   "HUNTER",  "ok",      { "MIGHT" },           { "FORT", "INT" },                   "ready" },
    { "Ilyndra",   "MAGE",    "missing", { "WISDOM", "LIGHT" }, { "FORT", "MOTW", "INT", "FLASK" },  "ready" },
    { "Corvin",    "MAGE",    "ok",      { "WISDOM" },          { "FORT", "INT", "FOOD" },           "notready" },
    { "Morwen",    "WARLOCK", "low",     { "WISDOM", "LIGHT" }, { "FORT", "MOTW", "INT" },           "waiting" },
    { "Sorrel",    "PRIEST",  "ok",      { "WISDOM", "LIGHT" }, { "FORT", "MOTW", "INT", "SPIRIT", "FOOD" }, "ready" },
    { "Ansel",     "PRIEST",  "missing", { "WISDOM" },          { "FORT", "INT", "SPIRIT" },         "ready", true },
    { "Mirelle",   "DRUID",   "ok",      { "WISDOM" },          { "FORT", "MOTW", "INT", "FLASK" },  "ready" },
    { "Thrallbek", "SHAMAN",  "missing", { "WISDOM" },          { "FORT", "MOTW", "INT" },           "waiting" },
    { "Grokka",    "SHAMAN",  "ok",      { "MIGHT", "LIGHT" },  { "FORT", "MOTW", "FOOD" },          "ready" },
}

local RAID_NAMES = {
    FORT = "Prayer of Fortitude", MOTW = "Gift of the Wild", INT = "Arcane Brilliance",
    SPIRIT = "Prayer of Spirit", FOOD = "Well Fed", FLASK = "Flask of the Titans",
}

function ns.IsFake(unit)
    return type(unit) == "string" and unit:sub(1, #PREFIX) == PREFIX
end

local function AddFakes()
    for i, f in ipairs(FAKES) do
        local e = {
            unit = PREFIX .. i, name = f[1], class = f[2], fake = true,
            state = f[3], others = f[4], raid = f[5], ready = f[6], dead = f[7],
        }
        ns.roster[#ns.roster + 1] = e
        ns.byClass[e.class] = ns.byClass[e.class] or {}
        table.insert(ns.byClass[e.class], e)
    end
end

-- Buff names on a pretend player, the way the ready check window reads them.
function ns.PreviewBuffs(e)
    local have = {}
    for _, k in ipairs(e.others or {}) do
        local b = ns.BY_KEY[k]
        if b then have[b.single] = b.icon end
    end
    local mine = ns.KeyFor(ns.Me(), e)
    if mine and ns.BY_KEY[mine] and e.state ~= "missing" and not e.dead then
        have[ns.BY_KEY[mine].single] = ns.BY_KEY[mine].icon
    end
    for _, r in ipairs(e.raid or {}) do have[RAID_NAMES[r]] = true end
    return have
end

-- Pretend paladins for the ready check window: Liadra gives Light to everyone, Tomas gives
-- Might to melee and Wisdom to everyone else.
local MELEE = { WARRIOR = true, ROGUE = true, HUNTER = true }
function ns.PreviewOwed(e)
    local owe = { LIGHT = "Liadra" }
    if MELEE[e.class] or e.name == "Grokka" then owe.MIGHT = "Tomas" else owe.WISDOM = "Tomas" end
    return owe
end

-- wrap the roster and status functions
local origScan = ns.ScanRoster
function ns.ScanRoster(...)
    origScan(...)
    if ns.preview then AddFakes() end
end

local origEligible = ns.Eligible
function ns.Eligible(e)
    if e and e.fake then return not e.dead end
    return origEligible(e)
end

local origRemaining = ns.MemberRemaining
function ns.MemberRemaining(e, key)
    if e and e.fake then
        if e.dead then return nil end
        local mine = ns.KeyFor(ns.Me(), e)
        if key == mine then
            if e.state == "ok" then return 50 * 60 end
            if e.state == "low" then return 2 * 60 end
            return nil
        end
        for _, k in ipairs(e.others or {}) do if k == key then return 45 * 60 end end
        return nil
    end
    return origRemaining(e, key)
end

-- never cast on a pretend player: clear any click that would
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
    ns.ScanRoster()
    if ns.AutoOverrides then ns.AutoOverrides() end
    ns.dirty = true
    if ns.RefreshWindow then pcall(ns.RefreshWindow) end
    if ns.RefreshOptions then pcall(ns.RefreshOptions) end   -- keep the Options checkbox in step
    if ns.preview then
        if ns.ShowReadyCheck then ns.ShowReadyCheck() end    -- show the ready check window filled in
    else
        local rc = _G.PallyPulseReadyCheck
        if rc then rc:Hide() end
    end
end

function ns.TogglePreview() ns.SetPreview(not ns.preview) end
