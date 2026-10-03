-- SimpleFrameAnchor - Unit Frames
--
-- Light touches on the DEFAULT Blizzard unit frames:
--   * Class-colored health bars (players get their class color; NPCs stay default).
--   * (coming) X/Y offset for Target & Focus auras only -- NOT player (Edit Mode owns it).
--
-- Class colors hook Blizzard's own health-bar update so the color is reasserted whenever
-- Blizzard repaints the bar; no SetScript on Blizzard frames, no taint.

local ADDON, ns = ...
ns = ns or {}

local UF = {}
ns.UF = UF

local UnitIsPlayer, UnitClass = UnitIsPlayer, UnitClass

local function ufdb()
    SimpleFrameAnchorDB = SimpleFrameAnchorDB or {}
    SimpleFrameAnchorDB.unitframes = SimpleFrameAnchorDB.unitframes or {}
    return SimpleFrameAnchorDB.unitframes
end

-- ---- class-colored health bars ----------------------------------------------
local function ClassColor(unit)
    if not (unit and UnitIsPlayer(unit)) then return nil end
    local _, class = UnitClass(unit)
    if not class then return nil end
    return (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
end

-- Color a standard unit-frame health bar (bar.unit set by Blizzard).
local function ColorBar(bar)
    if not ufdb().classColors then return end
    if not bar or not bar.unit then return end
    local c = ClassColor(bar.unit)
    if c then bar:SetStatusBarColor(c.r, c.g, c.b) end
end

local function HookHealth()
    if UF._hooked then return end
    UF._hooked = true
    -- The standard health-bar update fires on target/focus change and health events for
    -- player/target/focus/ToT/party; recolor right after Blizzard sets the default color.
    if type(UnitFrameHealthBar_Update) == "function" then
        hooksecurefunc("UnitFrameHealthBar_Update", ColorBar)
    end
    if type(HealthBar_OnValueChanged) == "function" then
        hooksecurefunc("HealthBar_OnValueChanged", ColorBar)
    end
end

-- Best-effort immediate recolor of the current frames (the hooks handle future updates).
function UF.RefreshColors()
    if not ufdb().classColors then return end
    local frames = { PlayerFrame, TargetFrame, FocusFrame, TargetFrameToT, FocusFrameToT, PetFrame }
    for _, f in ipairs(frames) do
        local bar = f and (f.healthbar or f.healthBar or f.HealthBar)
        if bar then ColorBar(bar) end
    end
end

function UF.IsClassColors() return ufdb().classColors and true or false end

function UF.SetClassColors(on)
    ufdb().classColors = on and true or false
    if on then
        HookHealth()
        UF.RefreshColors()
        print("|cff66ccffSimpleFrameAnchor|r: class-colored health bars ON.")
    else
        print("|cff66ccffSimpleFrameAnchor|r: class colors OFF -- |cffffff00/reload|r to restore default health colors.")
    end
end

-- ---- events -----------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    if ufdb().classColors then
        HookHealth()
        if C_Timer and C_Timer.After then C_Timer.After(0.3, UF.RefreshColors) else UF.RefreshColors() end
    end
end)
