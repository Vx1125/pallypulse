local ADDON, ns = ...

-- Smart Buff: one key casts the next buff you owe.
--
-- Out of combat (live): aura, Righteous Fury, missing Oath, missing blessings, Oath under a
-- minute, then blessings inside the refresh window. Out-of-range players are skipped. With
-- nothing to do the key refreshes Oath.
--
-- In combat addons can't read buffs or pick targets, so the list is frozen at the pull and a
-- secure snippet steps through it. After the list: re-bless a friendly target, else Oath.
-- Right-click casts Oath.

local recent = {}          -- "name|KEY" -> GetTime() of a successful cast
local RECENT_WINDOW = 3    -- seconds a fresh cast counts as applied before its aura shows up
local MAX_QUEUE = 40
local pending              -- what the last out-of-combat click was going to cast

function ns.RecentlyCast(name, key)
    local t = recent[name .. "|" .. key]
    return t and (GetTime() - t) < RECENT_WINDOW
end

local function MarkCast(name, key)
    recent[name .. "|" .. key] = GetTime()
end

-- true / false, or nil when the client can't tell (treated as "maybe in range").
function ns.InRange(spell, unit)
    local r
    local ok = pcall(function()
        if C_Spell and C_Spell.IsSpellInRange then
            r = C_Spell.IsSpellInRange(spell, unit)
        elseif IsSpellInRange then
            local v = IsSpellInRange(spell, unit)
            if v == 1 then r = true elseif v == 0 then r = false end
        end
    end)
    if not ok or not ns.Readable(r) then return nil end
    return r
end

local function FirstName(name) return (name and name:match("^(%S+)")) or name end
ns.FirstName = FirstName

-- Every buff you owe right now, most urgent first. Each job:
-- { spell, unit, name, key, class, greater, icon, label, remaining, score, near }
-- plus stats { missing, expiring, far }.
function ns.Candidates()
    local me = ns.Me()
    local row = ns.assign[me] or {}
    local thresh = ns.db.refresh
    local stats = { missing = 0, expiring = 0, far = 0, held = 0 }
    local jobs = {}

    local function add(score, job)
        job.score = score
        job.near = (ns.preview and ns.IsFake and ns.IsFake(job.unit))
            or (ns.SafeUnit(UnitIsVisible, job.unit, true) and ns.InRange(job.spell, job.unit) ~= false)
        if not job.near then stats.far = stats.far + 1 end
        jobs[#jobs + 1] = job
    end

    -- Oath of Light
    if ns.oathCap[me] then
        local ounit, oleft = ns.OathStatus()
        local tname = ns.oath[me]
        if ounit and not ns.SafeUnit(UnitIsDeadOrGhost, ounit, false) and not ns.RecentlyCast(tname, "OATH") then
            local job = {
                spell = ns.OATH.name, unit = ounit, name = tname, key = "OATH",
                icon = ns.OathIcon(), label = "Oath of Light", remaining = oleft,
            }
            if not oleft then
                stats.missing = stats.missing + 1
                add(0, job)
            elseif oleft < ns.OATH.warn then
                stats.expiring = stats.expiring + 1
                add(2e6 + oleft, job)
            end
        end
    end

    -- Your aura, then Righteous Fury (tanking), before any blessings
    local akey, aon, aknown = ns.AuraStatus()
    if akey and aknown and not aon then
        local a = ns.AURA_BY_KEY[akey]
        stats.missing = stats.missing + 1
        add(-20, { spell = a.name, unit = "player", name = me, key = "AURA", icon = a.icon,
                   label = a.name })
    end
    local needRF, rfOn = ns.RFStatus()
    if needRF and not rfOn then
        stats.missing = stats.missing + 1
        add(-10, { spell = ns.RF.name, unit = "player", name = me, key = "RF", icon = ns.RF.icon,
                   label = "Righteous Fury" })
    end

    -- Blessings, player by player. Usually the class blessing; a player with an exception gets
    -- theirs. A Greater Blessing would overwrite those exceptions, so a class that has any
    -- uses normal blessings.
    for ci, class in ipairs(ns.CLASSES) do
        local list = ns.byClass[class]
        local classKey = row[class]
        local classException = false
        for _, e in ipairs(list or {}) do
            if ns.IsException(me, e) then classException = true break end
        end
        for ri, e in ipairs(list or {}) do
            local key = ns.KeyFor(me, e)
            if key and ns.BY_KEY[key] then
                local spell, single = ns.CastNames(key, class)
                if classException or key ~= classKey then spell = single or spell end
                local b = ns.BY_KEY[key]
                local label = b.single:gsub("^Blessing of ", "")
                local greater = spell and spell ~= single
                if spell and ns.Eligible(e) then
                    local left = ns.MemberRemaining(e, key)
                    local hand = ns.HandActive(e.unit)
                    local job = {
                        spell = spell, unit = e.unit, name = e.name, key = key, class = class,
                        greater = greater, icon = b.icon, remaining = left, label = label,
                    }
                    -- only when the normal blessing is actually gone (if both can coexist, nothing to do)
                    if not left and (hand or ns.RecentlyFreed(e.name)) then
                        -- Their blessing was replaced by your Freedom/Protection/Sacrifice.
                        -- Put it back first; pressing the key overwrites a hand blessing that is
                        -- still running (that's intended: you choose when by pressing).
                        if hand then stats.held = stats.held + 1 end
                        job.rebless = true
                        stats.missing = stats.missing + 1
                        add(5e5 + ri, job)
                    elseif not left then
                        stats.missing = stats.missing + 1
                        -- yourself first among the missing, then class order
                        local selfFirst = (e.name == me) and -1000 or 0
                        add(1e6 + selfFirst + ci * 100 + ri, job)
                    elseif left < thresh then
                        stats.expiring = stats.expiring + 1
                        add(3e6 + left, job)
                    end
                end
            end
        end
    end

    table.sort(jobs, function(a, b) return a.score < b.score end)
    return jobs, stats
end

-- The single best cast right now (in range only).
function ns.NextBuff()
    local jobs, stats = ns.Candidates()
    for _, job in ipairs(jobs) do
        if job.near then return job, stats end
    end
    return nil, stats
end

-- ---------------------------------------------------------------------------
-- Secure button wiring (the button itself is created by the bar)
-- ---------------------------------------------------------------------------
local function SetOathAttributes(btn)
    local me = ns.Me()
    local target = ns.oath[me]
    local unit = ns.oathCap[me] and target and ns.UnitForName(target)
    btn:SetAttribute("type2", unit and "spell" or nil)
    btn:SetAttribute("spell2", unit and ns.OATH.name or nil)
    btn:SetAttribute("unit2", unit or nil)
    btn:SetAttribute("oath-u", unit or nil)
    btn:SetAttribute("oath-s", unit and ns.OATH.name or nil)

    -- Alt + key: your own class's blessing on yourself (WoW's usual self-cast modifier).
    -- The secure template uses "alt-" attributes while Alt is held, so this works in combat too.
    local _, myClass = UnitClass("player")
    local meEntry = { name = me, class = myClass, unit = "player" }
    local key = ns.KeyFor(me, meEntry)
    local self_spell
    if key and ns.BY_KEY[key] then
        local _, single = ns.CastNames(key, myClass)
        self_spell = single
    end
    btn:SetAttribute("alt-type1", self_spell and "spell" or nil)
    btn:SetAttribute("alt-spell1", self_spell)
    btn:SetAttribute("alt-unit1", self_spell and "player" or nil)
    ns.selfSpell = self_spell
    return unit, target
end

function ns.QueueSmart()
    local btn = ns.smartBtn
    if not btn or InCombatLockdown() then return end
    btn:SetAttribute("cq-on", nil)        -- live mode: the secure snippet stays out of the way
    btn.combatQueue = nil
    local job, stats = ns.NextBuff()
    btn.stats = stats
    local ounit = SetOathAttributes(btn)
    if job then
        btn:SetAttribute("type1", "spell")
        btn:SetAttribute("spell1", job.spell)
        btn:SetAttribute("unit1", job.unit)
    elseif ounit then
        -- nothing else to cast: the key refreshes Oath of Light (same as in combat)
        btn:SetAttribute("type1", "spell")
        btn:SetAttribute("spell1", ns.OATH.name)
        btn:SetAttribute("unit1", ounit)
    else
        btn:SetAttribute("type1", nil)
        btn:SetAttribute("spell1", nil)
        btn:SetAttribute("unit1", nil)
    end
    btn.job = job
end

-- PLAYER_REGEN_DISABLED: the last moment attributes can be set from normal addon code.
-- Freeze the queue into the button for the secure snippet to step through in combat.
function ns.ArmCombatQueue()
    local btn = ns.smartBtn
    if not btn or InCombatLockdown() then return end
    -- No fresh scan here: auras may already be hidden as combat starts. The last out-of-combat
    -- reads (plus the remembered expiries) are the trustworthy picture of who is missing what.

    -- old entries
    local oldN = btn:GetAttribute("cq-n") or 0
    for i = 1, oldN do
        btn:SetAttribute("cq-u" .. i, nil); btn:SetAttribute("cq-s" .. i, nil)
    end

    -- Only players with the blessing *missing* go in: refreshing a blessing that still has
    -- minutes left isn't worth a GCD mid-fight. Oath is handled separately (right-click /
    -- fallback). A greater blessing covers a whole class, so one entry per class is enough.
    local jobs = ns.Candidates()
    local queue, seenClass = {}, {}
    for _, job in ipairs(jobs) do
        -- job.near: visible and in spell range right now. There is no range check inside
        -- protected code, so anyone out of range at the pull is left for after combat.
        if job.key ~= "OATH" and job.remaining == nil and job.near and #queue < MAX_QUEUE then
            if not job.greater or not seenClass[job.class] then
                if job.greater then seenClass[job.class] = true end
                queue[#queue + 1] = job
            end
        end
    end
    for i, job in ipairs(queue) do
        btn:SetAttribute("cq-u" .. i, job.unit)
        btn:SetAttribute("cq-s" .. i, job.spell)
    end
    btn:SetAttribute("cq-n", #queue)
    btn:SetAttribute("cq-i", 1)
    btn:SetAttribute("cq-cur", nil); btn:SetAttribute("cq-t", nil)

    -- Which click edge actually casts (key down by default on modern clients).
    local castDown = true
    pcall(function()
        if C_CVar and C_CVar.GetCVarBool then castDown = C_CVar.GetCVarBool("ActionButtonUseKeyDown")
        elseif GetCVarBool then castDown = GetCVarBool("ActionButtonUseKeyDown") end
    end)
    btn:SetAttribute("castdown", castDown and true or false)

    -- Re-bless map for the snippet: every group member's unit, GUID and name, and the blessing
    -- you give them, plus one blessing per class where the whole class gets the same one.
    -- Used to re-bless your friendly target (e.g. after Blessing of Protection replaced their
    -- Might).
    local oldR = btn:GetAttribute("rb-n") or 0
    for i = 1, oldR do
        btn:SetAttribute("rb-u" .. i, nil); btn:SetAttribute("rb-s" .. i, nil)
        btn:SetAttribute("rb-g" .. i, nil); btn:SetAttribute("rb-nm" .. i, nil)
    end
    for _, c in ipairs(ns.CLASSES) do btn:SetAttribute("rc-" .. c, nil) end
    local rn, distinct, nDistinct, onlySpell = 0, {}, 0, nil
    local byClass = {}          -- class -> its one spell, or false when players differ
    for _, e in ipairs(ns.roster) do
        local key = ns.KeyFor(ns.Me(), e)
        if key and ns.BY_KEY[key] then
            local _, single = ns.CastNames(key, e.class)
            if single then
                rn = rn + 1
                btn:SetAttribute("rb-u" .. rn, e.unit)
                btn:SetAttribute("rb-s" .. rn, single)
                local g, nm
                pcall(function() g = UnitGUID(e.unit); nm = UnitName(e.unit) end)
                if ns.Readable(g) then btn:SetAttribute("rb-g" .. rn, g) end
                if ns.Readable(nm) then btn:SetAttribute("rb-nm" .. rn, nm) end
                if not distinct[single] then distinct[single] = true; nDistinct = nDistinct + 1; onlySpell = single end
                if byClass[e.class] == nil then byClass[e.class] = single
                elseif byClass[e.class] ~= single then byClass[e.class] = false end
            end
        end
    end
    for c, sp in pairs(byClass) do if sp then btn:SetAttribute("rc-" .. c, sp) end end
    btn:SetAttribute("rb-n", rn)
    btn:SetAttribute("rb-one", nDistinct == 1 and onlySpell or nil)   -- used if the client can't match units

    local ounit = SetOathAttributes(btn)
    -- Pre-load the first press so it works even before the snippet has run once.
    local first = queue[1]
    btn:SetAttribute("type1", (first or ounit) and "spell" or nil)
    btn:SetAttribute("spell1", first and first.spell or (ounit and ns.OATH.name) or nil)
    btn:SetAttribute("unit1", first and first.unit or ounit or nil)

    btn.combatQueue = queue
    if ns.trace then
        ns.Print(("|cffffff00trace|r combat start: %d in queue, same-blessing fallback=%s, self (Alt)=%s"):format(
            #queue, tostring(btn:GetAttribute("rb-one")), tostring(ns.selfSpell)))
        for i, job in ipairs(queue) do
            ns.Print(("|cffffff00trace|r   %d. %s -> %s (%s)"):format(i, job.spell, job.unit, job.name))
        end
    end
    btn:SetAttribute("cq-on", true)
end

-- Kept for older callers.
ns.DisarmSmart = ns.ArmCombatQueue

-- Runs inside Blizzard's protected code on every click, in or out of combat.
-- Out of combat "cq-on" is unset and it does nothing (the live queue is used instead).
local SNIPPET = [=[
    if not self:GetAttribute("cq-on") then return end
    if button ~= "LeftButton" then return end
    if IsAltKeyDown and IsAltKeyDown() then return end   -- Alt = self-cast, handled by alt- attributes
    if down ~= nil and down ~= self:GetAttribute("castdown") then return end

    -- 1. A friendly target: cast the blessing you're assigned to give *them*
    --    (target yourself to re-bless yourself, e.g. after Freedom).
    if SecureCmdOptionParse("[@target,help,nodead] 1") then
        -- Match the target to a group member with whatever this client allows here.
        local s
        local m = self:GetAttribute("rb-n") or 0
        if UnitIsUnit then
            for k = 1, m do
                local u = self:GetAttribute("rb-u" .. k)
                if u and UnitIsUnit("target", u) then s = self:GetAttribute("rb-s" .. k) break end
            end
        elseif UnitGUID then
            local g = UnitGUID("target")
            for k = 1, m do
                if g and self:GetAttribute("rb-g" .. k) == g then s = self:GetAttribute("rb-s" .. k) break end
            end
        elseif UnitName then
            local nm = UnitName("target")
            for k = 1, m do
                if nm and self:GetAttribute("rb-nm" .. k) == nm then s = self:GetAttribute("rb-s" .. k) break end
            end
        end
        if not s and UnitClass then
            local _, c = UnitClass("target")
            if c then s = self:GetAttribute("rc-" .. c) end
        end
        if not s then s = self:GetAttribute("rb-one") end
        if s then
            self:SetAttribute("type1", "spell")
            self:SetAttribute("spell1", s)
            self:SetAttribute("unit1", "target")
            return
        end
    end

    -- 2. No friendly target (e.g. you're targeting a mob): anyone missing a blessing at the pull.
    local n = self:GetAttribute("cq-n") or 0
    local i = self:GetAttribute("cq-i") or 1

    -- Protected code can't see whether a cast worked, so the queue moves on with each press.
    -- A press during the global cooldown fails, and would skip that player. Within 1.5 s of
    -- the last queue cast, press the same entry again instead of moving on.
    local now = GetTime and GetTime()
    local cur, last = self:GetAttribute("cq-cur"), self:GetAttribute("cq-t")
    if now and cur and last and now - last < 1.5 then
        local u = self:GetAttribute("cq-u" .. cur)
        if u and UnitExists(u) then
            self:SetAttribute("type1", "spell")
            self:SetAttribute("spell1", self:GetAttribute("cq-s" .. cur))
            self:SetAttribute("unit1", u)
            return
        end
    end

    while i <= n do
        local u = self:GetAttribute("cq-u" .. i)
        local s = self:GetAttribute("cq-s" .. i)
        i = i + 1
        if u and UnitExists(u) and not (UnitIsDead and UnitIsDead(u)) and not (UnitIsGhost and UnitIsGhost(u)) then
            self:SetAttribute("cq-i", i)
            self:SetAttribute("cq-cur", i - 1)
            if now then self:SetAttribute("cq-t", now) end
            self:SetAttribute("type1", "spell")
            self:SetAttribute("spell1", s)
            self:SetAttribute("unit1", u)
            return
        end
    end
    self:SetAttribute("cq-i", n + 1)

    -- 3. Nothing else to do: Oath of Light on your Oath target.
    local ou = self:GetAttribute("oath-u")
    if ou then
        self:SetAttribute("type1", "spell")
        self:SetAttribute("spell1", self:GetAttribute("oath-s"))
        self:SetAttribute("unit1", ou)
    else
        self:SetAttribute("type1", nil)
    end
]=]

function ns.WireSmart(btn)
    ns.smartBtn = btn
    btn:SetScript("PreClick", function(self)
        if InCombatLockdown() then return end
        if ns.BeginScan then ns.BeginScan() end   -- fresh aura data for the click
        ns.QueueSmart()
        if self.job then pending = { job = self.job, t = GetTime() } end
    end)
    -- PostClick runs after the cast attempt; attributes can still be *read* in combat, so the
    -- trace shows exactly which spell and unit the press used.
    btn:SetScript("PostClick", function(self, button, down)
        ns.dirty = true
        -- only the edge that actually casts (key down on most setups)
        local castDown = self:GetAttribute("castdown")
        if castDown == nil then castDown = true end
        if ns.trace and (down == nil or down == castDown) then
            local mods = (IsAltKeyDown() and "alt-" or "") .. (IsControlKeyDown() and "ctrl-" or "") .. (IsShiftKeyDown() and "shift-" or "")
            local sfx = (button == "RightButton") and "2" or "1"
            local spell = self:GetAttribute(mods .. "spell" .. sfx) or self:GetAttribute("spell" .. sfx)
            local unit = self:GetAttribute(mods .. "unit" .. sfx) or self:GetAttribute("unit" .. sfx)
            local who = unit and (ns.SafeUnit(function(u) return ns.FullName(u) end, unit, nil)) or "?"
            ns.Print(("|cffffff00trace|r %s %s down=%s combat=%s: %s -> %s (%s)"):format(
                button or "?", mods ~= "" and mods or "", tostring(down), tostring(InCombatLockdown()),
                tostring(spell), tostring(unit), tostring(who)))
        end
    end)

    local header
    local ok = pcall(function()
        header = CreateFrame("Frame", "PallyPulseSecureHeader", UIParent, "SecureHandlerBaseTemplate")
        SecureHandlerWrapScript(btn, "OnClick", header, SNIPPET)
    end)
    ns.combatQueueAvailable = ok
    -- Can protected code tell which group member your target is? If not, in-combat re-bless
    -- only works when you give every class the same blessing.
    if ok and header then
        pcall(function()
            header:Execute([[
                self:SetAttribute("rb-how", (UnitIsUnit and "unit") or (UnitGUID and "guid")
                    or (UnitName and "name") or (UnitClass and "class") or "one")
            ]])
            ns.reblessHow = header:GetAttribute("rb-how") or "one"
            ns.reblessExact = ns.reblessHow == "unit" or ns.reblessHow == "guid" or ns.reblessHow == "name"
        end)
    end
    if not ok then ns.Print("Combat queue unavailable.") end
end

-- What the combat queue will cast next (for the bar). Returns job or "oath" or nil, and how many left.
function ns.CombatNext()
    local btn = ns.smartBtn
    if not btn or not btn.combatQueue then return nil, 0 end
    local n = btn:GetAttribute("cq-n") or 0
    local i = btn:GetAttribute("cq-i") or 1
    local q = btn.combatQueue
    -- same order as the snippet: 1. friendly target, 2. queue, 3. Oath
    if ns.SafeUnit(UnitExists, "target", false) and ns.SafeUnit(function(u) return UnitCanAssist("player", u) end, "target", false)
        and not ns.SafeUnit(UnitIsDeadOrGhost, "target", false) then
        local spell
        local m = btn:GetAttribute("rb-n") or 0
        if ns.reblessExact ~= false then
            for k = 1, m do
                local u = btn:GetAttribute("rb-u" .. k)
                if u and ns.SafeUnit(function(x) return UnitIsUnit("target", x) end, u, false) then
                    spell = btn:GetAttribute("rb-s" .. k) break
                end
            end
        end
        if not spell and ns.reblessHow ~= "one" then
            local c = ns.SafeUnit(function(u) return select(2, UnitClass(u)) end, "target", nil)
            if c then spell = btn:GetAttribute("rc-" .. c) end
        end
        if not spell then spell = btn:GetAttribute("rb-one") end
        if spell then
            local key = ns.NAME2KEY[spell]
            return {
                spell = spell, unit = "target", name = ns.FullName("target") or "target",
                icon = key and ns.BY_KEY[key].icon, label = spell:gsub("^Blessing of ", ""),
                combatRebless = true,
            }, 0
        end
    end
    -- the snippet advances on the press, so entry i is the one the next press will try
    for k = i, n do
        local job = q[k]
        if job and not ns.SafeUnit(UnitIsDeadOrGhost, job.unit, false) then
            return job, n - k + 1
        end
    end
    if btn:GetAttribute("oath-u") then return "oath", 0 end
    return nil, 0
end

-- ---------------------------------------------------------------------------
-- Cast confirmation
-- ---------------------------------------------------------------------------
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
watcher:RegisterEvent("UNIT_SPELLCAST_SENT")
local sentTarget = {}   -- spellID -> target name from UNIT_SPELLCAST_SENT
watcher:SetScript("OnEvent", function(_, event, unit, a2, a3, a4)
    if unit ~= "player" then return end
    if event == "UNIT_SPELLCAST_SENT" then
        -- (unit, targetName, castGUID, spellID): remember who a hand blessing is going to
        local target, spellID = a2, a4
        if ns.Readable(target) and ns.Readable(spellID) and type(target) == "string" and target ~= "" then
            sentTarget[spellID] = ns.StripRealm(target)
        end
        return
    end
    local spellID = a3
    if not ns.Readable(spellID) then return end
    local name
    pcall(function()
        if C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(spellID)
        elseif GetSpellInfo then name = GetSpellInfo(spellID) end
    end)
    if not name or not ns.Readable(name) then return end

    -- Freedom / Protection / Sacrifice: that player's normal blessing from you is gone now.
    -- Remember them so Smart Buff puts it back first once the hand blessing ends.
    if ns.HAND[name] then
        local target = sentTarget[spellID]
        sentTarget[spellID] = nil
        if target then
            -- the SENT event may give a first name only; match it to the roster
            for _, e in ipairs(ns.roster) do
                if e.name == target or ns.FirstName(e.name) == target then target = e.name break end
            end
            ns.handCast[target] = GetTime()
            ns.ForgetMember(target)
            ns.InvalidateScan(ns.UnitForName(target))
        end
        ns.dirty = true
    end

    -- Any Oath of Light you cast restarts its timer, even in combat when the aura itself
    -- may be hidden from addons.
    if name == ns.OATH.name then
        local target = ns.oath[ns.Me()]
        if target then
            ns.auraMemory[target .. "|OATH"] = GetTime() + ns.OATH.duration
            MarkCast(target, "OATH")
            ns.dirty = true
        end
    end

    ns.dirty = true
    if not pending or (GetTime() - pending.t) > 2 then return end
    local job = pending.job
    if name ~= job.spell then return end
    pending = nil
    if job.greater and job.class and ns.byClass[job.class] then
        for _, e in ipairs(ns.byClass[job.class]) do MarkCast(e.name, job.key) end
    else
        MarkCast(job.name, job.key)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.3, function() ns.dirty = true; ns.QueueSmart() end)
    end
end)

-- Keybinding labels (Bindings.xml)
BINDING_HEADER_PALLYPULSE = "PallyPulse"
_G["BINDING_NAME_CLICK PallyPulseSmartButton:LeftButton"] = "Smart Buff"
_G["BINDING_NAME_CLICK PallyPulseOathTarget:LeftButton"] = "Oath of Light (Mouseover)"
BINDING_NAME_PALLYPULSE_TOGGLE = "Toggle Window"
function PallyPulse_ToggleWindow() if ns.ToggleWindow then ns.ToggleWindow() end end
