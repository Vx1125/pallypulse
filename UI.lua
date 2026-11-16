local ADDON, ns = ...

function ns.ApplyScale()
    if ns.bar then ns.bar:SetScale(ns.db.scale) end
    if ns.win then ns.win:SetScale(ns.db.scale) end
end

-- Called once from Core on PLAYER_LOGIN, after saved variables are ready.
function ns.BuildUI()
    ns.BuildBar()
    ns.BuildWindow()
    ns.BuildMinimap()
    ns.dirty = true
    ns.Print(("v%s loaded. /pulse opens the window, or click the minimap button."):format(ns.VERSION or "?"))
end
