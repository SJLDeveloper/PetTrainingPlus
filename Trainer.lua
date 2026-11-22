-- Pet Training+ · Beast Training. In Forever, Beast Training opens Blizzard's trainer window (ClassTrainerFrame) without
-- an NPC. Pet Training+ reads it and attaches its own window beside it (see the v1.5 note below).
--
-- Rules learned in game by other Forever addon authors (Forever Hunter Pets, Hunter Pet Trainer; MIT):
--   * BuyTrainerService, SelectTrainerService and ClassTrainer_SetSelection taint the trainer: Train is then blocked.
--   * ScrollBox APIs on the trainer list taint it too.
--   * SetTrainerServiceTypeFilter does not taint.
--   * A SecureActionButton of type "click" whose clickbutton is a trainer row selects that row untainted; a second
--     press with clickbutton = ClassTrainerTrainButton trains it.
-- So the Train button of Pet Training+ is one secure button pressed twice: Select, then Train.
--
-- Forever's own trainer code (wow-ui-source, branch "forever", Blizzard_TrainerUI/Mainline): Beast Training is a flat
-- ScrollBox list (no categories for pet trainers) with 47-px rows in a 330-px box, so only about 7 rows exist at a
-- time. A row button carries its service index (GetID) and display index (.displayIndex). Its scroll bar arrows react to
-- OnMouseDown only, so a secure click can't scroll it, and scrolling it from addon code taints Train. When the chosen
-- rank is off screen, Pet Training+ outlines the list and asks you to scroll it with the mouse wheel; the row is
-- picked up the moment it appears.
--
-- v1.5: the frame. Blizzard's Beast Training window is left exactly as Blizzard draws it, in its own place; Pet
-- Training+ attaches to its right edge and one border (a LOW-strata backing frame) is drawn around both. (v1.4 tried to
-- draw only Blizzard's list inside our window; Forever drew none of it, whatever the frames reported.)
local _, ns = ...
local T = {}
ns.T = T
local try, clean = ns.try, ns.clean

local FILTERS = { "used", "available", "unavailable" }
local VERIFY_DELAY = 0.3

T.live = nil          -- [petSpellID] = { status, lvl, tp, name, rankText } from the last full read
T.liveFam = nil
T.beast = false       -- Beast Training is open
T.npcTrainerOpen = false
T.wrapped = false

local function trainerFrame() return _G.ClassTrainerFrame end

local function tpLabelVisible()
  local l = _G.ClassTrainerFrameTrainingPointsLabel
  return l and l.IsVisible and l:IsVisible() and true or false
end

-- Beast Training, not an NPC trainer: the window shows training points (or there is no NPC at all).
function T.IsBeastTraining()
  local f = trainerFrame()
  if not (f and f:IsShown()) then return false end
  if tpLabelVisible() then return true end
  return not (UnitExists and UnitExists("npc"))
end

function T.LiveRow(r)
  if not (T.live and ns.pet and T.liveFam == ns.pet.fam) then return nil end
  return T.live[r.pet]
end

-- ------------------------------------------------------------------ filters
local function filterState()
  local st, allOn = {}, true
  if not GetTrainerServiceTypeFilter then return st, true end
  for _, k in ipairs(FILTERS) do
    local on = try(GetTrainerServiceTypeFilter, k) and true or false
    st[k] = on
    allOn = allOn and on
  end
  return st, allOn
end

local function setFilters(used, available, unavailable)
  if not SetTrainerServiceTypeFilter then return end
  local want = { used = used, available = available, unavailable = unavailable }
  local st = filterState()
  for _, k in ipairs(FILTERS) do
    if st[k] ~= want[k] then pcall(SetTrainerServiceTypeFilter, k, want[k] and true or false) end
  end
end

function T.ShowAllRows()
  if not T.savedFilters then T.savedFilters = filterState() end
  setFilters(true, true, true)
  T.availOnly = false
end

function T.ShowAvailableOnly()
  if not T.savedFilters then T.savedFilters = filterState() end
  setFilters(false, true, false)
  T.availOnly = true
end

local function restoreFilters()
  local s = T.savedFilters
  T.savedFilters, T.availOnly = nil, false
  if s and SetTrainerServiceTypeFilter then setFilters(s.used, s.available, s.unavailable) end
end

-- ------------------------------------------------------------------ reading the trainer list
local function rowRank(i, name, rankText)
  local get = C_TooltipInfo and C_TooltipInfo.GetTrainerService
  local tip = get and try(get, i)
  local id = type(tip) == "table" and clean(tip.id)
  local r = id and (ns.byPet[id] or ns.byHunter[id])
  if r then return r end
  local a = ns.FindAbility(name)
  local rk = ns.RankNumber(rankText)
  return a and rk and a.rankBy[rk] or nil
end

-- mode "beast": every row is a rank the hunter knows (and that this family can learn).
-- mode "npc": the pet trainer in town; "used" rows are ranks the hunter knows.
function T.Scan(mode)
  if ns.InCombat() or not (GetNumTrainerServices and GetTrainerServiceInfo) then return end
  local n = try(GetNumTrainerServices)
  if not n or n == 0 then return end
  local _, allOn = filterState()
  local pet = ns.pet
  local fam = pet and pet.fam
  local live, complete, changed = {}, true, false
  for i = 1, n do
    local name, status, _, level, rankText = try(GetTrainerServiceInfo, i)
    if type(name) == "string" and status and status ~= "header" then
      local r = rowRank(i, name, rankText)
      if r then
        ns.db.locNames[ns.norm(name)] = r.a.key
        if mode == "beast" then
          if ns.MarkKnown(r, "training") then changed = true end
          local cost = try(GetTrainerServiceCost, i)
          local m = ns.db.meta[r.pet] or {}
          if type(level) == "number" and level > 0 then m.lvl = level end
          -- the listed TP is the full cost only when the pet has no rank of it
          if type(cost) == "number" and not (pet and pet.ranks[r.a.key]) then m.tp = cost end
          ns.db.meta[r.pet] = m
          live[r.pet] = { status = status, lvl = level, tp = cost, name = name, rankText = rankText, i = i }
          if fam then
            ns.db.famCan[fam] = ns.db.famCan[fam] or {}
            ns.db.famCan[fam][r.a.key] = true
          end
        elseif mode == "npc" and status == "used" then
          if ns.MarkKnown(r, "trainer") then changed = true end
        end
      elseif not ns.RankNumber(rankText) then
        complete = false   -- right after the window opens some rows have no rank yet
      end
    end
  end
  if mode == "beast" then
    if allOn then
      T.live, T.liveFam = live, fam
      if fam and complete then ns.char.scanned[fam] = time() end
    elseif T.live then
      -- available-only list: what it no longer shows is not trainable now
      for id, row in pairs(T.live) do
        if row.status == "available" and not live[id] then row.status = "unavailable" end
      end
      for id, row in pairs(live) do T.live[id] = row end
    end
  end
  ns.Changed()
  return changed
end

-- ------------------------------------------------------------------ ghosting the Blizzard window
-- Framed: Pet Training+ sits beside Blizzard's untouched window, one border around both (T.wrapped while it shows).
function T.Wrap(on)
  T.wrapped = on and true or false
  if ns.UI and ns.UI.SetFramed then ns.UI.SetFramed(T.wrapped) end
end

function T.WrapMode() return ns.db.opts.replace and true or false end
T.ReplaceMode = T.WrapMode

function T.ApplyMode()
  if not T.beast then return end
  if ns.UI and ns.UI.AttachToTrainer then ns.UI.AttachToTrainer(trainerFrame(), T.WrapMode()) end
  T.Wrap(T.WrapMode() and ns.UI and ns.UI.frame and ns.UI.frame:IsShown() and true or false)
end

-- ------------------------------------------------------------------ session
local driver = CreateFrame("Frame")
driver:Hide()
local acc = 0
driver:SetScript("OnUpdate", function(_, dt)
  local f = trainerFrame()
  acc = acc + dt
  if acc >= 0.25 then
    acc = 0
    if T.beast and not (f and f:IsShown()) then T.EndBeast(); return end
    T.FollowWindowSelection()
    T.UpdateTrainButton()
  end
end)

function T.BeginBeast()
  local fresh = not T.beast
  T.beast, T.npcTrainerOpen = true, false
  T.target, T.mode = nil, "select"
  ns.ReadPet()
  -- a new session, or Beast Training shown again for another pet: read everything again
  if fresh or (ns.pet and T.liveFam ~= ns.pet.fam) then
    if not fresh then T.availOnly = false end
    T.ShowAllRows()
  end
  T.ApplyMode()
  if ns.UI and ns.UI.ShowForTrainer then ns.UI.ShowForTrainer() end
  driver:Show()
  for _, d in ipairs({ 0.3, 1.0, 2.0 }) do
    ns.After(d, function() if T.beast and not T.availOnly then T.Scan("beast") end end)
  end
  -- after reading everything you know, the list shows what can be trained now
  ns.After(2.3, function() if T.beast and not T.availOnly then T.ShowAvailableOnly() end end)
end

function T.EndBeast()
  if not T.beast then return end
  T.beast = false
  T.target, T.mode = nil, "select"
  T.ShowGlow(nil)
  T.Wrap(false)
  T.lastWindowSel = nil
  restoreFilters()
  driver:Hide()
  T.SetSecure(nil)
  if ns.UI and ns.UI.OnTrainerClosed then ns.UI.OnTrainerClosed() end
  ns.Changed()
end

local function decide()
  local f = trainerFrame()
  if not (f and f:IsShown()) then return end
  if T.IsBeastTraining() then
    T.BeginBeast()
  else
    if T.beast then T.EndBeast() end
    T.npcTrainerOpen = true
    for _, d in ipairs({ 0.3, 1.0 }) do ns.After(d, function() if T.npcTrainerOpen then T.Scan("npc") end end) end
  end
end

ns.On("TRAINER_SHOW", function() ns.After(0.05, decide) end)
ns.On("TRAINER_UPDATE", function()
  ns.Debounce("trainerUpdate", 0.25, function()
    if T.beast then
      T.Scan("beast")
    elseif T.npcTrainerOpen then
      T.Scan("npc")
    end
  end)
end)
ns.On("TRAINER_CLOSED", function()
  -- Beast Training opened next to an NPC closes the NPC window, and its TRAINER_CLOSED comes after our TRAINER_SHOW.
  ns.After(0.1, function()
    local f = trainerFrame()
    if f and f:IsShown() then decide(); return end
    T.npcTrainerOpen = false
    T.EndBeast()
  end)
end)

-- ------------------------------------------------------------------ the secure buttons
local CLICK_HALF = (GetCVarBool and GetCVarBool("ActionButtonUseKeyDown")) and "AnyDown" or "AnyUp"

local function collectTexts(frame, out, depth)
  for _, region in ipairs({ frame:GetRegions() }) do
    if region.GetText then
      local t = clean(region:GetText())
      if type(t) == "string" and t ~= "" then out[#out + 1] = t end
    end
  end
  if depth < 2 then
    for _, child in ipairs({ frame:GetChildren() }) do collectTexts(child, out, depth + 1) end
  end
  return out
end

-- Trainer rows are unnamed, recycled ScrollBox buttons: the one on screen that shows this name and rank.
-- The service index of a rank in the list as it is now (the filters change it).
function T.CurrentIndex(name, rk)
  local n = try(GetNumTrainerServices) or 0
  for i = 1, n do
    local nm, _, _, _, rankText = try(GetTrainerServiceInfo, i)
    if nm == name and ns.RankNumber(rankText) == rk then return i end
  end
  return nil
end

local function trim(t)
  return (t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The visible row buttons of the Blizzard list: { { frame, id } }, top to bottom as found.
local function visibleRows()
  local f = trainerFrame()
  local out = {}
  if not f then return out end
  local function scan(fr, depth)
    if depth > 12 then return end
    if fr:IsVisible() and fr:IsObjectType("Button") and fr:GetScript("OnClick") and fr ~= _G.ClassTrainerTrainButton then
      local id = clean(fr:GetID())
      if fr.displayIndex ~= nil or (type(id) == "number" and id > 0) then out[#out + 1] = { fr, id } end
    end
    for _, c in ipairs({ fr:GetChildren() }) do scan(c, depth + 1) end
  end
  scan(f.ScrollBox or f, 0)
  return out
end

T.VisibleRows = visibleRows

-- The row showing this rank, if it is on screen; else nil and which way to scroll ("down" / "up").
function T.FindRow(name, rankText)
  if not name then return nil end
  local rk = ns.RankNumber(rankText)
  local idx = T.CurrentIndex(name, rk)
  local rows = visibleRows()
  local lo, hi
  for _, row in ipairs(rows) do
    local fr, id = row[1], row[2]
    if type(id) == "number" then
      lo = (not lo or id < lo) and id or lo
      hi = (not hi or id > hi) and id or hi
    end
    -- exact: Forever's rows carry their service index
    if idx and id == idx then
      local ok = false
      for _, t in ipairs(collectTexts(fr, {}, 0)) do
        if trim(t) == name or t:find(name, 1, true) then ok = true; break end
      end
      if ok then return fr end
    end
  end
  -- fallback: the name and the rank number in the row's texts
  for _, row in ipairs(rows) do
    local hasName, hasRank = false, not rk
    for _, t in ipairs(collectTexts(row[1], {}, 0)) do
      local tt = trim(t)
      if tt == name then hasName = true
      elseif rk and ns.RankNumber(tt) == rk and tt:find("%(") then hasRank = true end
    end
    if hasName and hasRank then return row[1] end
  end
  local dir = "down"
  if idx and lo and idx < lo then dir = "up" end
  return nil, dir, idx
end

-- A pulsing frame over the Blizzard list: around the row to select, or around the list with "scroll" text.
local glow
function T.ShowGlow(anchor, text)
  if not anchor then
    if glow then glow:Hide() end
    return
  end
  if not glow then
    glow = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    glow:EnableMouse(false)
    glow:SetFrameStrata("DIALOG")
    if glow.SetBackdrop then
      glow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
      glow:SetBackdropBorderColor(.35, 1, .45, 1)
    end
    glow.fill = glow:CreateTexture(nil, "BACKGROUND")
    glow.fill:SetAllPoints()
    glow.fill:SetColorTexture(.35, 1, .45, .10)
    glow.text = glow:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    glow.text:SetPoint("BOTTOM", glow, "TOP", 0, 6)
    local ag = glow.CreateAnimationGroup and glow:CreateAnimationGroup()
    local a = ag and ag:CreateAnimation("Alpha")
    if a then
      ag:SetLooping("BOUNCE")
      a:SetFromAlpha(1)
      a:SetToAlpha(.4)
      a:SetDuration(.6)
      ag:Play()
    end
  end
  glow:ClearAllPoints()
  glow:SetPoint("TOPLEFT", anchor, "TOPLEFT", -2, 2)
  glow:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 2, -2)
  glow.text:SetText(text or "")
  glow:Show()
end

local function trainButton()
  if _G.ClassTrainerTrainButton then return _G.ClassTrainerTrainButton end
  local f = trainerFrame()
  return f and f.TrainButton or nil
end

local function closeButton()
  local f = trainerFrame()
  if not f then return nil end
  return _G.ClassTrainerFrameCloseButton or f.CloseButton or (f.TitleContainer and f.TitleContainer.CloseButton) or nil
end
T.CloseButton = closeButton

local function selectionMatches()
  if not (T.target and GetTrainerSelectionIndex) then return false end
  local sel = try(GetTrainerSelectionIndex)
  if not sel or sel == 0 then return false end
  local name, _, _, _, rankText = try(GetTrainerServiceInfo, sel)
  if name ~= T.target.name or ns.RankNumber(rankText) ~= T.target.r.r then return false end
  -- Train buys what Blizzard's window has selected: it must be this rank too, and untainted
  return (T.WindowSelects(sel))
end

-- The action button (Select / Train / Open Beast Training) and the close button over our X.
local actionBtn, closeBtn

function T.CreateSecureButtons(parent)
  if actionBtn then return actionBtn, closeBtn end
  actionBtn = CreateFrame("Button", "PetTrainingPlusActionButton", UIParent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
  actionBtn:SetSize(200, 26)
  actionBtn:RegisterForClicks(CLICK_HALF)
  actionBtn:SetMotionScriptsWhileDisabled(true)
  actionBtn:SetFrameStrata("DIALOG")
  actionBtn:SetScript("PreClick", function()
    if ns.InCombat() then return end
    if T.beast then T.UpdateTrainButton(true) end
  end)
  actionBtn:HookScript("PostClick", function()
    local pressed = T.mode
    if not T.beast then return end
    ns.After(VERIFY_DELAY, function()
      if ns.InCombat() or not T.target then return end
      if pressed == "select" then
        if selectionMatches() then
          T.mode = "train"
          T.warning = nil
        else
          T.warning = "The row did not get selected. Press again."
        end
      else
        local trained = T.target.r
        T.mode = "select"
        ns.RefreshPetSoon(0.5)
        ns.After(0.8, function() if T.beast then T.Scan("beast") end end)
        -- once the pet has it, move on to the next rank of the same skill
        ns.After(1.2, function() T.AfterTrain(trained, 0) end)
      end
      T.UpdateTrainButton()
    end)
  end)
  actionBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if T.beast then
      GameTooltip:SetText("Train")
      GameTooltip:AddLine("Press once to select the rank in Beast Training, press again to train it.", 1, 1, 1, true)
      GameTooltip:AddLine("While a rank is chosen, Beast Training lists only the ranks your pet can train now.", 0.8, 0.8, 0.8, true)
    else
      GameTooltip:SetText("Open Beast Training")
      GameTooltip:AddLine("Pet Training+ reads it and takes its place.", 1, 1, 1, true)
    end
    GameTooltip:Show()
  end)
  actionBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- our own close look: a template with its own OnClick (UIPanelCloseButton) would replace the secure click
  closeBtn = CreateFrame("Button", "PetTrainingPlusCloseTrainer", UIParent, "SecureActionButtonTemplate")
  closeBtn:SetSize(32, 32)
  closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
  closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
  closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
  closeBtn:RegisterForClicks(CLICK_HALF)
  closeBtn:SetFrameStrata("DIALOG")
  closeBtn:SetAttribute("type", "click")
  closeBtn:HookScript("PostClick", function()
    -- no close button found: close the old way
    if not closeBtn:GetAttribute("clickbutton") and ns.UI then ns.UI.Hide(true) end
  end)
  closeBtn:Hide()
  actionBtn:Hide()
  return actionBtn, closeBtn
end

-- After a train press: when the pet shows the rank (the spellbook updates a moment later), the window moves its
-- highlight to the next rank and points the Train button at it.
function T.AfterTrain(r, tries)
  if not T.beast or ns.InCombat() then return end
  local cur = ns.pet and ns.pet.ranks[r.a.key]
  if cur and cur >= r.r then
    if ns.UI and ns.UI.AdvanceAfterTrain then ns.UI.AdvanceAfterTrain(r) end
  elseif tries < 4 then
    ns.RefreshPetSoon(0.1)
    ns.After(0.6, function() T.AfterTrain(r, tries + 1) end)
  end
end

-- You clicked a row in Blizzard's list: our window follows (skill, rank and Train button).
function T.FollowWindowSelection()
  local f = trainerFrame()
  if not (T.beast and f) or ns.InCombat() then return end
  local sel = f.selectedService
  if sel == T.lastWindowSel then return end
  T.lastWindowSel = sel
  if not sel then return end
  local map = f.displayIndexToSkillIndex
  local idx = (type(map) == "table" and map[sel]) or sel
  local name, _, _, _, rankText = try(GetTrainerServiceInfo, idx)
  local a = ns.FindAbility(name)
  local r = a and a.rankBy[ns.RankNumber(rankText) or 0]
  if r and not (T.target and T.target.r == r) and ns.UI and ns.UI.SelectFromTrainer then
    ns.UI.SelectFromTrainer(r)
  end
end

-- Chosen rank for the Train button (from the window).
function T.SetTarget(r)
  if not T.beast or ns.InCombat() then return end
  local live = r and T.LiveRow(r)
  if not (live and live.status == "available" and ns.RankPetState(r) == "trainable") then
    T.target, T.mode = nil, "select"
    T.UpdateTrainButton()
    return
  end
  if not (T.target and T.target.r == r) then
    T.target = { r = r, name = live.name, rankText = live.rankText, at = GetTime() }
    T.mode = "select"
    T.warning = nil
  end
  -- only the trainable ranks in the Blizzard list, so the row is on screen
  if not T.availOnly then T.ShowAvailableOnly() end
  T.UpdateTrainButton()
end

-- ------------------------------------------------------------------ direct select (no scrolling)
-- Blizzard's Train button trains ClassTrainerFrame.selectedService, on screen or not. Besides a row click, Blizzard sets
-- it in its TRAINER_DESCRIPTION_UPDATE handler, from the game's own selection (SelectTrainerService), which an addon may
-- set. If that event follows our SelectTrainerService, Blizzard selects the off-screen rank itself, untainted.
-- We only go on to Train when the game reports the selection as secure (issecurevariable); otherwise: scroll.
local DIRECT_WAIT = 1.2
T.descEvents = 0
ns.On("TRAINER_DESCRIPTION_UPDATE", function() T.descEvents = T.descEvents + 1; T.lastDescAt = GetTime() end)

local function secure(tbl, key)
  if not issecurevariable then return true end
  local ok, isSecure = pcall(issecurevariable, tbl, key)
  return ok and isSecure and true or false
end

-- Does Blizzard's window have this service selected, cleanly?
function T.WindowSelects(idx)
  local f = trainerFrame()
  if not (f and idx) then return false, "no window" end
  local sel = f.selectedService
  if not sel then return false, "nothing selected" end
  local map = f.displayIndexToSkillIndex
  local skill = (type(map) == "table" and map[sel]) or sel
  if skill ~= idx then return false, "other row selected" end
  if not secure(f, "selectedService") or (map and not secure(f, "displayIndexToSkillIndex")) then
    return false, "tainted"
  end
  return true
end

function T.TryDirect(t)
  local idx = T.CurrentIndex(t.name, t.r.r)
  if not (idx and SelectTrainerService) then return false end
  t.directIdx, t.directAt, t.directEvents = idx, GetTime(), T.descEvents
  pcall(SelectTrainerService, idx)
  return true
end

-- Re-points the action button. out of combat only.
function T.UpdateTrainButton(fromClick)
  if not actionBtn or ns.InCombat() then return end
  if not T.beast then
    actionBtn:SetAttribute("type", "spell")
    actionBtn:SetAttribute("spell", ns.BEAST_TRAINING)
    actionBtn:SetAttribute("clickbutton", nil)
    actionBtn:SetText("Open Beast Training")
    local knows = (IsPlayerSpell and try(IsPlayerSpell, ns.BEAST_TRAINING)) or (IsSpellKnown and try(IsSpellKnown, ns.BEAST_TRAINING))
    if knows == false then actionBtn:Disable() else actionBtn:Enable() end
    T.state = "open"
    if ns.UI and ns.UI.OnTrainState then ns.UI.OnTrainState() end
    return
  end
  actionBtn:SetAttribute("type", "click")
  if T.target and ns.RankPetState(T.target.r) ~= "trainable" then T.target, T.mode = nil, "select" end
  local t = T.target
  local label, enabled, row
  if not t then
    label, enabled = "Choose a rank to train", false
    T.state = "none"
    T.ShowGlow(nil)
  else
    local nm = ns.AbilityName(t.r.a) .. " " .. t.r.r
    if T.mode == "train" and not selectionMatches() then T.mode = "select" end
    if T.mode == "train" then
      local tb = trainButton()
      actionBtn:SetAttribute("clickbutton", tb)
      if tb and tb:IsEnabled() then
        label, enabled = "Train " .. nm, true
        T.state = "train"
      else
        label, enabled = "Can't train " .. nm, false
        T.state = "blocked"
      end
    else
      local dir
      row, dir = T.FindRow(t.name, t.rankText)
      if row then
        actionBtn:SetAttribute("clickbutton", row)
        label, enabled = "Select " .. nm, true
        T.state = "select"
        T.ShowGlow(row)
        -- already selected in Blizzard's list (you clicked it there): straight to Train
        if selectionMatches() then T.mode = "train"; ns.After(0, T.UpdateTrainButton) end
      else
        actionBtn:SetAttribute("clickbutton", nil)
        T.scrollDir = dir
        -- (seen twice without the event and never working: this client doesn't do it, skip the wait)
        local skipDirect = not ns.db.directWorked and (ns.db.directNoEvent or 0) >= 2
        if skipDirect and not t.directAt then T.directResult = T.directResult or "skipped: no event on this client" end
        if not skipDirect and not t.directAt and GetTime() - (t.at or 0) >= 0.4 then T.TryDirect(t) end
        local waitingDirect = t.directAt and GetTime() - t.directAt < DIRECT_WAIT
        local direct, why = false, nil
        if t.directAt then direct, why = T.WindowSelects(t.directIdx) end
        if direct and not t.directDone then
          -- Blizzard selected it for us: straight to Train
          t.directDone = true
          T.directResult = "worked"
          if not ns.db.directWorked then
            ns.db.directWorked = true
            ns.Print("|cff9cff7aGood news:|r ranks off screen in Beast Training can be selected without scrolling on your client.")
          end
          T.mode = "train"
          ns.After(0, T.UpdateTrainButton)
        elseif t.directAt and not waitingDirect and not t.directReported then
          t.directReported = true
          T.directResult = (T.descEvents > (t.directEvents or 0)) and ("event came, " .. tostring(why)) or "no event"
          if T.directResult == "no event" then ns.db.directNoEvent = (ns.db.directNoEvent or 0) + 1 end
          if not ns.db.directWorked and not T.directToldNo then
            T.directToldNo = true
            ns.Print("Ranks off screen can't be selected directly here (" .. T.directResult .. "): use the scroll view. /ptp debug has details.")
          end
        end
        if direct or waitingDirect then
          label, enabled = "Finding " .. nm .. "…", false
          T.state = "finding"
        elseif GetTime() - (t.at or 0) < 0.7 then
          -- the list redraws a moment after the filter change
          label, enabled = "Finding " .. nm .. "…", false
          T.state = "finding"
        else
          -- off screen: outline Blizzard's list and say which way to scroll it
          local f = trainerFrame()
          local box = f and (f.ScrollBox or f)
          T.ShowGlow(box, ("Scroll %s to %s"):format(dir == "up" and "up" or "down", nm))
          label, enabled = "Scroll " .. (dir == "up" and "up" or "down") .. " to " .. nm, false
          T.state = "scroll"
        end
      end
    end
    if T.mode == "train" then
      T.ShowGlow(nil)
    end
  end
  if T.mode ~= "train" and not row then actionBtn:SetAttribute("clickbutton", nil) end
  actionBtn:SetText(label)
  if enabled then actionBtn:Enable() else actionBtn:Disable() end
  if ns.UI and ns.UI.OnTrainState then ns.UI.OnTrainState() end
end

-- Points the close button at Blizzard's (nil: no trainer).
function T.SetSecure(on)
  if not closeBtn or ns.InCombat() then return end
  if on then
    closeBtn:SetAttribute("clickbutton", closeButton())
  else
    closeBtn:SetAttribute("clickbutton", nil)
  end
end

function T.Refresh()
  if T.beast then T.UpdateTrainButton() end
end

function T.ActionButton() return actionBtn end
function T.CloseTrainerButton() return closeBtn end

-- ------------------------------------------------------------------ /ptp debug
function T.DebugReport()
  local function yes(v) return v and "yes" or "no" end
  ns.Print(("ClassTrainerFrame %s · shown %s · TP label %s · ScrollBox %s · Train button %s · close button %s"):format(
    yes(trainerFrame()), yes(trainerFrame() and trainerFrame():IsShown()), yes(tpLabelVisible()),
    yes(trainerFrame() and trainerFrame().ScrollBox), yes(trainButton()), yes(closeButton())))
  ns.Print(("Filters API %s · tooltip IDs %s · craft API %s"):format(yes(SetTrainerServiceTypeFilter),
    yes(C_TooltipInfo and C_TooltipInfo.GetTrainerService), yes(GetCraftInfo)))
  local tf = trainerFrame()
  local function rect(x)
    if type(x) ~= "table" then return "none" end
    local e = clean(x:GetEffectiveScale()) or 1
    local l, t, r, b = clean(x:GetLeft()), clean(x:GetTop()), clean(x:GetRight()), clean(x:GetBottom())
    if not (l and t) then return tostring(x:GetFrameStrata()) .. " (not placed)" end
    return ("%s %s at %d,%d-%d,%d"):format(tostring(x:GetFrameStrata()), x:IsVisible() and "visible" or "hidden",
      l * e, t * e, (r or l) * e, (b or t) * e)
  end
  ns.Print(("Framed: %s · mode %s"):format(tostring(T.wrapped), T.WrapMode() and "framed" or "plain"))
  ns.Print("  Blizzard window: " .. rect(tf))
  ns.Print("  our window: " .. rect(ns.UI and ns.UI.frame))
  local rows = visibleRows()
  local list = {}
  for _, row in ipairs(rows) do
    local texts = collectTexts(row[1], {}, 0)
    list[#list + 1] = tostring(row[2]) .. "=" .. table.concat(texts, "/")
  end
  ns.Print(("%d rows on screen: %s"):format(#rows, table.concat(list, " · ")))
  ns.Print(("Direct select (no scrolling): %s · TRAINER_DESCRIPTION_UPDATE seen %d times"):format(
    tostring(T.directResult or "not tried yet"), T.descEvents or 0))
  if T.target then
    ns.Print(("Target %s %s · index now %s · state %s"):format(tostring(T.target.name), tostring(T.target.rankText),
      tostring(T.CurrentIndex(T.target.name, T.target.r.r)), tostring(T.state)))
  end
  local p = ns.pet
  if p then
    local n = 0
    for _ in pairs(p.ranks) do n = n + 1 end
    ns.Print(("Pet %s · family %s (%s) · level %s · %d abilities read · TP %s/%s"):format(tostring(p.name),
      tostring(p.famName), tostring(p.fam), tostring(p.level), n, tostring(p.tpFree), tostring(p.tpTotal)))
  else
    ns.Print("No pet.")
  end
  local last = ns.char.log[#ns.char.log]
  if last then ns.Print("Last log entry: " .. tostring(last.kind) .. " " .. tostring(last.key) .. " " .. tostring(last.r) .. " raw=" .. tostring(last.raw)) end
end
