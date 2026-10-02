-- SimpleFrameAnchor - Cast Bars
--
-- "Legion Classic" reskin of Blizzard's default cast bars, using in-game textures
-- (Interface\CastingBar\*). Adapted from the LegionClassicCastbars approach: hide the
-- native fill, draw our own Legion-textured fill that tracks the bar's value, and swap
-- the Border / Shield / Flash / Spark / Text art. Colour is reasserted on the bar's own
-- OnEvent so interruptible/uninterruptible/channel states read correctly.
--
-- This client reports WOW_PROJECT_MAINLINE (probe): PlayerCastingBarFrame (no legacy
-- CastingBarFrame), and every cast bar exposes .Border/.BorderShield/.Flash/.Icon/
-- .Spark/.Text/.TextBorder, so the retail-style reskin ports directly.
--
-- Nameplate cast bars are intentionally a no-op for now.

local ADDON, ns = ...
ns = ns or {}

local CB = {}
ns.CB = CB

local issecretvalue = issecretvalue or function() return false end
local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo

-- ---- artwork (the only place textures are chosen) ---------------------------
local TEX = {
    fill         = [[Interface\TargetingFrame\UI-StatusBar]],
    borderSmall  = [[Interface\CastingBar\UI-CastingBar-Border-Small]],
    borderLarge  = [[Interface\CastingBar\UI-CastingBar-Border]],
    shield       = [[Interface\CastingBar\UI-CastingBar-Small-Shield]],
    flashSmall   = [[Interface\CastingBar\UI-CastingBar-Flash-Small]],
    spark        = [[Interface\CastingBar\UI-CastingBar-Spark]],
}
local COL = {
    standard    = { 1, 0.7, 0 },
    channel     = { 0, 1, 0 },
    uninterrupt = { 0.7, 0.7, 0.7 },
    interrupted = { 1, 0, 0 },
}

-- ---- DB ---------------------------------------------------------------------
local function cdb()
    SimpleFrameAnchorDB = SimpleFrameAnchorDB or {}
    SimpleFrameAnchorDB.castbars = SimpleFrameAnchorDB.castbars or {}
    return SimpleFrameAnchorDB.castbars
end

-- ---- colour -----------------------------------------------------------------
local function tint(tex, notInterruptible, cUn, cBase)
    if issecretvalue(notInterruptible) and tex.SetVertexColorFromBoolean then
        tex:SetVertexColorFromBoolean(notInterruptible,
            CreateColor(cUn[1], cUn[2], cUn[3], 1), CreateColor(cBase[1], cBase[2], cBase[3], 1))
    elseif notInterruptible then
        tex:SetVertexColor(cUn[1], cUn[2], cUn[3])
    else
        tex:SetVertexColor(cBase[1], cBase[2], cBase[3])
    end
end

-- Replace the fill with our Legion-textured one and colour it by cast state.
local function Recolor(self)
    if not self or (self.IsForbidden and self:IsForbidden()) or not self.unit then return end

    self:SetStatusBarColor(0, 0, 0, 0)
    local st = self:GetStatusBarTexture(); if st then st:Hide() end
    self:SetStatusBarTexture("")

    if not self.LCC_fill then
        self.LCC_fill = self:CreateTexture(nil, "BORDER", nil, 0)
        self.LCC_fill:SetAllPoints(self:GetStatusBarTexture())
        self.LCC_fill:SetTexture(TEX.fill)
        self.LCC_fill:SetHorizTile(true)
    end

    local unit = self.unit
    if UnitCastingInfo(unit) then
        local _, _, _, _, _, _, _, notInterruptible = UnitCastingInfo(unit)
        tint(self.LCC_fill, notInterruptible, COL.uninterrupt, COL.standard)
    elseif UnitChannelInfo(unit) then
        local _, _, _, _, _, _, notInterruptible, _, _, numStages = UnitChannelInfo(unit)
        if numStages and numStages > 0 then
            self.LCC_fill:SetVertexColor(0, 0, 0, 0)   -- empowered: let Blizzard's stage art show
        else
            tint(self.LCC_fill, notInterruptible, COL.uninterrupt, COL.channel)
            if self.Spark then self.Spark:Hide() end
        end
    end
end

-- ---- static skin ------------------------------------------------------------
local function skinCommon(self)
    if self.Background then self.Background:SetDrawLayer("BACKGROUND", 0); self.Background:SetColorTexture(0, 0, 0, 0.5) end
    if self.Border then self.Border:SetDrawLayer("ARTWORK", 0) end
    if self.Flash then self.Flash:SetDrawLayer("OVERLAY", 0) end
    if self.Text then self.Text:SetDrawLayer("OVERLAY", 0) end
    if self.Spark then self.Spark:SetDrawLayer("OVERLAY", 1) end
    if self.BorderShield then self.BorderShield:SetDrawLayer("OVERLAY", 0) end
    if self.Icon then self.Icon:SetDrawLayer("OVERLAY", 0) end
    if self.TextBorder then self.TextBorder:Hide() end
    if self.Spark then self.Spark:SetTexture(TEX.spark); self.Spark:SetBlendMode("ADD"); self.Spark:SetSize(32, 32) end
end

-- Small bars: target / focus / boss.
local function styleSmall(self)
    skinCommon(self)
    self:SetSize(150, 10)
    if self.Border then
        self.Border:ClearAllPoints()
        self.Border:SetPoint("TOPLEFT", -23, 20); self.Border:SetPoint("TOPRIGHT", 23, 20)
        self.Border:SetTexture(TEX.borderSmall); self.Border:SetSize(0, 49)
    end
    if self.BorderShield then
        self.BorderShield:SetTexture(TEX.shield)
        self.BorderShield:ClearAllPoints()
        self.BorderShield:SetPoint("TOPLEFT", -28, 20); self.BorderShield:SetPoint("TOPRIGHT", 18, 20)
        self.BorderShield:SetSize(0, 49)
    end
    if self.Flash then
        self.Flash:SetTexture(TEX.flashSmall); self.Flash:SetSize(0, 49)
        self.Flash:ClearAllPoints()
        self.Flash:SetPoint("TOPLEFT", -23, 20); self.Flash:SetPoint("TOPRIGHT", 23, 20)
        self.Flash:SetBlendMode("ADD")
    end
    if self.Text then
        self.Text:ClearAllPoints()
        self.Text:SetPoint("TOPLEFT", 0, 4); self.Text:SetPoint("TOPRIGHT", 0, 4)
        self.Text:SetSize(130, 16); self.Text:SetFontObject("SystemFont_Shadow_Small")
    end
    if self.Icon then
        self.Icon:ClearAllPoints()
        self.Icon:SetPoint("RIGHT", self, "LEFT", -5, 0); self.Icon:SetSize(16, 16)
    end
end

-- Player / pet: the large ornate Legion bar when free-floating; small when attached.
local function stylePlayer(self)
    skinCommon(self)
    local attached = self.attachedToPlayerFrame
    if attached then
        self:SetSize(150, 10)
        if self.Border then
            self.Border:SetTexture(TEX.borderSmall); self.Border:SetSize(0, 49)
            self.Border:ClearAllPoints()
            self.Border:SetPoint("TOPLEFT", -23, 20); self.Border:SetPoint("TOPRIGHT", 23, 20)
        end
        if self.BorderShield then
            self.BorderShield:SetTexture(TEX.shield); self.BorderShield:SetSize(0, 49)
            self.BorderShield:ClearAllPoints()
            self.BorderShield:SetPoint("TOPLEFT", -28, 20); self.BorderShield:SetPoint("TOPRIGHT", 18, 20)
        end
        if self.Text then
            self.Text:ClearAllPoints()
            self.Text:SetPoint("TOPLEFT", 0, 4); self.Text:SetPoint("TOPRIGHT", 0, 4)
            self.Text:SetSize(0, 16); self.Text:SetFontObject("SystemFont_Shadow_Small")
        end
        if self.Icon then self.Icon:Show() end
    else
        self:SetSize(195, 13)
        if self.Border then
            self.Border:SetTexture(TEX.borderLarge); self.Border:SetSize(256, 64)
            self.Border:ClearAllPoints(); self.Border:SetPoint("TOP", 0, 28)
        end
        if self.BorderShield then
            self.BorderShield:SetTexture(TEX.shield); self.BorderShield:SetSize(256, 64)
            self.BorderShield:ClearAllPoints(); self.BorderShield:SetPoint("TOP", 0, 28)
        end
        if self.Text then
            self.Text:ClearAllPoints(); self.Text:SetPoint("TOP", 0, 5)
            self.Text:SetSize(185, 16); self.Text:SetFontObject("GameFontHighlight")
        end
        if self.Icon then self.Icon:Hide() end
    end
end

-- ---- apply / hook a single bar ----------------------------------------------
local function applyBar(self, isPlayer)
    if not self or (self.IsForbidden and self:IsForbidden()) then return end
    local styleFn = isPlayer and stylePlayer or styleSmall
    pcall(styleFn, self)
    pcall(Recolor, self)

    if self.LCC_hooked then return end
    self.LCC_hooked = true

    self:HookScript("OnEvent", Recolor)
    -- Reassert our skin whenever Blizzard re-inits the bar's art.
    if isPlayer and self.GetTypeInfo then hooksecurefunc(self, "GetTypeInfo", function(s) pcall(styleFn, s) end) end
    if self.ShowSpark then hooksecurefunc(self, "ShowSpark", function(s)
        if s.Spark then s.Spark:SetTexture(TEX.spark); s.Spark:SetBlendMode("ADD"); s.Spark:SetSize(32, 32) end
    end) end
    if self.PlayFinishAnim then hooksecurefunc(self, "PlayFinishAnim", function(s)
        if s.Flash and s.LCC_fill then s.Flash:SetVertexColor(s.LCC_fill:GetVertexColor()) end
    end) end
end

-- ---- public API -------------------------------------------------------------
local function barList()
    local t = {
        { f = PlayerCastingBarFrame, player = true },
        { f = PetCastingBarFrame,    player = true },
        { f = TargetFrame and TargetFrame.spellbar },
        { f = FocusFrame and FocusFrame.spellbar },
    }
    for i = 1, 5 do
        local b = _G["Boss" .. i .. "TargetFrame"]
        if b and b.spellbar then t[#t + 1] = { f = b.spellbar } end
    end
    return t
end

function CB.IsEnabled()
    return cdb().legionStyle and true or false
end

function CB.ApplyAll()
    if not CB.IsEnabled() then return end
    for _, e in ipairs(barList()) do
        if e.f then pcall(applyBar, e.f, e.player) end
    end
end

function CB.SetEnabled(on)
    cdb().legionStyle = on and true or false
    if on then
        CB.ApplyAll()
        print("|cff66ccffSimpleFrameAnchor|r: Legion cast bar style ON.")
    else
        print("|cff66ccffSimpleFrameAnchor|r: Legion cast bar style OFF -- |cffffff00/reload|r to restore Blizzard's default art.")
    end
end

-- ---- events -----------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")   -- boss frames appear on entering instances
ev:SetScript("OnEvent", function()
    if C_Timer and C_Timer.After then C_Timer.After(0.3, CB.ApplyAll) else CB.ApplyAll() end
end)
