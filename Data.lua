local ADDON, ns = ...

-- Everything game-specific lives here so it is easy to tweak for WoW Forever.
-- Spell names are matched in English. Edit the strings below for other locales.

ns.CLASSES = {
    "WARRIOR", "ROGUE", "HUNTER", "MAGE", "WARLOCK",
    "PRIEST", "DRUID", "SHAMAN", "PALADIN",
}

local ICON = "Interface\\Icons\\"

-- key         : internal id used in saved data and addon messages (keep stable)
-- single      : single-target blessing spell name
-- greater     : class-wide blessing spell name
-- icon        : fixed icon so we can draw other paladins' blessings too
ns.BLESSINGS = {
    { key = "MIGHT",      single = "Blessing of Might",      greater = "Greater Blessing of Might",      icon = ICON .. "Spell_Holy_FistOfJustice" },
    { key = "WISDOM",     single = "Blessing of Wisdom",     greater = "Greater Blessing of Wisdom",     icon = ICON .. "Spell_Holy_SealOfWisdom" },
    { key = "KINGS",      single = "Blessing of Kings",      greater = "Greater Blessing of Kings",      icon = ICON .. "Spell_Magic_MageArmor" },
}

-- Rank-1 spell ids (same ids PallyPower uses): { single, greater }
local IDS = {
    MIGHT     = { 19740, 25782 },
    WISDOM    = { 19742, 25894 },
    KINGS     = { 20217, 25898 },
}
for _, b in ipairs(ns.BLESSINGS) do
    b.singleId, b.greaterId = IDS[b.key][1], IDS[b.key][2]
end

ns.BY_KEY = {}      -- key -> blessing
ns.NAME2KEY = {}    -- buff / spell name -> key
for _, b in ipairs(ns.BLESSINGS) do
    ns.BY_KEY[b.key] = b
    ns.NAME2KEY[b.single] = b.key
    ns.NAME2KEY[b.greater] = b.key
end

-- Preference order per class, used by Auto-assign. First entries win.
ns.PREFS = {
    WARRIOR = { "MIGHT", "KINGS", "WISDOM" },
    ROGUE   = { "MIGHT", "KINGS", "WISDOM" },
    HUNTER  = { "MIGHT", "KINGS", "WISDOM" },
    MAGE    = { "WISDOM", "KINGS", "MIGHT" },
    WARLOCK = { "WISDOM", "KINGS", "MIGHT" },
    PRIEST  = { "WISDOM", "KINGS", "MIGHT" },
    DRUID   = { "WISDOM", "KINGS", "MIGHT" },
    SHAMAN  = { "WISDOM", "KINGS", "MIGHT" },
    PALADIN = { "WISDOM", "KINGS", "MIGHT" },
}

-- Auras. pp = PallyPower's aura number, so aura assignments sync with PallyPower users.
-- Forever reportedly removed Retribution and Sanctity Aura; they stay listed but only show up
-- for a paladin who actually knows them.
ns.AURAS = {
    { key = "DEVOTION",      name = "Devotion Aura",          id = 465,   pp = 1, icon = ICON .. "Spell_Holy_DevotionAura" },
    { key = "RETRIBUTION",   name = "Retribution Aura",       id = 7294,  pp = 2, icon = ICON .. "Spell_Holy_AuraOfLight" },
    { key = "CONCENTRATION", name = "Concentration Aura",     id = 19746, pp = 3, icon = ICON .. "Spell_Holy_MindSooth" },
    { key = "SHADOW",        name = "Shadow Resistance Aura", id = 19876, pp = 4, icon = ICON .. "Spell_Shadow_SealOfKings" },
    { key = "FROST",         name = "Frost Resistance Aura",  id = 19888, pp = 5, icon = ICON .. "Spell_Frost_WizardMark" },
    { key = "FIRE",          name = "Fire Resistance Aura",   id = 19891, pp = 6, icon = ICON .. "Spell_Fire_SealOfFire" },
    { key = "SANCTITY",      name = "Sanctity Aura",          id = 20218, pp = 7, icon = ICON .. "Spell_Holy_MindVision" },
    { key = "CRUSADER",      name = "Crusader Aura",          id = 32223, pp = 8, icon = ICON .. "Spell_Holy_CrusaderAura" },
}
ns.AURA_BY_KEY, ns.AURA_BY_PP = {}, {}
for _, a in ipairs(ns.AURAS) do ns.AURA_BY_KEY[a.key] = a; ns.AURA_BY_PP[a.pp] = a end
-- Auto-assign hands these out in order, one per paladin.
ns.AURA_PREFS = { "DEVOTION", "CONCENTRATION", "RETRIBUTION", "SANCTITY", "FIRE", "FROST", "SHADOW", "CRUSADER" }

ns.RF = { name = "Righteous Fury", id = 25780, icon = ICON .. "Spell_Holy_SealOfFury" }

-- Greater Blessing reagent
ns.REAGENT = { id = 21177, name = "Symbol of Kings" }

ns.FORBEARANCE = "Forbearance"
ns.VIGIL = { name = "Light's Vigil", icon = ICON .. "Spell_Holy_Restoration" }

-- Role guessing (spec-aware assignments). What each kind of player wants, best first.
ns.ROLE_PREFS = {
    TANK   = { "KINGS", "MIGHT", "WISDOM" },
    MELEE  = { "MIGHT", "KINGS", "WISDOM" },
    CASTER = { "WISDOM", "KINGS", "MIGHT" },
    HEALER = { "WISDOM", "KINGS", "MIGHT" },
}
ns.ROLE_LABEL = { TANK = "Tank", MELEE = "Melee", CASTER = "Caster", HEALER = "Healer" }

-- Short "hand" blessings. A paladin can only have one blessing on a player, so casting one of
-- these replaces your normal blessing on them. Smart Buff won't overwrite them while they run,
-- and re-blesses that player first once they end.
ns.HAND = {
    ["Blessing of Freedom"]    = true,
    ["Blessing of Protection"] = true,
    ["Blessing of Sacrifice"]  = true,
}
ns.REBLESS_WINDOW = 120   -- seconds after a hand blessing during which that player is re-blessed first

-- Oath of Light: single target, 5 minutes, one target per paladin.
-- Kept apart from the class blessings; each paladin picks one player for it.
ns.OATH = {
    name     = "Oath of Light",
    icon     = ICON .. "Spell_Holy_HolyBolt",  -- fallback; replaced by the real spell icon at runtime if found
    duration = 300,
    warn     = 60,   -- seconds left before the bar starts warning
}

ns.DEFAULTS = {
    refresh = 300,   -- seconds remaining below which a blessing counts as "needs refresh"
    scale = 1,
    locked = false,
    compat = true,   -- speak PallyPower's "PLPWR" protocol alongside our own
    greaterMin = 2,
    override = {},        -- [paladin][player] = KEY   blessings set by hand for one player
    autoOverride = {},    -- [paladin][player] = KEY   set by spec-aware auto-assign
    requests = {},        -- [player] = { KEY, ... }   from "!bless want" or the Players tab
    roleOverride = {},    -- [player] = ROLE           role set by hand on the Players tab
    auraAssign = {},      -- [paladin] = AURA KEY
    rfReminder = true,    -- put Righteous Fury in Smart Buff while you're marked as tank
    reagentWarn = 20,     -- warn under this many Symbols of Kings (0 = off)
    selfCastWarned = false,
    chatRequests = true,  -- answer "!bless" chat commands
    frameIcons = true,    -- big blessing icons on Blizzard's party / raid frames
    frameIconSize = 22,
    autoOath = true,      -- Oath of Light follows the tank
    collapsed = false,
    showMinimap = true,
    minimapAngle = 200,
    presets = {},    -- [name] = { [slot] = { [CLASS] = KEY } }
    assign = {},     -- [paladin][CLASS] = KEY
    oath = {},       -- [paladin] = target name (Oath of Light)
    pos = {},
}

-- Look: native WoW feel. Dark tooltip-style panels, gold Friz Quadrata headings.
ns.STYLE = {
    font     = (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"),   -- body text, client default
    head     = "Fonts\\FRIZQT__.TTF",                            -- headings
    num      = "Fonts\\ARIALN.TTF",                              -- counts and timers on icons
    bg       = { 0.03, 0.03, 0.04, 0.92 },
    panel    = { 0.09, 0.09, 0.11, 1 },
    cell     = { 0.02, 0.02, 0.03, 0.85 },
    border   = { 0.26, 0.24, 0.20, 1 },     -- dark bronze for icon / cell edges
    frame    = { 0.62, 0.55, 0.42, 1 },     -- panel edge (tooltip border tint)
    gold     = { 1.00, 0.82, 0.00 },        -- Blizzard heading gold
    accent   = { 1.00, 0.82, 0.00 },        -- hover / focus
    paladin  = { 0.96, 0.55, 0.73 },
    text     = { 0.92, 0.90, 0.85 },
    good     = { 0.30, 0.85, 0.40 },
    warn     = { 1.00, 0.70, 0.15 },
    bad      = { 1.00, 0.30, 0.25 },
    dim      = { 0.58, 0.56, 0.52 },
}
