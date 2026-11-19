local ADDON, ns = ...

-- scale = the bar, winScale = the main window, rcScale = the ready check window
function ns.WinScale() return ns.db.winScale or ns.db.scale or 1 end
function ns.RCScale() return ns.db.rcScale or ns.WinScale() end

-- Change a frame's scale without moving it: its top left corner stays where it is on screen.
local function Rescale(f, scale, key)
    if not f or math.abs((f:GetScale() or 1) - scale) < 0.001 then return end
    local l, t = f:GetLeft(), f:GetTop()
    if not l or (InCombatLockdown() and f:IsProtected()) then f:SetScale(scale) return end
    local k = f:GetScale() / scale
    f:SetScale(scale)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l * k, t * k)
    if key then ns.W.SavePos(f, key) end
end

function ns.ApplyScale()
    Rescale(ns.bar, ns.db.scale, "bar")
    Rescale(ns.win, ns.WinScale(), "win")
    Rescale(_G.PallyPulseReadyCheck, ns.RCScale(), "ready")
    if ns.bar then ns.dirty = true end
end

-- Called once from Core on PLAYER_LOGIN, after saved variables are ready.
function ns.BuildUI()
    ns.BuildBar()
    ns.BuildWindow()
    ns.BuildMinimap()
    ns.dirty = true
end

-- ---------------------------------------------------------------------------
-- /pulse debug cpu: time spent in PallyPulse's main refreshes since login (or since the
-- last report), plus memory.
-- ---------------------------------------------------------------------------
local prof, since = {}, GetTime()
local function Wrap(name)
    local fn = ns[name]
    if type(fn) ~= "function" then return end
    local p = { calls = 0, ms = 0, max = 0 }
    prof[name] = p
    ns[name] = function(...)
        local t0 = debugprofilestop()
        local a, b, c, d = fn(...)
        local dt = debugprofilestop() - t0
        p.calls, p.ms = p.calls + 1, p.ms + dt
        if dt > p.max then p.max = dt end
        return a, b, c, d
    end
end
for _, name in ipairs({ "RefreshBar", "RefreshFrameIcons", "RefreshWindow", "RefreshReadyCheck", "QueueSmart", "ScanRoster" }) do
    Wrap(name)
end

function ns.ProfileReport()
    local secs = math.max(1, GetTime() - since)
    ns.Print(("CPU over %ds:"):format(secs))
    local total = 0
    for name, p in pairs(prof) do
        total = total + p.ms
        if p.calls > 0 then
            ns.Print(("  %s: %d calls, %.2f ms avg, %.1f ms max, %.2f ms/s"):format(name, p.calls, p.ms / p.calls, p.max, p.ms / secs))
        end
        p.calls, p.ms, p.max = 0, 0, 0
    end
    ns.Print(("  Total: %.2f ms/s"):format(total / secs))
    if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
        UpdateAddOnMemoryUsage()
        ns.Print(("  Memory: %.0f KB"):format(GetAddOnMemoryUsage(ADDON)))
    end
    since = GetTime()
end
