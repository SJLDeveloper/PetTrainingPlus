-- Pet Training+ · core: data index, what you know, what your pet has, tames and the learn log.
local ADDON, ns = ...
_G.PetTrainingPlus = ns

ns.BEAST_TRAINING = 5149
ns.TAME_BEAST = 1515

-- ------------------------------------------------------------------ safe API helpers
-- Forever runs on the modern engine: in combat many values are "secret" and throw when compared.
local function clean(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end
ns.clean = clean

local function packr(ok, ...) return ok, select("#", ...), { ... } end

-- Calls fn safely and returns its results with secret values turned into nil.
function ns.try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, n, t = packr(pcall(fn, ...))
  if not ok then return nil end
  for i = 1, n do t[i] = clean(t[i]) end
  return unpack(t, 1, n)
end
local try = ns.try

function ns.api(tbl, name) return type(tbl) == "table" and tbl[name] or nil end
local api = ns.api

function ns.Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff7fd47fPet Training+|r " .. tostring(msg)) end

function ns.After(sec, fn) if C_Timer and C_Timer.After then C_Timer.After(sec, fn) end end

-- Runs fn once, sec seconds after the last call with this key.
local debouncers = {}
function ns.Debounce(key, sec, fn)
  local d = debouncers[key]
  if not d then d = {}; debouncers[key] = d end
  d.fn, d.gen = fn, (d.gen or 0) + 1
  local gen = d.gen
  ns.After(sec, function() if d.gen == gen then d.fn() end end)
end

function ns.InCombat() return InCombatLockdown and InCombatLockdown() and true or false end

function ns.norm(s)
  if type(s) ~= "string" then return nil end
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
  return s:lower()
end

-- ------------------------------------------------------------------ events
local frame = CreateFrame("Frame")
local handlers = {}
ns.eventFrame = frame

local function canRegister(event)
  if C_EventUtils and C_EventUtils.IsEventValid then
    local ok, valid = pcall(C_EventUtils.IsEventValid, event)
    if ok then return valid and true or false end
  end
  return true
end

function ns.On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    if canRegister(event) then pcall(frame.RegisterEvent, frame, event) end
  end
  table.insert(handlers[event], fn)
end

frame:SetScript("OnEvent", function(_, event, ...)
  for _, fn in ipairs(handlers[event] or {}) do
    local ok, err = pcall(fn, ...)
    if not ok and ns.debug then ns.Print("|cffff6060" .. event .. ":|r " .. tostring(err)) end
  end
end)

-- ------------------------------------------------------------------ data index
ns.byKey, ns.byPet, ns.byHunter = {}, {}, {}

ns.FAMILY_EN = {
  [1] = "Wolf", [2] = "Cat", [3] = "Spider", [4] = "Bear", [5] = "Boar", [6] = "Crocolisk",
  [7] = "Carrion Bird", [8] = "Crab", [9] = "Gorilla", [11] = "Raptor", [12] = "Tallstrider",
  [20] = "Scorpid", [21] = "Turtle", [24] = "Bat", [25] = "Hyena", [26] = "Owl",
  [27] = "Wind Serpent", [319] = "Fox",
}

local function buildIndex()
  for i, a in ipairs(ns.Abilities) do
    a.index = i
    a.famSet = {}
    for _, f in ipairs(a.fam or {}) do a.famSet[f] = true end
    a.rankBy = {}
    a.maxRank = 0
    for _, r in ipairs(a.ranks) do
      r.a = a
      a.rankBy[r.r] = r
      if r.r > a.maxRank then a.maxRank = r.r end
      ns.byPet[r.pet] = r
      ns.byHunter[r.hunter] = r
    end
    ns.byKey[a.key] = a
  end
end
buildIndex()

-- Display name in the client's language (the pet spell's name), English key as fallback.
local nameCache = {}
function ns.AbilityName(a)
  local n = nameCache[a.key]
  if n then return n end
  n = C_Spell and try(C_Spell.GetSpellName, a.ranks[1].pet)
  if type(n) == "string" and n ~= "" then nameCache[a.key] = n; return n end
  return a.key
end

function ns.AbilityIcon(a)
  if a.icon then return a.icon end
  local icon = C_Spell and try(C_Spell.GetSpellTexture, a.ranks[1].pet)
  if icon then a.icon = icon; return icon end
  return 134400 -- question mark
end

local byName
function ns.FindAbility(name)
  local key = ns.norm(name)
  if not key then return nil end
  if not byName then
    byName = {}
    for _, a in ipairs(ns.Abilities) do
      byName[a.key:lower()] = a
      local loc = ns.AbilityName(a)
      if loc then byName[loc:lower()] = a end
    end
  end
  local a = byName[key]
  if a then return a end
  local learned = ns.db and ns.db.locNames[key]
  return learned and ns.byKey[learned] or nil
end

function ns.RankNumber(text)
  if type(text) ~= "string" then return nil end
  return tonumber(text:match("(%d+)"))
end

-- Pet level and training points of a rank: from what the game showed you, else the shipped data.
function ns.RankLevel(r)
  local m = ns.db and ns.db.meta[r.pet]
  return (m and m.lvl) or r.lvl
end
function ns.RankTP(r)
  local m = ns.db and ns.db.meta[r.pet]
  return (m and m.tp) or r.tp
end

function ns.FamName(id)
  if not id then return "?" end
  return (ns.db and ns.db.famNames[id]) or ns.FAMILY_EN[id] or ("Family " .. id)
end

-- Can a pet of this family learn this ability at all?  true / false / nil (nobody knows yet)
function ns.FamilyCanLearn(fam, a)
  if a.kind == "general" then return true end
  if not fam then return nil end
  if a.famSet[fam] then return true end
  local seen = ns.db and ns.db.famCan[fam]
  if seen and seen[a.key] then return true end
  -- families from the shipped data are complete for the abilities they list
  if next(a.famSet) then return false end
  return nil
end

-- ------------------------------------------------------------------ saved data
local DEFAULTS = { replace = true, autoOpen = true, showTames = true, filter = "all", petOnly = true, scale = 1.3 }

local function initDB()
  PetTrainingPlusDB = PetTrainingPlusDB or {}
  local db = PetTrainingPlusDB
  db.meta = db.meta or {}         -- [petSpellID] = { lvl, tp } seen in Beast Training
  db.famCan = db.famCan or {}     -- [familyID] = { [abilityKey] = true } seen in Beast Training / pet spellbook
  db.famNames = db.famNames or {} -- [familyID] = name in your client language
  db.locNames = db.locNames or {} -- [lowercase name in your language] = abilityKey
  db.creatures = db.creatures or {} -- [npcID] = { name, teaches = { [key] = rank }, t }
  db.opts = db.opts or {}
  for k, v in pairs(DEFAULTS) do if db.opts[k] == nil then db.opts[k] = v end end
  -- 1.2: the old "For my pet" filter became the pet toggle
  if db.opts.filter == "pet" then db.opts.filter, db.opts.petOnly = "all", true end
  ns.db = db

  PetTrainingPlusCharDB = PetTrainingPlusCharDB or {}
  local c = PetTrainingPlusCharDB
  c.known = c.known or {}     -- [abilityKey] = { [rank] = { t, src } }
  c.scanned = c.scanned or {} -- [familyID] = time of the last full Beast Training read with a pet of it
  c.pets = c.pets or {}       -- [id] = { id, name, fam, guid, origin = {...}, firstSeen, lastSeen }
  c.petSeq = c.petSeq or 0
  c.log = c.log or {}         -- newest last
  ns.char = c
end

-- ------------------------------------------------------------------ change notification
function ns.Changed()
  ns.Debounce("ui", 0.15, function()
    ns.RebuildLearnIndex()
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
    if ns.T and ns.T.Refresh then ns.T.Refresh() end
  end)
end

-- ------------------------------------------------------------------ what the hunter knows
function ns.MarkKnown(r, src)
  local k = ns.char.known[r.a.key]
  if not k then k = {}; ns.char.known[r.a.key] = k end
  if k[r.r] then return false end
  k[r.r] = { t = time(), src = src }
  ns.Changed()
  return true
end

function ns.IsKnown(r)
  local k = ns.char.known[r.a.key]
  return k and k[r.r] and true or false
end

-- "known" | "missing" (a full Beast Training read with a family that can learn it did not list it) | "unverified"
function ns.HunterRankState(r)
  if ns.IsKnown(r) then return "known" end
  for fam in pairs(ns.char.scanned) do
    if ns.FamilyCanLearn(fam, r.a) then return "missing" end
  end
  return "unverified"
end

function ns.KnownCount(a)
  local k, n = ns.char.known[a.key], 0
  if k then for _ in pairs(k) do n = n + 1 end end
  return n
end

-- Could you get this rank now? You don't know it, and you are at least the rank's pet level: a beast of that level
-- that knows it is one you can tame (you can tame beasts up to your own level); for trainer skills, a pet trainer
-- teaches it. nil when the rank's level isn't known yet.
function ns.PlayerLevel()
  local lvl = try(UnitLevel, "player")
  if type(lvl) == "number" and lvl > 0 then ns.lastPlayerLevel = lvl end
  return ns.lastPlayerLevel
end

function ns.CanObtain(r)
  if ns.IsKnown(r) then return false end
  local need, have = ns.RankLevel(r), ns.PlayerLevel()
  if not (need and have) then return nil end
  return have >= need
end

-- ------------------------------------------------------------------ your current pet
-- Spellbook of the pet: { [abilityKey] = rank }
function ns.ReadPetSpells()
  local ranks, any = {}, false
  local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
  local num = bank and try(api(C_SpellBook, "HasPetSpells"))
  if num and num > 0 then
    for i = 1, num do
      local info = try(C_SpellBook.GetSpellBookItemInfo, i, bank)
      local id = type(info) == "table" and clean(info.spellID)
      local r = id and ns.byPet[id]
      if r then
        any = true
        if not ranks[r.a.key] or r.r > ranks[r.a.key] then ranks[r.a.key] = r.r end
      end
    end
  end
  if not any and IsSpellKnown then
    -- fallback: ask rank by rank (IsSpellKnown(id, true) is true for the pet's ranks)
    for id, r in pairs(ns.byPet) do
      if try(IsSpellKnown, id, true) == true then
        any = true
        if not ranks[r.a.key] or r.r > ranks[r.a.key] then ranks[r.a.key] = r.r end
      end
    end
  end
  return ranks, any
end

local function petGuidKey()
  local g = clean(UnitGUID and UnitGUID("pet"))
  if type(g) ~= "string" then return nil end
  local parts = { strsplit("-", g) }
  return parts[#parts]
end

local function famFromUnit(unit)
  local name, id = try(UnitCreatureFamily, unit)
  if type(id) ~= "number" then
    id = nil
    if type(name) == "string" then
      for fid, n in pairs(ns.db.famNames) do if n == name then id = fid end end
      if not id then for fid, n in pairs(ns.FAMILY_EN) do if n == name then id = fid end end end
    end
  end
  if id and type(name) == "string" and name ~= "" then ns.db.famNames[id] = name end
  return id, name
end
ns.FamFromUnit = famFromUnit

-- The record of a pet: the one with its name and family; the GUID tail breaks ties and follows renames.
-- Retired records (v1.8.1: an older pet whose GUID a new tame took over) are never matched.
function ns.FindPetRecord(name, fam, gk)
  local best
  for _, p in pairs(ns.char.pets) do
    if not p.retired and p.name == name and (not fam or not p.fam or p.fam == fam) then
      if gk and p.guid == gk then return p end
      if not best or (p.lastSeen or 0) > (best.lastSeen or 0) then best = p end
    end
  end
  if best then return best end
  if gk then
    for _, p in pairs(ns.char.pets) do
      if not p.retired and p.guid == gk and p.fam == fam then return p end
    end
  end
  return nil
end

function ns.NewPetRecord(name, fam, gk)
  local c = ns.char
  c.petSeq = c.petSeq + 1
  local p = { id = c.petSeq, name = name, fam = fam, guid = gk, firstSeen = time(), lastSeen = time() }
  c.pets[p.id] = p
  return p
end

-- Reads the summoned pet (out of combat only: in combat the values are secret).
function ns.ReadPet()
  if ns.InCombat() then ns.pendingPetRead = true; return end
  if not (UnitExists and UnitExists("pet")) then
    ns.pet = nil
    ns.Changed()
    return
  end
  local name = try(UnitName, "pet")
  local fam, famName = famFromUnit("pet")
  local level = try(UnitLevel, "pet")
  local ranks, any = ns.ReadPetSpells()
  local total, spent = try(api(C_PetInfo, "GetPetTrainingPoints"))
  if total == nil and GetPetTrainingPoints then total, spent = try(GetPetTrainingPoints) end
  local gk = petGuidKey()
  local p = {
    name = name, fam = fam, famName = famName, level = level, ranks = ranks, spellsRead = any,
    tpTotal = total, tpSpent = spent, tpFree = (total and spent) and (total - spent) or nil, guid = gk,
  }
  -- what this family can learn: everything its spellbook shows
  if fam then
    ns.db.famCan[fam] = ns.db.famCan[fam] or {}
    for key in pairs(ranks) do ns.db.famCan[fam][key] = true end
  end
  -- during a tame the new pet has no record yet: don't lend it an old one with the same name (v1.8.1), or the loyalty
  -- recorder would start measuring under the old pet before the tame is recorded
  local taming = ns.tameInProgress and GetTime() - ns.tameInProgress < 60 -- a stuck flag expires after a minute
  if type(name) == "string" and name ~= "" and not taming then
    local rec = ns.FindPetRecord(name, fam, gk)
    if not rec and gk then
      -- renamed? same slot and family, but a name we have never seen
      for _, q in pairs(ns.char.pets) do
        if not q.retired and q.guid == gk and q.fam == fam and q.name ~= name then rec = q; rec.name = name; break end
      end
    end
    if not rec then rec = ns.NewPetRecord(name, fam, gk) end
    if rec then
      rec.lastSeen, rec.guid, rec.fam, rec.level = time(), gk or rec.guid, fam or rec.fam, level or rec.level
      p.rec = rec
    end
  end
  ns.pet = p
  ns.Changed()
end

function ns.RefreshPetSoon(sec) ns.Debounce("pet", sec or 0.4, ns.ReadPet) end

-- ------------------------------------------------------------------ state of a rank for your current pet
-- Returns state, detail. States: nopet, has, below, family, famunknown, unlearned, level, tp, trainable, unknown
function ns.RankPetState(r)
  local p = ns.pet
  if not p then return "nopet" end
  local cur = p.ranks[r.a.key]
  if cur and cur == r.r then return "has" end
  if cur and cur > r.r then return "below" end
  local can = ns.FamilyCanLearn(p.fam, r.a)
  if can == false then return "family" end
  local live = ns.T and ns.T.LiveRow(r)
  if live then
    if live.status == "available" then
      -- Blizzard calls a rank "available" once the level is met, even when the pet can't afford it
      if live.tp and p.tpFree and live.tp > p.tpFree then return "tp", live.tp end
      return "trainable", live.tp
    end
    local lvl = ns.RankLevel(r)
    if lvl and p.level and p.level < lvl then return "level", lvl end
    return "tp", live.tp
  end
  if not ns.IsKnown(r) then return "unlearned" end
  if can == nil then return "famunknown" end
  local lvl = ns.RankLevel(r)
  if lvl and p.level and p.level < lvl then return "level", lvl end
  local cost = ns.UpgradeCost(r)
  if cost and p.tpFree and cost > p.tpFree then return "tp", cost end
  return "trainable", cost
end

-- What training this rank costs your pet now: the live Beast Training value, else the rank's TP minus the rank it has.
function ns.UpgradeCost(r)
  local live = ns.T and ns.T.LiveRow(r)
  if live and live.tp then return live.tp end
  local tp = ns.RankTP(r)
  if not tp then return nil end
  local cur = ns.pet and ns.pet.ranks[r.a.key]
  local curR = cur and r.a.rankBy[cur]
  local refund = curR and ns.RankTP(curR) or 0
  return math.max(tp - refund, 0)
end

-- ------------------------------------------------------------------ position / zone
function ns.Where()
  local zone = GetRealZoneText and try(GetRealZoneText) or nil
  local sub = GetSubZoneText and try(GetSubZoneText) or nil
  local map = C_Map and try(C_Map.GetBestMapForUnit, "player")
  local x, y
  if map and C_Map.GetPlayerMapPosition then
    local pos = try(C_Map.GetPlayerMapPosition, map, "player")
    if type(pos) == "table" or type(pos) == "userdata" then
      local ok, px, py = pcall(pos.GetXY, pos)
      px, py = ok and clean(px), ok and clean(py)
      if px and py then x, y = math.floor(px * 1000 + 0.5) / 10, math.floor(py * 1000 + 0.5) / 10 end
    end
  end
  return { zone = zone, sub = (sub ~= "" and sub ~= zone) and sub or nil, map = map, x = x, y = y }
end

local function unitNpcId(unit)
  local g = clean(UnitGUID and UnitGUID(unit))
  if type(g) ~= "string" then return nil end
  local kind, _, _, _, _, id = strsplit("-", g)
  if kind ~= "Creature" then return nil end
  return tonumber(id)
end
ns.UnitNpcId = unitNpcId

-- ------------------------------------------------------------------ the learn log
function ns.AddLog(e)
  e.t = e.t or time()
  table.insert(ns.char.log, e)
  while #ns.char.log > 1000 do table.remove(ns.char.log, 1) end
  ns.Changed()
end

-- [abilityKey][rank] = the newest "learn" entry
ns.learnIndex = {}
function ns.RebuildLearnIndex()
  local idx = {}
  for _, e in ipairs(ns.char and ns.char.log or {}) do
    if e.kind == "learn" and e.key and e.r then
      idx[e.key] = idx[e.key] or {}
      idx[e.key][e.r] = e
    end
  end
  ns.learnIndex = idx
end
function ns.LearnEntry(r)
  local k = ns.learnIndex[r.a.key]
  return k and k[r.r]
end

-- Who taught it, in a few words: "Young Wolf (Lv 5) · Elwynn Forest"
function ns.SourceText(e)
  if not e then return nil end
  if e.src == "trainer" then
    return (e.trainer and ("Pet trainer " .. e.trainer) or "Pet trainer") .. (e.where and e.where.zone and (" · " .. e.where.zone) or "")
  end
  local o = e.origin
  if o and o.name then
    local s = o.name .. (o.level and (" (Lv " .. o.level .. ")") or "")
    if o.where and o.where.zone then s = s .. " · " .. o.where.zone end
    return s
  end
  if e.pet and e.pet.name then return "your pet " .. e.pet.name .. " (tamed before Pet Training+)" end
  return "unknown"
end

-- ------------------------------------------------------------------ learning: the hunter learns a rank
local LEARN_GLOBALS = { "ERR_LEARN_SPELL_S", "ERR_LEARN_ABILITY_S", "ERR_LEARN_PASSIVE_S" }
local PET_LEARN_GLOBALS = { "ERR_PET_LEARN_SPELL_S", "ERR_PET_LEARN_ABILITY_S", "ERR_PET_SPELL_LEARNED_S", "PET_LEARN_SPELL_S" }

local function toPattern(fmt)
  if type(fmt) ~= "string" or fmt == "" then return nil end
  local p = fmt:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  p = p:gsub("%%%%%d%%%$s", "(.+)"):gsub("%%%%s", "(.+)")
  return "^" .. p .. "$"
end

local learnPatterns, petPatterns
local function patterns()
  if learnPatterns then return learnPatterns, petPatterns end
  learnPatterns, petPatterns = {}, {}
  for _, g in ipairs(LEARN_GLOBALS) do local p = toPattern(_G[g]); if p then learnPatterns[#learnPatterns + 1] = p end end
  for _, g in ipairs(PET_LEARN_GLOBALS) do local p = toPattern(_G[g]); if p then petPatterns[#petPatterns + 1] = p end end
  return learnPatterns, petPatterns
end

-- From the text of a learn message: the rank (exact when the link carries a known spell ID), or ability + rank number.
function ns.ParseLearned(what)
  local spellID = tonumber(what:match("|Hspell:(%d+)"))
  local r = spellID and (ns.byHunter[spellID] or ns.byPet[spellID])
  if r then return r.a, r.r, spellID end
  local plain = what:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("^%[", ""):gsub("%]$", "")
  plain = plain:gsub("^['\"]", ""):gsub("['\"]$", "")
  local name, inner = plain:match("^(.-)%s*%((.-)%)$")
  local rank = inner and ns.RankNumber(inner)
  local a = ns.FindAbility(name or plain)
  if not a then return nil, nil, spellID end
  return a, rank, spellID
end

local recentLearn = {}

function ns.OnHunterLearned(a, rank, spellID, raw)
  -- the message has no rank: the hunter learns the rank the pet has (that is what the pet taught)
  if not rank and ns.pet and ns.pet.ranks[a.key] then rank = ns.pet.ranks[a.key] end
  local dedupe = a.key .. ":" .. tostring(rank)
  if recentLearn[dedupe] and time() - recentLearn[dedupe] < 30 then return end
  recentLearn[dedupe] = time()
  local r = rank and a.rankBy[rank]
  local src = "pet"
  local trainerName
  if ns.T and ns.T.npcTrainerOpen then
    src = "trainer"
    trainerName = try(UnitName, "npc")
  end
  if r then ns.MarkKnown(r, src == "trainer" and "trainer" or "learned") end
  local pet = ns.pet
  local rec = pet and pet.rec
  local e = {
    kind = "learn", key = a.key, r = rank, spell = spellID, src = src, trainer = trainerName,
    where = ns.Where(), raw = raw,
    pet = pet and { name = pet.name, fam = pet.fam, level = pet.level } or nil,
    origin = (src == "pet" and rec and rec.origin) or nil,
  }
  ns.AddLog(e)
  local nm = ns.AbilityName(a) .. (rank and (" (Rank " .. rank .. ")") or "")
  if src == "pet" then
    ns.Print(("Learned |cffffd100%s|r from %s."):format(nm, ns.SourceText(e) or "your pet"))
  else
    ns.Print(("Learned |cffffd100%s|r at the pet trainer."):format(nm))
  end
end

function ns.OnSystemMessage(msg)
  msg = clean(msg)
  if type(msg) ~= "string" then return end
  local lp, pp = patterns()
  for _, p in ipairs(lp) do
    local what = msg:match(p)
    if what then
      local a, rank, spellID = ns.ParseLearned(what)
      if a then ns.OnHunterLearned(a, rank, spellID, msg) end
      return
    end
  end
  for _, p in ipairs(pp) do
    if msg:match(p) then ns.RefreshPetSoon(0.5); return end
  end
  -- Forever's own pet message ("Your pet has learned the new spell '...'") has no global we know: any line naming a
  -- pet ability with "(Rank n)" re-reads the pet.
  if msg:find("%(.-%d+%)") then ns.RefreshPetSoon(0.6) end
end

function ns.OnLearnedSpellEvent(spellID)
  spellID = clean(spellID)
  local r = spellID and ns.byHunter[spellID]
  if r then ns.OnHunterLearned(r.a, r.r, spellID, "event") end
end

-- ------------------------------------------------------------------ tames: which creature your pet was
local pendingTame

local function isTameSpell(id)
  id = clean(id)
  if id == ns.TAME_BEAST then return true end
  if type(id) ~= "number" or not C_Spell then return false end
  local n = try(C_Spell.GetSpellName, id)
  return n ~= nil and n == try(C_Spell.GetSpellName, ns.TAME_BEAST)
end

function ns.OnTameStart(spellID)
  if not isTameSpell(spellID) then return end
  if pendingTame and GetTime() - pendingTame.clock < 3 then return end -- CHANNEL_START and SUCCEEDED both come
  local npc = unitNpcId("target")
  if not npc then pendingTame = nil; return end
  local fam, famName = famFromUnit("target")
  pendingTame = {
    clock = GetTime(), t = time(), npc = npc, name = try(UnitName, "target"), level = try(UnitLevel, "target"),
    fam = fam, famName = famName, cls = try(UnitClassification, "target"), where = ns.Where(),
  }
  ns.tameInProgress = GetTime()
end

function ns.OnTameStop(spellID)
  if not (pendingTame and isTameSpell(spellID)) then return end
  pendingTame.stop = GetTime()
  -- only a pet arriving within 10 s of the stop is a tame (moving cancels the channel without other events)
  ns.After(12, function()
    if pendingTame and pendingTame.stop and GetTime() - pendingTame.stop >= 10 then
      pendingTame = nil
      ns.tameInProgress = nil
    end
  end)
end

local function finishTame(tm)
  if not (UnitExists and UnitExists("pet")) then return false end
  local name = try(UnitName, "pet")
  local fam = famFromUnit("pet")
  if tm.fam and fam and tm.fam ~= fam then return false end
  local ranks = ns.ReadPetSpells()
  local origin = {
    npc = tm.npc, name = tm.name, level = tm.level, fam = tm.fam, cls = tm.cls, where = tm.where, t = tm.t, teaches = ranks,
  }
  -- Forever can give a new pet the GUID of one you abandoned: retire the old record so it isn't matched again (v1.8.1)
  local gk = petGuidKey()
  if gk then
    for _, q in pairs(ns.char.pets) do
      if q.guid == gk and not q.retired then q.retired = time() end
    end
  end
  local rec = ns.NewPetRecord(name, fam, gk)
  rec.origin = origin
  if ns.Loyalty then ns.Loyalty.OnTamed() end -- its first loyalty level is measured from the start
  local cr = ns.db.creatures[tm.npc] or {}
  cr.name, cr.t, cr.teaches = tm.name, time(), ranks
  ns.db.creatures[tm.npc] = cr
  ns.AddLog({ kind = "tame", origin = origin, petName = name, fam = fam })
  local list = {}
  for key, rk in pairs(ranks) do
    local a = ns.byKey[key]
    if a and a.key ~= "Growl" then list[#list + 1] = ns.AbilityName(a) .. " " .. rk end
  end
  table.sort(list)
  ns.Print(("Tamed |cffffd100%s|r%s. %s"):format(tm.name or "?", tm.level and (" (Lv " .. tm.level .. ")") or "",
    #list > 0 and ("It knows: " .. table.concat(list, ", ") .. ".") or ""))
  return true
end

function ns.OnUnitPet(unit)
  if unit ~= "player" then return end
  local tm = pendingTame
  if tm then
    local now = GetTime()
    local fresh = (tm.stop and now - tm.stop <= 10) or (not tm.stop and now - tm.clock >= 15 and now - tm.clock <= 40)
    if fresh then
      tm.petSeenAt = tm.petSeenAt or now
      -- the spellbook is filled at the second UNIT_PET: read a moment later
      ns.Debounce("tame", 1.5, function()
        if pendingTame ~= tm then return end
        if ns.InCombat() then return end
        local ok, done = pcall(finishTame, tm)
        if ok and done then
          pendingTame = nil
          ns.tameInProgress = nil
        elseif GetTime() - (tm.petSeenAt or 0) > 8 then
          pendingTame = nil
          ns.tameInProgress = nil
        end
        ns.ReadPet()
      end)
      return
    end
  end
  ns.RefreshPetSoon(0.8)
end

-- /ptp origin: your target becomes the creature your current pet came from (for pets tamed before the addon).
function ns.SetOriginFromTarget()
  if not (ns.pet and ns.pet.rec) then ns.Print("Summon the pet first."); return end
  local npc = unitNpcId("target")
  if not npc then ns.Print("Target the creature (a beast of the same kind) first."); return end
  ns.pet.rec.origin = {
    npc = npc, name = try(UnitName, "target"), level = try(UnitLevel, "target"), fam = famFromUnit("target"),
    where = ns.Where(), t = time(), manual = true,
  }
  ns.Print(("%s now counts as tamed from %s."):format(ns.pet.name or "Your pet", ns.pet.rec.origin.name or "?"))
  ns.Changed()
end

-- ------------------------------------------------------------------ wiring
ns.On("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  initDB()
  ns.RebuildLearnIndex()
end)

ns.On("PLAYER_LOGIN", function()
  if not ns.db then initDB() end
  ns.After(2, ns.ReadPet)
  if ns.UI and ns.UI.Init then ns.UI.Init() end
end)

ns.On("CHAT_MSG_SYSTEM", function(msg) ns.OnSystemMessage(msg) end)
ns.On("LEARNED_SPELL_IN_SKILL_LINE", function(id) ns.OnLearnedSpellEvent(id) end)
ns.On("LEARNED_SPELL_IN_TAB", function(id) ns.OnLearnedSpellEvent(id) end)

ns.On("UNIT_PET", function(unit) ns.OnUnitPet(unit) end)
ns.On("PET_BAR_UPDATE", function() ns.RefreshPetSoon() end)
ns.On("SPELLS_CHANGED", function() ns.RefreshPetSoon() end)
ns.On("UNIT_PET_TRAINING_POINTS", function() ns.RefreshPetSoon(0.2) end)
ns.On("UNIT_LEVEL", function(unit) if unit == "pet" then ns.RefreshPetSoon() end end)
ns.On("UNIT_NAME_UPDATE", function(unit) if unit == "pet" then ns.RefreshPetSoon() end end)
ns.On("PLAYER_LEVEL_UP", function(lvl)
  if type(clean(lvl)) == "number" then ns.lastPlayerLevel = lvl end
  ns.Changed()
end)
ns.On("PLAYER_REGEN_ENABLED", function()
  if ns.pendingPetRead then ns.pendingPetRead = nil; ns.RefreshPetSoon(0.3) end
end)

for _, e in ipairs({ "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_SUCCEEDED" }) do
  ns.On(e, function(unit, _, spellID) if unit == "player" then ns.OnTameStart(spellID) end end)
end
ns.On("UNIT_SPELLCAST_CHANNEL_STOP", function(unit, _, spellID) if unit == "player" then ns.OnTameStop(spellID) end end)
for _, e in ipairs({ "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED" }) do
  ns.On(e, function(unit, _, spellID)
    if unit == "player" and pendingTame and isTameSpell(spellID) and GetTime() - pendingTame.clock > 1 then
      pendingTame = nil; ns.tameInProgress = nil
    end
  end)
end

-- ------------------------------------------------------------------ slash commands
SLASH_PETTRAININGPLUS1 = "/ptp"
SLASH_PETTRAININGPLUS2 = "/pettraining"
SlashCmdList.PETTRAININGPLUS = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "log" then
    if ns.UI then ns.UI.Show("log") end
  elseif msg == "loyalty" then
    if ns.Loyalty then ns.Loyalty.Report() end
  elseif msg == "loyalty export" then
    if ns.Loyalty then ns.Loyalty.ShowExport() end
  elseif msg == "origin" then
    ns.SetOriginFromTarget()
  elseif msg == "debug" then
    ns.debug = not ns.debug
    ns.Print("debug " .. (ns.debug and "on" or "off"))
    if ns.T and ns.T.DebugReport then ns.T.DebugReport() end
  elseif msg == "dock" or msg == "replace" then
    ns.db.opts.replace = (msg == "replace")
    ns.Print(ns.db.opts.replace and "Beast Training: Blizzard's window and Pet Training+ framed together as one."
      or "Beast Training: Blizzard's window and Pet Training+ as two windows side by side.")
    if ns.T and ns.T.ApplyMode then ns.T.ApplyMode() end
  elseif msg:match("^scale") then
    local v = tonumber(msg:match("^scale%s+([%d%.]+)"))
    if v and v >= 0.6 and v <= 2 then
      ns.db.opts.scale = v
      if ns.UI and ns.UI.ApplyScale then ns.UI.ApplyScale() end
      ns.Print(("Window scale %.2f."):format(v))
    else
      ns.Print(("Window scale is %.2f. Use /ptp scale 0.6 to 2 (1.3 is the default)."):format(ns.db.opts.scale or 1.3))
    end
  elseif msg == "resetpos" then
    if ns.UI and ns.UI.ResetPosition then ns.UI.ResetPosition() end
    ns.Print("Window position reset.")
  elseif msg == "reset" then
    PetTrainingPlusCharDB = nil
    initDB()
    ns.RebuildLearnIndex()
    ns.ReadPet()
    ns.Print("This character's known ranks, pets and log were cleared.")
  elseif msg == "help" or msg == "?" then
    ns.Print("/ptp — open/close · /ptp log — learn log · /ptp origin — set your pet's origin to your target")
    ns.Print("/ptp replace | dock — how the window behaves in Beast Training · /ptp scale 1.3 — window size")
    ns.Print("Drag the window anywhere (in Beast Training, dragging moves both windows) · /ptp resetpos — put it back")
    ns.Print("/ptp loyalty — loyalty level, rate and progress · /ptp loyalty export — copy the recorded loyalty data")
    ns.Print("/ptp reset — clear this character")
  else
    if ns.UI then ns.UI.Toggle() end
  end
end

function PetTrainingPlus_OnCompartmentClick() if ns.UI then ns.UI.Toggle() end end
