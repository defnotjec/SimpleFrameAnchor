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

-- ============================================================================
--  Show / Move  (Target, Focus -- native bars; ToT created separately)
--  Re-anchor the native spell bar to UIParent at a saved offset and reassert it
--  whenever Blizzard re-shows/re-anchors it. If this proves not to stick on this
--  client (protected layout), these bars move to the own-bar path like ToT.
-- ============================================================================
local MOVE_KEYS = { "target", "focus" }
local MOVE_BAR = {
    target = function() return TargetFrame and TargetFrame.spellbar end,
    focus  = function() return FocusFrame and FocusFrame.spellbar end,
}
local MOVE_DEFAULT = { target = { x = 0, y = -180 }, focus = { x = 0, y = -210 } }

local function mcfg(key)
    local d = cdb()
    d.move = d.move or {}
    if not d.move[key] then
        local def = MOVE_DEFAULT[key] or { x = 0, y = -200 }
        d.move[key] = { enabled = false, x = def.x, y = def.y }
    end
    return d.move[key]
end

local function applyMove(key)
    local bar = MOVE_BAR[key] and MOVE_BAR[key]()
    if not bar then return end
    local cfg = mcfg(key)
    if cfg.enabled then
        bar.LCC_moved = true
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", UIParent, "CENTER", cfg.x, cfg.y)
    end
end

local moveHooked = {}
local function hookMove(key)
    local bar = MOVE_BAR[key] and MOVE_BAR[key]()
    if not bar or moveHooked[key] then return end
    moveHooked[key] = true
    -- Reassert on show. Apply SYNCHRONOUSLY first (so it renders in the moved spot with no
    -- first-frame flicker at the original location), then once more next frame as a backup
    -- in case Blizzard re-anchors after its own OnShow.
    bar:HookScript("OnShow", function()
        if not mcfg(key).enabled then return end
        applyMove(key)
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() if mcfg(key).enabled then applyMove(key) end end)
        end
    end)
end

function CB.MoveApplyAll()
    for _, key in ipairs(MOVE_KEYS) do
        hookMove(key)
        applyMove(key)
    end
end

local positionTest   -- defined in the test/preview section below

function CB.GetMove(key) return mcfg(key) end

function CB.SetMoveEnabled(key, on)
    mcfg(key).enabled = on and true or false
    hookMove(key)
    applyMove(key)
    if not on then
        print("|cff66ccffSimpleFrameAnchor|r: " .. key .. " cast bar position released -- |cffffff00/reload|r to restore default.")
    end
end

function CB.SetMovePos(key, axis, v)
    mcfg(key)[axis] = v
    applyMove(key)
    positionTest(key)   -- keep any visible preview in sync with the sliders
end

-- ---- test / preview frame ---------------------------------------------------
-- A draggable Legion-styled mock bar so you can position without a live cast.
local testFrames = {}
local TEST_LABEL = { target = "Target Cast Bar", focus = "Focus Cast Bar", tot = "ToT Cast Bar" }

positionTest = function(key)   -- forward-declared above (used by SetMovePos)
    local f = testFrames[key]
    if not f then return end
    local cfg = mcfg(key)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", cfg.x, cfg.y)
end

local function buildTest(key)
    if testFrames[key] then return testFrames[key] end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(150, 10)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)
    f:Hide()

    local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(f); bg:SetColorTexture(0, 0, 0, 0.5)

    local fill = f:CreateTexture(nil, "BORDER"); fill:SetTexture(TEX.fill); fill:SetHorizTile(true)
    fill:SetVertexColor(COL.standard[1], COL.standard[2], COL.standard[3])
    fill:SetPoint("TOPLEFT"); fill:SetPoint("BOTTOMLEFT")

    local border = f:CreateTexture(nil, "ARTWORK"); border:SetTexture(TEX.borderSmall)
    border:SetPoint("TOPLEFT", -23, 20); border:SetPoint("TOPRIGHT", 23, 20); border:SetHeight(49)

    local spark = f:CreateTexture(nil, "OVERLAY"); spark:SetTexture(TEX.spark)
    spark:SetBlendMode("ADD"); spark:SetSize(32, 32)

    local icon = f:CreateTexture(nil, "OVERLAY")
    icon:SetTexture([[Interface\ICONS\Spell_Nature_Lightning]])
    icon:SetPoint("RIGHT", f, "LEFT", -5, 0); icon:SetSize(16, 16); icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local txt = f:CreateFontString(nil, "OVERLAY"); txt:SetFontObject("SystemFont_Shadow_Small")
    txt:SetPoint("TOPLEFT", 0, 4); txt:SetPoint("TOPRIGHT", 0, 4); txt:SetHeight(16); txt:SetJustifyH("CENTER")
    txt:SetText(TEST_LABEL[key] or "Cast Bar")

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("BOTTOM", f, "TOP", 0, 8); hint:SetText("|cffaaaaaadrag to move|r")

    local function layoutFill()
        local w = f:GetWidth() or 150
        fill:SetWidth(math.max(1, w * 0.65))
        spark:ClearAllPoints(); spark:SetPoint("CENTER", f, "LEFT", w * 0.65, 0)
    end
    f:SetScript("OnSizeChanged", layoutFill)
    layoutFill()

    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if cx and ux then
            local cfg = mcfg(key)
            cfg.x = math.floor(cx - ux + 0.5)
            cfg.y = math.floor(cy - uy + 0.5)
            applyMove(key)
        end
        positionTest(key)
    end)

    testFrames[key] = f
    return f
end

function CB.IsTestShown(key)
    return (testFrames[key] and testFrames[key]:IsShown()) and true or false
end

function CB.SetTest(key, on)
    local f = buildTest(key)
    if on then positionTest(key); f:Show() else f:Hide() end
end

function CB.HideAllTests()
    for _, f in pairs(testFrames) do f:Hide() end
end

-- ---- events -----------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")   -- boss frames appear on entering instances
ev:SetScript("OnEvent", function()
    local function run()
        CB.ApplyAll()
        CB.MoveApplyAll()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.3, run) else run() end
end)
