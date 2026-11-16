local ADDON, ns = ...

-- Version list: who in the group runs PallyPulse (and which version), PallyPower, or neither.
-- Also: reagent count, and a one-time warning about the game's Auto Self Cast setting.

local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
ns.VERSION = (GetMeta and GetMeta(ADDON, "Version")) or "?"

ns.versions = {}   -- name -> { addon = "PallyPulse" | "PallyPower", ver = "1.0.0", t = GetTime() }
local newerSeen

local function Parse(v)
    local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.?(%d*)")
    return (tonumber(a) or 0) * 10000 + (tonumber(b) or 0) * 100 + (tonumber(c) or 0)
end

function ns.NoteAddon(name, addon, ver)
    if not name then return end
    local cur = ns.versions[name]
    -- PallyPulse also speaks PallyPower's protocol, so never downgrade a known PallyPulse user
    if cur and cur.addon == "PallyPulse" and addon ~= "PallyPulse" then cur.t = GetTime() return end
    ns.versions[name] = { addon = addon, ver = ver, t = GetTime() }
    if addon == "PallyPulse" and ver and Parse(ver) > Parse(ns.VERSION) and newerSeen ~= ver then
        newerSeen = ver
        ns.Print(("New version available: %s"):format(ver))
    end
    if ns.RefreshWindow then ns.RefreshWindow() end
end

ns.comm["V"] = function(sender, ver) ns.NoteAddon(sender, "PallyPulse", ver) end
ns.comm["VQ"] = function(sender) ns.Send("V|" .. ns.VERSION) end

table.insert(ns.syncHooks, function() ns.Send("V|" .. ns.VERSION) end)

function ns.RequestVersions()
    ns.versions[ns.Me()] = { addon = "PallyPulse", ver = ns.VERSION, t = GetTime() }
    ns.Send("VQ")
    ns.Send("V|" .. ns.VERSION)
    if ns.CompatRequest then ns.CompatRequest(true) end
end

-- Rows for the Group tab: every group member with what they run.
function ns.VersionRows()
    local rows = {}
    local me = ns.Me()
    for _, e in ipairs(ns.roster) do
        local v = ns.versions[e.name]
        if e.name == me then v = { addon = "PallyPulse", ver = ns.VERSION } end
        rows[#rows + 1] = { name = e.name, class = e.class, addon = v and v.addon, ver = v and v.ver }
    end
    table.sort(rows, function(a, b)
        if (a.class == "PALADIN") ~= (b.class == "PALADIN") then return a.class == "PALADIN" end
        return a.name < b.name
    end)
    return rows
end

function ns.PrintVersions()
    for _, r in ipairs(ns.VersionRows()) do
        ns.Print(("%s: %s"):format(r.name, r.addon and (r.addon .. (r.ver and (" " .. r.ver) or "")) or "-"))
    end
end

-- ---------------------------------------------------------------------------
-- Reagents
-- ---------------------------------------------------------------------------
function ns.ReagentCount()
    local n
    pcall(function()
        if C_Item and C_Item.GetItemCount then n = C_Item.GetItemCount(ns.REAGENT.id)
        elseif GetItemCount then n = GetItemCount(ns.REAGENT.id) end
    end)
    return n
end

-- Only meaningful once you know a Greater Blessing.
function ns.KnowsAnyGreater()
    for _, b in ipairs(ns.BLESSINGS) do
        if ns.KnownSpell(b.greater, b.greaterId, true) then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Auto Self Cast warning
-- ---------------------------------------------------------------------------
local function AutoSelfCastOn()
    local on
    pcall(function()
        if C_CVar and C_CVar.GetCVarBool then on = C_CVar.GetCVarBool("autoSelfCast")
        elseif GetCVarBool then on = GetCVarBool("autoSelfCast") end
    end)
    return on
end
ns.AutoSelfCastOn = AutoSelfCastOn

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    local function check()
        if ns.db and not ns.db.selfCastWarned and AutoSelfCastOn() then
            ns.Print("Auto Self Cast is on: out-of-range blessings land on you.")
            ns.db.selfCastWarned = true
        end
        ns.RequestVersions()
    end
    if C_Timer and C_Timer.After then C_Timer.After(8, check) else check() end
end)
