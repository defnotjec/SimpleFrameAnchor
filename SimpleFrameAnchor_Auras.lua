-- SimpleFrameAnchor - Auras
--
-- Our OWN movable buff/debuff displays for TARGET and FOCUS, with independent X/Y
-- per category (target-buffs, target-debuffs, focus-buffs, focus-debuffs).
--
-- Why our own frames: this client makes aura DATA secret (C_UnitAuras returns
-- nothing to addon code in combat/instances) AND the native TargetFrame aura
-- container's layout is a secret value that crashes on read and taints
-- TargetFrame.Update when written. So we cannot move Blizzard's auras. Instead we
-- instantiate Blizzard's native AuraContainer widget as OUR frame: the engine reads
-- the secret data engine-side and fills regions we register; we own the frame and
-- its position. No GetPoint/SetPoint/hook on Blizzard's container -> zero taint.
--
-- Blizzard's native target/focus auras are suppressed (alpha 0 on their container --
-- not a protected write and no secret read, so taint-free) when ours are enabled.

local ADDON, ns = ...
ns = ns or {}

local AU = {}
ns.AU = AU

local ELEMENT = 24      -- icon size (px)
local SPACING = 2
local PER_ROW = 8       -- wrap after this many icons

local UNIT_FRAME = { target = function() return TargetFrame end, focus = function() return FocusFrame end }
local CATS = { "buffs", "debuffs" }
local FILTER = { buffs = "HELPFUL", debuffs = "HARMFUL" }
local MAXCOUNT = { buffs = 32, debuffs = 16 }

-- ---- config -----------------------------------------------------------------
local function db()
    SimpleFrameAnchorDB = SimpleFrameAnchorDB or {}
    local d = SimpleFrameAnchorDB.auras2
    if type(d) ~= "table" then d = {}; SimpleFrameAnchorDB.auras2 = d end
    for _, u in ipairs({ "target", "focus" }) do
        local e = d[u]
        if type(e) ~= "table" then e = {}; d[u] = e end
        if e.enabled == nil then e.enabled = false end
        e.buffs   = e.buffs   or { x = 0, y = -6 }
        e.debuffs = e.debuffs or { x = 0, y = -6 - (ELEMENT + 8) }
    end
    -- Global duration-text style shared by all four aura groups.
    local t = d.text
    if type(t) ~= "table" then t = {}; d.text = t end
    if t.show == nil then t.show = true end
    t.size = t.size or 12
    t.x = t.x or 0
    t.y = t.y or 0
    -- Global icon size per category (applied as container SetScale off the base ELEMENT).
    local s = d.size
    if type(s) ~= "table" then s = {}; d.size = s end
    if s.buffs == nil then s.buffs = ELEMENT end
    if s.debuffs == nil then s.debuffs = ELEMENT end
    return d
end
local function cfg(unit) return db()[unit] end
local function sizeOf(cat) return db().size[cat] or ELEMENT end

-- ---- duration text style (global) -------------------------------------------
-- We draw our OWN duration FontString (SetDurationText) so we fully control size,
-- position and visibility -- Blizzard's built-in cooldown numbers are hidden. These
-- are our own regions, so restyling them live is taint-free. Hide via alpha (not
-- SetShown) so the engine's text updates can't un-hide them.
local DUR_FONT = STANDARD_TEXT_FONT
local durTexts = {}   -- every duration FontString we create, for live restyle

local function styleDur(fs)
    local t = db().text
    fs:SetFont(DUR_FONT, t.size or 12, "OUTLINE")
    fs:ClearAllPoints()
    fs:SetPoint("CENTER", fs:GetParent(), "CENTER", t.x or 0, t.y or 0)
    fs:SetAlpha(t.show == false and 0 or 1)
end

-- ---- button initializer -----------------------------------------------------
-- Engine flow layout only ANCHORS buttons; it does NOT size them. We MUST set the
-- button size here or it renders nothing.
local function initButton(button)
    button:SetSize(ELEMENT, ELEMENT)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Cooldown: show the radial swipe, hide the built-in numbers (we draw our own).
    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints(button)
    if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.6) end
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end

    -- Text carrier above the swipe. Fonts MUST be set before registering with the
    -- engine (the register runs a display pass that SetText()s the string).
    local carrier = CreateFrame("Frame", nil, button)
    carrier:SetAllPoints(button)
    carrier:SetFrameLevel(cd:GetFrameLevel() + 5)
    carrier:EnableMouse(false)
    local count = carrier:CreateFontString(nil, "OVERLAY")
    count:SetFontObject("NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", 1, 0)
    local dur = carrier:CreateFontString(nil, "OVERLAY")
    styleDur(dur)
    durTexts[#durTexts + 1] = dur

    pcall(button.SetMouseClickEnabled, button, false)

    button:SetIcon(icon)
    button:SetDurationCooldown(cd)
    button:SetApplicationCount(count, {})
    pcall(button.SetDurationText, button, dur, {})
end

-- ---- containers -------------------------------------------------------------
local containers = {}   -- containers[unit][cat] = AuraContainer

local function makeContainer(unit, cat)
    if not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if not ok or not c then return nil end

    c:SetSize(1, 1)
    local dir = AnchorUtil and AnchorUtil.FlowDirection
    if c.SetFlowLayoutGrowthDirection and dir then c:SetFlowLayoutGrowthDirection(dir.Right, dir.Down) end
    if c.SetFlowLayoutAnchorPoint then c:SetFlowLayoutAnchorPoint("TOPLEFT") end
    if c.SetFlowLayoutMaximumLineSize then pcall(c.SetFlowLayoutMaximumLineSize, c, PER_ROW * (ELEMENT + SPACING)) end

    local layout = { elementWidth = ELEMENT, elementHeight = ELEMENT, elementSpacing = SPACING, lineSpacing = SPACING }
    local okg = pcall(c.AddAuraGroup, c, "g", FILTER[cat], {
        maxFrameCount = MAXCOUNT[cat],
        initializeFrame = initButton,
        layout = layout,
    })
    if not okg then c:Hide(); return nil end
    if c.SetAuraGroupLayout then pcall(c.SetAuraGroupLayout, c, "g", layout) end
    if c.SetAuraGroupMaxFrameCount then pcall(c.SetAuraGroupMaxFrameCount, c, "g", MAXCOUNT[cat]) end

    pcall(function()
        c:SetUnit(unit)          -- unit LAST (gates UNIT_AURA registration on groups)
        c:UpdateAllAuras()
    end)
    return c
end

local function getContainer(unit, cat)
    containers[unit] = containers[unit] or {}
    if not containers[unit][cat] then
        containers[unit][cat] = makeContainer(unit, cat)
    end
    return containers[unit][cat]
end

-- Anchor our container to the unit frame + the saved X/Y (reading the frame's
-- position is taint-free; we never write to it).
local function anchorContainer(unit, cat)
    local c = containers[unit] and containers[unit][cat]
    local frame = UNIT_FRAME[unit] and UNIT_FRAME[unit]()
    if not (c and frame) then return end
    local pos = cfg(unit)[cat]
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", pos.x or 0, pos.y or 0)
end

-- ---- suppress Blizzard's native auras ---------------------------------------
-- Alpha 0 on the native container hides its buttons without a protected write or a
-- secret read, so it is taint-free. Reasserted on the events below.
local function nativeContainer(unit)
    local f = UNIT_FRAME[unit] and UNIT_FRAME[unit]()
    if f and f.GetAuraContainer then
        local ok, c = pcall(f.GetAuraContainer, f)
        if ok then return c end
    end
    return nil
end

local function suppressNative(unit, on)
    local c = nativeContainer(unit)
    if c and c.SetAlpha then pcall(c.SetAlpha, c, on and 0 or 1) end
end

-- ---- apply ------------------------------------------------------------------
local function refresh(unit)
    local c = containers[unit]
    if not c then return end
    for _, cat in ipairs(CATS) do
        if c[cat] and c[cat].UpdateAllAuras then pcall(c[cat].UpdateAllAuras, c[cat]) end
    end
end

local function apply(unit)
    local e = cfg(unit)
    if e.enabled then
        for _, cat in ipairs(CATS) do
            local c = getContainer(unit, cat)
            if c then
                anchorContainer(unit, cat)
                pcall(c.SetScale, c, sizeOf(cat) / ELEMENT)
                pcall(function() c:SetShown(true); c:UpdateAllAuras() end)
            end
        end
        suppressNative(unit, true)
    else
        local cc = containers[unit]
        if cc then
            for _, cat in ipairs(CATS) do
                if cc[cat] then pcall(cc[cat].Hide, cc[cat]) end
            end
        end
        suppressNative(unit, false)
    end
end

-- ---- public API (called by the /sfa Auras pane) -----------------------------
function AU.GetEnabled(unit) return cfg(unit).enabled and true or false end

function AU.SetEnabled(unit, on)
    cfg(unit).enabled = on and true or false
    apply(unit)
end

function AU.GetPos(unit, cat) return cfg(unit)[cat] end

function AU.SetPos(unit, cat, axis, v)
    cfg(unit)[cat][axis] = v
    anchorContainer(unit, cat)
end

-- ---- duration text (global) -------------------------------------------------
local function refreshText()
    for _, fs in ipairs(durTexts) do pcall(styleDur, fs) end
end

function AU.GetText() return db().text end

function AU.SetTextShow(on)
    db().text.show = on and true or false
    refreshText()
end

function AU.SetTextSize(v)
    db().text.size = v
    refreshText()
end

function AU.SetTextPos(axis, v)
    db().text[axis] = v
    refreshText()
end

-- ---- icon size (global, per category) ---------------------------------------
function AU.GetSize(cat) return sizeOf(cat) end

function AU.SetSize(cat, v)
    db().size[cat] = v
    local scale = v / ELEMENT
    for _, unit in ipairs({ "target", "focus" }) do
        local c = containers[unit] and containers[unit][cat]
        if c then pcall(c.SetScale, c, scale) end
    end
end

-- ---- events -----------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("PLAYER_FOCUS_CHANGED")
ev:RegisterEvent("UNIT_AURA")
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_ENTERING_WORLD" then
        if C_Timer and C_Timer.After then
            C_Timer.After(0.3, function() apply("target"); apply("focus") end)
        else
            apply("target"); apply("focus")
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if cfg("target").enabled then apply("target") end
    elseif event == "PLAYER_FOCUS_CHANGED" then
        if cfg("focus").enabled then apply("focus") end
    elseif event == "UNIT_AURA" then
        if unit == "target" and cfg("target").enabled then refresh("target"); suppressNative("target", true)
        elseif unit == "focus" and cfg("focus").enabled then refresh("focus"); suppressNative("focus", true) end
    end
end)
