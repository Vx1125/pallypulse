local ADDON, ns = ...
local S, W = ns.STYLE, ns.W

-- Presets are stored by paladin *slot* (you first, then the others alphabetically),
-- not by name, so a layout saved in one group can be loaded in another.

local function Copy(t)
    local c = {}
    for k, v in pairs(t or {}) do c[k] = v end
    return c
end

function ns.SavePreset(name)
    name = strtrim(name or "")
    if name == "" then return end
    local rows = {}
    for i, pal in ipairs(ns.paladins) do rows[i] = Copy(ns.assign[pal]) end
    ns.db.presets[name] = rows
    ns.Print(("Saved preset '%s' (%d paladin row%s)."):format(name, #rows, #rows == 1 and "" or "s"))
end

function ns.LoadPreset(name)
    local rows = ns.db.presets[name]
    if not rows then return end
    local applied = 0
    for i, pal in ipairs(ns.paladins) do
        local row = rows[i]
        if row and ns.CanEditRow(pal) then
            local caps = ns.caps[pal]
            ns.assign[pal] = {}
            for class, key in pairs(row) do
                -- never hand a paladin a blessing they are known not to have
                if ns.BY_KEY[key] and (not caps or caps[key]) then
                    ns.assign[pal][class] = key
                end
            end
            ns.BroadcastRow(pal)
            applied = applied + 1
        end
    end
    ns.dirty = true
    if ns.OnAssignmentsChanged then ns.OnAssignmentsChanged() end
    local extra = #rows > #ns.paladins and (" Preset has %d more row(s) than paladins; extras were ignored."):format(#rows - #ns.paladins) or ""
    ns.Print(("Loaded '%s' onto %d paladin(s).%s"):format(name, applied, extra))
end

function ns.DeletePreset(name)
    ns.db.presets[name] = nil
    ns.Print(("Deleted preset '%s'."):format(name))
end

StaticPopupDialogs["PALLYPULSE_SAVE_PRESET"] = {
    text = "Save current assignments as preset:",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = 1,
    maxLetters = 24,
    OnAccept = function(self)
        local eb = self.editBox or self.EditBox
        ns.SavePreset(eb:GetText())
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        ns.SavePreset(self:GetText())
        parent:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
}

-- ---------------------------------------------------------------------------
-- Popup menu
-- ---------------------------------------------------------------------------
local menu
local ITEM_H, MENU_W = 24, 220

local function SortedNames()
    local names = {}
    for name in pairs(ns.db.presets) do names[#names + 1] = name end
    table.sort(names)
    return names
end

local function GetItem(i)
    local it = menu.items[i]
    if it then return it end
    it = CreateFrame("Frame", nil, menu)
    it:SetSize(MENU_W - 12, ITEM_H)
    it.load = W.Button(it, "", MENU_W - 12 - ITEM_H - 4, ITEM_H, function()
        ns.LoadPreset(it.name); menu:Hide()
    end)
    it.load:SetPoint("LEFT")
    it.load.label:SetJustifyH("LEFT")
    it.load.label:ClearAllPoints(); it.load.label:SetPoint("LEFT", 8, 0); it.load.label:SetPoint("RIGHT", -8, 0)
    it.load.label:SetWordWrap(false)
    it.del = W.Button(it, "x", ITEM_H, ITEM_H, function()
        ns.DeletePreset(it.name); ns.RefreshPresetMenu()
    end)
    it.del:SetPoint("RIGHT")
    W.Tip(it.del, function(t) t:AddLine("Delete preset", 1, 0.5, 0.5) end)
    menu.items[i] = it
    return it
end

function ns.RefreshPresetMenu()
    if not menu then return end
    local names = SortedNames()
    for _, it in ipairs(menu.items) do it:Hide() end
    local y = -8
    for i, name in ipairs(names) do
        local it = GetItem(i)
        it.name = name
        it.load.label:SetText(name)
        it:ClearAllPoints(); it:SetPoint("TOPLEFT", 6, y)
        it:Show()
        y = y - (ITEM_H + 2)
    end
    menu.empty:SetShown(#names == 0)
    if #names == 0 then y = y - 18 end
    menu.save:ClearAllPoints()
    menu.save:SetPoint("TOPLEFT", 6, y - 2)
    menu:SetHeight(-y + ITEM_H + 12)
end

local function Build()
    menu = W.Panel(UIParent, MENU_W, 80)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:Hide()
    menu.items = {}
    menu.empty = W.Text(menu, 11, S.dim, "CENTER")
    menu.empty:SetPoint("TOP", 0, -10); menu.empty:SetWidth(MENU_W - 16)
    menu.empty:SetText("No presets saved yet")
    menu.save = W.Button(menu, "+  Save current...", MENU_W - 12, ITEM_H, function()
        menu:Hide()
        StaticPopup_Show("PALLYPULSE_SAVE_PRESET")
    end, true)
    W.AutoClose(menu)
end

function ns.TogglePresetMenu(anchor)
    if not menu then Build() end
    if menu:IsShown() then menu:Hide() return end
    if ns.HideMenus then ns.HideMenus() end
    menu.anchor = anchor
    menu:ClearAllPoints()
    menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 4)
    ns.RefreshPresetMenu()
    menu:Show()
end

function ns.HidePresetMenu() if menu then menu:Hide() end end
