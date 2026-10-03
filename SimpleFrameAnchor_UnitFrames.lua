-- SimpleFrameAnchor - Unit Frames
--
-- Light touches on the DEFAULT Blizzard unit frames:
--   * Class-colored health bars (players only; flat texture so no gradient).
--   * X/Y offset for TARGET & FOCUS auras only -- never player (Edit Mode owns it).
--
-- Auras: this client pools them behind TargetFrame:GetAuraContainer(); we offset that
-- container after Blizzard anchors it (hook UpdateAuraContainerAnchors) with
-- AdjustPointsOffset, so the whole buff+debuff block moves. No SetScript on Blizzard
-- frames, no taint.

local ADDON, ns = ...
ns = ns or {}

local UF = {}
ns.UF = UF

local UnitIsPlayer, UnitClass = UnitIsPlayer, UnitClass

local function ufdb()
    SimpleFrameAnchorDB = SimpleFrameAnchorDB or {}
    local d = SimpleFrameAnchorDB.unitframes
    if type(d) ~= "table" then d = {}; SimpleFrameAnchorDB.unitframes = d end
    d.auras = d.auras or {}
    for _, k in ipairs({ "target", "focus" }) do
        d.auras[k] = d.auras[k] or { enabled = false, x = 0, y = 0 }
    end
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

local function ColorBar(bar, unit)
    if not ufdb().classColors then return end
    unit = unit or (bar and bar.unit)
    if not (bar and unit and bar.SetStatusBarColor) then return end
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
--  Target / Focus aura offset
-- ============================================================================
local AURA_FRAME = { target = function() return TargetFrame end, focus = function() return FocusFrame end }

local function acfg(key) return ufdb().auras[key] end

local function OffsetAuras(frame, key)
    local cfg = acfg(key)
    if not (frame and frame.GetAuraContainer) or not cfg.enabled then return end
    local container = frame:GetAuraContainer()
    if not container then return end
    if container.AdjustPointsOffset then
        container:AdjustPointsOffset(cfg.x, cfg.y)   -- Blizzard re-anchors to base each pass, so not cumulative
    else
        local p, rel, rp, ox, oy = container:GetPoint(1)
        if p then container:SetPoint(p, rel, rp, (ox or 0) + cfg.x, (oy or 0) + cfg.y) end
    end
end

local auraHooked = {}
local function HookAuras(key)
    local frame = AURA_FRAME[key] and AURA_FRAME[key]()
    if not frame or auraHooked[key] then return end
    if type(frame.UpdateAuraContainerAnchors) ~= "function" then return end
    auraHooked[key] = true
    hooksecurefunc(frame, "UpdateAuraContainerAnchors", function(self) OffsetAuras(self, key) end)
end

-- Force Blizzard to re-anchor now (resets to base; our hook re-applies the offset),
-- so slider/toggle changes show live and disabling restores the base position.
local function ReAnchor(key)
    local frame = AURA_FRAME[key] and AURA_FRAME[key]()
    if frame and frame.UpdateAuraContainerAnchors then pcall(frame.UpdateAuraContainerAnchors, frame) end
end

function UF.GetAura(key) return acfg(key) end

function UF.SetAuraEnabled(key, on)
    acfg(key).enabled = on and true or false
    HookAuras(key)
    ReAnchor(key)
end

function UF.SetAuraPos(key, axis, v)
    acfg(key)[axis] = v
    ReAnchor(key)
end

-- Install the hook (if the frame/method is ready yet) AND force-apply the saved offset,
-- so it persists across reloads without needing a live aura change.
local function TryAura(key)
    HookAuras(key)
    if acfg(key).enabled then ReAnchor(key) end
end

-- ============================================================================
--  Events
-- ============================================================================
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")   -- frames fully ready; retry if login was too early
ev:RegisterEvent("PLAYER_FOCUS_CHANGED")    -- FocusFrame may only init on the first focus
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_FOCUS_CHANGED" then
        TryAura("focus")
        return
    end
    local function run()
        TryAura("target"); TryAura("focus")
        if ufdb().classColors then HookHealth(); UF.RefreshColors() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.3, run) else run() end
end)
