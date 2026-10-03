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

local function containerOf(frame)
    if frame and frame.GetAuraContainer then return frame:GetAuraContainer() end
    return nil
end

-- Set the container to base + offset, computing the TRUE base via a sentinel so it is
-- never cumulative (a plain AdjustPointsOffset drifts when an anchor fires without Blizzard
-- first resetting to base -- which is exactly what Focus does on a target change). SetPoint
-- is made idempotent (skipped when already correct) so it cannot re-trigger a layout loop,
-- and a once-per-frame flag blocks re-entry -- so hooking the broad UpdateAuras is safe and
-- catches the initial render (no base-then-jump flicker).
local applied = {}
local function OffsetAuras(frame, key)
    local cfg = acfg(key)
    if not cfg.enabled or applied[key] then return end
    local container = containerOf(frame)
    if not (container and container.GetPoint) then return end
    local p, rel, rp, ox, oy = container:GetPoint(1)
    if not p then return end
    ox, oy = ox or 0, oy or 0

    applied[key] = true
    if C_Timer and C_Timer.After then C_Timer.After(0, function() applied[key] = false end) end

    -- Detect whether the current point 1 is our last-applied result; if so the base is
    -- unchanged (and the currently-applied offset is m.off); otherwise Blizzard reset to a
    -- fresh base with no offset. Then shift ALL points by the delta to reach base + cfg.
    local m = container._sfaSet
    local ours = m and m.p == p and m.rel == rel and m.rp == rp
        and math.abs(ox - (m.baseX + m.offX)) < 0.5 and math.abs(oy - (m.baseY + m.offY)) < 0.5
    local baseX, baseY, curOffX, curOffY
    if ours then
        baseX, baseY, curOffX, curOffY = m.baseX, m.baseY, m.offX, m.offY
    else
        baseX, baseY, curOffX, curOffY = ox, oy, 0, 0
    end

    local dx, dy = cfg.x - curOffX, cfg.y - curOffY
    if math.abs(dx) > 0.5 or math.abs(dy) > 0.5 then
        if container.AdjustPointsOffset then container:AdjustPointsOffset(dx, dy)
        else container:SetPoint(p, rel, rp, ox + dx, oy + dy) end
    end
    container._sfaSet = { p = p, rel = rel, rp = rp, baseX = baseX, baseY = baseY, offX = cfg.x, offY = cfg.y }
end

local function RestoreAuras(frame)
    local container = containerOf(frame)
    local m = container and container._sfaSet
    if not m then return end
    local p, _, _, ox, oy = container:GetPoint(1)
    if p and math.abs((ox or 0) - (m.baseX + m.offX)) < 0.5 and math.abs((oy or 0) - (m.baseY + m.offY)) < 0.5 then
        if container.AdjustPointsOffset then container:AdjustPointsOffset(-m.offX, -m.offY)
        else container:SetPoint(m.p, m.rel, m.rp, m.baseX, m.baseY) end
    end
    container._sfaSet = nil
end

local AURA_ANCHOR_FNS = { "UpdateAuraContainerAnchors", "AnchorAuraContainer", "ConfigureAuraContainer", "UpdateAuras" }
local auraHooked = {}
local function HookAuras(key)
    local frame = AURA_FRAME[key] and AURA_FRAME[key]()
    if not frame then return false end
    auraHooked[key] = auraHooked[key] or {}
    local any = false
    for _, fn in ipairs(AURA_ANCHOR_FNS) do
        if type(frame[fn]) == "function" and not auraHooked[key][fn] then
            auraHooked[key][fn] = true
            hooksecurefunc(frame, fn, function(self) OffsetAuras(self, key) end)
            any = true
        end
    end
    return any
end

local function ApplyNow(key)
    applied[key] = false
    OffsetAuras(AURA_FRAME[key] and AURA_FRAME[key](), key)
end

function UF.GetAura(key) return acfg(key) end

function UF.SetAuraEnabled(key, on)
    acfg(key).enabled = on and true or false
    HookAuras(key)
    if on then ApplyNow(key) else RestoreAuras(AURA_FRAME[key] and AURA_FRAME[key]()) end
end

function UF.SetAuraPos(key, axis, v)
    acfg(key)[axis] = v
    ApplyNow(key)
end

-- Install the hook (if the frame/method is ready yet) AND force-apply the saved offset,
-- so it persists across reloads without needing a live aura change.
local function TryAura(key)
    HookAuras(key)
    if acfg(key).enabled then ApplyNow(key) end
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
