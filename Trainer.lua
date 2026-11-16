-- Pet Training+ · Beast Training. In Forever, Beast Training opens Blizzard's trainer window (ClassTrainerFrame) without
-- an NPC. Pet Training+ reads it, makes it invisible and shows its own window on top.
--
-- Rules learned in game by other Forever addon authors (Forever Hunter Pets, Hunter Pet Trainer; MIT):
--   * BuyTrainerService, SelectTrainerService and ClassTrainer_SetSelection taint the trainer: Train is then blocked.
--   * ScrollBox APIs on the trainer list taint it too.
--   * SetTrainerServiceTypeFilter does not taint.
--   * A SecureActionButton of type "click" whose clickbutton is a trainer row selects that row untainted; a second
--     press with clickbutton = ClassTrainerTrainButton trains it.
-- So the Train button of Pet Training+ is one secure button pressed twice: Select, then Train.
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
T.ghosted = false

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
local blocker
local function getBlocker()
  if blocker then return blocker end
  blocker = CreateFrame("Frame", nil, UIParent)
  blocker:EnableMouse(true)
  if blocker.EnableMouseWheel then blocker:EnableMouseWheel(true) end
  blocker:SetScript("OnMouseWheel", function() end)
  blocker:Hide()
  return blocker
end

function T.Ghost(on)
  local f = trainerFrame()
  if not f then return end
  if on then
    if not T.ghosted then T.savedAlpha = f:GetAlpha() end
    T.ghosted = true
    f:SetAlpha(0)
    local b = getBlocker()
    b:ClearAllPoints()
    b:SetAllPoints(f)
    b:SetFrameStrata(f:GetFrameStrata())
    b:SetFrameLevel(math.min(f:GetFrameLevel() + 200, 9000))
    b:Show()
  else
    if T.ghosted then f:SetAlpha(T.savedAlpha or 1) end
    T.ghosted = false
    if blocker then blocker:Hide() end
  end
end

function T.ApplyMode()
  if not T.beast then return end
  T.Ghost(ns.db.opts.replace)
  if ns.UI and ns.UI.AttachToTrainer then ns.UI.AttachToTrainer(trainerFrame(), ns.db.opts.replace) end
end

-- ------------------------------------------------------------------ session
local driver = CreateFrame("Frame")
driver:Hide()
local acc = 0
driver:SetScript("OnUpdate", function(_, dt)
  local f = trainerFrame()
  if T.ghosted and f and f:GetAlpha() > 0 then f:SetAlpha(0) end
  acc = acc + dt
  if acc >= 0.25 then
    acc = 0
    if T.beast and not (f and f:IsShown()) then T.EndBeast(); return end
    T.UpdateTrainButton()
  end
end)

function T.BeginBeast()
  local fresh = not T.beast
  T.beast, T.npcTrainerOpen = true, false
  T.target, T.mode = nil, "select"
  if fresh then T.ShowAllRows() end
  ns.ReadPet()
  T.ApplyMode()
  if ns.UI and ns.UI.ShowForTrainer then ns.UI.ShowForTrainer() end
  driver:Show()
  for _, d in ipairs({ 0.3, 1.0, 2.0 }) do
    ns.After(d, function() if T.beast and not T.availOnly then T.Scan("beast") end end)
  end
end

function T.EndBeast()
  if not T.beast then return end
  T.beast = false
  T.target, T.mode = nil, "select"
  T.Ghost(false)
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
function T.FindRow(name, rankText)
  local f = trainerFrame()
  if not (f and name) then return nil end
  local rk = ns.RankNumber(rankText)
  local found
  local function scan(fr, depth)
    if found or depth > 12 then return end
    if fr:IsVisible() and fr:IsObjectType("Button") and fr:GetScript("OnClick") and fr ~= _G.ClassTrainerTrainButton then
      local hasName, hasRank = false, false
      for _, t in ipairs(collectTexts(fr, {}, 0)) do
        if t == name then
          hasName = true
        elseif rankText and (t == rankText or t:find(rankText, 1, true)) then
          hasRank = true
        elseif rk and t:find(name, 1, true) and ns.RankNumber(t:sub(#name + 1)) == rk then
          hasName, hasRank = true, true -- "Bite (Rank 3)" in one string
        end
      end
      if hasName and (hasRank or not rankText) then found = fr; return end
    end
    for _, c in ipairs({ fr:GetChildren() }) do scan(c, depth + 1) end
  end
  scan(f.ScrollBox or f, 0)
  return found
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
  if name ~= T.target.name then return false end
  return ns.RankNumber(rankText) == T.target.r.r
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
    if not closeBtn:GetAttribute("clickbutton") and ns.UI then ns.UI.Hide() end
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

-- Chosen rank for the Train button (from the window).
function T.SetTarget(r)
  if not T.beast or ns.InCombat() then return end
  local live = r and T.LiveRow(r)
  if not (live and live.status == "available") then
    T.target, T.mode = nil, "select"
    T.UpdateTrainButton()
    return
  end
  if not (T.target and T.target.r == r) then
    T.target = { r = r, name = live.name, rankText = live.rankText }
    T.mode = "select"
    T.warning = nil
  end
  -- only the trainable ranks in the Blizzard list, so the row is on screen
  if not T.availOnly then T.ShowAvailableOnly() end
  T.UpdateTrainButton()
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
      row = T.FindRow(t.name, t.rankText)
      if row then
        actionBtn:SetAttribute("clickbutton", row)
        label, enabled = "Select " .. nm, true
        T.state = "select"
      else
        actionBtn:SetAttribute("clickbutton", nil)
        label, enabled = "Finding " .. nm .. "…", false
        T.state = "missing"
      end
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
