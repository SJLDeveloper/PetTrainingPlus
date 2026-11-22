-- Pet Training+ · loyalty: what the game shows (level name, happiness, loyalty rate) and a recorder that measures how
-- much "rate × time" each loyalty level takes, so time to the next level can be estimated.
--
-- Forever's API (Blizzard_APIDocumentationGenerated/PetInfoDocumentation.lua, branch "forever"):
--   C_PetInfo.GetPetLoyalty()   -> loyaltyName ("Unruly")
--   C_PetInfo.GetPetHappiness() -> happiness (1-3), damagePercentage (125 when happy), loyaltyRate (20 seen in game)
-- Loyalty points inside a level are not exposed. Seen in game (Nov 22): level 22 pet, Unruly, 44 total TP, so
-- total TP = pet level × loyalty level on Forever.
local _, ns = ...
local L = {}
ns.Loyalty = L
local try, clean = ns.try, ns.clean

L.NAMES = { "Rebellious", "Unruly", "Submissive", "Dependable", "Faithful", "Best Friend" }
L.MAX = #L.NAMES

-- Rate-seconds each level takes before the next one (from complete recorded segments; shipped when known).
-- [level] = rate-seconds from the start of that level to the next. Empty until measured.
L.SHIPPED = {}

local SAMPLE = 5 -- seconds between samples while the pet is out

-- Loyalty level from the game's name (English), else from training points (total TP = pet level × loyalty level).
function L.LevelFromName(name)
  if type(name) ~= "string" then return nil end
  local n = name:lower()
  for i, nm in ipairs(L.NAMES) do
    if n == nm:lower() or n:find(nm:lower(), 1, true) then return i end
  end
  local num = tonumber(n:match("(%d+)"))
  if num and num >= 1 and num <= L.MAX then return num end
  return nil
end

function L.LevelFromTP(pet)
  if not (pet and pet.tpTotal and pet.level and pet.level > 0) then return nil end
  local v = pet.tpTotal / pet.level
  if v >= 1 and v <= L.MAX and math.abs(v - math.floor(v + 0.5)) < 0.01 then return math.floor(v + 0.5) end
  return nil
end

-- What the game says right now about the summoned pet (nil when no pet / secret values).
function L.Read()
  if not (UnitExists and UnitExists("pet")) then return nil end
  local api = C_PetInfo
  local name = api and try(api.GetPetLoyalty)
  local happiness, dmg, rate = nil, nil, nil
  if api then happiness, dmg, rate = try(api.GetPetHappiness) end
  local level = L.LevelFromName(name)
  local tpLevel = L.LevelFromTP(ns.pet)
  if not level then level = tpLevel end
  if not (level or rate) then return nil end
  return { name = name, level = level, tpLevel = tpLevel, happiness = happiness, damage = dmg, rate = rate }
end

-- ------------------------------------------------------------------ the recorder
local function db()
  local d = ns.db.loyalty
  if not d then
    d = { version = 1, segments = {}, events = {}, current = {} }
    ns.db.loyalty = d
  end
  d.segments, d.events, d.current = d.segments or {}, d.events or {}, d.current or {}
  return d
end

local function petKey()
  local rec = ns.pet and ns.pet.rec
  if not rec then return nil end
  local who = (UnitName and try(UnitName, "player")) or "?"
  local realm = (GetRealmName and try(GetRealmName)) or ""
  return who .. "-" .. realm .. "#" .. rec.id
end

local function newRun(read, fromStart)
  return {
    level = read.level, name = read.name, fromStart = fromStart and true or false,
    started = time(), lastSample = time(), summonedSec = 0, rateSec = 0, samples = 0,
    rateMin = read.rate, rateMax = read.rate, lastRate = read.rate,
    happySec = { 0, 0, 0 }, petLevelStart = ns.pet and ns.pet.level, family = ns.pet and ns.pet.fam,
    petName = ns.pet and ns.pet.name,
  }
end

-- A pet that has just been tamed starts its first level now: that level is measured from its start.
function L.OnTamed()
  L.freshTame = time()
end

function L.Sample()
  if not ns.db or ns.InCombat() then return end
  local read = L.Read()
  local key = petKey()
  if not (read and key) then L.lastKey = nil; return end
  local d = db()
  local run = d.current[key]
  local now = time()
  if not run or not run.level then
    -- first sight of this pet: a fresh tame starts at the beginning of its level, otherwise we join halfway
    local fresh = L.freshTame and now - L.freshTame < 120
    d.current[key] = newRun(read, fresh)
    L.freshTame = nil
    L.lastKey = key
    return
  end
  -- time since the last sample counts only while this pet was out the whole time (continuous sampling)
  local dt = now - (run.lastSample or now)
  local continuous = L.lastKey == key and dt > 0 and dt <= SAMPLE * 4
  if continuous then
    local rate = run.lastRate or read.rate or 0
    run.summonedSec = run.summonedSec + dt
    run.rateSec = run.rateSec + rate * dt
    run.samples = run.samples + 1
    if run.lastHappiness and run.happySec[run.lastHappiness] then
      run.happySec[run.lastHappiness] = run.happySec[run.lastHappiness] + dt
    end
  else
    run.gaps = (run.gaps or 0) + 1
  end
  run.lastSample = now
  if read.rate then
    run.lastRate = read.rate
    run.rateMin = math.min(run.rateMin or read.rate, read.rate)
    run.rateMax = math.max(run.rateMax or read.rate, read.rate)
  end
  run.lastHappiness = read.happiness
  run.petLevelEnd = ns.pet and ns.pet.level
  L.lastKey = key
  -- the level changed: close the run as a segment
  if read.level and read.level ~= run.level then
    if read.level == run.level + 1 then
      table.insert(d.segments, {
        from = run.level, to = read.level, complete = run.fromStart, summonedSec = run.summonedSec,
        rateSec = math.floor(run.rateSec + 0.5), samples = run.samples, gaps = run.gaps or 0,
        rateMin = run.rateMin, rateMax = run.rateMax, happySec = run.happySec,
        petLevelStart = run.petLevelStart, petLevelEnd = run.petLevelEnd, family = run.family, petName = run.petName,
        wallSec = now - run.started, ended = now,
      })
      ns.Print(("Loyalty: %s is now |cffffd100%s|r (%d/%d)."):format(run.petName or "your pet",
        L.NAMES[read.level] or tostring(read.name), read.level, L.MAX))
    else
      table.insert(d.events, { t = now, kind = "change", from = run.level, to = read.level, petName = run.petName })
    end
    d.current[key] = newRun(read, read.level == run.level + 1)
  end
  if ns.UI and ns.UI.RefreshPet then ns.UI.RefreshPet() end
end

-- ------------------------------------------------------------------ estimates
-- Rate-seconds a level takes: shipped value, else the average of your complete segments for that level.
function L.Needed(level)
  if L.SHIPPED[level] then return L.SHIPPED[level], "shipped" end
  local sum, n = 0, 0
  for _, s in ipairs(ns.db and ns.db.loyalty and ns.db.loyalty.segments or {}) do
    if s.complete and s.from == level and s.rateSec and s.rateSec > 0 then sum, n = sum + s.rateSec, n + 1 end
  end
  if n > 0 then return sum / n, "measured", n end
  return nil
end

-- For the summoned pet: { level, name, rate, happiness, progress (0-1), etaSec, source } or nil.
function L.Status()
  local read = L.Read()
  if not read then return nil end
  local st = { level = read.level, name = read.name, rate = read.rate, happiness = read.happiness, damage = read.damage }
  local key = petKey()
  local run = key and ns.db and ns.db.loyalty and ns.db.loyalty.current[key]
  if run and run.level == read.level then
    st.summonedSec, st.rateSec, st.fromStart = run.summonedSec, run.rateSec, run.fromStart
  end
  if read.level and read.level < L.MAX then
    local need, source = L.Needed(read.level)
    if need and st.rateSec and st.fromStart then
      st.progress = math.min(st.rateSec / need, 1)
      if read.rate and read.rate > 0 then st.etaSec = math.max(need - st.rateSec, 0) / read.rate end
      st.source = source
    end
  end
  return st
end

function L.FormatDuration(sec)
  if not sec then return "?" end
  if sec < 90 then return ("%d s"):format(sec) end
  if sec < 5400 then return ("%d min"):format(math.floor(sec / 60 + 0.5)) end
  return ("%.1f h"):format(sec / 3600)
end

-- ------------------------------------------------------------------ /ptp loyalty
function L.Report()
  local st = L.Status()
  if not st then ns.Print("Loyalty: no pet summoned."); return end
  local lvl = st.level and (L.NAMES[st.level] .. " " .. st.level .. "/" .. L.MAX) or tostring(st.name)
  ns.Print(("Loyalty: %s · rate %s · happiness %s · damage %s%%"):format(lvl, tostring(st.rate), tostring(st.happiness), tostring(st.damage)))
  if st.summonedSec then
    ns.Print(("  this level: %s summoned, %d rate-seconds%s"):format(L.FormatDuration(st.summonedSec), math.floor(st.rateSec or 0),
      st.fromStart and "" or " (joined partway through this level)"))
  end
  if st.progress then
    ns.Print(("  about %d%% · ~%s to %s (%s)"):format(st.progress * 100, L.FormatDuration(st.etaSec),
      L.NAMES[st.level + 1] or "?", st.source))
  end
  local segs = ns.db.loyalty and ns.db.loyalty.segments or {}
  ns.Print(("  %d level-ups recorded (%d complete). /ptp loyalty export to copy them."):format(#segs, (function()
    local c = 0 for _, s in ipairs(segs) do if s.complete then c = c + 1 end end return c end)()))
end

-- Plain text of every recorded segment and event, one per line.
function L.ExportText()
  local d = ns.db.loyalty or {}
  local lines = { "PetTrainingPlus loyalty v1 " .. date("%Y-%m-%d %H:%M") }
  for _, s in ipairs(d.segments or {}) do
    local h = s.happySec or {}
    lines[#lines + 1] = ("seg %d>%d complete=%s rateSec=%d summoned=%d wall=%d samples=%d gaps=%d rate=%s-%s happy=%d/%d/%d petLv=%s-%s fam=%s pet=%s"):format(
      s.from, s.to, tostring(s.complete), s.rateSec or 0, s.summonedSec or 0, s.wallSec or 0, s.samples or 0, s.gaps or 0,
      tostring(s.rateMin), tostring(s.rateMax), h[1] or 0, h[2] or 0, h[3] or 0, tostring(s.petLevelStart),
      tostring(s.petLevelEnd), tostring(s.family), tostring(s.petName))
  end
  for _, e in ipairs(d.events or {}) do
    lines[#lines + 1] = ("event %s %s>%s at=%d pet=%s"):format(tostring(e.kind), tostring(e.from), tostring(e.to), e.t or 0, tostring(e.petName))
  end
  for key, run in pairs(d.current or {}) do
    lines[#lines + 1] = ("now %s level=%s fromStart=%s rateSec=%d summoned=%d rate=%s-%s pet=%s"):format(key, tostring(run.level),
      tostring(run.fromStart), math.floor(run.rateSec or 0), run.summonedSec or 0, tostring(run.rateMin), tostring(run.rateMax), tostring(run.petName))
  end
  return table.concat(lines, "\n")
end

local exportFrame
function L.ShowExport()
  if not exportFrame then
    local f = CreateFrame("Frame", "PetTrainingPlusLoyaltyExport", UIParent, "BackdropTemplate")
    f:SetSize(620, 320)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    if f.SetBackdrop then
      f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      f:SetBackdropColor(.05, .045, .04, .97)
      f:SetBackdropBorderColor(.75, .6, .3, 1)
    end
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Pet Training+ loyalty data: Ctrl+A, Ctrl+C, then paste it to share")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -32)
    sf:SetPoint("BOTTOMRIGHT", -32, 12)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(560)
    eb:SetAutoFocus(true)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    sf:SetScrollChild(eb)
    f.edit = eb
    table.insert(UISpecialFrames, "PetTrainingPlusLoyaltyExport")
    exportFrame = f
  end
  exportFrame.edit:SetText(L.ExportText())
  exportFrame.edit:HighlightText()
  exportFrame:Show()
end

-- ------------------------------------------------------------------ wiring
local function loop()
  pcall(L.Sample)
  ns.After(SAMPLE, loop)
end

ns.On("PLAYER_LOGIN", function() ns.After(SAMPLE, loop) end)
ns.On("UNIT_HAPPINESS", function() ns.Debounce("loyaltySample", 0.5, function() pcall(L.Sample) end) end)
