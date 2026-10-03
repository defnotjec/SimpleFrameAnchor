-- SimpleFrameAnchor - Unit Frames
--
-- Light touches on the DEFAULT Blizzard unit frames:
--   * Class-colored health bars (player/pet/target/focus; flat texture, no gradient).
--   * Self-target name fix (Blizzard omits the name FontString for self-target).
--   * Optional black unit-frame borders (tint the ornate FrameTexture black).
--
-- Target/Focus aura display lives in SimpleFrameAnchor_Auras.lua (own frames via the
-- native AuraContainer widget) -- the protected Blizzard aura container cannot be
-- moved taint-free on this client.

local ADDON, ns = ...
ns = ns or {}

local UF = {}
ns.UF = UF

local UnitIsPlayer, UnitClass = UnitIsPlayer, UnitClass

local function ufdb()
    SimpleFrameAnchorDB = SimpleFrameAnchorDB or {}
    local d = SimpleFrameAnchorDB.unitframes
    if type(d) ~= "table" then d = {}; SimpleFrameAnchorDB.unitframes = d end
    return d
end

-- ============================================================================
--  Class-colored health bars
-- ============================================================================
local FLAT_BAR = "Interface\\TargetingFrame\\UI-StatusBar"

local function ClassColor(unit)
    if not (unit and UnitIsPlayer(unit)) then return nil end
    local _, class = UnitClass(unit)
    return class and (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
end

-- Modern frames nest the bar; fall back through the known path.
local function HealthBarOf(frame)
    if not frame then return nil end
    if frame.healthbar then return frame.healthbar end
    if frame.healthBar then return frame.healthBar end
    local c = frame.TargetFrameContent
    c = c and c.TargetFrameContentMain
    c = c and c.HealthBarsContainer
    return c and c.HealthBar
end

-- Units we recolor. Target/Focus ARE included: SetStatusBarColor/SetStatusBarTexture
-- are display ops (not protected writes) and don't read secret values, so they're
-- taint-free. The old "self-target loses its name" bug was a SEPARATE Blizzard quirk
-- (name FontString not set for self) handled by the self-target name fix below --
-- not caused by recoloring.
local SAFE_COLOR_UNITS = { player = true, pet = true, target = true, focus = true, targettarget = true, focustarget = true }

local function ColorBar(bar, unit)
    if not ufdb().classColors then return end
    unit = unit or (bar and bar.unit)
    if not (bar and unit and bar.SetStatusBarColor) then return end
    if not SAFE_COLOR_UNITS[unit] then return end
    local c = ClassColor(unit)
    if c then
        if bar.SetStatusBarTexture then bar:SetStatusBarTexture(FLAT_BAR) end
        bar:SetStatusBarColor(c.r, c.g, c.b)
    end
end

local UNIT_FRAMES = {
    { f = function() return PlayerFrame end,    unit = "player" },
    { f = function() return TargetFrame end,    unit = "target" },
    { f = function() return FocusFrame end,     unit = "focus" },
    { f = function() return TargetFrameToT end, unit = "targettarget" },
    { f = function() return FocusFrameToT end,  unit = "focustarget" },
    { f = function() return PetFrame end,       unit = "pet" },
}

function UF.RefreshColors()
    if not ufdb().classColors then return end
    for _, e in ipairs(UNIT_FRAMES) do
        ColorBar(HealthBarOf(e.f()), e.unit)
    end
end

local function HookHealth()
    if UF._hooked then return end
    UF._hooked = true
    if type(UnitFrameHealthBar_Update) == "function" then
        hooksecurefunc("UnitFrameHealthBar_Update", function(self) ColorBar(self) end)
    end
    if type(HealthBar_OnValueChanged) == "function" then
        hooksecurefunc("HealthBar_OnValueChanged", function(self) ColorBar(self) end)
    end
    -- Target/focus repaint their bar art on unit change; recolor right after.
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_TARGET_CHANGED")
    ev:RegisterEvent("PLAYER_FOCUS_CHANGED")
    ev:RegisterEvent("UNIT_PET")
    ev:SetScript("OnEvent", function()
        if C_Timer and C_Timer.After then C_Timer.After(0, UF.RefreshColors) else UF.RefreshColors() end
    end)
end

function UF.IsClassColors() return ufdb().classColors and true or false end

function UF.SetClassColors(on)
    ufdb().classColors = on and true or false
    if on then
        HookHealth(); UF.RefreshColors()
        print("|cff66ccffSimpleFrameAnchor|r: class-colored health bars ON.")
    else
        print("|cff66ccffSimpleFrameAnchor|r: class colors OFF -- |cffffff00/reload|r to restore default health colors.")
    end
end

-- ============================================================================
--  Black unit-frame borders
--
--  Tint the ornate FrameTexture (Player/Target/Focus) black -- keeps the frame
--  shape, just recolors it. SetVertexColor on a texture is not a protected action,
--  so this is taint-free. Reasserted on login + target/focus change.
-- ============================================================================
local function borderTextures()
    local t = {}
    local function add(container) if container and container.FrameTexture then t[#t + 1] = container.FrameTexture end end
    add(PlayerFrame and PlayerFrame.PlayerFrameContainer)
    add(TargetFrame and TargetFrame.TargetFrameContainer)
    add(FocusFrame and FocusFrame.TargetFrameContainer)
    return t
end

local function ApplyBorders()
    local v = ufdb().bordersBlack and 0 or 1
    for _, tex in ipairs(borderTextures()) do
        pcall(tex.SetVertexColor, tex, v, v, v)
    end
end

function UF.IsBordersBlack() return ufdb().bordersBlack and true or false end

function UF.SetBordersBlack(on)
    ufdb().bordersBlack = on and true or false
    ApplyBorders()
    if not on then
        print("|cff66ccffSimpleFrameAnchor|r: unit-frame borders restored -- |cffffff00/reload|r if any border art looks off.")
    end
end

-- ============================================================================
--  Self-target name fix
--
--  On this client Blizzard's TargetFrame does NOT set its name FontString when the
--  target is YOU (self-target) -- it stays blank or stuck on the previous target
--  (confirmed: other players/mobs set fine, only UnitIsUnit("target","player")
--  fails). UnitName("target") is correct, so we fill it in. SetText on a FontString
--  is not a protected action -> taint-free. Deferred one frame so it runs after
--  Blizzard's own (name-skipping) TargetFrame update.
-- ============================================================================
local function FixSelfTargetName()
    local nm = TargetFrame and TargetFrame.name
    if nm and UnitExists("target") and UnitIsUnit("target", "player") then
        nm:SetText(UnitName("target"))
    end
end
local nameFix = CreateFrame("Frame")
nameFix:RegisterEvent("PLAYER_TARGET_CHANGED")
nameFix:RegisterEvent("PLAYER_ENTERING_WORLD")
nameFix:SetScript("OnEvent", function()
    local function run() FixSelfTargetName(); ApplyBorders() end
    if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end)

-- ============================================================================
--  Events
-- ============================================================================
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")   -- frames fully ready; retry if login was too early
ev:SetScript("OnEvent", function()
    local function run()
        if ufdb().classColors then HookHealth(); UF.RefreshColors() end
        ApplyBorders()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.3, run) else run() end
end)
