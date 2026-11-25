local ADDON, ns = ...
local S = ns.STYLE

-- Widget kit. Panels use the client's own tooltip textures and buttons use Blizzard's
-- templates where they exist, so PallyPulse looks like part of the default UI.
local W = {}
ns.W = W

local WHITE = "Interface\\Buttons\\WHITE8x8"
W.WHITE = WHITE
W.QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
W.READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
W.NOTREADY = "Interface\\RaidFrame\\ReadyCheck-NotReady"
W.WAITING = "Interface\\RaidFrame\\ReadyCheck-Waiting"

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

function W.ClassColor(class)
    local c = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

function W.Hex(r, g, b)
    return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

-- ---------------------------------------------------------------------------
-- Look: one theme. Flat panels with 1px bronze edges, plain buttons and boxes. Text registers
-- itself so a font change (Options > Advanced > Font, from LibSharedMedia when another addon
-- has loaded it) applies at once, without a reload.
-- ---------------------------------------------------------------------------
local skinned = { texts = {} }

local EDGE = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } }
W.EDGE = EDGE

-- bg: fill colour (default: the window background)
function W.StylePanel(f, bg)
    if not f.SetBackdrop then return end
    f:SetBackdrop(EDGE)
    f:SetBackdropColor(unpack(bg or S.bg)); f:SetBackdropBorderColor(unpack(S.border))
end

function W.Panel(parent, w, h, name, bg)
    local f = CreateFrame("Frame", name, parent, BACKDROP_TEMPLATE)
    if w then f:SetSize(w, h) end
    W.StylePanel(f, bg)
    return f
end

-- 1px box drawn with textures, for widgets that have no backdrop of their own
local function Box(owner, inset, bg)
    local bx = {}
    bx.bg = owner:CreateTexture(nil, "BACKGROUND", nil, -7)
    bx.bg:SetPoint("TOPLEFT", inset, -inset); bx.bg:SetPoint("BOTTOMRIGHT", -inset, inset)
    bx.bg:SetColorTexture(unpack(bg or S.panel))
    bx.edges = {}
    for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = owner:CreateTexture(nil, "BORDER", nil, 7)
        t:SetColorTexture(unpack(S.border))
        t:SetPoint(pts[1], bx.bg, pts[1]); t:SetPoint(pts[2], bx.bg, pts[2])
        if i <= 2 then t:SetHeight(1) else t:SetWidth(1) end
        bx.edges[i] = t
    end
    function bx:SetShown(on)
        self.bg:SetShown(on)
        for _, t in ipairs(self.edges) do t:SetShown(on) end
    end
    function bx:SetEdge(c)
        for _, t in ipairs(self.edges) do t:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
    end
    return bx
end
W.Box = Box

-- Hide a template's own art (InputBoxTemplate, scroll arrows...)
local function HideArt(f, keys)
    for _, k in ipairs(keys) do
        local t = f[k]
        if t and t.SetAlpha then t:SetAlpha(0) end
    end
end

-- Font for all PallyPulse text: "Default" keeps the game's fonts.
local function FontPaths()
    local name = ns.db and ns.db.font
    if name and name ~= "Default" then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        local path = LSM and LSM:Fetch("font", name, true)
        if path then return path, path, path end
    end
    return S.font, S.head, S.num
end

function W.FontList()
    local out = { { name = "Default" } }
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        for _, n in ipairs(LSM:List("font")) do out[#out + 1] = { name = n } end
    end
    return out
end

-- Re-apply the font everywhere (Options: Font).
function W.ApplyStyle()
    local body, head, num = FontPaths()
    for _, fs in ipairs(skinned.texts) do
        local path = (fs.ppRole == "head" and head) or (fs.ppRole == "num" and num) or body
        pcall(fs.SetFont, fs, path, fs.ppSize, fs.ppFlags)
    end
    if ns.OnStyleChanged then ns.OnStyleChanged() end
    ns.dirty = true
end

function W.Text(parent, size, color, justify, font, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs.ppRole = (font == S.head and "head") or (font == S.num and "num") or "body"
    fs.ppSize, fs.ppFlags = size or 12, flags or ""
    table.insert(skinned.texts, fs)
    local body, head, num = FontPaths()
    local path = (fs.ppRole == "head" and head) or (fs.ppRole == "num" and num) or body
    if font and font ~= S.font and font ~= S.head and font ~= S.num then path = font end
    fs:SetFont(path, fs.ppSize, fs.ppFlags)
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 1)
    local c = color or S.text
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

function W.Heading(parent, size)
    return W.Text(parent, size or 13, S.gold, "LEFT", S.head)
end

-- Section heading with a thin bronze rule under it.
function W.Section(parent, text, w)
    local h = W.Heading(parent, 12)
    h:SetText(text)
    h.rule = parent:CreateTexture(nil, "ARTWORK")
    h.rule:SetHeight(1)
    h.rule:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -3)
    h.rule:SetWidth(w or 228)
    h.rule:SetColorTexture(S.border[1], S.border[2], S.border[3], 0.8)
    return h
end

-- Flat button: panel fill, bronze edge, gold on hover.
function W.Button(parent, label, w, h, onClick)
    local b = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    b:SetSize(w, h)
    if b.SetBackdrop then
        b:SetBackdrop(EDGE)
        b:SetBackdropColor(unpack(S.panel)); b:SetBackdropBorderColor(unpack(S.border))
    end
    local fs = W.Text(b, 11, S.text, "CENTER", S.head)
    fs:SetPoint("LEFT", 4, 0); fs:SetPoint("RIGHT", -4, 0)
    fs:SetWordWrap(false)
    b:SetFontString(fs)
    b.label = fs
    b:SetText(label ~= "" and label or " ")
    pcall(b.SetPushedTextOffset, b, 1, -1)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 1, -1); hl:SetPoint("BOTTOMRIGHT", -1, 1)
    hl:SetColorTexture(S.gold[1], S.gold[2], S.gold[3], 0.08)
    b:HookScript("OnEnter", function(self)
        if not self:IsEnabled() then return end
        if self.SetBackdropBorderColor then self:SetBackdropBorderColor(unpack(S.gold)) end
        if not self.keepColor then self.label:SetTextColor(unpack(S.gold)) end
    end)
    b:HookScript("OnLeave", function(self)
        if self.SetBackdropBorderColor then self:SetBackdropBorderColor(unpack(S.border)) end
        if not self.keepColor then self.label:SetTextColor(unpack(S.text)) end
    end)
    b:HookScript("OnDisable", function(self) self.label:SetTextColor(unpack(S.dim)) end)
    b:HookScript("OnEnable", function(self) self.label:SetTextColor(unpack(S.text)) end)
    if onClick then b:SetScript("OnClick", function(self) onClick(self) end) end
    return b
end

-- Small close "x": dim, gold on hover.
function W.CloseButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    b.t = W.Text(b, 13, S.dim, "CENTER", S.head)
    b.t:SetPoint("CENTER", 0, 1); b.t:SetText("x")
    b:SetScript("OnEnter", function(self) self.t:SetTextColor(unpack(S.gold)) end)
    b:SetScript("OnLeave", function(self) self.t:SetTextColor(unpack(S.dim)) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- Thin scrollbar on a UIPanelScrollFrameTemplate: no arrows, a slim bronze thumb.
-- Every client builds this template a little differently, so each step is optional.
function W.SkinScroll(sf)
    pcall(function()
        local name = sf:GetName()
        local bar = sf.ScrollBar or (name and _G[name .. "ScrollBar"])
        if not bar then return end
        for _, k in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
            local btn = bar[k] or (name and _G[name .. "ScrollBar" .. k])
            if btn then btn:SetAlpha(0); btn:EnableMouse(false); btn:SetSize(1, 1) end
        end
        for _, r in ipairs({ bar:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "Texture" and r ~= bar:GetThumbTexture() then r:SetAlpha(0) end
        end
        if bar.SetThumbTexture then
            bar:SetThumbTexture(WHITE)
            local th = bar:GetThumbTexture()
            th:SetSize(4, 28)
            th:SetVertexColor(S.border[1], S.border[2], S.border[3], 1)
        end
        local track = bar:CreateTexture(nil, "BACKGROUND")
        track:SetPoint("TOP", 0, 0); track:SetPoint("BOTTOM", 0, 0); track:SetWidth(4)
        track:SetColorTexture(0, 0, 0, 0.35)
    end)
end

-- Small square check box (gold mark) with a label. get() -> bool, set(bool)
-- tip (optional): one short line shown on hover
local function AddTip(frame, label, tip)
    if not tip then return end
    W.Tip(frame, function(t)
        t:AddLine(label, 1, 1, 1)
        t:AddLine(tip, S.dim[1], S.dim[2], S.dim[3], true)
    end)
end

function W.Check(parent, label, get, set, tip)
    local c = CreateFrame("CheckButton", nil, parent)
    c:SetSize(24, 24)
    c.box = Box(c, 5)
    c.mark = c:CreateTexture(nil, "OVERLAY")
    c.mark:SetPoint("TOPLEFT", 8, -8); c.mark:SetPoint("BOTTOMRIGHT", -8, 8)
    c.mark:SetColorTexture(S.gold[1], S.gold[2], S.gold[3], 1)
    c.text = W.Text(c, 12, S.text)
    c.text:SetPoint("LEFT", c, "RIGHT", 2, 1)
    c.text:SetText(label)
    c:SetHitRectInsets(0, -200, 0, 0)
    c:SetScript("OnEnter", function(self) self.box:SetEdge(S.gold) end)
    c:SetScript("OnLeave", function(self) self.box:SetEdge(S.border) end)
    AddTip(c, label, tip)
    local function Show(self) self.mark:SetShown(self:GetChecked() and true or false) end
    function c:Refresh() self:SetChecked(get() and true or false); Show(self) end
    c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); Show(self) end)
    c:Refresh()
    return c
end

-- Label with [-] value [+]. get() -> number, set(number)
-- Keybind row: click the button, press a key (with Shift / Ctrl / Alt if you like) to bind it.
-- Escape cancels, right-click clears. Uses the game's own bindings, so it's the same as setting
-- it under Key Bindings > AddOns.
function W.KeyBind(parent, label, command, tip)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(236, 24)
    local txt = W.Text(f, 12, S.text)
    txt:SetPoint("LEFT", 4, 0); txt:SetText(label)
    local b = W.Button(f, "", 96, 20)
    b:SetPoint("RIGHT")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local capturing = false
    local function Save()
        pcall(function() SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 1) end)
    end
    local function ClearAll()
        local keys = { GetBindingKey(command) }
        for _, k in ipairs(keys) do SetBinding(k) end
    end
    local function Stop()
        capturing = false
        b:EnableKeyboard(false)
        b:SetScript("OnKeyDown", nil)
        f:Refresh()
    end
    local function Bind(key)
        ClearAll()
        local mod = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "")
        SetBinding(mod .. key, command)
        Save()
        Stop()
    end

    function f:Refresh()
        if capturing then return end
        local k = GetBindingKey(command)
        b:SetText(k and (GetBindingText and GetBindingText(k, "KEY_") or k) or "Not bound")
    end

    b:SetScript("OnClick", function(_, btn)
        if InCombatLockdown() then return end          -- the game blocks binding changes in combat
        if btn == "RightButton" then
            if capturing then Stop() return end
            ClearAll(); Save(); f:Refresh()
            return
        end
        if capturing then Stop() return end
        capturing = true
        b:SetText("Press a key")
        b:EnableKeyboard(true)
        pcall(b.SetPropagateKeyboardInput, b, false)
        b:SetScript("OnKeyDown", function(_, key)
            if key == "ESCAPE" then Stop() return end
            if key:find("SHIFT$") or key:find("CTRL$") or key:find("ALT$") then return end   -- wait for the real key
            Bind(key)
        end)
    end)
    b:SetScript("OnMouseDown", function(_, btn)
        if not capturing then return end
        local map = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }
        if map[btn] then Bind(map[btn]) end
    end)
    b:SetScript("OnHide", function() if capturing then Stop() end end)

    if tip then f:EnableMouse(true); AddTip(f, label, tip .. " Right-click the key to clear it.") end
    f:Refresh()
    return f
end

-- Dropdown row: a button showing the current choice; click it for a list (mouse wheel scrolls
-- long lists). list() returns { {name=...}, ... }; current() returns the chosen name.
function W.Dropdown(parent, label, list, current, onPick, tip, btnW)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(236, 24)
    local txt = W.Text(f, 12, S.text)
    txt:SetPoint("LEFT", 4, 0); txt:SetText(label)
    local b = W.Button(f, "", btnW or 140, 20)
    b:SetPoint("RIGHT")
    if b.label then b.label:SetWordWrap(false); b.label:SetWidth((btnW or 140) - 22) end
    local arrow = b:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12); arrow:SetPoint("RIGHT", -5, 0)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    arrow:SetRotation(-math.pi / 2)

    local ROWS, RH = 12, 18
    local menu = W.Panel(UIParent, (btnW or 140) + 40, 20)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    menu:Hide()
    menu.anchor = b
    W.AutoClose(menu)
    menu.offset = 0
    menu.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, menu)
        r:SetHeight(RH)
        r:SetPoint("TOPLEFT", 6, -6 - (i - 1) * RH); r:SetPoint("RIGHT", -6, 0)
        r.text = W.Text(r, 11, S.text, "LEFT")
        r.text:SetPoint("LEFT", 4, 0); r.text:SetPoint("RIGHT", -4, 0); r.text:SetWordWrap(false)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.12)
        r:SetScript("OnClick", function(self)
            if self.item then onPick(self.item); menu:Hide(); f:Refresh() end
        end)
        menu.rows[i] = r
    end
    local function Fill()
        local items = list()
        local cur = current()
        local maxOff = math.max(0, #items - ROWS)
        menu.offset = math.max(0, math.min(menu.offset, maxOff))
        local shown = math.min(ROWS, #items)
        for i = 1, ROWS do
            local r, item = menu.rows[i], items[i + menu.offset]
            r.item = item
            if item and i <= shown then
                r.text:SetText(item.name)
                r.text:SetTextColor(unpack(item.name == cur and S.gold or S.text))
                r:Show()
            else
                r:Hide()
            end
        end
        menu:SetHeight(12 + shown * RH)
    end
    menu:EnableMouseWheel(true)
    menu:SetScript("OnMouseWheel", function(_, d) menu.offset = menu.offset - d * 3; Fill() end)
    b:SetScript("OnClick", function()
        if menu:IsShown() then menu:Hide() return end
        -- open scrolled so the current choice is visible
        local items, cur = list(), current()
        for i, item in ipairs(items) do if item.name == cur then menu.offset = i - 3 end end
        menu:SetScale(f:GetEffectiveScale() / UIParent:GetEffectiveScale())
        menu:ClearAllPoints(); menu:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 0, -2)
        Fill(); menu:Show()
    end)
    f:SetScript("OnHide", function() menu:Hide() end)

    function f:Refresh() b:SetText(current() or "") end
    if tip then f:EnableMouse(true); AddTip(f, label, tip) end
    f:Refresh()
    return f
end

function W.Stepper(parent, label, get, set, step, minv, maxv, fmt, tip, valW)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(236, 24)
    if tip then f:EnableMouse(true); AddTip(f, label, tip) end
    local txt = W.Text(f, 12, S.text)
    txt:SetPoint("LEFT", 4, 0); txt:SetText(label)
    local function bump(d)
        local v = math.floor((get() + d * step) * 100 + 0.5) / 100
        v = math.max(minv, math.min(maxv, v))
        set(v); f:Refresh()
    end
    local plus = W.Button(f, "+", 24, 20, function() bump(1) end)
    plus:SetPoint("RIGHT")
    local val = W.Text(f, 12, S.gold, "CENTER", S.head)
    val:SetPoint("RIGHT", plus, "LEFT", -2, 0); val:SetWidth(valW or 52); val:SetWordWrap(false)
    local minus = W.Button(f, "-", 24, 20, function() bump(-1) end)
    minus:SetPoint("RIGHT", val, "LEFT", -2, 0)
    function f:Refresh() val:SetText(fmt and fmt(get()) or tostring(get())) end
    f:Refresh()
    return f
end

-- Label with a small number box; Enter applies, Escape restores. get() -> number, set(number)
function W.NumberBox(parent, label, get, set, tip)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(236, 24)
    if tip then f:EnableMouse(true); AddTip(f, label, tip) end
    local txt = W.Text(f, 12, S.text)
    txt:SetPoint("LEFT", 4, 0); txt:SetText(label)
    local ok, e = pcall(CreateFrame, "EditBox", nil, f, "InputBoxTemplate")
    if not ok or not e then e = CreateFrame("EditBox", nil, f, BACKDROP_TEMPLATE) end
    e:SetSize(64, 20); e:SetPoint("RIGHT", -4, 0)
    HideArt(e, { "Left", "Middle", "Right" })
    e.box = Box(e, -2, S.cell)
    e:SetTextInsets(2, 2, 0, 0)
    e:SetAutoFocus(false); e:SetJustifyH("CENTER")
    e:SetFontObject(ChatFontNormal)
    e:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v then set(v) end
        self:ClearFocus(); f:Refresh()
    end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Refresh() end)
    e:SetScript("OnEditFocusLost", function() f:Refresh() end)
    function f:Refresh() if not e:HasFocus() then e:SetText(tostring(get() or "")) end end
    f:Refresh()
    return f
end

-- Priority row: a label and three blessing icons in order. Click an icon to move it one
-- place to the left. get() -> { KEY, KEY, KEY }, set(list)
-- labelFn (optional) gives the label each Refresh; a row with no label hides its icons.
function W.Priority(parent, label, get, set, icons, labelFn)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(236, 24)
    local txt = W.Text(f, 12, S.text)
    txt:SetPoint("LEFT", 4, 0); txt:SetText(label)
    f.slots = {}
    for i = 1, 3 do
        local b = CreateFrame("Button", nil, f, BACKDROP_TEMPLATE)
        b:SetSize(20, 20)
        b:SetPoint("RIGHT", f, "RIGHT", -4 - (3 - i) * 30, 0)
        b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        b:SetBackdropColor(0, 0, 0, 0.8); b:SetBackdropBorderColor(unpack(S.border))
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.num = W.Text(f, 10, S.dim, "RIGHT", S.num)
        b.num:SetPoint("RIGHT", b, "LEFT", -2, 0); b.num:SetText(i)
        local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(b.icon); hl:SetColorTexture(1, 1, 1, 0.2)
        b:SetScript("OnClick", function()
            if i == 1 then return end
            local list = { unpack(get()) }
            list[i - 1], list[i] = list[i], list[i - 1]
            set(list); f:Refresh()
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.name or "", 1, 1, 1)
            if i > 1 then GameTooltip:AddLine("Click: move up", S.dim[1], S.dim[2], S.dim[3]) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.slots[i] = b
    end
    function f:Refresh()
        local list = get()
        local name = labelFn and labelFn() or label
        txt:SetText(name or "")
        local on = name ~= nil and name ~= ""
        for i, b in ipairs(self.slots) do
            b:SetShown(on); b.num:SetShown(on)
            local k = list[i]
            b.icon:SetTexture(k and icons(k) or W.QUESTION)
            b.name = k and ns.BY_KEY[k] and ns.BY_KEY[k].single:gsub("^Blessing of ", "") or ""
        end
    end
    f:Refresh()
    return f
end

-- A row of class icons; click one to pick it. get() -> CLASS, set(CLASS)
function W.ClassPicker(parent, classes, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(236, 24)
    f.btns = {}
    for i, class in ipairs(classes) do
        local b = CreateFrame("Button", nil, f, BACKDROP_TEMPLATE)
        b:SetSize(22, 22)
        b:SetPoint("LEFT", f, "LEFT", 4 + (i - 1) * 25, 0)
        b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        b:SetBackdropColor(0, 0, 0, 0.8)
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetPoint("TOPLEFT", 1, -1); t:SetPoint("BOTTOMRIGHT", -1, 1)
        local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if tc then
            t:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
            t:SetTexCoord(tc[1] + 0.02, tc[2] - 0.02, tc[3] + 0.02, tc[4] - 0.02)
        end
        b.icon = t
        b:SetScript("OnClick", function() set(class); f:Refresh() end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class, W.ClassColor(class))
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b.class = class
        f.btns[i] = b
    end
    function f:Refresh()
        local cur = get()
        for _, b in ipairs(self.btns) do
            local on = b.class == cur
            b:SetBackdropBorderColor(unpack(on and S.gold or S.border))
            b.icon:SetDesaturated(not on)
            b.icon:SetAlpha(on and 1 or 0.6)
        end
    end
    f:Refresh()
    return f
end

-- Popup with a multi-line text box: shows text to copy (Export) or takes pasted text
-- (Import, with onAccept).
local dialog
function W.TextDialog(title, text, acceptLabel, onAccept)
    if not dialog then
        dialog = W.Panel(UIParent, 420, 220, "PallyPulseTextDialog")
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetPoint("CENTER")
        dialog:EnableMouse(true)
        dialog:SetMovable(true); dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", dialog.StartMoving)
        dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
        tinsert(UISpecialFrames, "PallyPulseTextDialog")
        dialog.title = W.Heading(dialog, 13)
        dialog.title:SetPoint("TOPLEFT", 12, -10)
        local close = W.CloseButton(dialog, function() dialog:Hide() end)
        close:SetPoint("TOPRIGHT", -4, -4)
        local sf = CreateFrame("ScrollFrame", "PallyPulseTextDialogScroll", dialog, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 12, -32); sf:SetPoint("BOTTOMRIGHT", -24, 42)
        W.SkinScroll(sf)
        local well = W.Box(dialog, 0, S.cell)
        well.bg:ClearAllPoints(); well.bg:SetPoint("TOPLEFT", sf, "TOPLEFT", -4, 4); well.bg:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 4, -4)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true); eb:SetAutoFocus(false)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(370)
        eb:SetScript("OnEscapePressed", function() dialog:Hide() end)
        sf:SetScrollChild(eb)
        dialog.edit = eb
        dialog.hint = W.Text(dialog, 11, S.dim)
        dialog.hint:SetPoint("BOTTOMLEFT", 12, 16)
        dialog.accept = W.Button(dialog, "Import", 90, 22)
        dialog.accept:SetPoint("BOTTOMRIGHT", -12, 10)
    end
    dialog.title:SetText(title)
    dialog.edit:SetText(text or "")
    dialog.edit:SetFocus()
    dialog.edit:HighlightText()
    dialog.hint:SetText(onAccept and "Paste a profile, then Import." or "Ctrl+C to copy.")
    dialog.accept:SetShown(onAccept ~= nil)
    if onAccept then
        dialog.accept:SetText(acceptLabel or "Import")
        dialog.accept:SetScript("OnClick", function()
            if onAccept(dialog.edit:GetText()) ~= false then dialog:Hide() end
        end)
    end
    dialog:Show()
end

function W.Tip(frame, fn)
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        fn(GameTooltip)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Over(f)
    if not f then return false end
    if f.IsMouseOver then return f:IsMouseOver() end
    if MouseIsOver then return MouseIsOver(f) end
    return false
end

-- Popovers close when you click anywhere outside them (or their anchor).
function W.AutoClose(frame)
    frame:SetScript("OnUpdate", function(self)
        if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
            and not Over(self) and not Over(self.anchor) then
            self:Hide()
        end
    end)
end

function W.FormatTime(sec)
    if not sec or sec == math.huge then return "" end
    if sec >= 3600 then return ("%dh"):format(sec / 3600) end
    if sec >= 60 then return ("%dm"):format(sec / 60) end
    return ("%ds"):format(sec)
end

function W.SavePos(frame, key)
    local p, _, rp, x, y = frame:GetPoint()
    ns.db.pos[key] = { p, rp, x, y }
end

function W.RestorePos(frame, key, default)
    local p = ns.db.pos[key] or default
    frame:ClearAllPoints()
    frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

-- noCombatMove: the frame has secure buttons anchored to it (the buff bar). The game refuses to
-- move such a frame in combat, so say so instead of attempting it.
function W.MakeDraggable(frame, handle, key, respectLock, noCombatMove)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    -- Moved by hand rather than StartMoving: the frame follows the cursor exactly from where
    -- it was grabbed, whatever its scale or anchor, and is kept on screen.
    local moving = false
    local lastMsg = 0
    local grabX, grabY, startL, startT
    local function Cursor()
        local x, y = GetCursorPosition()
        local s = frame:GetEffectiveScale()
        return x / s, y / s
    end
    local mover = CreateFrame("Frame", nil, frame)
    mover:Hide()
    mover:SetScript("OnUpdate", function()
        local x, y = Cursor()
        local l, t = startL + (x - grabX), startT + (y - grabY)
        local s = frame:GetEffectiveScale()
        local sw, sh = UIParent:GetWidth() * UIParent:GetEffectiveScale() / s, UIParent:GetHeight() * UIParent:GetEffectiveScale() / s
        local w, h = frame:GetWidth(), frame:GetHeight()
        l = math.max(0, math.min(l, sw - w))
        t = math.max(h, math.min(t, sh))
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    end)
    handle:SetScript("OnDragStart", function()
        if respectLock and ns.db.locked then return end
        if noCombatMove and InCombatLockdown() then
            if GetTime() - lastMsg > 5 then
                lastMsg = GetTime()
                ns.Print("Can't move in combat.")
            end
            return
        end
        if not frame:GetLeft() then return end
        moving = true
        frame.pulseMoving = true      -- the bar holds off re-laying itself out while dragged
        grabX, grabY = Cursor()
        startL, startT = frame:GetLeft(), frame:GetTop()
        mover:Show()
    end)
    handle:SetScript("OnDragStop", function()
        if not moving then return end
        moving = false
        mover:Hide()
        frame.pulseMoving = false
        W.SavePos(frame, key)
        ns.dirty = true
    end)
end

-- Icon slot used across the bar: icon + 1px edge + optional class strip, count and timer.
function W.IconSlot(btn, size)
    btn:SetSize(size, size)
    if btn.SetBackdrop then
        btn:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
        btn:SetBackdropColor(0, 0, 0, 0.8)
        btn:SetBackdropBorderColor(unpack(S.border))
    end
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", 1, -1); btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.strip = btn:CreateTexture(nil, "OVERLAY")
    btn.strip:SetPoint("BOTTOMLEFT", 1, 1); btn.strip:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.strip:SetHeight(2)
    btn.check = btn:CreateTexture(nil, "OVERLAY", nil, 2)
    btn.check:SetSize(size * 0.42, size * 0.42); btn.check:SetPoint("BOTTOMRIGHT", 1, -1)
    btn.check:SetTexture(W.READY)
    btn.count = W.Text(btn, math.max(10, math.floor(size * 0.45)), S.warn, "CENTER", S.num, "OUTLINE")
    btn.count:SetPoint("CENTER", 0, 1)
    btn.timer = W.Text(btn, math.max(9, math.floor(size * 0.3)), S.text, "RIGHT", S.num, "OUTLINE")
    btn.timer:SetPoint("TOPRIGHT", 0, -1)
    btn.hl = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.hl:SetPoint("TOPLEFT", 1, -1); btn.hl:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.hl:SetColorTexture(1, 1, 1, 0.15)
    return btn
end

-- state: "ok" (covered), "low" (expiring), "need" (some missing), "all" (everyone missing)
function W.SetSlotState(btn, state, count, timer)
    btn.slotState = state
    local covered = state == "ok"
    btn.icon:SetDesaturated(covered)
    local v = covered and 0.55 or 1
    btn.icon:SetVertexColor(v, v, v)
    btn.check:SetShown(covered)
    btn.count:SetShown(not covered and count ~= nil)
    if count then btn.count:SetText(count) end
    local c = (state == "all" and S.bad) or (state == "need" and S.bad) or (state == "low" and S.warn) or S.good
    btn.count:SetTextColor(c[1], c[2], c[3])
    btn.timer:SetText(W.FormatTime(timer))
    btn.baseBorder = covered and S.border or c
    if btn.SetBackdropBorderColor then btn:SetBackdropBorderColor(unpack(btn.baseBorder)) end
end
