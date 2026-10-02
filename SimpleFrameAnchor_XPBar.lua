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
    replace    = true,        -- hide Blizzard's status-tracking XP bar and sit where it was
    posInit    = false,       -- have we adopted Blizzard's position/width once?
    x          = 0,
    y          = -120,
    width      = 360,
    height     = 14,
    frame      = "forever",   -- "forever" | "prof" | "none"  (default per request)
    profession = "Cooking",   -- flipbook profession atlas suffix, or "none" (default per request)
    stretch    = true,        -- stretch one copy of the profession art across the whole bar
                              -- (default); off tiles it at the art's native proportions
    showTicks   = true,       -- 10% dividers (use the divider-text color)
    show5       = false,      -- extra 5% dividers
    divider5Style = "dashed", -- "solid" | "dashed" | "dotted" | "none"
    tick5Color  = { 220 / 255, 167 / 255, 127 / 255 },   -- bronze (EUI default)
    dividerText = true,       -- % labels at each 10% divider
    dividerTextX     = 0,     -- label horizontal offset
    dividerTextY     = 2,     -- label vertical offset above the bar
    dividerTextColor = { 1, 1, 1 },   -- also used for the 10% lines
    showText    = true,       -- level / XP% on the bar
    textX       = 0,          -- bar text offset
    textY       = 10,         -- default 10px higher
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
local PlayFlipOnce   -- defined in the flipbook section; used by UpdateXP below

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

    -- Profession flipbook: one pass on each XP gain (a level-up is a gain too).
    if bar._fvFlipSmart then
        local lv = bar._lastLevel
        if lv and (level > lv or (level == lv and cur > (bar._lastXP or 0))) then
            PlayFlipOnce()
        end
    end
    bar._lastXP, bar._lastLevel = cur, level

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

-- ---- profession flipbook fill (ported from EllesmereUI ApplyXPFlipFill) ------
-- The client's skill-bar art (2 columns x rows, 856x34 frames) tiled over the
-- XP fill, masked to the fill's right edge, one 2 s pass played on each XP gain.
local FLIP_MAX_TILES = 24
local FLIP_SLOW_IN = {
    Skillbar_Fill_Flipbook_Jewelcrafting = true,
    Skillbar_Fill_Flipbook_Leatherworking = true,
}

-- The client keeps the flipbook FRAME size constant (856 x 34) and varies the atlas's
-- native size per profession, so cols AND rows must be derived per atlas -- a fixed 2-col
-- grid samples the wrong cells on other sizes (texture appears to rotate). (Per XPFlipTest.)
local FLIP_FRAME_W, FLIP_FRAME_H = 856, 34
local function FlipGrid(info)
    local cols = math.max(1, math.floor(info.width / FLIP_FRAME_W + 0.5))
    local rows = math.max(1, math.floor(info.height / FLIP_FRAME_H + 0.5))
    return cols, rows
end

local function FlipStatic(tex, info, cols, rows)
    tex:SetTexture(info.file or info.filename)
    local l, r, t, b = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    tex:SetTexCoord(l, l + (r - l) / cols, t, t + (b - t) / rows)   -- frame 0 (top-left cell)
end

local function NewFlipTile(parent, mask)
    local t = {}
    t.idle = parent:CreateTexture(nil, "OVERLAY", nil, 0)
    t.flip = parent:CreateTexture(nil, "OVERLAY", nil, 1)
    t.idle:AddMaskTexture(mask); t.flip:AddMaskTexture(mask)
    local function Book(group)
        local fb = group:CreateAnimation("FlipBook")
        fb:SetTarget(t.flip); fb:SetDuration(2); fb:SetFlipBookColumns(2)
        fb:SetFlipBookFrameWidth(0); fb:SetFlipBookFrameHeight(0)
        return fb
    end
    local once = parent:CreateAnimationGroup()
    once._fb = Book(once)
    local fIn = once:CreateAnimation("Alpha"); fIn:SetTarget(t.flip); fIn:SetFromAlpha(0); fIn:SetToAlpha(1); once._fadeIn = fIn
    local fOut = once:CreateAnimation("Alpha"); fOut:SetTarget(t.flip); fOut:SetOrder(2)
    fOut:SetFromAlpha(1); fOut:SetToAlpha(0); fOut:SetStartDelay(0.2); fOut:SetDuration(0.5)
    t.once = once
    local loop = parent:CreateAnimationGroup(); loop._fb = Book(loop); loop:SetLooping("REPEAT"); t.loop = loop
    return t
end

local function HideFlipTile(t) t.once:Stop(); t.loop:Stop(); t.flip:Hide(); t.idle:Hide() end

local function PlaceFlipLayer(r, parent, x, tw)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", parent, "TOPLEFT", x, 0)
    r:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, 0)
    r:SetWidth(tw)
end

local function FlipAtlasFor(d)
    if not d.profession or d.profession == "none" then return nil end
    return "Skillbar_Fill_Flipbook_" .. d.profession
end

local function ApplyFlipFill()
    if not bar then return end
    local d = xdb()
    local fill = bar.Fill
    local tex = fill:GetStatusBarTexture()
    local atlas = FlipAtlasFor(d)
    local info = atlas and C_Texture.GetAtlasInfo(atlas)
    local tiles = bar._fvTiles
    if not info then
        if bar._fvFlipOn then
            bar._fvFlipOn, bar._fvFlipSmart, bar._fvTileN, bar._fvFlipAtlas = nil, nil, nil, nil
            if tiles then for i = 1, #tiles do HideFlipTile(tiles[i]) end end
            if tex then tex:SetAlpha(1) end
        end
        return
    end
    local mask = bar._fvFlipMask
    if not tiles then
        mask = fill:CreateMaskTexture()
        mask:SetTexture("Interface\\Buttons\\WHITE8x8",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE", "NEAREST")
        bar._fvFlipMask = mask
        tiles = {}; bar._fvTiles = tiles
    end
    mask:ClearAllPoints()
    mask:SetPoint("RIGHT", tex, "RIGHT")   -- rides the fill edge on every value change
    mask:SetSize(bar:GetSize())

    local cols, rows = FlipGrid(info)
    local frameW, frameH = info.width / cols, info.height / rows
    local bw, bh = fill:GetSize()
    local n, tw = 1, bw   -- stretch (default): one copy across the whole bar
    if (not d.stretch) and bh > 0 then
        tw = math.max(1, math.floor(bh * frameW / frameH + 0.5))
        n = math.max(1, math.ceil(bw / tw))
        if n > FLIP_MAX_TILES then n = FLIP_MAX_TILES; tw = bw / n end
    end
    local resync = n ~= bar._fvTileN or atlas ~= bar._fvFlipAtlas
    for i = #tiles + 1, n do tiles[i] = NewFlipTile(fill, mask) end
    for i = n + 1, #tiles do HideFlipTile(tiles[i]) end
    local fadeIn = FLIP_SLOW_IN[atlas] and 0.5 or 0.25
    for i = 1, n do
        local t = tiles[i]
        if resync then t.once:Stop(); t.loop:Stop() end
        if t.atlas ~= atlas then
            t.once._fb:SetFlipBookColumns(cols); t.once._fb:SetFlipBookRows(rows); t.once._fb:SetFlipBookFrames(cols * rows)
            t.loop._fb:SetFlipBookColumns(cols); t.loop._fb:SetFlipBookRows(rows); t.loop._fb:SetFlipBookFrames(cols * rows)
            t.once._fadeIn:SetDuration(fadeIn)
            t.flip:SetAtlas(atlas)
            FlipStatic(t.idle, info, cols, rows)
            t.atlas = atlas
        end
        local x = (i - 1) * tw
        PlaceFlipLayer(t.flip, fill, x, tw)
        PlaceFlipLayer(t.idle, fill, x, tw)
        t.idle:Show()
    end
    bar._fvFlipOn, bar._fvTileN, bar._fvFlipAtlas = true, n, atlas
    if tex then tex:SetAlpha(0) end
    bar._fvFlipSmart = true   -- play one pass on each XP gain
    for i = 1, n do
        local t = tiles[i]
        t.loop:Stop()
        t.flip:SetAlpha(0); t.flip:Show()
    end
end

PlayFlipOnce = function()
    local tiles, n = bar and bar._fvTiles, bar and bar._fvTileN
    if not (tiles and n) or (tiles[1] and tiles[1].once:IsPlaying()) then return end
    for i = 1, n do tiles[i].once:Play() end
end

-- Position the bar's level/XP% text (its own X/Y offset).
local function PositionText()
    if not (bar and bar.Text and bar.Overlay) then return end
    local d = xdb()
    bar.Text:ClearAllPoints()
    bar.Text:SetPoint("CENTER", bar.Overlay, "CENTER", d.textX or 0, d.textY or 0)
end

-- Divider ticks (EUI model): full 10% lines in the divider-text color; optional 5% lines
-- in their own colour with a style -- solid / dashed / dotted / none. All on the overlay
-- (above the fill/flipbook). Width/height come from the holder's SetSize (resolved now),
-- not the anchored fill's GetWidth (still 0 this frame). Segments share one pool.
local function DrawTicks()
    if not (bar and bar.Overlay) then return end
    local d = xdb()
    bar._tickSegs = bar._tickSegs or {}
    bar._tickText = bar._tickText or {}
    for _, t in ipairs(bar._tickSegs) do t:Hide() end
    for _, fs in ipairs(bar._tickText) do fs:Hide() end
    if not d.showTicks then return end

    local inset = ((d.frame == "forever") and ForeverOK()) and RING_LINE or 0
    local w = (d.width or bar:GetWidth() or 0) - 2 * inset
    local h = (d.height or bar:GetHeight() or 0) - 2 * inset
    if w <= 0 or h <= 0 then return end

    local tenC = d.dividerTextColor or { 1, 1, 1 }
    local fiveC = d.tick5Color or { 220 / 255, 167 / 255, 127 / 255 }
    local style5 = d.divider5Style or "dashed"

    local segIdx = 0
    local function seg(x, yTop, segH, c)
        segIdx = segIdx + 1
        local t = bar._tickSegs[segIdx]
        if not t then t = bar.Overlay:CreateTexture(nil, "OVERLAY", nil, 3); bar._tickSegs[segIdx] = t end
        t:SetWidth(1)
        t:SetColorTexture(c[1], c[2], c[3], c[4] or 0.9)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", bar.Fill, "TOPLEFT", x, -yTop)
        t:SetHeight(math.max(1, segH))
        t:Show()
    end

    -- 5% lines (the odd marks) with the chosen style.
    if d.show5 and style5 ~= "none" then
        local dashLen = (style5 == "dotted") and 1 or 2
        local step = dashLen + 2
        for p = 5, 95, 10 do
            local x = (p / 100) * w
            if style5 == "solid" then
                seg(x, 0, h, fiveC)
            else
                local yy = 0
                while yy < h do seg(x, yy, math.min(dashLen, h - yy), fiveC); yy = yy + step end
            end
        end
    end

    -- 10% lines (full height, divider-text colour).
    for p = 10, 90, 10 do seg((p / 100) * w, 0, h, tenC) end

    -- % labels.
    if d.dividerText then
        local n = 0
        for p = 10, 90, 10 do
            n = n + 1
            local fs = bar._tickText[n]
            if not fs then
                fs = bar.Overlay:CreateFontString(nil, "OVERLAY")
                fs:SetFontObject("GameFontHighlightSmall")
                bar._tickText[n] = fs
            end
            fs:SetText(p .. "%")
            fs:SetTextColor(tenC[1], tenC[2], tenC[3])
            fs:ClearAllPoints()
            fs:SetPoint("BOTTOM", bar.Fill, "TOPLEFT", (p / 100) * w + (d.dividerTextX or 0), d.dividerTextY or 2)
            fs:Show()
        end
    end
end

local function Layout()
    if not bar then return end
    local d = xdb()
    bar:SetSize(d.width, d.height)
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", UIParent, "CENTER", d.x, d.y)
    ApplySkin()
    ApplyFlipFill()
    DrawTicks()
    PositionText()
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

    -- Overlay frame ABOVE the fill so the text and dividers aren't covered by the
    -- fill's own texture / the profession flipbook (child textures draw over parent).
    local overlay = CreateFrame("Frame", nil, bar)
    overlay:SetAllPoints(bar)
    overlay:SetFrameLevel(fill:GetFrameLevel() + 5)
    bar.Overlay = overlay

    local text = overlay:CreateFontString(nil, "OVERLAY")
    text:SetFontObject("SystemFont_Shadow_Small")
    text:SetPoint("CENTER", overlay, "CENTER", 0, 0)
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

-- Professions whose skill-bar flipbook atlas exists on this client (for the picker).
local PROFESSIONS = {
    "Cooking", "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Herbalism",
    "Inscription", "Jewelcrafting", "Leatherworking", "Mining", "Skinning", "Tailoring", "Fishing",
}
function XP.ProfessionOptions()
    local opts = { { value = "none", text = "None (plain fill)" } }
    for _, p in ipairs(PROFESSIONS) do
        if C_Texture.GetAtlasInfo("Skillbar_Fill_Flipbook_" .. p) then
            opts[#opts + 1] = { value = p, text = p }
        end
    end
    return opts
end

-- ---- public API -------------------------------------------------------------
function XP.Get() return xdb() end

-- ---- replace Blizzard's status-tracking XP bar + adopt its position ---------
local function BlizzBar()
    return _G.MainStatusTrackingBarContainer or _G.StatusTrackingBarManager
end

local function HideBlizz()
    local b = BlizzBar()
    if not b then return end
    if not b._sfaHooked then
        b._sfaHooked = true
        b:HookScript("OnShow", function(self)
            if xdb().enabled and xdb().replace then self:Hide() end
        end)
    end
    b:Hide()
end

local function ShowBlizz()
    local b = BlizzBar()
    if b then b:Show() end   -- best effort; a /reload fully restores Blizzard's management
end

-- Adopt Blizzard's bar position + width once, so ours lands where the default was.
local function MatchBlizzPosition()
    local b = BlizzBar()
    if not b or not b.GetCenter then return false end
    local cx, cy = b:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and ux) then return false end
    local d = xdb()
    d.x = math.floor(cx - ux + 0.5)
    d.y = math.floor(cy - uy + 0.5)
    local w = b:GetWidth()
    if w and w > 60 then d.width = math.floor(w + 0.5) end
    return true
end
XP.MatchBlizzPosition = function() if MatchBlizzPosition() then Layout() end end

function XP.ApplyAll()
    local d = xdb()
    if not d.enabled then
        if bar then bar:Hide() end
        return
    end
    -- Adopt the default bar's spot the first time, BEFORE hiding it.
    if not d.posInit then
        if MatchBlizzPosition() then d.posInit = true end
    end
    if d.replace then HideBlizz() end
    EnsureBar()
    Layout()
    UpdateXP()
end

function XP.SetEnabled(on)
    local d = xdb()
    d.enabled = on and true or false
    if on then
        if not d.posInit and MatchBlizzPosition() then d.posInit = true end
        if d.replace then HideBlizz() end
        EnsureBar(); Layout(); UpdateXP()
        print("|cff66ccffSimpleFrameAnchor|r: Experience bar ON" .. (d.replace and " (Blizzard's hidden)." or "."))
    else
        if bar then bar:Hide() end
        ShowBlizz()
        print("|cff66ccffSimpleFrameAnchor|r: Experience bar OFF -- |cffffff00/reload|r if Blizzard's bar does not return.")
    end
end

function XP.SetReplace(on)
    xdb().replace = on and true or false
    if xdb().enabled then
        if on then HideBlizz() else ShowBlizz() end
    end
    if not on then print("|cff66ccffSimpleFrameAnchor|r: /reload if Blizzard's XP bar does not return.") end
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
