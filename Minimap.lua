local ADDON, ns = ...
local S, W = ns.STYLE, ns.W

local btn
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function Place()
    local a = math.rad(ns.db.minimapAngle or 200)
    local r = (Minimap:GetWidth() / 2) + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", r * math.cos(a), r * math.sin(a))
end

function ns.UpdateMinimap()
    if not btn then return end
    btn:SetShown(ns.db.showMinimap and true or false)
end

function ns.BuildMinimap()
    btn = CreateFrame("Button", "PallyPulseMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\Spell_Magic_MageArmor")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    btn:SetScript("OnClick", function(_, b)
        if b == "RightButton" then ns.ToggleBar() else ns.ToggleWindow() end
    end)

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            ns.db.minimapAngle = math.deg(atan2(py - my, px - mx))
            Place()
        end)
    end)
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("PallyPulse", unpack(S.accent))
        GameTooltip:AddLine("Left-click: assignments", 0.8, 0.8, 0.85)
        GameTooltip:AddLine("Right-click: show / hide buff bar", 0.8, 0.8, 0.85)
        GameTooltip:AddLine("Drag: move this button", 0.55, 0.58, 0.65)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    Place()
    ns.UpdateMinimap()
end
