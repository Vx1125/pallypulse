local ADDON, ns = ...

-- scale = the bar, winScale = the main window, rcScale = the ready check window
function ns.WinScale() return ns.db.winScale or ns.db.scale or 1 end
function ns.RCScale() return ns.db.rcScale or ns.WinScale() end

function ns.ApplyScale()
    if ns.bar then ns.bar:SetScale(ns.db.scale) end
    if ns.win then ns.win:SetScale(ns.WinScale()) end
    local rc = _G.PallyPulseReadyCheck
    if rc then rc:SetScale(ns.RCScale()) end
end

-- Called once from Core on PLAYER_LOGIN, after saved variables are ready.
function ns.BuildUI()
    ns.BuildBar()
    ns.BuildWindow()
    ns.BuildMinimap()
    ns.dirty = true
end
