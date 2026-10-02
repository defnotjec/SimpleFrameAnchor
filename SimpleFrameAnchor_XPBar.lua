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

-- ---- "Forever" frame: WoW Forever's bronze border, ported from EllesmereUI's
--      ForeverBorder. All in-game atlas art (UI-HUD-ActionBar-Frame), no bundle. ---
local RING_ATLAS = "UI-HUD-ActionBar-Frame"
local RS, RM, RC, RD, RE = 55, 3, 8.5, 6, 12
local RING_LINE = 2   -- the bronze line's thickness; fill/bg sit inside it
local RING_CUT, RING_AT
do
    local c, d, e = RC / RS, RD / RS, RE / RS
    RING_CUT = {
        { 0, c, 0, c }, { 1 - c, 1, 0, c }, { 0, c, 1 - c, 1 }, { 1 - c, 1, 1 - c, 1 },
        { e, 1 - e, 0, d }, { e, 1 - e, 1 - d, 1 }, { 0, d, e, 1 - e }, { 1 - d, 1, e, 1 - e },
    }
    RING_AT = {
        { "TOPLEFT", 0, 0 }, { "TOPRIGHT", 0, 0 }, { "BOTTOMLEFT", 0, 0 }, { "BOTTOMRIGHT", 0, 0 },
        { "TOPLEFT", RC, 0, "TOPRIGHT", -RC, 0 }, { "BOTTOMLEFT", RC, 0, "BOTTOMRIGHT", -RC, 0 },
        { "TOPLEFT", 0, -RC, "BOTTOMLEFT", 0, RC }, { "TOPRIGHT", 0, -RC, "BOTTOMRIGHT", 0, RC },
    }
end

local function ForeverOK()
    return C_Texture.GetAtlasInfo(RING_ATLAS) ~= nil   -- present only on the Forever client
end

local function MakeRing(frame)
    local info = C_Texture.GetAtlasInfo(RING_ATLAS); if not info then return nil end
    local file = info.file or info.filename
    local L, T = info.leftTexCoord, info.topTexCoord
    local W, H = info.rightTexCoord - L, info.bottomTexCoord - T
    local box = frame:CreateTexture()
    local ring = { box = box }
    for i = 1, 8 do
        local t = frame:CreateTexture(nil, "OVERLAY", nil, 1)
        t:SetTexture(file)
        local cut, at = RING_CUT[i], RING_AT[i]
        t:SetTexCoord(L + W * cut[1], L + W * cut[2], T + H * cut[3], T + H * cut[4])
        t:SetPoint(at[1], box, at[1], at[2], at[3])
        if at[4] then
            t:SetPoint(at[4], box, at[4], at[5], at[6])
            if i <= 6 then t:SetHeight(RD) else t:SetWidth(RD) end
        else
            t:SetSize(RC, RC)
        end
        ring[i] = t
    end
    return ring
end

local function SeatRing(ring, rel)
    local box = ring.box
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", rel, "TOPLEFT", -RM, RM)
    box:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", RM, -RM)
end

local function FitRing(ring, w, h)
    local span = 2 * (RC - RM)
    local wide, tall = w >= span, h >= span
    ring[5]:SetShown(wide); ring[6]:SetShown(wide)
    ring[7]:SetShown(tall); ring[8]:SetShown(tall)
end

-- ---- the bar ----------------------------------------------------------------
local bar   -- lazily created holder Frame (bar.Fill / bar.Rested / bar.BG / bar.Text)

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

    bar.Fill:SetMinMaxValues(0, maxXP)
    bar.Fill:SetValue(cur)

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

-- Apply the selected frame skin (inset the fill by the border line + show the ring).
local function ApplySkin()
    if not bar then return end
    local d = xdb()
    local useForever = (d.frame == "forever") and ForeverOK()
    local inset = useForever and RING_LINE or 0

    for _, f in ipairs({ bar.BG, bar.Fill, bar.Rested }) do
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", bar, "TOPLEFT", inset, -inset)
        f:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -inset, inset)
    end

    if useForever then
        if not bar._ring then
            bar._ring = MakeRing(bar)
            if bar._ring then SeatRing(bar._ring, bar) end
        end
        if bar._ring then
            for i = 1, 8 do bar._ring[i]:Show() end
            FitRing(bar._ring, bar:GetWidth(), bar:GetHeight())
        end
    elseif bar._ring then
        for i = 1, 8 do bar._ring[i]:Hide() end
    end
end

local function Layout()
    if not bar then return end
    local d = xdb()
    bar:SetSize(d.width, d.height)
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", UIParent, "CENTER", d.x, d.y)
    ApplySkin()
end

local function EnsureBar()
    if bar then return bar end
    bar = CreateFrame("Frame", "SFA_XPBar", UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:Hide()

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0, 0, 0, 0.5)
    bar.BG = bg

    -- Rested overlay (behind the fill), then the fill.
    local rested = CreateFrame("StatusBar", nil, bar)
    rested:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    rested:SetStatusBarColor(COLOR.rested[1], COLOR.rested[2], COLOR.rested[3], 0.6)
    rested:GetStatusBarTexture():SetDrawLayer("ARTWORK", 0)
    rested:SetMinMaxValues(0, 1); rested:SetValue(0)
    rested:Hide()
    bar.Rested = rested

    local fill = CreateFrame("StatusBar", nil, bar)
    fill:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    fill:SetStatusBarColor(COLOR.xp[1], COLOR.xp[2], COLOR.xp[3])
    fill:GetStatusBarTexture():SetDrawLayer("ARTWORK", 1)
    fill:SetMinMaxValues(0, 1); fill:SetValue(0)
    bar.Fill = fill

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

function XP.ForeverAvailable() return ForeverOK() end

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
