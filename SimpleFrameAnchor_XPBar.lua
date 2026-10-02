-- SimpleFrameAnchor - Experience Bar
--
-- A standalone XP bar (our own StatusBar, no EUI dependency) that can wear the
-- "EUI Forever" and "EUI Professions" skins -- all drawn from IN-GAME atlases, so
-- nothing is bundled. This increment is the bar itself: fill + rested overlay +
-- text, driven by the XP events, movable from /sfa. The Forever/Professions frame
-- art, the profession flipbook fill, and the ticks are layered on next.

local ADDON, ns = ...
ns = ns or {}

local XP = {}
ns.XP = XP

local UnitXP, UnitXPMax, UnitLevel = UnitXP, UnitXPMax, UnitLevel
local GetXPExhaustion = GetXPExhaustion

local COLOR = {
    xp       = { 0.25, 0.20, 0.60 },   -- Blizzard-ish XP purple/blue
    rested   = { 0.18, 0.30, 0.55 },
}

-- ---- DB ---------------------------------------------------------------------
local DEFAULTS = {
    enabled    = false,
    x          = 0,
    y          = -120,
    width      = 360,
    height     = 14,
    frame      = "forever",   -- "forever" | "prof"  (default per request)
    profession = "cooking",   -- flipbook profession (default per request)
    showTicks  = true,
    showText   = true,
}

local function xdb()
    SimpleFrameAnchorDB = SimpleFrameAnchorDB or {}
    local d = SimpleFrameAnchorDB.xpbar
    if type(d) ~= "table" then d = {}; SimpleFrameAnchorDB.xpbar = d end
    for k, v in pairs(DEFAULTS) do
        if d[k] == nil then d[k] = v end
    end
    return d
end

-- ---- the bar ----------------------------------------------------------------
local bar   -- lazily created holder StatusBar

local function AtMaxLevel()
    if IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel() then return true end
    local level = UnitLevel("player") or 0
    local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion())
        or (GetMaxPlayerLevel and GetMaxPlayerLevel())
    return (maxLevel and level >= maxLevel) or false
end

local function UpdateXP()
    if not bar then return end
    local d = xdb()

    if (not d.enabled) or AtMaxLevel() or (IsXPUserDisabled and IsXPUserDisabled()) then
        bar:Hide()
        return
    end

    local cur = UnitXP("player")
    local maxXP = UnitXPMax("player"); if maxXP <= 0 then maxXP = 1 end
    local rested = GetXPExhaustion() or 0
    local level = UnitLevel("player")

    bar:SetMinMaxValues(0, maxXP)
    bar:SetValue(cur)

    if rested > 0 then
        bar.Rested:SetMinMaxValues(0, maxXP)
        bar.Rested:SetValue(math.min(cur + rested, maxXP))
        bar.Rested:Show()
    else
        bar.Rested:Hide()
    end

    if d.showText then
        local pct = (cur / maxXP) * 100
        local t = string.format("%s %d - %.1f%%", LEVEL or "Level", level, pct)
        if rested > 0 then t = t .. string.format(" (R: %.1f%%)", (rested / maxXP) * 100) end
        bar.Text:SetText(t)
        bar.Text:Show()
    else
        bar.Text:Hide()
    end

    bar:Show()
end
XP.Update = UpdateXP

local function Layout()
    if not bar then return end
    local d = xdb()
    bar:SetSize(d.width, d.height)
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", UIParent, "CENTER", d.x, d.y)
end

local function EnsureBar()
    if bar then return bar end
    bar = CreateFrame("StatusBar", "SFA_XPBar", UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:GetStatusBarTexture():SetHorizTile(false)
    bar:SetStatusBarColor(COLOR.xp[1], COLOR.xp[2], COLOR.xp[3])
    bar:Hide()

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetColorTexture(0, 0, 0, 0.5)
    bar.BG = bg

    -- Rested overlay behind the fill.
    local rested = CreateFrame("StatusBar", nil, bar)
    rested:SetAllPoints(bar)
    rested:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    rested:SetStatusBarColor(COLOR.rested[1], COLOR.rested[2], COLOR.rested[3], 0.6)
    rested:GetStatusBarTexture():SetDrawLayer("ARTWORK", 1)
    rested:SetMinMaxValues(0, 1); rested:SetValue(0)
    rested:Hide()
    bar.Rested = rested

    local text = bar:CreateFontString(nil, "OVERLAY")
    text:SetFontObject("SystemFont_Shadow_Small")
    text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    text:SetDrawLayer("OVERLAY", 2)
    bar.Text = text

    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_XP_UPDATE")
    ev:RegisterEvent("PLAYER_LEVEL_UP")
    ev:RegisterEvent("UPDATE_EXHAUSTION")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", UpdateXP)

    Layout()
    return bar
end

-- ---- public API -------------------------------------------------------------
function XP.Get() return xdb() end

function XP.ApplyAll()
    if not xdb().enabled then
        if bar then bar:Hide() end
        return
    end
    EnsureBar()
    Layout()
    UpdateXP()
end

function XP.SetEnabled(on)
    xdb().enabled = on and true or false
    if on then
        EnsureBar(); Layout(); UpdateXP()
        print("|cff66ccffSimpleFrameAnchor|r: Experience bar ON.")
    else
        if bar then bar:Hide() end
        print("|cff66ccffSimpleFrameAnchor|r: Experience bar OFF.")
    end
end

function XP.SetValue(key, v)
    xdb()[key] = v
    if bar then Layout(); UpdateXP() end
end

-- ---- events -----------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    if C_Timer and C_Timer.After then C_Timer.After(0.3, XP.ApplyAll) else XP.ApplyAll() end
end)
