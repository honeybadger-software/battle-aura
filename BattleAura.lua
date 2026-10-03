-- BattleAura v3.1.1 - immersive personal damage meter for WoW Forever (Interface 16001).
-- The frame IS the approved Tripo "Battle Aura" art (number lifted out) with LIVE effects laid on it. All positions are in
-- ART PIXELS of the 1024x1024 plate; the frame is scaled with SetScale.
--
-- WHAT IS LEGAL ON FOREVER (confirmed in-game / against shipping mods):
--   * Combat NUMBERS are secret in combat: never do Lua math/compare on them; only hand them to C-side sinks
--     (SetFormattedText "%.0f", AbbreviateNumbers). That is how the totals AND the floating hit numbers are shown.
--   * Timing is NOT secret: UNIT_COMBAT arrival (per-hit rhythm, flagText CRITICAL), UNIT_SPELLCAST_SUCCEEDED (casts),
--     combat start/end, DAMAGE_METER_* update cadence. All the motion/heat/combo/ring effects run on those.
--   * Per-hit amounts come from UNIT_COMBAT on "target" (same technique as the MidnightBattleText mod; read for the idea, no code
--     copied). Untested on Forever until now: BattleAuraDB.probe records whether it fires + whether amounts are secret.
--   * Records (best hit/DPS/damage) are compared only OUT of combat, when the numbers are readable plain numbers.
--
-- Slash: /ba  | scale | font | aura | hits | grouphits | best | test | reset

-- SavedVariables are NOT available while this file executes: WoW restores them just BEFORE ADDON_LOADED fires. So DB starts as
-- plain defaults (the frame builds and works immediately) and initDB() swaps in the real saved table on ADDON_LOADED.
-- (v3.0/3.1 grabbed BattleAuraDB at load time = a throwaway table: nothing was ever saved. Never cache the global at file level.)
local DB = { scale = 0.5, fontSize = 120, aura = true, hits = true, fights = {}, best = {}, ver = 3 }

local ART = "Interface\\AddOns\\BattleAura\\Art\\"
local NUMBER_FONT = "Fonts\\FRIZQT__.TTF"     -- Blizzard's own font; swap to a shipped OFL .ttf (e.g. Cinzel) later
local LABEL_FONT = "Fonts\\FRIZQT__.TTF"

-- layout in ART PIXELS (origin top-left, y grows downward), measured from the approved render
local NUM_X, NUM_Y = 762, 318                   -- the lifted "12,480"
local ROW_X, ROW1_Y, ROW2_Y, VAL_X = 590, 572, 614, 1000
local AURA_X, AURA_Y, AURA_SIZE = 330, 540, 820 -- glow behind the painted hero
local TIP_X, TIP_Y = 720, 815                   -- sword tip: floating hit numbers spawn here
local STAR_X, STAR_Y = 965, 405                 -- end star of the baked spark-line
local PATH = { {572,511},{600,510},{628,506},{656,503},{684,499},{712,499},{740,491},{768,497},{796,485},{824,478},{852,460},{880,466},{908,444},{936,430},{965,405} }

local sin, cos, exp, floor, random, min, max = math.sin, math.cos, math.exp, math.floor, math.random, math.min, math.max

-- ---- helpers ------------------------------------------------------------------------------
local OPTS_SHORT = { breakpointData = {
    { breakpoint = 1000000000, significandDivisor = 1000000000, fractionDivisor = 1, abbreviation = "B" },
    { breakpoint = 1000000,    significandDivisor = 1000000,    fractionDivisor = 1, abbreviation = "M" },
    { breakpoint = 1000,       significandDivisor = 1000,       fractionDivisor = 1, abbreviation = "K" },
    { breakpoint = 1,          significandDivisor = 1,          fractionDivisor = 1, abbreviation = ""  },
}}
local function isSecret(v) return issecretvalue and issecretvalue(v) end
local function plain(v)                          -- a plain Lua number, or nil when secret / not numeric
    if v == nil or isSecret(v) then return nil end
    local ok, n = pcall(function() return v + 0 end)
    if ok then return n end
    return nil
end
local function setFont(fs, path, size, flags)
    local ok = fs:SetFont(path, size, flags)
    if not ok then fs:SetFontObject(GameFontNormalHuge) end
end
local function showNum(fs, v)                    -- abbreviated, secret-safe (totals / dps / biggest hit)
    if v == nil then return end
    local ok, s = pcall(AbbreviateNumbers, v, OPTS_SHORT)
    if ok and type(s) == "string" then
        if not pcall(function() fs:SetText(s) end) then pcall(function() fs:SetFormattedText("%.0f", v) end) end
    else
        pcall(function() fs:SetFormattedText("%.0f", v) end)
    end
end
local function showRaw(fs, v)                    -- full integer, secret-safe (floating hit numbers)
    if v == nil then return false end
    if pcall(function() fs:SetFormattedText("%.0f", v) end) then return true end
    return (pcall(function() fs:SetText(v) end))
end

-- ---- frame + art -----------------------------------------------------------------------------
local ui = CreateFrame("Frame", "BattleAuraFrame", UIParent)
ui:SetSize(1024, 1024)
ui:SetScale(DB.scale)
ui:SetFrameStrata("MEDIUM")
ui:SetClampedToScreen(true)
ui:SetMovable(true)
ui:EnableMouse(true)
ui:RegisterForDrag("LeftButton")
ui:SetScript("OnDragStart", ui.StartMoving)
ui:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    DB.pos = { p = p, rp = rp, x = x, y = y }
end)
local function place()
    ui:ClearAllPoints()
    if DB.pos then ui:SetPoint(DB.pos.p or "CENTER", UIParent, DB.pos.rp or "CENTER", DB.pos.x or 0, DB.pos.y or 0)
    else ui:SetPoint("CENTER", UIParent, "CENTER", 0, 80) end
end
place()

local function tex(layer, sub, file, blend)
    local t = ui:CreateTexture(nil, layer)
    if t.SetDrawLayer then t:SetDrawLayer(layer, sub or 0) end
    t:SetTexture(ART .. file)
    if blend then t:SetBlendMode(blend) end
    return t
end
local plate = tex("BACKGROUND", 0, "BattleAura_Plate"); plate:SetAllPoints(ui)
local hurtTex = tex("BACKGROUND", 3, "BattleAura_Plate", "ADD"); hurtTex:SetAllPoints(ui); hurtTex:SetVertexColor(1.0, 0.12, 0.08); hurtTex:SetAlpha(0)
local aura = tex("BORDER", 0, "BattleAura_Glow", "ADD"); aura:SetSize(AURA_SIZE, AURA_SIZE)
aura:SetPoint("CENTER", ui, "TOPLEFT", AURA_X, -AURA_Y); aura:SetAlpha(0.05)
local numGlow = tex("ARTWORK", 0, "BattleAura_Glow", "ADD"); numGlow:SetSize(560, 250)
numGlow:SetPoint("CENTER", ui, "TOPLEFT", NUM_X, -NUM_Y); numGlow:SetVertexColor(1.0, 0.62, 0.18); numGlow:SetAlpha(0.25)
local starTex = tex("ARTWORK", 2, "BattleAura_Glow", "ADD"); starTex:SetSize(90, 90)
starTex:SetPoint("CENTER", ui, "TOPLEFT", STAR_X, -STAR_Y); starTex:SetVertexColor(1.0, 0.8, 0.4); starTex:SetAlpha(0.2)

-- ---- live text ------------------------------------------------------------------------------
local bigNum = ui:CreateFontString(nil, "OVERLAY")
setFont(bigNum, NUMBER_FONT, DB.fontSize, "OUTLINE")
bigNum:SetPoint("CENTER", ui, "TOPLEFT", NUM_X, -NUM_Y)
bigNum:SetTextColor(1.0, 0.87, 0.52); bigNum:SetShadowColor(0.35, 0.12, 0.0, 0.95); bigNum:SetShadowOffset(3, -3)
bigNum:SetText("--")

local function makeRow(label, y)
    local l = ui:CreateFontString(nil, "OVERLAY"); setFont(l, LABEL_FONT, 34, "OUTLINE")
    l:SetPoint("LEFT", ui, "TOPLEFT", ROW_X, -y); l:SetTextColor(0.93, 0.80, 0.55); l:SetText(label)
    local v = ui:CreateFontString(nil, "OVERLAY"); setFont(v, NUMBER_FONT, 44, "OUTLINE")
    v:SetPoint("RIGHT", ui, "TOPLEFT", VAL_X, -y); v:SetTextColor(1.0, 0.87, 0.52); v:SetJustifyH("RIGHT"); v:SetText("--")
    return v
end
local hitVal = makeRow("BIGGEST HIT", ROW1_Y)
local dpsVal = makeRow("DPS", ROW2_Y)

local lastLabel = ui:CreateFontString(nil, "OVERLAY"); setFont(lastLabel, LABEL_FONT, 30, "OUTLINE")
lastLabel:SetPoint("CENTER", ui, "TOPLEFT", NUM_X, -(NUM_Y - 118)); lastLabel:SetTextColor(0.85, 0.72, 0.5); lastLabel:SetText("LAST FIGHT"); lastLabel:SetAlpha(0)

local banner = ui:CreateFontString(nil, "OVERLAY"); setFont(banner, NUMBER_FONT, 66, "OUTLINE")
banner:SetPoint("CENTER", ui, "TOPLEFT", 512, -150); banner:SetTextColor(1.0, 0.82, 0.3); banner:SetShadowColor(0.4, 0.1, 0, 1); banner:SetShadowOffset(3, -3); banner:SetAlpha(0)

local comboLabel = ui:CreateFontString(nil, "OVERLAY"); setFont(comboLabel, LABEL_FONT, 30, "OUTLINE")
comboLabel:SetPoint("LEFT", ui, "TOPLEFT", 70, -905); comboLabel:SetTextColor(0.95, 0.82, 0.55); comboLabel:SetText("COMBO"); comboLabel:SetAlpha(0)
local comboNum = ui:CreateFontString(nil, "OVERLAY"); setFont(comboNum, NUMBER_FONT, 78, "OUTLINE")
comboNum:SetPoint("LEFT", ui, "TOPLEFT", 70, -965); comboNum:SetTextColor(1.0, 0.87, 0.52); comboNum:SetAlpha(0)

local function applyFont()
    setFont(bigNum, NUMBER_FONT, DB.fontSize, "OUTLINE")
end

-- ---- effect pools ------------------------------------------------------------------------------
local rings, embers, hitPool, critPool = {}, {}, {}, {}
for i = 1, 6 do local r = tex("ARTWORK", 3, "BattleAura_Ring", "ADD"); r:SetAlpha(0); r.on = false; rings[i] = r end
for i = 1, 36 do local e = tex("ARTWORK", 1, "BattleAura_Glow", "ADD"); e:SetAlpha(0); e.on = false; embers[i] = e end
local function makeHit(size)
    local f = ui:CreateFontString(nil, "OVERLAY"); setFont(f, NUMBER_FONT, size, "OUTLINE")
    f:SetShadowColor(0.3, 0.1, 0, 0.9); f:SetShadowOffset(2, -2); f:SetAlpha(0); f.on = false; return f
end
for i = 1, 10 do hitPool[i] = makeHit(54) end
for i = 1, 4 do critPool[i] = makeHit(86) end
local comet = { tex("ARTWORK", 2, "BattleAura_Glow", "ADD"), tex("ARTWORK", 2, "BattleAura_Glow", "ADD"), tex("ARTWORK", 2, "BattleAura_Glow", "ADD") }
local cometSize, cometAlpha = { 70, 46, 30 }, { 0.9, 0.5, 0.25 }
for i = 1, 3 do comet[i]:SetVertexColor(1.0, 0.85, 0.5); comet[i]:SetSize(cometSize[i], cometSize[i]); comet[i]:SetAlpha(0) end

-- ---- state -------------------------------------------------------------------------------
local inCombat, showLive = false, true
local heat, flash, pulse, hurt, starFlash = 0, 0, 0, 0, 0
local shakeAmp, shakeUntil = 0, 0
local comboN, comboT, lastRing = 0, 0, 0
local lastUC = -100                                   -- last time a UNIT_COMBAT event arrived (fallback gate)
local fightMax = 0                                   -- biggest single hit THIS fight, from the per-hit events (solo only; plain numbers)
local cometS, emberAcc = -0.2, 0
local bannerQueue, bannerCur, bannerT0 = {}, nil, 0
local cr, cg, cb = 1.0, 0.7, 0.2                      -- class colour (aura rings)

local function spawnRing(x, y, s0, s1, dur, r, g, b, a0)
    local ring
    for i = 1, #rings do if not rings[i].on then ring = rings[i]; break end end
    ring = ring or rings[1]
    ring.on, ring.t0, ring.dur, ring.s0, ring.s1, ring.a0 = true, GetTime(), dur, s0, s1, a0
    ring:SetVertexColor(r, g, b); ring:ClearAllPoints(); ring:SetPoint("CENTER", ui, "TOPLEFT", x, -y)
    ring:SetSize(s0, s0); ring:SetAlpha(a0)
end

local function queueBanner(text) bannerQueue[#bannerQueue + 1] = text end

local function spawnEmber()
    for i = 1, #embers do
        local e = embers[i]
        if not e.on then
            e.on, e.t0, e.life = true, GetTime(), 1.6 + random() * 1.4
            e.x, e.y = 140 + random() * 420, 640 + random() * 290
            e.vx, e.vy = -15 + random() * 40, -(60 + random() * 90)
            e.peak = 0.35 + random() * 0.5
            local s = 10 + random() * 16
            e:SetSize(s, s); e:SetVertexColor(1.0, 0.4 + random() * 0.3, 0.08)
            return
        end
    end
end

local function spawnHit(amount, crit)
    local pool = crit and critPool or hitPool
    local f
    for i = 1, #pool do if not pool[i].on then f = pool[i]; break end end
    if not f then return end
    if not showRaw(f, amount) then return end
    f.on, f.t0 = true, GetTime()
    f.life = crit and 1.2 or 0.85
    f.x0, f.y0 = TIP_X + (random() * 70 - 35), TIP_Y + (random() * 40 - 20)
    f.dx, f.rise = (40 + random() * 80) * (crit and 1.4 or 1), 150 + random() * 80 + (crit and 60 or 0)
    if crit then f:SetTextColor(1.0, 0.5, 0.12) else f:SetTextColor(1.0, 0.95, 0.78) end
end

-- one "hit landed" beat: shake + ring + flare + heat (driven by timing only, never by the secret amount)
local function tick(crit)
    local t = GetTime()
    heat = min(1, heat + (crit and 0.30 or 0.10))
    flash = 1
    shakeAmp, shakeUntil = (crit and 9 or 4), t + 0.09
    if crit or (t - lastRing) > 0.22 then
        lastRing = t
        spawnRing(NUM_X, NUM_Y, 120, crit and 520 or 300, crit and 0.55 or 0.38, 1.0, 0.78, 0.3, crit and 0.55 or 0.32)
    end
    starFlash = max(starFlash, crit and 1 or 0.5)
end

-- ---- per-frame animation ------------------------------------------------------------------------
local function pathAt(s)
    local n = #PATH
    local idx = min(max(s, 0), 1) * (n - 1)
    local i = floor(idx); local f = idx - i
    local a, b = PATH[i + 1], PATH[min(i + 2, n)]
    return a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
end

ui:SetScript("OnUpdate", function(_, dt)
    local t = GetTime()
    if dt > 0.1 then dt = 0.1 end
    heat = heat * exp(-dt / 1.4)
    flash = max(0, flash - dt * 3.2)
    starFlash = max(0, starFlash - dt * 1.8)
    pulse = max(0, pulse - dt * 1.8)
    hurt = max(0, hurt - dt * 2.2)

    if DB.aura then                                    -- aura: breathes, swells with heat, flashes on every cast
        local base = inCombat and (0.10 + 0.22 * heat + 0.04 * sin(t * 3.0)) or 0.045
        aura:SetAlpha(min(1, base + pulse * 0.45))
        local sz = AURA_SIZE * (1 + 0.07 * heat + 0.05 * pulse); aura:SetSize(sz, sz)
    else aura:SetAlpha(0) end

    numGlow:SetAlpha(0.22 + 0.55 * flash + 0.20 * heat)   -- big number: flares on a hit, hot-white flash, impact shake
    local k = flash * 0.8
    bigNum:SetTextColor(1.0, 0.87 + 0.12 * k, 0.52 + 0.40 * k)
    local ox, oy = 0, 0
    if t < shakeUntil then
        local m = (shakeUntil - t) / 0.09
        ox, oy = (random() * 2 - 1) * shakeAmp * m, (random() * 2 - 1) * shakeAmp * m
    end
    bigNum:SetPoint("CENTER", ui, "TOPLEFT", NUM_X + ox, -(NUM_Y + oy))
    hurtTex:SetAlpha(min(0.4, hurt * 0.4))

    emberAcc = emberAcc + dt * (inCombat and (5 + heat * 38) or 2.5)
    while emberAcc >= 1 do emberAcc = emberAcc - 1; spawnEmber() end
    for i = 1, #embers do
        local e = embers[i]
        if e.on then
            local age = t - e.t0; local u = age / e.life
            if u >= 1 then e.on = false; e:SetAlpha(0)
            else e:SetPoint("CENTER", ui, "TOPLEFT", e.x + e.vx * age, -(e.y + e.vy * age)); e:SetAlpha(e.peak * sin(3.14159 * u)) end
        end
    end
    for i = 1, #rings do
        local r = rings[i]
        if r.on then
            local u = (t - r.t0) / r.dur
            if u >= 1 then r.on = false; r:SetAlpha(0)
            else local s = r.s0 + (r.s1 - r.s0) * (1 - (1 - u) * (1 - u)); r:SetSize(s, s); r:SetAlpha(r.a0 * (1 - u)) end
        end
    end
    for p = 1, 2 do
        local pool = (p == 1) and hitPool or critPool
        for i = 1, #pool do
            local f = pool[i]
            if f.on then
                local u = (t - f.t0) / f.life
                if u >= 1 then f.on = false; f:SetAlpha(0)
                else
                    local e = 1 - (1 - u) * (1 - u)
                    f:SetPoint("CENTER", ui, "TOPLEFT", f.x0 + f.dx * e, -(f.y0 - f.rise * e))
                    local a = (u < 0.12) and (u / 0.12) or (1 - ((u - 0.12) / 0.88) ^ 2)
                    f:SetAlpha(max(0, a))
                end
            end
        end
    end

    -- comet along the baked spark-line: speed follows heat; flares the end star on arrival
    cometS = cometS + dt * (inCombat and (0.30 + 0.90 * heat) or 0.10)
    if cometS >= 1 then cometS = -0.25; starFlash = 1; spawnRing(STAR_X, STAR_Y, 40, 200, 0.5, 1.0, 0.8, 0.4, 0.45) end
    for i = 1, 3 do
        local s = cometS - (i - 1) * 0.035
        if s < 0 then comet[i]:SetAlpha(0)
        else local x, y = pathAt(s); comet[i]:SetPoint("CENTER", ui, "TOPLEFT", x, -y); comet[i]:SetAlpha(cometAlpha[i]) end
    end
    local ss = 90 + 70 * starFlash
    starTex:SetSize(ss, ss); starTex:SetAlpha(0.2 + 0.6 * starFlash + 0.25 * heat)

    if bannerCur then                                   -- record / combo banner
        local u = (t - bannerT0) / 2.2
        if u >= 1 then bannerCur = nil; banner:SetAlpha(0)
        else banner:SetAlpha(sin(3.14159 * u)); banner:SetPoint("CENTER", ui, "TOPLEFT", 512, -(150 - 24 * u)) end
    elseif #bannerQueue > 0 then
        bannerCur = table.remove(bannerQueue, 1); bannerT0 = t; banner:SetText(bannerCur)
    end

    if comboN > 0 and (t - comboT) > 4.0 then comboN = 0 end
    if comboN >= 2 then
        local fade = min(1, (4.0 - (t - comboT)) / 1.0)
        comboNum:SetText(comboN); comboNum:SetAlpha(fade); comboLabel:SetAlpha(fade * 0.9)
        if comboN >= 20 then comboNum:SetTextColor(1.0, 0.97, 0.85)
        elseif comboN >= 10 then comboNum:SetTextColor(1.0, 0.45, 0.2)
        elseif comboN >= 5 then comboNum:SetTextColor(1.0, 0.65, 0.25)
        else comboNum:SetTextColor(1.0, 0.87, 0.52) end
    else comboNum:SetAlpha(0); comboLabel:SetAlpha(0) end
    lastLabel:SetAlpha(inCombat and 0 or 0.65)
end)

-- ---- data (C_DamageMeter) -----------------------------------------------------------------------
local function findMe(session)
    local sources = session.combatSources
    if not sources or isSecret(sources) then return nil end
    local n = #sources
    if n == 0 then return nil end
    for i = 1, n do
        local e = sources[i]
        if e and not isSecret(e) and e.isLocalPlayer ~= nil and not isSecret(e.isLocalPlayer) and e.isLocalPlayer then return e end
    end
    return sources[1]
end

local function newestSessionId()
    local okL, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
    if okL and sessions and not isSecret(sessions) and #sessions > 0 then
        local newest = sessions[#sessions]
        return newest and newest.sessionID
    end
end

-- source detail (maxAmount) for a finished fight: by session type, else by the newest session id
local function sourceDetail(guid)
    local S, T = Enum.DamageMeterSessionType, Enum.DamageMeterType.Dps
    local ok, d = pcall(C_DamageMeter.GetCombatSessionSourceFromType, S.Expired, T, guid)
    if ok and d and not isSecret(d) and d.maxAmount ~= nil then return d end
    local id = newestSessionId()
    if id ~= nil and C_DamageMeter.GetCombatSessionSourceFromID then
        local ok2, d2 = pcall(C_DamageMeter.GetCombatSessionSourceFromID, id, T, guid)
        if ok2 and d2 and not isSecret(d2) and d2.maxAmount ~= nil then return d2 end
    end
end

local function renderLive()
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType and Enum and Enum.DamageMeterType) then return end
    local T = Enum.DamageMeterType.Dps
    local ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, Enum.DamageMeterSessionType.Current, T)
    if not ok or not session or isSecret(session) then return end
    local me = findMe(session)
    if not me or isSecret(me) then return end
    showNum(bigNum, me.totalAmount); showNum(dpsVal, me.amountPerSecond)
    if fightMax == 0 then       -- no per-hit data (grouped / secret): fall back to the meter's own number. (On Forever it reads 0.)
        local gok, d = pcall(C_DamageMeter.GetCombatSessionSourceFromType, Enum.DamageMeterSessionType.Current, T, me.sourceGUID)
        if gok and d and not isSecret(d) and d.maxAmount ~= nil then showNum(hitVal, d.maxAmount) end
    end
end

-- the finished fight's session: "Expired" first, else the newest completed session by id (shared by display AND recorder)
local function finishedSession()
    local S, T = Enum.DamageMeterSessionType, Enum.DamageMeterType.Dps
    local ok, s1 = pcall(C_DamageMeter.GetCombatSessionFromType, S.Expired, T)
    if ok and s1 and not isSecret(s1) and findMe(s1) then return s1 end
    local id = newestSessionId()
    if id ~= nil and C_DamageMeter.GetCombatSessionFromID then
        local ok2, s2 = pcall(C_DamageMeter.GetCombatSessionFromID, id, T)
        if ok2 and s2 and not isSecret(s2) and findMe(s2) then return s2 end
    end
end

-- fight over: freeze the finished fight. NEVER blanks a field it cannot refill (that was the "BIGGEST HIT --" bug)
local function renderFinished()
    local session = finishedSession()
    if not session then return end
    local me = findMe(session)
    if not me or isSecret(me) then return end
    showNum(bigNum, me.totalAmount); showNum(dpsVal, me.amountPerSecond)
    if fightMax > 0 then showNum(hitVal, fightMax); return end
    local d = sourceDetail(me.sourceGUID)
    if d then showNum(hitVal, d.maxAmount) end
end

-- write the finished fight to SavedVariables (readable out of combat) so results can be verified from disk
local function recordFight()
    local rec = { at = (date and date("%H:%M:%S")) or "" }
    local session = finishedSession()
    local api                                           -- the meter's own biggest hit (reads a plain 0 on Forever)
    if session then
        local me = findMe(session)
        if me and not isSecret(me) then
            rec.total, rec.dps = plain(me.totalAmount), plain(me.amountPerSecond)
            local d = sourceDetail(me.sourceGUID)
            if d then api = plain(d.maxAmount) end
        end
    end
    -- the per-hit tracker is the source of truth whenever it saw hits (it is what the player actually watched)
    if fightMax > 0 and (api == nil or api < fightMax) then rec.maxHit = fightMax else rec.maxHit = api end
    rec.readable = (rec.total ~= nil)
    DB.fights[#DB.fights + 1] = rec
    while #DB.fights > 25 do table.remove(DB.fights, 1) end
    return rec
end

local function checkRecords(rec)                       -- plain numbers only (out of combat) -> safe to compare
    if not (rec and rec.readable) then return end
    local function chk(key, label)
        local v = rec[key]
        if not v then return end
        local old = DB.best[key]
        if old == nil then DB.best[key] = v
        elseif v > old then DB.best[key] = v; queueBanner("NEW BEST " .. label .. "!") end
    end
    chk("maxHit", "HIT"); chk("dps", "DPS"); chk("total", "DAMAGE")
end

-- ---- UNIT_COMBAT (per-hit) -------------------------------------------------------------------------
local function hitsAllowed()
    if DB.hits == false then return false end
    if IsInGroup and IsInGroup() and not DB.hitsGroup then return false end   -- target events include other players' hits
    return true
end

local MISS = { MISS = true, DODGE = true, PARRY = true, BLOCK = true, EVADE = true, IMMUNE = true, RESIST = true, ABSORB = true }
local function onUnitCombat(unit, action, flagText, amount)
    local P = DB.probe
    if not P then return end
    P.uc = P.uc + 1; P.lastAction = tostring(action)
    lastUC = GetTime()
    if unit == "target" and action == "WOUND" then
        P.woundTarget = P.woundTarget + 1
        if isSecret(amount) then P.secretAmt = P.secretAmt + 1 else P.plainAmt = P.plainAmt + 1 end
        local n = plain(amount)                         -- only solo: in a group the target's events include other players' hits
        if n and n > fightMax and not (IsInGroup and IsInGroup()) then fightMax = n; showNum(hitVal, n) end
        local crit = (flagText == "CRITICAL")
        if crit then P.crit = P.crit + 1 end
        if hitsAllowed() then spawnHit(amount, crit); tick(crit) end
    elseif unit == "player" and action == "WOUND" then
        P.woundPlayer = P.woundPlayer + 1
        hurt = 1
    end
end

-- ---- events ------------------------------------------------------------------------------------
local function initDB()
    BattleAuraDB = BattleAuraDB or {}
    local S = BattleAuraDB
    if S.scale == nil then S.scale = 0.5 end
    if S.fontSize == nil then S.fontSize = 120 end
    if S.aura == nil then S.aura = true end
    if S.hits == nil then S.hits = true end
    S.fights = S.fights or {}
    S.best = S.best or {}
    if S.ver ~= 3 then S.pos = nil; S.ver = 3 end      -- v3 frame is 512px+ : drop the old small-box position once
    DB = S                                              -- every function below now reads/writes the SAVED table
    ui:SetScale(DB.scale); place(); applyFont()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED")
ev:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
local function registerUnitCombat()
    return (pcall(function() ev:RegisterUnitEvent("UNIT_COMBAT", "player", "target") end))
end

ev:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if (...) == "BattleAura" then initDB() end
    elseif event == "UNIT_COMBAT" then
        local unit, action, flagText, amount = ...
        pcall(onUnitCombat, unit, action, flagText, amount)
    elseif event == "PLAYER_LOGIN" then
        local _, classFile = UnitClass("player")
        local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if c then cr, cg, cb = c.r, c.g, c.b end
        aura:SetVertexColor(cr, cg, cb); applyFont()
        DB.probe = { uc = 0, woundTarget = 0, woundPlayer = 0, secretAmt = 0, plainAmt = 0, crit = 0, lastAction = "",
                     registered = registerUnitCombat(), at = (date and date("%H:%M:%S")) or "" }
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100[BattleAura]|r v3.1.1 loaded - /ba test previews the effects; drag to move.")
    elseif event == "PLAYER_TARGET_CHANGED" then
        registerUnitCombat()                        -- re-bind the "target" unit filter to the new target
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local t = GetTime()
        pulse = 1
        if (t - comboT) > 4.0 then comboN = 0 end
        comboN = comboN + 1; comboT = t
        spawnRing(AURA_X, AURA_Y - 60, 160, 640, 0.6, cr, cg, cb, 0.45)
        if comboN % 5 == 0 then
            queueBanner("COMBO x" .. comboN .. "!")
            spawnRing(AURA_X, AURA_Y - 60, 220, 900, 0.9, 1.0, 0.85, 0.4, 0.6)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat, showLive, fightMax = true, true, 0
        bigNum:SetText("0"); hitVal:SetText("--"); dpsVal:SetText("--")
        flash = 1; spawnRing(NUM_X, NUM_Y, 160, 700, 0.7, 1.0, 0.8, 0.35, 0.5)
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat, showLive = false, false
        pcall(renderFinished)
        local ok, rec = pcall(recordFight)
        if ok then pcall(checkRecords, rec) end
        flash = 1.4; spawnRing(NUM_X, NUM_Y, 160, 760, 0.9, 1.0, 0.85, 0.45, 0.6)
    else                                            -- DAMAGE_METER_* update
        if showLive then
            pcall(renderLive)
            if (GetTime() - lastUC) > 1.0 then tick(false) end   -- fallback beat when UNIT_COMBAT is silent
        end
    end
end)

-- ---- slash commands ---------------------------------------------------------------------------
SLASH_BATTLEAURA1 = "/ba"
SLASH_BATTLEAURA2 = "/battleaura"
local function say(t) DEFAULT_CHAT_FRAME:AddMessage("|cFFFFD100[BattleAura]|r " .. t) end
SlashCmdList["BATTLEAURA"] = function(msg)
    local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "scale" then
        local n = tonumber(arg)
        if n and n >= 0.3 and n <= 1.2 then DB.scale = n; ui:SetScale(n); say("scale " .. n)
        else say("usage: /ba scale 0.3 - 1.2   (now " .. DB.scale .. ")") end
    elseif cmd == "font" then
        local n = tonumber(arg)
        if n and n >= 60 and n <= 200 then DB.fontSize = n; applyFont(); say("number font " .. n)
        else say("usage: /ba font 60 - 200   (now " .. DB.fontSize .. ")") end
    elseif cmd == "aura" then
        DB.aura = not DB.aura; say("aura " .. (DB.aura and "on" or "off"))
    elseif cmd == "hits" then
        DB.hits = not DB.hits; say("floating hit numbers " .. (DB.hits and "on" or "off"))
    elseif cmd == "grouphits" then
        DB.hitsGroup = not DB.hitsGroup; say("hit numbers while grouped " .. (DB.hitsGroup and "on (shows other players' hits too)" or "off"))
    elseif cmd == "best" then
        say(string.format("best hit %s | best dps %s | best damage %s", tostring(DB.best.maxHit), tostring(DB.best.dps), tostring(DB.best.total)))
    elseif cmd == "test" then                       -- preview every effect without a fight
        inCombat = true; flash = 1
        for i = 1, 14 do
            C_Timer.After(i * 0.22, function()
                local crit = (i % 5 == 0)
                spawnHit(random(120, 980) * (crit and 3 or 1), crit); tick(crit)
                pulse = 1; comboN = i; comboT = GetTime()
            end)
        end
        C_Timer.After(1.2, function() queueBanner("NEW BEST HIT!") end)
        C_Timer.After(3.8, function() inCombat = false; hurt = 1; flash = 1.4; spawnRing(NUM_X, NUM_Y, 160, 760, 0.9, 1.0, 0.85, 0.45, 0.6) end)
        say("test: 14 hits, combo, banner, hurt flash, finish")
    elseif cmd == "reset" then
        DB.pos, DB.scale, DB.fontSize, DB.aura, DB.hits = nil, 0.5, 120, true, true
        ui:SetScale(0.5); place(); applyFont(); say("reset to defaults")
    else
        say("/ba scale | font | aura | hits | grouphits | best | test | reset   (drag the frame to move it)")
    end
end

ui.debug = { queue = bannerQueue, tick = tick, spawnHit = spawnHit, hitVal = hitVal }   -- test hooks
