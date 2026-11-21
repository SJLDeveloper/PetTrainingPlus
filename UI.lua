-- Pet Training+ · the window: every pet skill with all its ranks on one line, what your pet has and can use,
-- and the log of where each rank was learned.
local _, ns = ...
local UI = {}
ns.UI = UI
local T = ns.T

local BASE_W, H = 790, 560 -- skills + detail
local W = BASE_W
local LIST_W = 372
local ROW_H = 30
local RANK_ROW_H = 20
local LOG_ROW_H = 36
local TOGGLE_H = 38
local SCALE = 1.3 -- the whole window, text included (about +4 points on the usual fonts); /ptp scale changes it
local WHITE = "Interface\\Buttons\\WHITE8X8"

local READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local NOTREADY = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local WAITING = "Interface\\RaidFrame\\ReadyCheck-Waiting"

-- pill colours: bg, border, text
local STYLE = {
  unknown   = { { .09, .09, .09 }, { .22, .22, .22 }, { .42, .42, .42 } },
  missing   = { { .13, .06, .06 }, { .38, .16, .16 }, { .62, .36, .36 } },
  known     = { { .28, .21, .06 }, { .62, .47, .14 }, { 1, .82, 0 } },
  trainable = { { .22, .30, .08 }, { .45, 1, .35 }, { .75, 1, .55 } },
  has       = { { .07, .34, .12 }, { .30, .92, .42 }, { 1, 1, 1 } },
  below     = { { .06, .17, .08 }, { .18, .40, .22 }, { .55, .75, .58 } },
}

local f -- main frame
local state = { tab = "skills", ability = nil, rank = nil, offset = 0, logOffset = 0, search = "" }
UI.state = state

-- ------------------------------------------------------------------ small builders
local function tex(parent, layer, r, g, b, a)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  if r then t:SetColorTexture(r, g, b, a or 1) end
  return t
end

local function fs(parent, font, justify)
  local s = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  s:SetJustifyH(justify or "LEFT")
  if s.SetWordWrap then s:SetWordWrap(false) end
  return s
end

local function backdrop(frame, bg, border, edge)
  if not frame.SetBackdrop then return end
  frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = edge or 1 })
  frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
  frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function textButton(parent, text, w, h)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, h or 20)
  backdrop(b, { .12, .10, .07, 1 }, { .40, .32, .15, 1 })
  b.label = fs(b, "GameFontNormalSmall", "CENTER")
  b.label:SetPoint("CENTER")
  b.label:SetText(text)
  local hl = tex(b, "HIGHLIGHT", 1, .82, 0, .12)
  hl:SetAllPoints()
  function b:SetActive(on)
    if on then
      backdrop(self, { .30, .22, .06, 1 }, { .85, .65, .2, 1 })
      self.label:SetTextColor(1, .9, .4)
    else
      backdrop(self, { .12, .10, .07, 1 }, { .40, .32, .15, 1 })
      self.label:SetTextColor(1, .82, 0)
    end
  end
  return b
end

local function tooltipFor(owner, fn)
  owner:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    fn(self)
    GameTooltip:Show()
  end)
  owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- right-click anywhere on a skill: show it in Forever Bestiary
local function rightClick(a, button)
  if button == "RightButton" then
    if ns.Bestiary then ns.Bestiary.ShowAbility(a) end
    return true
  end
end
local function bestiaryHint()
  if ns.Bestiary and ns.Bestiary.Available() then GameTooltip:AddLine("Right-click: show in Forever Bestiary", .45, .75, 1) end
end
UI.BestiaryHint = bestiaryHint

local function fmtDate(t) return t and date("%b %d, %H:%M", t) or "" end

local function whereText(w)
  if not w then return nil end
  local s = w.zone
  if w.sub then s = (s and (s .. " (" .. w.sub .. ")")) or w.sub end
  return s
end

-- ------------------------------------------------------------------ rank state for display
-- The combined look of a rank: what your pet has wins over what you know.
local function rankStyle(r)
  local ps, detail = ns.RankPetState(r)
  if ps == "has" then return "has", ps, detail end
  if ps == "below" then return "below", ps, detail end
  local hs = ns.HunterRankState(r)
  if hs == "known" then
    if ps == "trainable" then return "trainable", ps, detail end
    return "known", ps, detail
  end
  return hs == "missing" and "missing" or "unknown", ps, detail
end

local PET_TEXT = {
  has = "|cff4dff6aHas it|r", below = "|cff7fbf86Has higher|r", family = "|cffff5050Family can't|r",
  famunknown = "|cffaaaaaa?|r", unlearned = "|cff777777—|r", nopet = "|cff777777—|r",
}
local function petCell(r)
  local ps, d = ns.RankPetState(r)
  if ps == "trainable" then return "|cff9cff7aTrainable" .. (d and (" · " .. d .. " TP") or "") .. "|r" end
  if ps == "level" then return "|cffffa040Pet Lv " .. tostring(d) .. "|r" end
  if ps == "tp" then return "|cffffa040" .. (d and (d .. " TP") or "TP") .. "|r" end
  return PET_TEXT[ps] or ""
end

function UI.RankTooltip(r)
  GameTooltip:SetSpellByID(r.pet)
  GameTooltip:AddLine(" ")
  local hs = ns.HunterRankState(r)
  local e = ns.LearnEntry(r)
  if hs == "known" then
    local k = ns.char.known[r.a.key][r.r]
    if e then
      GameTooltip:AddLine("You learned it " .. fmtDate(e.t), 1, .82, 0)
      GameTooltip:AddLine("From: " .. (ns.SourceText(e) or "?"), 1, 1, 1, true)
      if e.pet and e.pet.name and e.src == "pet" then
        GameTooltip:AddLine("Your pet then: " .. e.pet.name .. (e.pet.level and (", Lv " .. e.pet.level) or ""), .8, .8, .8)
      end
      local w = whereText(e.where)
      if w and e.src == "pet" then GameTooltip:AddLine("Learned in: " .. w, .8, .8, .8) end
    else
      GameTooltip:AddLine("You know this rank", 1, .82, 0)
      if k and k.src == "training" then
        GameTooltip:AddLine("Read from Beast Training (learned before Pet Training+ was logging).", .7, .7, .7, true)
      end
    end
  elseif hs == "missing" then
    GameTooltip:AddLine("You have not learned this rank.", 1, .4, .4)
  else
    GameTooltip:AddLine("Not confirmed yet: open Beast Training with a pet that can learn it.", .7, .7, .7, true)
  end
  local lvl, tp = ns.RankLevel(r), ns.RankTP(r)
  if lvl or tp then
    GameTooltip:AddLine(("Pet level %s · %s TP"):format(lvl or "?", tp or "?"), .8, .8, .8)
  end
  local ps = petCell(r)
  if ns.pet and ps ~= "" then GameTooltip:AddLine((ns.pet.name or "Pet") .. ": " .. ps, 1, 1, 1) end
  bestiaryHint()
end

-- ------------------------------------------------------------------ rank pills
local function makePill(parent)
  local p = CreateFrame("Button", nil, parent, "BackdropTemplate")
  p:SetSize(17, 17)
  p.text = fs(p, "GameFontHighlightSmall", "CENTER")
  p.text:SetPoint("CENTER", 0, 0)
  p:SetScript("OnEnter", function(self)
    if not self.r then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    UI.RankTooltip(self.r)
    GameTooltip:Show()
  end)
  p:SetScript("OnLeave", function() GameTooltip:Hide() end)
  p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  p:SetScript("OnClick", function(self, button)
    if not self.r or rightClick(self.r.a, button) then return end
    UI.Select(self.r.a, self.r)
  end)
  return p
end

local function stylePill(p, r)
  p.r = r
  local key = rankStyle(r)
  local s = STYLE[key]
  backdrop(p, s[1], s[2], key == "trainable" and 2 or 1)
  p.text:SetTextColor(s[3][1], s[3][2], s[3][3])
  p.text:SetText(r.r)
end

-- ------------------------------------------------------------------ list of abilities
local listRows = {}
local listItems = {}

local function abilityMatches(a)
  if state.search ~= "" then
    local n = ns.AbilityName(a):lower()
    if not n:find(state.search, 1, true) and not a.key:lower():find(state.search, 1, true) then return false end
  end
  if ns.db.opts.filter == "known" and ns.KnownCount(a) == 0 then return false end
  if UI.PetOnlyActive() and ns.FamilyCanLearn(ns.pet.fam, a) == false then return false end
  return true
end

-- The "only what my pet can learn" toggle hides skills only while a pet is out.
function UI.PetOnlyActive()
  return ns.db.opts.petOnly and ns.pet ~= nil and ns.pet.fam ~= nil
end

-- How many skills the current pet's family can't learn (what the toggle hides).
local function hiddenByPet()
  if not (ns.pet and ns.pet.fam) then return 0 end
  local n = 0
  for _, a in ipairs(ns.Abilities) do
    if ns.FamilyCanLearn(ns.pet.fam, a) == false then n = n + 1 end
  end
  return n
end

local function sortKey(a)
  local can = ns.pet and ns.FamilyCanLearn(ns.pet.fam, a)
  return (can == false and 1 or 0), ns.AbilityName(a)
end

local function buildList()
  wipe(listItems)
  local sections = {
    { kind = "tame", title = "Learned from beasts" },
    { kind = "general", title = "Taught by pet trainers" },
  }
  for _, sec in ipairs(sections) do
    local items = {}
    for _, a in ipairs(ns.Abilities) do
      if a.kind == sec.kind and abilityMatches(a) then items[#items + 1] = a end
    end
    table.sort(items, function(x, y)
      local x1, x2 = sortKey(x)
      local y1, y2 = sortKey(y)
      if x1 ~= y1 then return x1 < y1 end
      return x2 < y2
    end)
    if #items > 0 then
      listItems[#listItems + 1] = { header = sec.title, n = #items }
      for _, a in ipairs(items) do listItems[#listItems + 1] = { a = a } end
    end
  end
end

local function makeListRow(parent, i)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(LIST_W - 14, ROW_H)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  row.sel = tex(row, "BACKGROUND", 1, .82, 0, .14)
  row.sel:SetAllPoints()
  row.sel:Hide()
  local hl = tex(row, "HIGHLIGHT", 1, 1, 1, .06)
  hl:SetAllPoints()
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(24, 24)
  row.icon:SetPoint("LEFT", 4, 0)
  row.icon:SetTexCoord(.07, .93, .07, .93)
  row.name = fs(row, "GameFontNormal")
  row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 7, 0)
  row.name:SetWidth(150)
  row.sub = fs(row, "GameFontDisableSmall")
  row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 7, 0)
  row.sub:SetWidth(150)
  row.header = fs(row, "GameFontNormalSmall")
  row.header:SetPoint("BOTTOMLEFT", 4, 5)
  row.line = tex(row, "ARTWORK", .6, .48, .2, .5)
  row.line:SetHeight(1)
  row.line:SetPoint("BOTTOMLEFT", 2, 2)
  row.line:SetPoint("BOTTOMRIGHT", -2, 2)
  row.pills = {}
  for k = 1, 10 do
    local p = makePill(row)
    p:SetPoint("RIGHT", row, "RIGHT", -2 - (10 - k) * 18, 0)
    row.pills[k] = p
  end
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row:SetScript("OnClick", function(self, button)
    if not self.a or rightClick(self.a, button) then return end
    UI.Select(self.a)
  end)
  row:SetScript("OnEnter", function(self)
    if not (self.a and ns.Bestiary and ns.Bestiary.Available()) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(ns.AbilityName(self.a))
    GameTooltip:AddLine("Click: details · Right-click: show in Forever Bestiary", .45, .75, 1)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:EnableMouseWheel(true)
  row:SetScript("OnMouseWheel", function(_, d) UI.Scroll(-d) end)
  return row
end

local function petSubText(a)
  local p = ns.pet
  local n, total = ns.KnownCount(a), a.maxRank
  local known = ("%d/%d known"):format(n, total)
  if not p then return known end
  local cur = p.ranks[a.key]
  if cur then return known .. " · |cff4dff6apet: Rank " .. cur .. "|r" end
  local can = ns.FamilyCanLearn(p.fam, a)
  if can == false then return known .. " · |cffff6060not for " .. ns.FamName(p.fam) .. "|r" end
  if can == nil then return known .. " · |cffaaaaaa? for " .. ns.FamName(p.fam) .. "|r" end
  return known
end

function UI.RefreshList()
  if not f then return end
  buildList()
  local maxOff = math.max(#listItems - #listRows, 0)
  if state.offset > maxOff then state.offset = maxOff end
  for i, row in ipairs(listRows) do
    local item = listItems[i + state.offset]
    row.a = nil
    if not item then
      row:Hide()
    else
      row:Show()
      local isHeader = item.header ~= nil
      row.header:SetShown(isHeader)
      row.line:SetShown(isHeader)
      row.icon:SetShown(not isHeader)
      row.name:SetShown(not isHeader)
      row.sub:SetShown(not isHeader)
      row:EnableMouse(not isHeader)
      if isHeader then
        row.header:SetText(item.header .. "  |cff8a7a5a(" .. item.n .. ")|r")
        row.sel:Hide()
        for _, p in ipairs(row.pills) do p:Hide() end
      else
        local a = item.a
        row.a = a
        row.icon:SetTexture(ns.AbilityIcon(a))
        row.name:SetText(ns.AbilityName(a))
        local anyKnown = ns.KnownCount(a) > 0
        local can = ns.pet and ns.FamilyCanLearn(ns.pet.fam, a)
        if can == false then
          row.name:SetTextColor(.6, .5, .4)
          row.icon:SetDesaturated(true)
        elseif anyKnown then
          row.name:SetTextColor(1, .82, 0)
          row.icon:SetDesaturated(false)
        else
          row.name:SetTextColor(.75, .75, .75)
          row.icon:SetDesaturated(false)
        end
        row.sub:SetText(petSubText(a))
        row.sel:SetShown(state.ability == a)
        -- right-aligned pills: the last rank sits at the right edge
        local n = #a.ranks
        for k = 1, 10 do
          local p = row.pills[k]
          local r = a.ranks[k - (10 - n)]
          if r and k > 10 - n then
            stylePill(p, r)
            p:Show()
          else
            p:Hide()
          end
        end
      end
    end
  end
  -- scroll thumb
  local bar = f.skills.scroll
  if #listItems > #listRows then
    bar:Show()
    local h = bar:GetHeight()
    local th = math.max(h * #listRows / #listItems, 20)
    bar.thumb:SetHeight(th)
    bar.thumb:SetPoint("TOP", bar, "TOP", 0, -(h - th) * (state.offset / math.max(maxOff, 1)))
  else
    bar:Hide()
  end
end

-- The skills the list shows now (for tests and debugging).
function UI.ListedAbilities()
  buildList()
  local out = {}
  for _, it in ipairs(listItems) do if it.a then out[it.a.key] = true end end
  return out
end

function UI.RefreshToggle()
  local tg = f and f.skills and f.skills.toggle
  if not tg then return end
  local p = ns.pet
  if not (p and p.fam) then
    backdrop(tg, { .10, .10, .10, 1 }, { .30, .30, .30, 1 }, 2)
    tg.icon:SetTexture("Interface\\Icons\\Ability_Hunter_BeastCall")
    tg.icon:SetDesaturated(true)
    tg.title:SetText("|cffaaaaaaNo pet summoned: showing every skill|r")
    tg.sub:SetText("|cff888888Summon a pet to hide what it can't learn|r")
    return
  end
  tg.icon:SetDesaturated(false)
  if SetPortraitTexture then pcall(SetPortraitTexture, tg.icon, "pet") end
  local who = (p.name or "your pet") .. " (" .. ns.FamName(p.fam) .. ")"
  local n = hiddenByPet()
  if ns.db.opts.petOnly then
    backdrop(tg, { .10, .28, .10, 1 }, { .35, .95, .40, 1 }, 2)
    tg.title:SetText("|cff9cff7aShowing only what " .. who .. " can learn|r")
    tg.sub:SetText(n .. " skill" .. (n == 1 and "" or "s") .. " hidden · click to show all skills")
  else
    backdrop(tg, { .30, .21, .05, 1 }, { 1, .75, .25, 1 }, 2)
    tg.title:SetText("|cffffd100Showing all skills|r")
    tg.sub:SetText("Click to hide the " .. n .. " that " .. who .. " can't learn")
  end
end

function UI.Scroll(delta)
  if state.tab == "log" then
    state.logOffset = math.max(state.logOffset + delta * 2, 0)
    UI.RefreshLog()
  else
    state.offset = math.max(state.offset + delta * 2, 0)
    UI.RefreshList()
  end
end

-- ------------------------------------------------------------------ detail of one ability
local rankRows = {}

local function bestTrainable(a)
  local best
  for _, r in ipairs(a.ranks) do
    if ns.RankPetState(r) == "trainable" and ns.IsKnown(r) then best = r end
  end
  return best
end

-- After training rank r: the next rank of that skill your pet can train now, else simply the next rank (its row then
-- shows what it still needs), else stay on r.
function UI.AdvanceAfterTrain(r)
  local a = r.a
  local nextR
  for k = r.r + 1, a.maxRank do
    local rk = a.rankBy[k]
    if rk and ns.RankPetState(rk) == "trainable" then nextR = rk; break end
  end
  nextR = nextR or a.rankBy[r.r + 1] or r
  state.ability = a
  state.rank = nextR
  if T.beast then T.SetTarget(nextR) end
  UI.Refresh()
end

function UI.Select(a, r)
  state.ability = a
  state.rank = r or bestTrainable(a)
  if T.beast then T.SetTarget(state.rank) end
  UI.Refresh()
end

local function makeRankRow(parent, i)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(LIST_W + 4, RANK_ROW_H)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * RANK_ROW_H)
  row.sel = tex(row, "BACKGROUND", 1, .82, 0, .16)
  row.sel:SetAllPoints()
  row.sel:Hide()
  row.zebra = tex(row, "BACKGROUND", 1, 1, 1, (i % 2 == 0) and .03 or 0)
  row.zebra:SetAllPoints()
  local hl = tex(row, "HIGHLIGHT", 1, 1, 1, .07)
  hl:SetAllPoints()
  row.rank = fs(row, "GameFontHighlightSmall")
  row.rank:SetPoint("LEFT", 6, 0)
  row.rank:SetWidth(44)
  row.lvl = fs(row, "GameFontHighlightSmall", "CENTER")
  row.lvl:SetPoint("LEFT", 50, 0)
  row.lvl:SetWidth(36)
  row.tp = fs(row, "GameFontHighlightSmall", "CENTER")
  row.tp:SetPoint("LEFT", 86, 0)
  row.tp:SetWidth(30)
  row.you = row:CreateTexture(nil, "ARTWORK")
  row.you:SetSize(14, 14)
  row.you:SetPoint("LEFT", 128, 0)
  row.pet = fs(row, "GameFontHighlightSmall")
  row.pet:SetPoint("LEFT", 152, 0)
  row.pet:SetWidth(92)
  row.from = fs(row, "GameFontHighlightSmall")
  row.from:SetPoint("LEFT", 246, 0)
  row.from:SetPoint("RIGHT", -4, 0)
  row:SetScript("OnEnter", function(self)
    if not self.r then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    UI.RankTooltip(self.r)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row:SetScript("OnClick", function(self, button)
    if not self.r or rightClick(self.r.a, button) then return end
    UI.Select(self.r.a, self.r)
  end)
  return row
end

local function familiesText(a)
  if a.kind == "general" then return "All pet families" end
  local names, seen = {}, {}
  for _, id in ipairs(a.fam) do seen[id] = true; names[#names + 1] = ns.FamName(id) end
  for fam, list in pairs(ns.db.famCan) do
    if list[a.key] and not seen[fam] then seen[fam] = true; names[#names + 1] = ns.FamName(fam) end
  end
  if #names == 0 then return "|cffaaaaaaNot known yet: it fills in as you see pets with it|r" end
  table.sort(names)
  return table.concat(names, ", ")
end

function UI.RefreshDetail()
  if not f then return end
  local d = f.skills.detail
  local a = state.ability
  if not a then
    d.empty:Show()
    d.body:Hide()
    return
  end
  d.empty:Hide()
  d.body:Show()
  d.icon:SetTexture(ns.AbilityIcon(a))
  d.name:SetText(ns.AbilityName(a))
  d.bestiary:SetShown(ns.Bestiary and ns.Bestiary.Available() or false)
  d.kind:SetText(a.kind == "general" and "Taught by pet trainers in the cities"
    or "Learned from beasts: tame one that knows it and fight alongside it")
  d.fams:SetText("|cffffd100Families:|r " .. familiesText(a))
  local p = ns.pet
  if p then
    local can = ns.FamilyCanLearn(p.fam, a)
    local cur = p.ranks[a.key]
    local who = (p.name or "Your pet") .. " (" .. ns.FamName(p.fam) .. ")"
    if cur then
      d.usable:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t " .. who .. " has Rank " .. cur)
    elseif can == true then
      d.usable:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t " .. who .. " can learn this")
    elseif can == false then
      d.usable:SetText("|TInterface\\RaidFrame\\ReadyCheck-NotReady:14|t " .. who .. " can't learn this")
    else
      d.usable:SetText("|TInterface\\RaidFrame\\ReadyCheck-Waiting:14|t Not known yet whether a " .. ns.FamName(p.fam) .. " can learn this")
    end
  else
    d.usable:SetText("|cffaaaaaaNo pet summoned|r")
  end
  local descR = state.rank or a.ranks[#a.ranks]
  local desc = C_Spell and ns.try(C_Spell.GetSpellDescription, descR.pet)
  if (not desc or desc == "") and C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, descR.pet) end
  d.desc:SetText(desc or "")
  for i, row in ipairs(rankRows) do
    local r = a.ranks[i]
    row.r = r
    if not r then
      row:Hide()
    else
      row:Show()
      row.sel:SetShown(state.rank == r)
      row.rank:SetText("Rank " .. r.r)
      local hs = ns.HunterRankState(r)
      row.rank:SetTextColor(hs == "known" and 1 or .6, hs == "known" and .82 or .6, hs == "known" and 0 or .6)
      local lvl, tp = ns.RankLevel(r), ns.RankTP(r)
      row.lvl:SetText(lvl or "|cff666666?|r")
      row.tp:SetText(tp or "|cff666666?|r")
      row.you:SetTexture(hs == "known" and READY or hs == "missing" and NOTREADY or WAITING)
      row.you:SetAlpha(hs == "unverified" and .5 or 1)
      row.pet:SetText(petCell(r))
      local e = ns.LearnEntry(r)
      local k = ns.char.known[a.key] and ns.char.known[a.key][r.r]
      if e then
        local o = e.origin
        local s
        if e.src == "trainer" then s = "Pet trainer"
        elseif o and o.name then s = o.name .. (o.level and (" (" .. o.level .. ")") or "")
        else s = "pet " .. ((e.pet and e.pet.name) or "?") end
        row.from:SetText("|cffe6d2a0" .. s .. "|r")
      elseif k then
        row.from:SetText("|cff888888before logging|r")
      else
        row.from:SetText("")
      end
    end
  end
end

-- ------------------------------------------------------------------ log
local logRows = {}
local logItems = {}

local function makeLogRow(parent, i)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(BASE_W - 40, LOG_ROW_H)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * LOG_ROW_H)
  row.zebra = tex(row, "BACKGROUND", 1, 1, 1, (i % 2 == 0) and .035 or 0)
  row.zebra:SetAllPoints()
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(26, 26)
  row.icon:SetPoint("LEFT", 6, 0)
  row.icon:SetTexCoord(.07, .93, .07, .93)
  row.title = fs(row, "GameFontNormal")
  row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
  row.title:SetWidth(520)
  row.sub = fs(row, "GameFontHighlightSmall")
  row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, -1)
  row.sub:SetWidth(600)
  row.sub:SetTextColor(.78, .74, .66)
  row.when = fs(row, "GameFontDisableSmall", "RIGHT")
  row.when:SetPoint("TOPRIGHT", -8, -5)
  row:EnableMouse(true)
  row:SetScript("OnMouseWheel", function(_, d) UI.Scroll(-d) end)
  row:SetScript("OnMouseUp", function(self, button)
    local e = self.e
    if e and e.kind == "learn" and e.key and ns.byKey[e.key] then rightClick(ns.byKey[e.key], button) end
  end)
  tooltipFor(row, function(self)
    local e = self.e
    if not e then return end
    if e.kind == "learn" and e.key and ns.byKey[e.key] then
      local a = ns.byKey[e.key]
      local r = e.r and a.rankBy[e.r]
      if r then GameTooltip:SetSpellByID(r.pet) else GameTooltip:SetText(ns.AbilityName(a)) end
    else
      GameTooltip:SetText("Tame")
    end
    local o = e.origin
    if o then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Creature: " .. (o.name or "?") .. (o.level and (" (Lv " .. o.level .. ")") or ""), 1, 1, 1)
      if o.fam then GameTooltip:AddLine("Family: " .. ns.FamName(o.fam), .8, .8, .8) end
      local w = whereText(o.where)
      if w then
        local xy = (o.where.x and o.where.y) and (("  %.1f, %.1f"):format(o.where.x, o.where.y)) or ""
        GameTooltip:AddLine("Tamed in: " .. w .. xy, .8, .8, .8)
      end
      if o.t then GameTooltip:AddLine("Tamed on: " .. fmtDate(o.t), .8, .8, .8) end
      if o.npc then GameTooltip:AddLine("NPC ID: " .. o.npc, .6, .6, .6) end
      if o.manual then GameTooltip:AddLine("Origin set by hand (/ptp origin)", .6, .6, .6) end
    end
    if e.kind == "learn" then
      local w = whereText(e.where)
      if w then GameTooltip:AddLine("Learned in: " .. w, .8, .8, .8) end
      if e.raw and e.raw ~= "event" then GameTooltip:AddLine(e.raw, .5, .5, .5, true) end
      bestiaryHint()
    end
  end)
  return row
end

function UI.RefreshLog()
  if not f then return end
  wipe(logItems)
  local show = ns.db.opts.showTames
  local log = ns.char.log
  for i = #log, 1, -1 do
    local e = log[i]
    if e.kind == "learn" or (e.kind == "tame" and show) then logItems[#logItems + 1] = e end
  end
  local lp = f.log
  local maxOff = math.max(#logItems - #logRows, 0)
  if state.logOffset > maxOff then state.logOffset = maxOff end
  lp.empty:SetShown(#logItems == 0)
  local learned = 0
  for _, e in ipairs(log) do if e.kind == "learn" then learned = learned + 1 end end
  lp.count:SetText(learned .. " ranks learned since Pet Training+ was installed")
  for i, row in ipairs(logRows) do
    local e = logItems[i + state.logOffset]
    row.e = e
    if not e then
      row:Hide()
    else
      row:Show()
      row.when:SetText(fmtDate(e.t))
      if e.kind == "learn" then
        local a = e.key and ns.byKey[e.key]
        row.icon:SetTexture(a and ns.AbilityIcon(a) or 134400)
        row.icon:SetDesaturated(false)
        local nm = (a and ns.AbilityName(a) or tostring(e.key)) .. (e.r and (" (Rank " .. e.r .. ")") or " (rank unknown)")
        if e.src == "trainer" then
          row.title:SetText("Learned " .. nm .. " |cffaaaaaaat the pet trainer|r")
          row.sub:SetText((e.trainer or "Pet trainer") .. (whereText(e.where) and (" · " .. whereText(e.where)) or ""))
        else
          local o = e.origin
          local from = (o and o.name) and (o.name .. (o.level and (" (Lv " .. o.level .. ")") or "")) or nil
          row.title:SetText("Learned " .. nm .. (from and (" |cffaaaaaafrom|r |cffffffff" .. from .. "|r") or ""))
          local bits = {}
          if o and o.where and whereText(o.where) then bits[#bits + 1] = "tamed in " .. whereText(o.where) end
          if e.pet and e.pet.name then
            bits[#bits + 1] = "via your pet " .. e.pet.name .. (e.pet.level and (" (Lv " .. e.pet.level .. ")") or "")
          end
          if not from then bits[#bits + 1] = "|cff999999origin unknown: tamed before Pet Training+ (/ptp origin)|r" end
          row.sub:SetText(table.concat(bits, " · "))
        end
      else
        local o = e.origin or {}
        row.icon:SetTexture("Interface\\Icons\\Ability_Hunter_BeastTaming")
        row.icon:SetDesaturated(true)
        row.title:SetText("|cffbbbbbbTamed|r " .. (o.name or "?") .. (o.level and (" (Lv " .. o.level .. ")") or ""))
        local teach = {}
        for key, rk in pairs(o.teaches or {}) do
          local a = ns.byKey[key]
          if a and key ~= "Growl" then teach[#teach + 1] = ns.AbilityName(a) .. " " .. rk end
        end
        table.sort(teach)
        local bits = {}
        if whereText(o.where) then bits[#bits + 1] = whereText(o.where) end
        bits[#bits + 1] = #teach > 0 and ("knows " .. table.concat(teach, ", ")) or "no abilities to learn"
        row.sub:SetText(table.concat(bits, " · "))
      end
    end
  end
end

-- ------------------------------------------------------------------ pet bar and footer
function UI.RefreshPet()
  if not f then return end
  local b = f.petbar
  local p = ns.pet
  if p then
    if SetPortraitTexture then pcall(SetPortraitTexture, b.portrait, "pet") end
    b.portrait:Show()
    b.name:SetText(p.name or "?")
    b.info:SetText(("Level %s %s"):format(p.level or "?", ns.FamName(p.fam)))
    if p.tpFree then
      local c = p.tpFree < 0 and "|cffff5050" or "|cff9cff7a"
      b.tp:SetText(c .. p.tpFree .. "|r |cffaaaaaaTP free|r")
      b.tpsub:SetText(("%d total · %d spent"):format(p.tpTotal or 0, p.tpSpent or 0))
    else
      b.tp:SetText("")
      b.tpsub:SetText("")
    end
    local o = p.rec and p.rec.origin
    b.origin:SetText(o and ("Tamed from " .. (o.name or "?") .. (o.level and (" (Lv " .. o.level .. ")") or "") ..
      (whereText(o.where) and (" in " .. whereText(o.where)) or "")) or "|cff888888Origin unknown (tamed before Pet Training+) — target the same kind of beast and type /ptp origin|r")
  else
    b.portrait:Hide()
    b.name:SetText("|cffaaaaaaNo pet summoned|r")
    b.info:SetText("Showing what you know. Summon a pet to see what it has and can learn.")
    b.tp:SetText("")
    b.tpsub:SetText("")
    b.origin:SetText("")
  end
  -- mode line
  if T.beast then
    f.mode:SetText("|cff9cff7aBeast Training|r")
  else
    f.mode:SetText("")
  end
  f.blizz:SetShown(T.beast)
  f.blizz.label:SetText(T.WrapMode() and "Unframe" or "Frame together")
end

function UI.OnTrainState()
  if not f then return end
  local s = T.state
  local txt = ""
  if T.beast then
    if s == "none" then
      txt = "Pick a rank marked |cff9cff7aTrainable|r to train it."
      local r = state.rank
      if r then
        local nm = ns.AbilityName(r.a) .. " " .. r.r
        local ps, d = ns.RankPetState(r)
        local why = ({
          has = "your pet already has it", below = "your pet has a higher rank",
          family = "this family can't learn it", unlearned = "you haven't learned this rank yet",
          famunknown = "not known yet whether this family can learn it",
          level = "needs pet level " .. tostring(d), tp = "needs " .. tostring(d) .. " training points",
        })[ps]
        if why then txt = nm .. ": " .. why .. "." end
      end
    elseif s == "select" then
      txt = "Press once to select, then again to train."
    elseif s == "train" then
      local r = T.target and T.target.r
      local c = r and ns.UpgradeCost(r)
      txt = "|cff9cff7aSelected.|r Press again to train" .. (c and (" for " .. c .. " TP") or "") .. "."
    elseif s == "finding" then
      txt = "Looking for the rank in Beast Training…"
    elseif s == "scroll" then
      local nm = T.target and (ns.AbilityName(T.target.r.a) .. " " .. T.target.r.r) or "the rank"
      txt = ("|cff9cff7a%s is %s in Beast Training's list (left).|r Scroll it with the mouse wheel until it lights up, or click it there."):format(
        nm, T.scrollDir == "up" and "further up" or "further down")
    elseif s == "blocked" then
      txt = "Beast Training won't train this rank now."
    end
    if T.warning then txt = "|cffffa040" .. T.warning .. "|r" end
  else
    local unread = true
    for _ in pairs(ns.char.scanned) do unread = false; break end
    txt = unread and "Open Beast Training once with each pet family so Pet Training+ can read every rank you know."
      or "Open Beast Training to train. Pet Training+ takes its place."
  end
  f.footerText:SetText(txt)
end

-- ------------------------------------------------------------------ build the window
-- Framed Beast Training: one border drawn behind Blizzard's window and ours (LOW layer, below both).
local back
local function getBack()
  if back then return back end
  back = CreateFrame("Frame", "PetTrainingPlusFrameBack", UIParent, "BackdropTemplate")
  back:SetFrameStrata("LOW")
  if back.SetBackdrop then
    back:SetBackdrop({ bgFile = WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    back:SetBackdropColor(.04, .035, .03, .96)
    back:SetBackdropBorderColor(.85, .68, .32, 1)
  end
  back:EnableMouse(true) -- clicks between the two windows don't fall through to the world
  back:Hide()
  return back
end

function UI.SetFramed(on)
  local tf = _G.ClassTrainerFrame
  if on and f and tf then
    local b = getBack()
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", tf, "TOPLEFT", -10, 10)
    b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 8, -8)
    -- (Blizzard's window can be taller than ours: reach its bottom too)
    local tb, fb = ns.clean(tf:GetBottom()), ns.clean(f:GetBottom())
    local te, fe = ns.clean(tf:GetEffectiveScale()) or 1, ns.clean(f:GetEffectiveScale()) or 1
    if tb and fb and tb * te < fb * fe then
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", tf, "TOPLEFT", -10, 10)
      b:SetPoint("BOTTOM", tf, "BOTTOM", 0, -10)
      b:SetPoint("RIGHT", f, "RIGHT", 8, 0)
    end
    b:Show()
  elseif back then
    back:Hide()
  end
end

local function buildSkills(parent)
  local s = CreateFrame("Frame", nil, parent)
  s:SetPoint("TOPLEFT", 10, -118)
  s:SetPoint("BOTTOMRIGHT", -10, 44)
  f.skills = s

  -- left: search + filter + list
  local search = CreateFrame("EditBox", nil, s, "InputBoxTemplate")
  search:SetSize(150, 20)
  search:SetPoint("TOPLEFT", 6, 0)
  search:SetAutoFocus(false)
  search.hint = fs(search, "GameFontDisableSmall")
  search.hint:SetPoint("LEFT", 2, 0)
  search.hint:SetText("Search")
  search:SetScript("OnTextChanged", function(self)
    state.search = (self:GetText() or ""):lower()
    self.hint:SetShown(state.search == "")
    state.offset = 0
    UI.RefreshList()
  end)
  search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

  local filters = { { "all", "All ranks" }, { "known", "Known only" } }
  s.filterButtons = {}
  local prev
  for i, fl in ipairs(filters) do
    local b = textButton(s, fl[2], 80, 20)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 3, 0) else b:SetPoint("LEFT", search, "RIGHT", 8, 0) end
    b:SetScript("OnClick", function()
      ns.db.opts.filter = fl[1]
      state.offset = 0
      UI.Refresh()
    end)
    b.key = fl[1]
    s.filterButtons[i] = b
    prev = b
  end

  -- the big pet toggle: fixed above the list, it never scrolls
  local tg = CreateFrame("Button", nil, s, "BackdropTemplate")
  tg:SetPoint("TOPLEFT", 0, -26)
  tg:SetSize(LIST_W, TOGGLE_H)
  tg.icon = tg:CreateTexture(nil, "ARTWORK")
  tg.icon:SetSize(22, 22)
  tg.icon:SetPoint("LEFT", 8, 0)
  tg.title = fs(tg, "GameFontNormal")
  tg.title:SetPoint("TOPLEFT", tg.icon, "TOPRIGHT", 8, 1)
  tg.title:SetPoint("RIGHT", -8, 0)
  tg.sub = fs(tg, "GameFontHighlightSmall")
  tg.sub:SetPoint("BOTTOMLEFT", tg.icon, "BOTTOMRIGHT", 8, -2)
  tg.sub:SetPoint("RIGHT", -8, 0)
  local thl = tex(tg, "HIGHLIGHT", 1, 1, 1, .08)
  thl:SetAllPoints()
  tg:SetScript("OnClick", function()
    if not (ns.pet and ns.pet.fam) then return end
    ns.db.opts.petOnly = not ns.db.opts.petOnly
    state.offset = 0
    UI.Refresh()
  end)
  s.toggle = tg

  local list = CreateFrame("Frame", nil, s, "BackdropTemplate")
  list:SetPoint("TOPLEFT", 0, -(26 + TOGGLE_H + 6))
  list:SetSize(LIST_W, 1)
  list:SetPoint("BOTTOM", s, "BOTTOM", 0, 0)
  backdrop(list, { 0, 0, 0, .25 }, { .3, .25, .15, .6 })
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(_, d) UI.Scroll(-d) end)
  local inner = CreateFrame("Frame", nil, list)
  inner:SetPoint("TOPLEFT", 4, -3)
  inner:SetPoint("BOTTOMRIGHT", -10, 3)
  s.list = list
  local n = math.floor((H - 118 - 44 - 26 - TOGGLE_H - 6 - 6) / ROW_H)
  for i = 1, n do listRows[i] = makeListRow(inner, i) end

  local bar = CreateFrame("Frame", nil, list)
  bar:SetWidth(4)
  bar:SetPoint("TOPRIGHT", -3, -4)
  bar:SetPoint("BOTTOMRIGHT", -3, 4)
  local track = tex(bar, "BACKGROUND", 1, 1, 1, .06)
  track:SetAllPoints()
  bar.thumb = tex(bar, "ARTWORK", .8, .65, .25, .8)
  bar.thumb:SetWidth(4)
  s.scroll = bar

  -- right: detail
  local d = CreateFrame("Frame", nil, s, "BackdropTemplate")
  d:SetPoint("TOPLEFT", s, "TOPLEFT", LIST_W + 10, 0)
  d:SetPoint("BOTTOMRIGHT", 0, 0)
  backdrop(d, { 0, 0, 0, .25 }, { .3, .25, .15, .6 })
  s.detail = d
  d.empty = fs(d, "GameFontDisable", "CENTER")
  d.empty:SetPoint("CENTER")
  d.empty:SetWidth(300)
  if d.empty.SetWordWrap then d.empty:SetWordWrap(true) end
  d.empty:SetText("Pick a skill on the left.\n\nEach line shows every rank: |cffffd100gold|r = you know it, " ..
    "|cff4dff6agreen|r = your pet has it, |cff9cff7abright edge|r = trainable now.")

  local body = CreateFrame("Frame", nil, d)
  body:SetAllPoints()
  d.body = body
  d.icon = body:CreateTexture(nil, "ARTWORK")
  d.icon:SetSize(40, 40)
  d.icon:SetPoint("TOPLEFT", 10, -10)
  d.icon:SetTexCoord(.07, .93, .07, .93)
  d.name = fs(body, "GameFontNormalLarge")
  d.name:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 10, -2)
  d.bestiary = textButton(body, "View in Bestiary", 112, 20)
  d.bestiary:SetPoint("TOPRIGHT", -10, -10)
  d.bestiary:SetScript("OnClick", function() if state.ability then ns.Bestiary.ShowAbility(state.ability) end end)
  tooltipFor(d.bestiary, function()
    GameTooltip:SetText("Forever Bestiary")
    GameTooltip:AddLine("Opens this ability in Forever Bestiary's Abilities tab: every rank and the beasts that teach it.", 1, 1, 1, true)
  end)
  d.kind = fs(body, "GameFontDisableSmall")
  d.kind:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -4)
  d.fams = fs(body, "GameFontHighlightSmall")
  d.fams:SetPoint("TOPLEFT", d.icon, "BOTTOMLEFT", 0, -10)
  d.fams:SetPoint("RIGHT", -10, 0)
  if d.fams.SetWordWrap then d.fams:SetWordWrap(true) end
  d.usable = fs(body, "GameFontHighlight")
  d.usable:SetPoint("TOPLEFT", d.fams, "BOTTOMLEFT", 0, -6)
  d.desc = fs(body, "GameFontHighlightSmall")
  d.desc:SetPoint("TOPLEFT", d.usable, "BOTTOMLEFT", 0, -6)
  d.desc:SetPoint("RIGHT", -10, 0)
  d.desc:SetHeight(40)
  d.desc:SetJustifyV("TOP")
  if d.desc.SetWordWrap then d.desc:SetWordWrap(true) end
  d.desc:SetTextColor(.82, .78, .7)

  local head = CreateFrame("Frame", nil, body)
  head:SetPoint("TOPLEFT", d.desc, "BOTTOMLEFT", -4, -6)
  head:SetSize(LIST_W + 4, 18)
  local hb = tex(head, "BACKGROUND", .6, .48, .2, .18)
  hb:SetAllPoints()
  local cols = { { "Rank", 6 }, { "Pet Lv", 50 }, { "TP", 92 }, { "You", 124 }, { "Your pet", 152 }, { "Learned from", 246 } }
  for _, c in ipairs(cols) do
    local t = fs(head, "GameFontNormalSmall")
    t:SetPoint("LEFT", c[2], 0)
    t:SetText(c[1])
  end
  local rows = CreateFrame("Frame", nil, body)
  rows:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -2)
  rows:SetSize(LIST_W + 4, 10 * RANK_ROW_H)
  for i = 1, 10 do rankRows[i] = makeRankRow(rows, i) end
end

local function buildLog(parent)
  local l = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  l:SetPoint("TOPLEFT", 10, -118)
  l:SetPoint("BOTTOMRIGHT", -10, 44)
  backdrop(l, { 0, 0, 0, .25 }, { .3, .25, .15, .6 })
  l:EnableMouseWheel(true)
  l:SetScript("OnMouseWheel", function(_, d) UI.Scroll(-d) end)
  f.log = l
  l.count = fs(l, "GameFontNormalSmall")
  l.count:SetPoint("TOPLEFT", 10, -8)
  local tames = textButton(l, "", 110, 18)
  tames:SetPoint("TOPRIGHT", -8, -5)
  tames:SetScript("OnClick", function()
    ns.db.opts.showTames = not ns.db.opts.showTames
    UI.Refresh()
  end)
  l.tames = tames
  l.empty = fs(l, "GameFontDisable", "CENTER")
  l.empty:SetPoint("CENTER")
  l.empty:SetWidth(520)
  if l.empty.SetWordWrap then l.empty:SetWordWrap(true) end
  l.empty:SetText("Nothing logged yet.\n\nWhen you tame a beast and then learn a skill from it, Pet Training+ writes down " ..
    "which skill and rank, the creature it came from, its level and where you tamed it, the moment the game tells you.")
  local inner = CreateFrame("Frame", nil, l)
  inner:SetPoint("TOPLEFT", 6, -28)
  inner:SetPoint("BOTTOMRIGHT", -6, 4)
  local n = math.floor((H - 118 - 44 - 32) / LOG_ROW_H)
  for i = 1, n do logRows[i] = makeLogRow(inner, i) end
end

-- Two remembered places: the normal one, and the one you dragged it to while Beast Training was open.
local function savePosition()
  local point, _, rel, x, y = f:GetPoint(1)
  local pos = { point = point, rel = rel, x = x, y = y }
  if UI.attached then ns.db.trainerPos = pos else ns.db.pos = pos end
end

local movingTrainer
local function startMove()
  if ns.InCombat() then return end -- the secure buttons hang on the window: it can't move in combat
  local tf = _G.ClassTrainerFrame
  if UI.attached and tf and tf:IsShown() and tf.IsMovable and tf:IsMovable() then
    -- we hang on Blizzard's window: move it (Blizzard marks it movable), ours follows
    movingTrainer = tf
    tf:StartMoving()
  else
    f:StartMoving()
  end
end
local function stopMove()
  if movingTrainer then
    movingTrainer:StopMovingOrSizing()
    movingTrainer = nil
    if T.wrapped then UI.SetFramed(true) end
  else
    f:StopMovingOrSizing()
    savePosition()
  end
end

function UI.ResetPosition()
  if not ns.db then return end
  ns.db.pos, ns.db.trainerPos = nil, nil
  if not f then return end
  if T.beast then T.ApplyMode() else
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  end
end

local function restorePosition()
  f:ClearAllPoints()
  local p = ns.db.pos
  if p and p.point then
    f:SetPoint(p.point, UIParent, p.rel or p.point, p.x or 0, p.y or 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  end
end

-- Scale of the window (1.3 by default), never taller than the screen, nor wider than the room it has: while Beast
-- Training is open, the room to the right of Blizzard's window.
local function windowScale()
  local want = (ns.db and ns.db.opts.scale) or SCALE
  local uh = UIParent and ns.clean(UIParent:GetHeight())
  local uw = UIParent and ns.clean(UIParent:GetWidth())
  local s = want
  if type(uh) == "number" and uh > 0 then s = math.min(s, uh * 0.95 / H) end
  if type(uw) == "number" and uw > 0 then
    local room = uw * 0.98
    local tf = _G.ClassTrainerFrame
    if UI.attached and tf then
      local r, te = ns.clean(tf:GetRight()), ns.clean(tf:GetEffectiveScale())
      local ue = ns.clean(UIParent:GetEffectiveScale()) or 1
      if r and te then room = uw - (r * te / ue) - 30 end
    end
    s = math.min(s, room / BASE_W)
  end
  return math.max(s, 0.6)
end

function UI.ApplyLayout()
  if not f or ns.InCombat() then return end
  f:SetScale(windowScale())
  W = BASE_W
  f:SetWidth(W)
end

function UI.ApplyScale()
  if not f or ns.InCombat() then return end
  UI.ApplyLayout()
  if f:IsShown() then UI.PlaceSecure() end
end

local function placeSecure()
  if ns.InCombat() then UI.securePending = true; return end
  local act, close = T.CreateSecureButtons(f)
  -- the secure buttons sit on UIParent: same scale as the window
  act:SetScale(f:GetScale())
  close:SetScale(f:GetScale())
  -- always a layer above the window, which can be raised inside its own layer
  local strata = f:GetFrameStrata() == "DIALOG" and "FULLSCREEN" or "DIALOG"
  act:SetFrameStrata(strata)
  close:SetFrameStrata(strata)
  act:ClearAllPoints()
  act:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
  act:SetFrameLevel(f:GetFrameLevel() + 30)
  close:ClearAllPoints()
  close:SetPoint("CENTER", f.close, "CENTER", 0, 0)
  close:SetFrameLevel(f:GetFrameLevel() + 30)
  local showing = f:IsShown()
  act:SetShown(showing)
  -- in Beast Training our X closes Blizzard's window (a secure click), so both close together
  local secureClose = showing and T.beast and T.CloseButton() ~= nil
  close:SetShown(secureClose)
  f.close:SetShown(not secureClose)
  T.SetSecure(T.beast)
  T.UpdateTrainButton()
end
UI.PlaceSecure = placeSecure

function UI.Init()
  if f then return end
  f = CreateFrame("Frame", "PetTrainingPlusFrame", UIParent, "BackdropTemplate")
  UI.frame = f
  f:SetSize(W, H)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:Hide()
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = WHITE, edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(.055, .048, .04, .97)
    f:SetBackdropBorderColor(.75, .6, .3, 1)
  end
  table.insert(UISpecialFrames, "PetTrainingPlusFrame")

  local title = CreateFrame("Frame", nil, f)
  title:SetPoint("TOPLEFT", 4, -4)
  title:SetPoint("TOPRIGHT", -4, -4)
  title:SetHeight(26)
  local tb = tex(title, "BACKGROUND", .16, .12, .06, 1)
  tb:SetAllPoints()
  title:EnableMouse(true)
  title:RegisterForDrag("LeftButton")
  title:SetScript("OnDragStart", startMove)
  title:SetScript("OnDragStop", stopMove)
  -- the whole window drags too (wherever no button is)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", startMove)
  f:SetScript("OnDragStop", stopMove)
  -- a click on our window brings it back in front of Forever Bestiary
  f:SetScript("OnMouseDown", function()
    if ns.Bestiary and ns.Bestiary.SendBack then ns.Bestiary.SendBack() end
  end)
  local ticon = title:CreateTexture(nil, "ARTWORK")
  ticon:SetSize(20, 20)
  ticon:SetPoint("LEFT", 6, 0)
  ticon:SetTexture("Interface\\Icons\\Ability_Hunter_BeastTraining")
  ticon:SetTexCoord(.07, .93, .07, .93)
  local ttext = fs(title, "GameFontNormalLarge")
  ttext:SetPoint("LEFT", ticon, "RIGHT", 8, 0)
  ttext:SetText("Pet Training|cff9cff7a+|r")
  f.mode = fs(title, "GameFontHighlightSmall")
  f.mode:SetPoint("LEFT", ttext, "RIGHT", 12, -1)

  f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.close:SetPoint("TOPRIGHT", 0, 0)
  f.close:SetScript("OnClick", function() UI.Hide() end)

  -- (the button that switches between the wrapped list and Blizzard's whole window sits by the tabs, built below)

  -- pet bar
  local b = CreateFrame("Frame", nil, f, "BackdropTemplate")
  b:SetPoint("TOPLEFT", 10, -36)
  b:SetPoint("TOPRIGHT", -10, -36)
  b:SetHeight(50)
  backdrop(b, { .1, .085, .06, 1 }, { .35, .28, .14, .8 })
  f.petbar = b
  b.portrait = b:CreateTexture(nil, "ARTWORK")
  b.portrait:SetSize(40, 40)
  b.portrait:SetPoint("LEFT", 6, 0)
  b.name = fs(b, "GameFontHighlightLarge")
  b.name:SetPoint("TOPLEFT", 54, -6)
  b.info = fs(b, "GameFontNormalSmall")
  b.info:SetPoint("LEFT", b.name, "RIGHT", 10, -1)
  b.origin = fs(b, "GameFontHighlightSmall")
  b.origin:SetPoint("BOTTOMLEFT", 54, 7)
  b.origin:SetWidth(560)
  b.origin:SetTextColor(.8, .75, .65)
  b.tp = fs(b, "GameFontNormalLarge", "RIGHT")
  b.tp:SetPoint("TOPRIGHT", -10, -7)
  b.tpsub = fs(b, "GameFontDisableSmall", "RIGHT")
  b.tpsub:SetPoint("BOTTOMRIGHT", -10, 7)

  -- tabs
  f.tabSkills = textButton(f, "Skills", 90, 22)
  f.tabSkills:SetPoint("TOPLEFT", 12, -92)
  f.tabSkills:SetScript("OnClick", function() state.tab = "skills"; UI.Refresh() end)
  f.tabLog = textButton(f, "Learn Log", 90, 22)
  f.tabLog:SetPoint("LEFT", f.tabSkills, "RIGHT", 4, 0)
  f.tabLog:SetScript("OnClick", function() state.tab = "log"; UI.Refresh() end)

  f.blizz = textButton(f, "Unframe", 130, 22)
  f.blizz:SetPoint("LEFT", f.tabLog, "RIGHT", 12, 0)
  f.blizz:SetScript("OnClick", function()
    if ns.InCombat() then return end
    ns.db.opts.replace = not ns.db.opts.replace
    T.ApplyMode()
    UI.Refresh()
  end)
  tooltipFor(f.blizz, function()
    GameTooltip:SetText("Beast Training")
    GameTooltip:AddLine("Draw one border around Blizzard's Beast Training window and Pet Training+, or show them as two windows.", 1, 1, 1, true)
    GameTooltip:AddLine("/ptp replace (framed) or /ptp dock (two windows) sets this for good.", .7, .7, .7)
  end)

  -- legend
  local legend = CreateFrame("Frame", nil, f)
  legend:SetPoint("TOPRIGHT", -14, -92)
  legend:SetSize(420, 22)
  local items = { { "known", "You know" }, { "has", "Pet has" }, { "trainable", "Trainable" }, { "missing", "Not learned" }, { "unknown", "Not seen yet" } }
  local x = 0
  for i = #items, 1, -1 do
    local it = items[i]
    local lbl = fs(legend, "GameFontDisableSmall", "RIGHT")
    lbl:SetPoint("RIGHT", -x, 0)
    lbl:SetText(it[2])
    x = x + (lbl:GetStringWidth() or 50) + 4
    local sw = CreateFrame("Frame", nil, legend, "BackdropTemplate")
    sw:SetSize(12, 12)
    sw:SetPoint("RIGHT", -x, 0)
    local st = STYLE[it[1]]
    backdrop(sw, st[1], st[2], it[1] == "trainable" and 2 or 1)
    x = x + 12 + 12
  end

  buildSkills(f)
  buildLog(f)
  UI.ApplyLayout()

  f.footerText = fs(f, "GameFontHighlightSmall")
  f.footerText:SetPoint("BOTTOMLEFT", 16, 17)
  f.footerText:SetPoint("RIGHT", f, "RIGHT", -224, 0)
  f.footerText:SetTextColor(.85, .8, .7)

  f:SetScript("OnShow", function()
    UI.ApplyLayout()
    if T.beast then T.ApplyMode() elseif not UI.attached then restorePosition() end
    ns.RefreshPetSoon(0.05)
    placeSecure()
    UI.Refresh()
  end)
  f:SetScript("OnHide", function()
    GameTooltip:Hide()
    -- our window closed while Beast Training stays open: give the Blizzard window back
    if T.wrapped then T.Wrap(false) end
    placeSecure()
  end)
  ns.On("PLAYER_REGEN_ENABLED", function()
    if UI.securePending then UI.securePending = nil; placeSecure() end
  end)
  restorePosition()
end

function UI.Refresh()
  if not (f and f:IsShown()) then return end
  local skills = state.tab == "skills"
  f.skills:SetShown(skills)
  f.log:SetShown(not skills)
  f.tabSkills:SetActive(skills)
  f.tabLog:SetActive(not skills)
  for _, b in ipairs(f.skills.filterButtons) do b:SetActive(ns.db.opts.filter == b.key) end
  UI.RefreshToggle()
  f.log.tames:SetActive(ns.db.opts.showTames)
  f.log.tames.label:SetText(ns.db.opts.showTames and "Hide tames" or "Show tames")
  UI.RefreshPet()
  if skills then
    UI.RefreshList()
    UI.RefreshDetail()
  else
    UI.RefreshLog()
  end
  UI.OnTrainState()
end

function UI.Show(tab)
  if not f then UI.Init() end
  if tab then state.tab = tab end
  f:Show()
  UI.Refresh()
end

function UI.Hide()
  if f then f:Hide() end
end

function UI.Toggle()
  if not f then UI.Init() end
  if f:IsShown() then UI.Hide() else UI.Show() end
end

-- ------------------------------------------------------------------ Beast Training
function UI.AttachToTrainer(trainer, framed)
  if not f or not trainer then return end
  if not UI.attached then UI.wasShown = f:IsShown() end
  UI.attached = true
  UI.ApplyLayout()
  f:ClearAllPoints()
  -- beside Blizzard's window, tops level (framed: a little gap for the shared border)
  f:SetPoint("TOPLEFT", trainer, "TOPRIGHT", framed and 12 or 6, 0)
  f:SetFrameStrata("MEDIUM")
end

-- You clicked a rank in Blizzard's list: show it here and get Train ready.
function UI.SelectFromTrainer(r)
  state.ability = r.a
  state.rank = r
  if T.beast then T.SetTarget(r) end
  UI.Refresh()
end

function UI.ShowForTrainer()
  if not f then UI.Init() end
  if not (ns.db.opts.autoOpen or f:IsShown()) then return end
  state.tab = "skills"
  if ns.db.opts.filter == "known" then ns.db.opts.filter = "all" end
  f:Show()
  -- start on what this pet can train now
  if not state.ability or ns.RankPetState(state.rank or state.ability.ranks[1]) == "family" then
    for _, a in ipairs(ns.Abilities) do
      if bestTrainable(a) then state.ability = a; break end
    end
  end
  if state.ability then UI.Select(state.ability, state.rank) end
  placeSecure()
  UI.Refresh()
end

function UI.OnTrainerClosed()
  if not f then return end
  local was = UI.wasShown
  UI.attached = false
  UI.wasShown = nil
  f:SetFrameStrata("HIGH")
  UI.ApplyLayout() -- the full screen width is available again
  restorePosition()
  if not was then f:Hide() end
  placeSecure()
  UI.Refresh()
end
