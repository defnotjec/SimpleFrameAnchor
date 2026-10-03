-- SimpleFrameAnchor
-- Lightweight anchor manager for the Player, Target and Cooldown Manager frames.
--
-- Core idea: WoW's layout engine keeps SetPoint relationships live. If the Player
-- frame's RIGHT edge is anchored to the Cooldown Manager's LEFT edge, then when the
-- CDM grows (adds icons, spreading from its centre) its left edge moves left and the
-- Player frame follows -- "pushed outward" for free, no polling. Target frame mirrors
-- it on the right. That flanking layout is the shipped default.
--
-- Blizzard unit frames + the Cooldown Viewer are governed by Edit Mode, so we only
-- reposition out of combat and re-apply on the events that make Edit Mode reclaim a
-- frame (login, zone-in, layout changes, exiting Edit Mode). Each frame's original
-- anchor is captured once so turning management off hands it back to Edit Mode.

local ADDON, ns = ...
ns = ns or {}

-- ============================================================================
--  Config model
-- ============================================================================
local POINTS = {
    "TOPLEFT", "TOP", "TOPRIGHT",
    "LEFT",    "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}
local POINT_LABEL = {
    TOPLEFT = "Top Left",   TOP = "Top",       TOPRIGHT = "Top Right",
    LEFT = "Left",          CENTER = "Center", RIGHT = "Right",
    BOTTOMLEFT = "Bottom Left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom Right",
}

-- Frames that can be picked as an anchor target ("Anchor to ...").
local TARGETS = {
    { key = "UIParent",                 label = "Screen (UIParent)" },
    { key = "PlayerFrame",              label = "Player Frame" },
    { key = "TargetFrame",              label = "Target Frame" },
    { key = "EssentialCooldownViewer",  label = "Cooldown Mgr - Essential" },
    { key = "UtilityCooldownViewer",    label = "Cooldown Mgr - Utility" },
    { key = "BuffIconCooldownViewer",   label = "Cooldown Mgr - Buffs" },
}

-- Frames this addon can move (the sidebar sections + saved-var keys).
local SUBJECTS = {
    { key = "PlayerFrame",             label = "Player Frame" },
    { key = "TargetFrame",             label = "Target Frame" },
    { key = "EssentialCooldownViewer", label = "Cooldown Manager" },
}
local SUBJECT_LABEL = {}
for _, s in ipairs(SUBJECTS) do SUBJECT_LABEL[s.key] = s.label end

-- Shipped defaults: Player hugs the left of the CDM, Target hugs the right, both
-- vertically centred on it. The CDM itself is left to Edit Mode (management off).
local DEFAULTS = {
    PlayerFrame = {
        enabled = true, relativeTo = "EssentialCooldownViewer",
        point = "RIGHT", relativePoint = "LEFT", x = -12, y = 0,
    },
    TargetFrame = {
        enabled = true, relativeTo = "EssentialCooldownViewer",
        point = "LEFT", relativePoint = "RIGHT", x = 12, y = 0,
    },
    EssentialCooldownViewer = {
        enabled = false, relativeTo = "UIParent",
        point = "CENTER", relativePoint = "CENTER", x = 0, y = -160,
    },
}

local function copyTable(t)
    local o = {}
    for k, v in pairs(t) do o[k] = v end
    return o
end

local function ensureDB()
    SimpleFrameAnchorDB = SimpleFrameAnchorDB or {}
    for key, def in pairs(DEFAULTS) do
        local c = SimpleFrameAnchorDB[key]
        if type(c) ~= "table" then c = {}; SimpleFrameAnchorDB[key] = c end
        for k, v in pairs(def) do
            if c[k] == nil then c[k] = v end
        end
    end
    return SimpleFrameAnchorDB
end

-- ============================================================================
--  Anchor application (combat-safe)
-- ============================================================================
local resolveFrame
resolveFrame = function(key)
    if not key then return nil end
    if key == "UIParent" then return UIParent end
    return _G[key]
end

local originalAnchor = {}   -- subjectKey -> captured pre-SimpleFrameAnchor SetPoint
local pending = false       -- an apply/restore was blocked by combat

-- Remember where a frame lived before we ever touched it, so we can hand it back.
local function captureOriginal(key)
    if originalAnchor[key] ~= nil then return end
    local f = resolveFrame(key)
    if not f or not f.GetPoint then return end
    local p, rel, rp, x, y = f:GetPoint(1)
    if p then
        originalAnchor[key] = { point = p, rel = rel, relPoint = rp, x = x or 0, y = y or 0 }
    else
        originalAnchor[key] = false   -- had no explicit point; nothing to restore to
    end
end

local function applyOne(key)
    local cfg = SimpleFrameAnchorDB and SimpleFrameAnchorDB[key]
    if not cfg or not cfg.enabled then return end
    local f = resolveFrame(key)
    if not f or not f.SetPoint then return end
    local rel = resolveFrame(cfg.relativeTo) or UIParent
    if rel == f then rel = UIParent end   -- guard: a frame can't anchor to itself
    if f.SetMovable then pcall(f.SetMovable, f, true) end
    f:ClearAllPoints()
    f:SetPoint(cfg.point or "CENTER", rel, cfg.relativePoint or cfg.point or "CENTER",
        cfg.x or 0, cfg.y or 0)
end

local function restoreOne(key)
    local f = resolveFrame(key)
    local o = originalAnchor[key]
    if not f or not f.SetPoint or not o then return end
    f:ClearAllPoints()
    if o.rel then
        f:SetPoint(o.point, o.rel, o.relPoint, o.x, o.y)
    else
        f:SetPoint(o.point or "CENTER", o.x or 0, o.y or 0)
    end
end

local function applyAll()
    ensureDB()
    if InCombatLockdown() then pending = true; return end
    for _, s in ipairs(SUBJECTS) do
        captureOriginal(s.key)
        pcall(applyOne, s.key)   -- a bad combo (anchor cycle) fails silently for that frame
    end
    pending = false
end

-- Enable/disable a single frame's management live.
local function setManaged(key, enabled)
    ensureDB()
    SimpleFrameAnchorDB[key].enabled = enabled and true or false
    if InCombatLockdown() then pending = true; return end
    captureOriginal(key)
    if enabled then pcall(applyOne, key) else pcall(restoreOne, key) end
end

-- ============================================================================
--  UI theme (matched to the DropChanceTooltip options panel)
-- ============================================================================
local UI = { W = 740, H = 470, SIDEBAR_W = 158, PAD = 14, ROW_H = 24, LABEL_W = 96 }
local ACCENT = { 0.40, 0.80, 1.00 }
local FONT = "Fonts\\FRIZQT__.TTF"
local FONT_SCALE = 0.90   -- trim all text slightly so the panel reads less "big"

local optionsFrame
local pageCache = {}          -- sectionKey -> wrapper frame
local sectionButtons = {}
local activeSection, activeRefreshers, doSelectSection

local function SolidTex(parent, layer, r, g, b, a)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(r, g, b, a or 1)
    return t
end

local function MakeFont(parent, size, r, g, b, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, math.max(8, math.floor(size * FONT_SCALE + 0.5)), flags or "")
    fs:SetTextColor(r or 0.9, g or 0.9, b or 0.9, 1)
    return fs
end

local function MakeBorder(parent, r, g, b, a)
    r, g, b, a = r or 0, g or 0, b or 0, a or 1
    local top = SolidTex(parent, "BORDER", r, g, b, a); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
    local bot = SolidTex(parent, "BORDER", r, g, b, a); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT"); bot:SetHeight(1)
    local lft = SolidTex(parent, "BORDER", r, g, b, a); lft:SetPoint("TOPLEFT"); lft:SetPoint("BOTTOMLEFT"); lft:SetWidth(1)
    local rgt = SolidTex(parent, "BORDER", r, g, b, a); rgt:SetPoint("TOPRIGHT"); rgt:SetPoint("BOTTOMRIGHT"); rgt:SetWidth(1)
end

-- ---- widget factory ---------------------------------------------------------
local function makeSection(parent, text, y)
    local fs = MakeFont(parent, 11, 0.5, 0.5, 0.56)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.PAD, y - 4)
    fs:SetText(string.upper(text))
    local line = SolidTex(parent, "ARTWORK", 1, 1, 1, 0.08)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
    line:SetPoint("RIGHT", parent, "RIGHT", -UI.PAD, 0)
    line:SetHeight(1)
    return 26
end

local function makeInfo(parent, text, y)
    local fs = MakeFont(parent, 12, 0.6, 0.6, 0.64)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.PAD, y)
    fs:SetPoint("RIGHT", parent, "RIGHT", -UI.PAD, 0)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return math.max(fs:GetStringHeight() or 0, 28) + 10
end

local function makeToggle(parent, text, y, get, set, tooltip)
    local rowIndex = parent._rows or 0
    parent._rows = rowIndex + 1
    local row = CreateFrame("Button", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.PAD, y)
    row:SetPoint("RIGHT", parent, "RIGHT", -UI.PAD, 0)
    row:SetHeight(UI.ROW_H)
    local bg = SolidTex(row, "BACKGROUND", 1, 1, 1, (rowIndex % 2 == 0) and 0.03 or 0.06)
    bg:SetAllPoints(row)
    local label = MakeFont(row, 13, 0.88, 0.88, 0.9); label:SetPoint("LEFT", 8, 0); label:SetText(text)

    local track = CreateFrame("Frame", nil, row); track:SetSize(38, 16); track:SetPoint("RIGHT", -8, 0)
    local trackTex = SolidTex(track, "ARTWORK", 0.28, 0.28, 0.32, 1); trackTex:SetAllPoints(track)
    local knob = track:CreateTexture(nil, "OVERLAY"); knob:SetSize(12, 12); knob:SetColorTexture(0.9, 0.9, 0.9, 1)

    local ON_X, OFF_X = 24, 2
    local function place() knob:ClearAllPoints(); knob:SetPoint("LEFT", track, "LEFT", get() and ON_X or OFF_X, 0) end
    local function applyVisual()
        local on = get() and true or false
        trackTex:SetColorTexture(on and ACCENT[1] or 0.28, on and ACCENT[2] or 0.28, on and ACCENT[3] or 0.32, on and 0.9 or 1)
        place()
    end
    applyVisual()

    row:SetScript("OnClick", function() set(not get()); applyVisual() end)
    if tooltip then
        row:SetScript("OnEnter", function()
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, 1, 1, 1, 1, true); GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    if activeRefreshers then activeRefreshers[#activeRefreshers + 1] = applyVisual end
    return UI.ROW_H
end

local function makeSlider(parent, text, y, minV, maxV, step, get, set, fmt)
    -- Compact single row: label (left) | track (middle) | value box (right).
    local H = UI.ROW_H
    local rowIndex = parent._rows or 0
    parent._rows = rowIndex + 1
    local c = CreateFrame("Frame", nil, parent)
    c:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.PAD, y); c:SetPoint("RIGHT", parent, "RIGHT", -UI.PAD, 0); c:SetHeight(H)
    local bg = SolidTex(c, "BACKGROUND", 1, 1, 1, (rowIndex % 2 == 0) and 0.03 or 0.06); bg:SetAllPoints(c)
    local label = MakeFont(c, 13, 0.88, 0.88, 0.9); label:SetPoint("LEFT", 8, 0); label:SetText(text)

    -- editable value box on the right (type a number for granular control)
    local vbox = CreateFrame("Frame", nil, c); vbox:SetSize(50, 18); vbox:SetPoint("RIGHT", -8, 0)
    SolidTex(vbox, "BACKGROUND", 0.10, 0.10, 0.12, 1):SetAllPoints(vbox)
    MakeBorder(vbox, 0, 0, 0, 0.8)
    local vedit = CreateFrame("EditBox", nil, vbox); vedit:SetAllPoints(vbox)
    vedit:SetFont(FONT, math.floor(12 * FONT_SCALE + 0.5), "")
    vedit:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    vedit:SetJustifyH("CENTER"); vedit:SetAutoFocus(false)

    local track = CreateFrame("Frame", nil, c)
    track:SetPoint("LEFT", c, "LEFT", UI.LABEL_W, 0); track:SetPoint("RIGHT", vbox, "LEFT", -10, 0); track:SetHeight(6)
    track:EnableMouse(true)
    SolidTex(track, "ARTWORK", 0.24, 0.24, 0.28, 1):SetAllPoints(track)
    local fill = SolidTex(track, "OVERLAY", ACCENT[1], ACCENT[2], ACCENT[3], 0.85)
    fill:SetPoint("TOPLEFT"); fill:SetPoint("BOTTOMLEFT"); fill:SetWidth(1)
    local thumb = CreateFrame("Button", nil, track); thumb:SetSize(14, 14)
    SolidTex(thumb, "OVERLAY", 0.95, 0.95, 0.95, 1):SetAllPoints(thumb)
    MakeBorder(thumb, 0, 0, 0, 0.9)

    local function clamp(v)
        v = math.max(minV, math.min(maxV, v))
        if step and step > 0 then v = math.floor((v - minV) / step + 0.5) * step + minV end
        return v
    end
    local value = clamp(get() or minV)
    local function layout()
        local w = track:GetWidth() or 1
        local frac = (maxV > minV) and (value - minV) / (maxV - minV) or 0
        thumb:ClearAllPoints(); thumb:SetPoint("CENTER", track, "LEFT", frac * w, 0)
        fill:SetWidth(math.max(1, frac * w))
        if not vedit:HasFocus() then vedit:SetText(fmt and fmt(value) or tostring(value)) end
    end
    vedit:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v then value = clamp(v); layout(); set(value) end
        self:ClearFocus()
    end)
    vedit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); layout() end)
    local function fromCursor()
        local x = GetCursorPosition() / (track:GetEffectiveScale() or 1)
        local left = track:GetLeft() or 0
        local w = track:GetWidth() or 1
        return clamp(minV + ((x - left) / w) * (maxV - minV))
    end
    local dragging = false
    thumb:SetScript("OnMouseDown", function() dragging = true end)
    thumb:SetScript("OnMouseUp", function() dragging = false; value = fromCursor(); layout(); set(value) end)
    thumb:SetScript("OnUpdate", function() if dragging then value = fromCursor(); layout(); set(value) end end)
    track:SetScript("OnMouseDown", function() value = fromCursor(); layout(); set(value) end)
    track:SetScript("OnSizeChanged", layout)
    if activeRefreshers then activeRefreshers[#activeRefreshers + 1] = function() value = clamp(get() or minV); layout() end end
    if C_Timer and C_Timer.After then C_Timer.After(0, layout) end
    return H
end

local function makeButton(parent, text, y, onClick, width)
    local b = CreateFrame("Button", nil, parent)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.PAD, y)
    b:SetSize(width or 240, 26)
    local bg = SolidTex(b, "ARTWORK", 0.16, 0.16, 0.19, 1); bg:SetAllPoints(b)
    MakeBorder(b, 0, 0, 0, 0.8)
    local fs = MakeFont(b, 13, 0.9, 0.9, 0.9); fs:SetPoint("CENTER"); fs:SetText(text)
    b:SetScript("OnEnter", function() bg:SetColorTexture(ACCENT[1] * 0.35, ACCENT[2] * 0.35, ACCENT[3] * 0.35, 1) end)
    b:SetScript("OnLeave", function() bg:SetColorTexture(0.16, 0.16, 0.19, 1) end)
    b:SetScript("OnClick", onClick)
    return 34
end

-- ---- dropdown (not in DCT; built in the same style) -------------------------
local openMenu
local function closeMenu() if openMenu then openMenu:Hide(); openMenu = nil end end

local function makeDropdown(parent, labelText, y, options, get, set)
    local H = UI.ROW_H
    local rowIndex = parent._rows or 0
    parent._rows = rowIndex + 1
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.PAD, y); row:SetPoint("RIGHT", parent, "RIGHT", -UI.PAD, 0); row:SetHeight(H)
    local bg = SolidTex(row, "BACKGROUND", 1, 1, 1, (rowIndex % 2 == 0) and 0.03 or 0.06); bg:SetAllPoints(row)
    local label = MakeFont(row, 13, 0.88, 0.88, 0.9); label:SetPoint("LEFT", 8, 0); label:SetText(labelText)

    -- Width capped at 210 but shrinks to fit a narrow (two-column) parent.
    local avail = (parent:GetWidth() or 300) - 2 * UI.PAD - UI.LABEL_W - 8
    local bw = math.max(80, math.min(210, avail))
    local btn = CreateFrame("Button", nil, row); btn:SetSize(bw, 20); btn:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    local bg = SolidTex(btn, "ARTWORK", 0.16, 0.16, 0.19, 1); bg:SetAllPoints(btn)
    MakeBorder(btn, 0, 0, 0, 0.8)
    local val = MakeFont(btn, 12, 0.9, 0.9, 0.9); val:SetPoint("LEFT", 8, 0); val:SetPoint("RIGHT", -18, 0); val:SetJustifyH("LEFT")
    local arrow = MakeFont(btn, 10, ACCENT[1], ACCENT[2], ACCENT[3]); arrow:SetPoint("RIGHT", -7, -1); arrow:SetText("v")

    local function labelFor(v) for _, o in ipairs(options) do if o.value == v then return o.text end end return tostring(v) end
    local function refresh() val:SetText(labelFor(get())) end
    refresh()

    btn:SetScript("OnEnter", function() bg:SetColorTexture(ACCENT[1] * 0.35, ACCENT[2] * 0.35, ACCENT[3] * 0.35, 1) end)
    btn:SetScript("OnLeave", function() bg:SetColorTexture(0.16, 0.16, 0.19, 1) end)
    btn:SetScript("OnClick", function()
        if openMenu and openMenu._owner == btn then closeMenu(); return end
        closeMenu()
        local w = btn:GetWidth()
        local rowH = 20
        local m = CreateFrame("Frame", nil, UIParent)
        m._owner = btn
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:SetSize(w, rowH * #options + 4)
        m:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
        SolidTex(m, "BACKGROUND", 0.1, 0.1, 0.12, 0.98):SetAllPoints(m)
        MakeBorder(m, 0, 0, 0, 1)
        for i, o in ipairs(options) do
            local sel = (o.value == get())
            local ob = CreateFrame("Button", nil, m)
            ob:SetSize(w - 4, rowH); ob:SetPoint("TOPLEFT", 2, -2 - (i - 1) * rowH)
            local obbg = SolidTex(ob, "ARTWORK", 1, 1, 1, sel and 0.10 or 0.0); obbg:SetAllPoints(ob)
            local ofs = MakeFont(ob, 12, sel and ACCENT[1] or 0.9, sel and ACCENT[2] or 0.9, sel and ACCENT[3] or 0.9)
            ofs:SetPoint("LEFT", 6, 0); ofs:SetText(o.text)
            ob:SetScript("OnEnter", function() obbg:SetColorTexture(ACCENT[1] * 0.4, ACCENT[2] * 0.4, ACCENT[3] * 0.4, 1) end)
            ob:SetScript("OnLeave", function() obbg:SetColorTexture(1, 1, 1, sel and 0.10 or 0.0) end)
            ob:SetScript("OnClick", function() set(o.value); refresh(); closeMenu() end)
        end
        openMenu = m
    end)

    if activeRefreshers then activeRefreshers[#activeRefreshers + 1] = refresh end
    return H
end

-- ---- color swatch (opens Blizzard's ColorPickerFrame) -----------------------
local function makeColorSwatch(parent, text, y, getColor, setColor)
    local H = UI.ROW_H
    local rowIndex = parent._rows or 0; parent._rows = rowIndex + 1
    local row = CreateFrame("Button", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.PAD, y); row:SetPoint("RIGHT", parent, "RIGHT", -UI.PAD, 0); row:SetHeight(H)
    SolidTex(row, "BACKGROUND", 1, 1, 1, (rowIndex % 2 == 0) and 0.03 or 0.06):SetAllPoints(row)
    local label = MakeFont(row, 13, 0.88, 0.88, 0.9); label:SetPoint("LEFT", 8, 0); label:SetText(text)
    local sw = CreateFrame("Button", nil, row); sw:SetSize(22, 14); sw:SetPoint("RIGHT", -8, 0)
    MakeBorder(sw, 0, 0, 0, 0.9)
    local swtex = SolidTex(sw, "ARTWORK", 1, 1, 1, 1); swtex:SetAllPoints(sw)
    local function refresh() local c = getColor() or { 1, 1, 1 }; swtex:SetColorTexture(c[1], c[2], c[3], 1) end
    refresh()
    local function open()
        local c = getColor() or { 1, 1, 1 }
        local function applied()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            setColor(r, g, b); refresh()
        end
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow({ r = c[1], g = c[2], b = c[3], swatchFunc = applied, hasOpacity = false })
        else
            ColorPickerFrame.func = applied; ColorPickerFrame.hasOpacity = false
            ColorPickerFrame.previousValues = { c[1], c[2], c[3] }
            ColorPickerFrame:SetColorRGB(c[1], c[2], c[3])
            ColorPickerFrame:Hide(); ColorPickerFrame:Show()
        end
    end
    row:SetScript("OnClick", open); sw:SetScript("OnClick", open)
    if activeRefreshers then activeRefreshers[#activeRefreshers + 1] = refresh end
    return H
end

-- ---- option lists -----------------------------------------------------------
local pointOptions, targetOptions = {}, {}
for _, p in ipairs(POINTS) do pointOptions[#pointOptions + 1] = { value = p, text = POINT_LABEL[p] } end
for _, t in ipairs(TARGETS) do targetOptions[#targetOptions + 1] = { value = t.key, text = t.label } end

-- ============================================================================
--  Panes
-- ============================================================================
local function C(key) return ensureDB()[key] end

local function resetSubject(key)
    SimpleFrameAnchorDB[key] = copyTable(DEFAULTS[key])
    applyAll()
    if doSelectSection and activeSection then doSelectSection(activeSection) end
end

local function buildSubjectPane(subjectKey, wrapper)
    local y = -UI.PAD
    y = y - makeSection(wrapper, "Position", y)
    y = y - makeToggle(wrapper, "Manage this frame's position", y,
        function() return C(subjectKey).enabled end,
        function(v) setManaged(subjectKey, v) end,
        "When on, SimpleFrameAnchor controls where this frame sits.\nWhen off, it is handed back to Edit Mode.")
    y = y - 4
    y = y - makeDropdown(wrapper, "Anchor to", y, targetOptions,
        function() return C(subjectKey).relativeTo end,
        function(v) C(subjectKey).relativeTo = v; applyAll() end)
    y = y - makeDropdown(wrapper, "This frame's point", y, pointOptions,
        function() return C(subjectKey).point end,
        function(v) C(subjectKey).point = v; applyAll() end)
    y = y - makeDropdown(wrapper, "...to target's point", y, pointOptions,
        function() return C(subjectKey).relativePoint end,
        function(v) C(subjectKey).relativePoint = v; applyAll() end)
    y = y - 6
    y = y - makeSlider(wrapper, "Horizontal offset (X)", y, -800, 800, 1,
        function() return C(subjectKey).x end,
        function(v) C(subjectKey).x = v; applyAll() end,
        function(v) return tostring(math.floor(v + 0.5)) end)
    y = y - makeSlider(wrapper, "Vertical offset (Y)", y, -800, 800, 1,
        function() return C(subjectKey).y end,
        function(v) C(subjectKey).y = v; applyAll() end,
        function(v) return tostring(math.floor(v + 0.5)) end)
    y = y - 10
    y = y - makeButton(wrapper, "Reset " .. SUBJECT_LABEL[subjectKey] .. " to default", y,
        function() resetSubject(subjectKey) end)
    return -y + UI.PAD
end

local function applyFlankPreset()
    ensureDB()
    SimpleFrameAnchorDB.PlayerFrame = copyTable(DEFAULTS.PlayerFrame)
    SimpleFrameAnchorDB.TargetFrame = copyTable(DEFAULTS.TargetFrame)
    applyAll()
    if doSelectSection and activeSection then doSelectSection(activeSection) end
end

local function resetAll()
    -- Wipe to shipped defaults. The CDM is disabled by default, so if we had been
    -- moving it, hand it back to Edit Mode before re-applying the rest.
    SimpleFrameAnchorDB = {}
    ensureDB()
    restoreOne("EssentialCooldownViewer")
    applyAll()
    if doSelectSection and activeSection then doSelectSection(activeSection) end
end

local function buildGeneral(wrapper)
    local y = -UI.PAD
    y = y - makeSection(wrapper, "Unit Frames", y)
    y = y - makeToggle(wrapper, "Enable class colors", y,
        function() return ns.UF and ns.UF.IsClassColors() end,
        function(v) if ns.UF then ns.UF.SetClassColors(v) end end,
        "Color the default unit-frame health bars by class (players only).\nTurn off then /reload to restore default colors.")
    y = y - 8
    y = y - makeSection(wrapper, "Preset", y)
    y = y - makeInfo(wrapper,
        "Flank layout: the Player and Target frames hug the Cooldown Manager's left and right edges and slide outward as it grows.", y)
    y = y - makeButton(wrapper, "Apply flank preset", y, applyFlankPreset, 240)
    y = y - 8
    y = y - makeSection(wrapper, "Reset", y)
    y = y - makeButton(wrapper, "Reset ALL frames to defaults", y, resetAll, 240)
    y = y - 10
    y = y - makeSection(wrapper, "Notes", y)
    y = y - makeInfo(wrapper,
        "Frames are only moved out of combat; changes made in combat apply the moment it ends. " ..
        "If a Cooldown Manager bar is set to hide when inactive, frames anchored to it may drift when it hides -- " ..
        "keep the bar always shown for a steady layout.", y)
    return -y + UI.PAD
end

local function buildCastbars(wrapper)
    local CB = ns.CB
    local y = -UI.PAD
    y = y - makeSection(wrapper, "Legion Classic Style", y)
    y = y - makeInfo(wrapper,
        "Reskin the default cast bars (Player, Pet, Target, Focus, Boss) with the old Legion " ..
        "Classic look, using in-game textures. Nameplate cast bars are not affected yet.", y)
    y = y - makeToggle(wrapper, "Replace all cast bars with Legion style", y,
        function() return CB and CB.IsEnabled() end,
        function(v) if CB then CB.SetEnabled(v) end end,
        "Applies the Legion skin immediately when turned on.\nTurn off then /reload to restore Blizzard's default art.")
    y = y - 10

    -- Per-bar move controls (Target / Focus). ToT is added once its bar is built.
    local MOVERS = {
        { key = "target", label = "Target" },
        { key = "focus",  label = "Focus" },
    }
    for _, m in ipairs(MOVERS) do
        y = y - makeSection(wrapper, m.label .. " Cast Bar", y)
        y = y - makeToggle(wrapper, "Move the " .. m.label .. " cast bar", y,
            function() return CB and CB.GetMove(m.key).enabled end,
            function(v) if CB then CB.SetMoveEnabled(m.key, v) end end,
            "Re-anchor this cast bar to a fixed screen position.\nTurn off then /reload to hand it back to Blizzard.")
        y = y - makeSlider(wrapper, "Horizontal (X)", y, -800, 800, 1,
            function() return CB and CB.GetMove(m.key).x or 0 end,
            function(v) if CB then CB.SetMovePos(m.key, "x", v) end end,
            function(v) return tostring(math.floor(v + 0.5)) end)
        y = y - makeSlider(wrapper, "Vertical (Y)", y, -800, 800, 1,
            function() return CB and CB.GetMove(m.key).y or 0 end,
            function(v) if CB then CB.SetMovePos(m.key, "y", v) end end,
            function(v) return tostring(math.floor(v + 0.5)) end)
        y = y - makeToggle(wrapper, "Show test frame (drag to position)", y,
            function() return CB and CB.IsTestShown(m.key) end,
            function(v) if CB then CB.SetTest(m.key, v) end end,
            "Show a draggable mock cast bar so you can place it without waiting for a real cast.\nDragging it updates the X/Y above.")
        y = y - 6
    end

    y = y - makeSection(wrapper, "Notes", y)
    y = y - makeInfo(wrapper,
        "Move controls re-anchor the native bar; target/focus something that casts to see it. " ..
        "Target-of-Target has no native cast bar -- a created one is coming next. " ..
        "Turning style/move off needs a /reload to fully restore the defaults.", y)
    return -y + UI.PAD
end

-- Two-column layout (POC of UX B): full() spans the width; two() places a left and a
-- right control side by side. Each control is given its own half-width parent frame.
local function Columns(wrapper)
    local W = wrapper:GetWidth(); if not W or W < 50 then W = UI.W - UI.SIDEBAR_W - 12 end
    local gap = 14
    local colW = math.floor((W - gap) / 2)
    local flowY = -UI.PAD
    local function full(fn)
        flowY = flowY - (fn(wrapper, flowY) or 0)
    end
    local function two(leftFn, rightFn)
        local lf = CreateFrame("Frame", nil, wrapper)
        lf:SetPoint("TOPLEFT", 0, flowY); lf:SetSize(colW, 1)
        local hL = leftFn and (leftFn(lf, 0) or 0) or 0
        local hR = 0
        if rightFn then
            local rf = CreateFrame("Frame", nil, wrapper)
            rf:SetPoint("TOPLEFT", colW + gap, flowY); rf:SetSize(colW, 1)
            hR = rightFn(rf, 0) or 0
        end
        flowY = flowY - math.max(hL, hR)
    end
    local function gap_(n) flowY = flowY - (n or 6) end
    local function height() return -flowY + UI.PAD end
    return full, two, gap_, height
end

local function buildXPBar(wrapper)
    local X = ns.XP
    local full, two, gap, height = Columns(wrapper)
    local function tog(text, key, tip, onset)
        return function(p, y) return makeToggle(p, text, y,
            function() return X and X.Get()[key] end,
            function(v) if X then (onset or function(vv) X.SetValue(key, vv) end)(v) end end, tip) end
    end
    local function sld(text, key, lo, hi)
        return function(p, y) return makeSlider(p, text, y, lo, hi, 1,
            function() return X and X.Get()[key] or 0 end,
            function(v) if X then X.SetValue(key, v) end end,
            function(v) return tostring(math.floor(v + 0.5)) end) end
    end

    full(function(w, y) return makeSection(w, "Experience Bar", y) end)
    two(
        tog("Show XP bar", "enabled", "Show a standalone XP bar.", function(v) X.SetEnabled(v) end),
        tog("Replace Blizzard's", "replace", "Hide Blizzard's status-tracking XP bar.\nOff + /reload restores it.", function(v) X.SetReplace(v) end))
    two(
        function(p, y) return makeDropdown(p, "Frame style", y,
            { { value = "none", text = "None (plain)" }, { value = "forever", text = "EUI Forever" } },
            function() return X and X.Get().frame or "forever" end,
            function(v) if X then X.SetValue("frame", v) end end) end,
        function(p, y) return makeDropdown(p, "Profession fill", y, (X and X.ProfessionOptions()) or { { value = "none", text = "None" } },
            function() return X and X.Get().profession or "none" end,
            function(v) if X then X.SetValue("profession", v) end end) end)
    two(
        tog("Stretch fill", "stretch", "Stretch one copy of the art across the bar (default); off tiles it."),
        tog("Show text", "showText", "Level / XP% on the bar."))
    two(sld("Text X", "textX", -300, 300), sld("Text Y", "textY", -100, 100))

    full(function(w, y) return makeSection(w, "Position & Size", y) end)
    two(sld("Position X", "x", -800, 800), sld("Position Y", "y", -800, 800))
    two(sld("Width", "width", 120, 1920), sld("Height", "height", 6, 40))
    full(function(w, y) return makeButton(w, "Match Blizzard bar position", y,
        function() if X then X.MatchBlizzPosition() end end, 240) end)

    full(function(w, y) return makeSection(w, "Dividers", y) end)
    two(
        tog("Show dividers (10%)", "showTicks", "Full lines every 10%, in the divider text color."),
        tog("5% lines", "show5", "Add lines at the 5% marks."))
    two(
        function(p, y) return makeDropdown(p, "5% line style", y,
            { { value = "dashed", text = "Dashed" }, { value = "dotted", text = "Dotted" },
              { value = "solid", text = "Solid" }, { value = "none", text = "None" } },
            function() return X and X.Get().divider5Style or "dashed" end,
            function(v) if X then X.SetValue("divider5Style", v) end end) end,
        function(p, y) return makeColorSwatch(p, "5% color", y,
            function() return X and X.Get().tick5Color end,
            function(r, g, b) if X then X.SetValue("tick5Color", { r, g, b }) end end) end)
    two(
        tog("Divider text", "dividerText", "Percentage labels (10% .. 90%) on the 10% lines."),
        function(p, y) return makeColorSwatch(p, "Divider text color", y,
            function() return X and X.Get().dividerTextColor end,
            function(r, g, b) if X then X.SetValue("dividerTextColor", { r, g, b }) end end) end)
    two(sld("Divider X", "dividerTextX", -40, 40), sld("Divider Y", "dividerTextY", -20, 20))

    return height()
end

local SECTIONS = {
    { key = "PlayerFrame",             title = "Player Frame",     desc = "Where the player unit frame sits.",  build = function(w) return buildSubjectPane("PlayerFrame", w) end },
    { key = "TargetFrame",             title = "Target Frame",     desc = "Where the target unit frame sits.",  build = function(w) return buildSubjectPane("TargetFrame", w) end },
    { key = "EssentialCooldownViewer", title = "Cooldown Manager", desc = "Move the Cooldown Manager itself. Off by default -- Edit Mode owns it.", build = function(w) return buildSubjectPane("EssentialCooldownViewer", w) end },
    { key = "castbars",                title = "Cast Bars",        desc = "Legion Classic cast bar style for the default cast bars.", build = buildCastbars },
    { key = "xpbar",                   title = "Experience Bar",   desc = "A standalone XP bar with the EUI Forever / Professions skins.", build = buildXPBar },
    { key = "general",                 title = "General",          desc = "Presets, reset and notes.",          build = buildGeneral },
}
local sectionByKey = {}
for _, sec in ipairs(SECTIONS) do sectionByKey[sec.key] = sec end

-- ============================================================================
--  Window shell
-- ============================================================================
local function createOptionsWindow()
    if optionsFrame then return optionsFrame end

    local f = CreateFrame("Frame", "SimpleFrameAnchorOptionsFrame", UIParent)
    f:SetSize(UI.W, UI.H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetScript("OnMouseDown", closeMenu)
    f:SetScript("OnHide", function() closeMenu(); if ns.CB and ns.CB.HideAllTests then ns.CB.HideAllTests() end end)
    f:Hide()
    SolidTex(f, "BACKGROUND", 0.06, 0.06, 0.07, 0.97):SetAllPoints(f)
    MakeBorder(f, 0, 0, 0, 1)
    if UISpecialFrames then tinsert(UISpecialFrames, "SimpleFrameAnchorOptionsFrame") end

    local titleFs = MakeFont(f, 16, ACCENT[1], ACCENT[2], ACCENT[3]); titleFs:SetPoint("TOPLEFT", 14, -10); titleFs:SetText("SimpleFrameAnchor")
    local close = CreateFrame("Button", nil, f); close:SetSize(22, 22); close:SetPoint("TOPRIGHT", -8, -7)
    local closeX = MakeFont(close, 17, 0.75, 0.28, 0.28); closeX:SetPoint("CENTER"); closeX:SetText("X")
    close:SetScript("OnEnter", function() closeX:SetTextColor(1, 0.2, 0.2) end)
    close:SetScript("OnLeave", function() closeX:SetTextColor(0.75, 0.28, 0.28) end)
    close:SetScript("OnClick", function() f:Hide() end)
    SolidTex(f, "ARTWORK", 1, 1, 1, 0.08):SetPoint("TOPLEFT", 0, -34)
    local tl = SolidTex(f, "ARTWORK", 1, 1, 1, 0.08); tl:SetPoint("TOPLEFT", 0, -34); tl:SetPoint("TOPRIGHT", 0, -34); tl:SetHeight(1)

    local sidebar = CreateFrame("Frame", nil, f)
    sidebar:SetPoint("TOPLEFT", 0, -34); sidebar:SetPoint("BOTTOMLEFT", 0, 0); sidebar:SetWidth(UI.SIDEBAR_W)
    SolidTex(sidebar, "BACKGROUND", 1, 1, 1, 0.02):SetAllPoints(sidebar)
    local sbLine = SolidTex(sidebar, "ARTWORK", 1, 1, 1, 0.08); sbLine:SetPoint("TOPRIGHT"); sbLine:SetPoint("BOTTOMRIGHT"); sbLine:SetWidth(1)

    local right = CreateFrame("Frame", nil, f)
    right:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 0, 0); right:SetPoint("BOTTOMRIGHT", 0, 0)
    local headerFs = MakeFont(right, 18, 0.95, 0.95, 0.97); headerFs:SetPoint("TOPLEFT", UI.PAD, -12)
    local descFs = MakeFont(right, 12, 0.6, 0.6, 0.64)
    descFs:SetPoint("TOPLEFT", headerFs, "BOTTOMLEFT", 0, -4); descFs:SetPoint("RIGHT", right, "RIGHT", -UI.PAD, 0); descFs:SetJustifyH("LEFT")

    local scrollFrame = CreateFrame("ScrollFrame", nil, right)
    scrollFrame:SetPoint("TOPLEFT", right, "TOPLEFT", 0, -56)
    scrollFrame:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -6, 8)
    local scrollChild = CreateFrame("Frame", nil, scrollFrame); scrollChild:SetSize(1, 1)
    scrollFrame:SetScrollChild(scrollChild)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, (scrollChild:GetHeight() or 0) - (self:GetHeight() or 0))
        local nv = math.min(maxScroll, math.max(0, self:GetVerticalScroll() - (delta or 0) * 28))
        self:SetVerticalScroll(nv)
    end)

    local function selectSection(key)
        activeSection = key
        local section = sectionByKey[key]
        if not section then return end
        headerFs:SetText(section.title)
        descFs:SetText(section.desc or "")
        for k, b in pairs(sectionButtons) do
            local on = (k == key)
            if on then b._accent:Show() else b._accent:Hide() end
            b._label:SetTextColor(on and 1 or 0.72, on and 1 or 0.72, on and 1 or 0.75)
            if on then b._hl:Show() else b._hl:Hide() end
        end
        for _, w in pairs(pageCache) do w:Hide() end
        local contentW = scrollFrame:GetWidth()
        if not contentW or contentW < 1 then contentW = UI.W - UI.SIDEBAR_W - 12 end
        -- rebuild fresh each time so slider/dropdown closures read current DB
        if pageCache[key] then pageCache[key]:Hide(); pageCache[key] = nil end
        local wrapper = CreateFrame("Frame", nil, scrollChild)
        wrapper:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
        wrapper:SetWidth(contentW)
        wrapper._refreshers = {}
        activeRefreshers = wrapper._refreshers
        local h = section.build(wrapper) or 20
        activeRefreshers = nil
        wrapper:SetHeight(h)
        pageCache[key] = wrapper
        wrapper:Show()
        scrollChild:SetSize(contentW, h)
        scrollFrame:SetVerticalScroll(0)
        closeMenu()
    end
    doSelectSection = selectSection

    for i, section in ipairs(SECTIONS) do
        local b = CreateFrame("Button", nil, sidebar)
        b:SetHeight(32)
        b:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 0, -8 - (i - 1) * 34)
        b:SetPoint("RIGHT", sidebar, "RIGHT", 0, 0)
        b._accent = SolidTex(b, "OVERLAY", ACCENT[1], ACCENT[2], ACCENT[3], 1)
        b._accent:SetPoint("TOPLEFT"); b._accent:SetPoint("BOTTOMLEFT"); b._accent:SetWidth(3); b._accent:Hide()
        b._hl = SolidTex(b, "BACKGROUND", 1, 1, 1, 0.05); b._hl:SetAllPoints(b); b._hl:Hide()
        b._label = MakeFont(b, 14, 0.72, 0.72, 0.75); b._label:SetPoint("LEFT", 16, 0); b._label:SetText(section.title)
        b:SetScript("OnEnter", function() if activeSection ~= section.key then b._hl:Show() end end)
        b:SetScript("OnLeave", function() if activeSection ~= section.key then b._hl:Hide() end end)
        b:SetScript("OnClick", function() selectSection(section.key) end)
        sectionButtons[section.key] = b
    end

    optionsFrame = f
    selectSection("PlayerFrame")
    return f
end

local function openOptions()
    ensureDB()
    local f = createOptionsWindow()
    if f:IsShown() then f:Hide() else f:Show() end
end

-- ============================================================================
--  [DEV PROBE] castbar frame discovery -> SimpleFrameAnchorDB._castbarProbe
--  Dumps which cast bar frames exist on this client and their sub-regions, so the
--  Legion reskin can target the right field names. Run `/sfa probe`, /reload, read it.
-- ============================================================================
local function probeCastbars()
    ensureDB()
    local KEYS = { "Border", "BorderShield", "Flash", "Icon", "Spark", "Text",
                   "Background", "Spellbar", "unit", "barType", "Shield", "TextBorder" }
    local PATHS = {
        "CastingBarFrame", "PlayerCastingBarFrame", "PetCastingBarFrame",
        "TargetFrame.spellbar", "FocusFrame.spellbar",
        "Boss1TargetFrame.spellbar",
        "TargetFrameToT", "FocusFrameToT",
    }
    local function resolvePath(path)
        local obj
        for part in path:gmatch("[^.]+") do
            if obj == nil then obj = _G[part]
            elseif type(obj) == "table" then obj = obj[part]
            else return nil end
        end
        return obj
    end
    local out = {}
    out[#out+1] = "CastingBarFrame_OnEvent fn = " .. type(_G.CastingBarFrame_OnEvent)
    out[#out+1] = "WOW_PROJECT_ID = " .. tostring(WOW_PROJECT_ID) .. " / MAINLINE=" .. tostring(WOW_PROJECT_MAINLINE)
    for _, path in ipairs(PATHS) do
        local f = resolvePath(path)
        if not f then
            out[#out+1] = path .. " = NIL"
        else
            local line = path .. " | type=" .. (f.GetObjectType and f:GetObjectType() or "?")
            if f.unit ~= nil then line = line .. " unit=" .. tostring(f.unit) end
            local present = {}
            for _, k in ipairs(KEYS) do
                local v = f[k]
                if v ~= nil then
                    present[#present+1] = k .. ":" .. (type(v) == "table" and (v.GetObjectType and v:GetObjectType() or "table") or type(v))
                end
            end
            line = line .. " | keys={" .. table.concat(present, ", ") .. "}"
            out[#out+1] = line
            -- region inventory (textures/fontstrings) with draw layers
            if f.GetRegions then
                for i = 1, select("#", f:GetRegions()) do
                    local r = select(i, f:GetRegions())
                    if r and r.GetObjectType then
                        local layer, sub = (r.GetDrawLayer and r:GetDrawLayer())
                        out[#out+1] = "    region[" .. i .. "] " .. r:GetObjectType()
                            .. " layer=" .. tostring(layer) .. ":" .. tostring(sub)
                            .. " tex=" .. tostring(r.GetTexture and r:GetTexture())
                    end
                end
            end
        end
    end
    -- nameplate castbar probe (if a plate is up)
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local plate = C_NamePlate.GetNamePlateForUnit("target")
        local uf = plate and plate.UnitFrame
        local cb = uf and (uf.castBar or uf.CastBar)
        out[#out+1] = "nameplate(target).castBar = " .. tostring(cb)
            .. (cb and (" keys Border=" .. tostring(cb.Border) .. " Spark=" .. tostring(cb.Spark)) or "")
    end
    SimpleFrameAnchorDB._castbarProbe = out
    print("|cff66ccffSimpleFrameAnchor|r: castbar probe written (" .. #out .. " lines). Target a caster mid-cast for best results, then /reload.")
end

-- ============================================================================
--  [DIAG] general dump-to-disk -> SimpleFrameAnchorDB._dump
--    /sfa dump              SFA state: XP-art atlas availability, SFA_XPBar + cast
--                           bar frames, config snapshot.
--    /sfa dump <Frame|Path> KRD-style regions+children of any frame (dotted path ok).
--  Writes to our SavedVariable (flushes on /reload); read whichever is present.
-- ============================================================================
local function diagResolvePath(path)
    local obj
    for part in path:gmatch("[^.]+") do
        if obj == nil then obj = _G[part]
        elseif type(obj) == "table" then obj = obj[part]
        else return nil end
    end
    return obj
end

local function diagDumpFrame(f, out, tag)
    if not (f and f.GetObjectType) then out[#out + 1] = tag .. " = NIL"; return end
    local w = f.GetWidth and f:GetWidth()
    local h = f.GetHeight and f:GetHeight()
    out[#out + 1] = tag .. " | type=" .. (f:GetObjectType() or "?")
        .. " shown=" .. tostring(f.IsShown and f:IsShown())
        .. " size=" .. tostring(w and math.floor(w)) .. "x" .. tostring(h and math.floor(h))
    if f.GetRegions then
        for i = 1, select("#", f:GetRegions()) do
            local r = select(i, f:GetRegions())
            if r and r.GetObjectType then
                local layer, sub = (r.GetDrawLayer and r:GetDrawLayer())
                out[#out + 1] = "   region[" .. i .. "] " .. r:GetObjectType()
                    .. " layer=" .. tostring(layer) .. ":" .. tostring(sub)
                    .. " atlas=" .. tostring(r.GetAtlas and r:GetAtlas())
                    .. " tex=" .. tostring(r.GetTexture and r:GetTexture())
                    .. " shown=" .. tostring(r.IsShown and r:IsShown())
            end
        end
    end
    local function kids(fr, depth, pad)
        for i = 1, (fr.GetNumChildren and fr:GetNumChildren() or 0) do
            local c = select(i, fr:GetChildren())
            if c and c.GetObjectType then
                out[#out + 1] = pad .. "child " .. (c.GetDebugName and c:GetDebugName() or "?")
                    .. " " .. c:GetObjectType() .. " shown=" .. tostring(c.IsShown and c:IsShown())
                if depth > 1 then kids(c, depth - 1, pad .. "  ") end
            end
        end
    end
    kids(f, 2, "   ")
end

local function sfaDump(arg)
    ensureDB()
    local out = { "SFA dump | WOW_PROJECT_ID=" .. tostring(WOW_PROJECT_ID) }
    if arg and arg ~= "" then
        local f = arg:find("%.") and diagResolvePath(arg) or _G[arg]
        diagDumpFrame(f, out, arg)
    else
        for _, a in ipairs({ "UI-HUD-ActionBar-Frame", "Professions-skillbar-frame",
            "Skillbar_Fill_Flipbook_Cooking", "Skillbar_Fill_Flipbook_Jewelcrafting" }) do
            out[#out + 1] = "atlas " .. a .. " = " .. tostring(C_Texture.GetAtlasInfo(a) ~= nil)
        end
        diagDumpFrame(_G.SFA_XPBar, out, "SFA_XPBar")
        diagDumpFrame(_G.MainStatusTrackingBarContainer, out, "MainStatusTrackingBarContainer")
        diagDumpFrame(_G.StatusTrackingBarManager, out, "StatusTrackingBarManager")
        diagDumpFrame(_G.PlayerCastingBarFrame, out, "PlayerCastingBarFrame")
        diagDumpFrame(TargetFrame and TargetFrame.spellbar, out, "TargetFrame.spellbar")
        out[#out + 1] = "DB.xpbar = " .. (SimpleFrameAnchorDB.xpbar and "present" or "nil")
        out[#out + 1] = "DB.castbars = " .. (SimpleFrameAnchorDB.castbars and "present" or "nil")
    end
    SimpleFrameAnchorDB._dump = out
    print("|cff66ccffSimpleFrameAnchor|r: dump written (" .. #out .. " lines) to SavedVariables; |cffffff00/reload|r to flush.")
end

-- ============================================================================
--  Events + slash
-- ============================================================================
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(function() ev:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED") end)

local function delayedApply(delay)
    if C_Timer and C_Timer.After then C_Timer.After(delay or 0.2, applyAll) else applyAll() end
end

ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        ensureDB()
        for _, s in ipairs(SUBJECTS) do captureOriginal(s.key) end
        delayedApply(0.5)
        -- reapply once Edit Mode exits and reclaims frames
        if EditModeManagerFrame and EditModeManagerFrame.ExitEditMode then
            hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function() delayedApply(0.1) end)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then applyAll() end
    else -- PLAYER_ENTERING_WORLD / EDIT_MODE_LAYOUTS_UPDATED
        delayedApply(0.2)
    end
end)

SLASH_SIMPLEFRAMEANCHOR1 = "/simpleframeanchor"
SLASH_SIMPLEFRAMEANCHOR2 = "/sfa"
SlashCmdList.SIMPLEFRAMEANCHOR = function(msg)
    msg = msg or ""
    -- "dump [Frame|Path]" is parsed BEFORE lowercasing so a frame name keeps its case.
    local dumpArg = msg:match("^%s*[Dd][Uu][Mm][Pp]%s*(.-)%s*$")
    if dumpArg ~= nil then
        sfaDump(dumpArg)
        return
    end
    msg = msg:lower():gsub("%s+", "")
    if msg == "probe" then
        probeCastbars()
    elseif msg == "reset" then
        resetAll()
        print("|cff66ccffSimpleFrameAnchor|r: reset all frames to defaults.")
    elseif msg == "preset" then
        applyFlankPreset()
        print("|cff66ccffSimpleFrameAnchor|r: applied flank preset.")
    else
        openOptions()
    end
end
