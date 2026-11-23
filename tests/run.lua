package.path = "./tests/?.lua;" .. package.path
local M = require("mock")
local DIR = "./"
local ns = {}
for _, file in ipairs({ "Data.lua", "Core.lua", "Trainer.lua", "Bestiary.lua", "Loyalty.lua", "UI.lua" }) do
  local chunk = assert(loadfile(DIR .. file))
  chunk("PetTrainingPlus", ns)
end
local function backShown() return PetTrainingPlusFrameBack ~= nil and PetTrainingPlusFrameBack:IsShown() end
local function untouched()
  -- Blizzard's window drawn exactly as Blizzard draws it
  return ClassTrainerFrame:GetAlpha() == 1 and ClassTrainerTrainButton:GetAlpha() == 1 and ClassTrainerFrame.ScrollBox:GetAlpha() == 1
end
local function wrappedLook() return ns.T.wrapped and backShown() and untouched() end
local function plainLook() return not backShown() and untouched() end
local function check(cond, msg) if cond then print("PASS " .. msg) else print("FAIL " .. msg); M.failed = true end end

-- English spell names for the ranks we use
for _, a in ipairs(ns.Abilities) do for _, r in ipairs(a.ranks) do M.spellNames[r.pet] = a.key end end
M.spellNames[1515] = "Tame Beast"

ns.debug = true
M.fire("ADDON_LOADED", "PetTrainingPlus")
M.fire("PLAYER_LOGIN")
M.advance(3)
check(ns.UI.frame ~= nil, "window built at login")

-- a pet tamed before the addon: a boar with Bite 3, Charge 2, Growl 2
M.units.pet = { name = "Fang", level = 17, guid = "Pet-0-1-2-3-165189-0400AB", fam = 5, famName = "Boar" }
M.petSpells = { 17256, 26177, 14916 }
M.fire("UNIT_PET", "player")
M.advance(2)
check(ns.pet and ns.pet.name == "Fang" and ns.pet.ranks.Bite == 3, "pet read: Bite 3")
check(ns.pet.tpFree == 69, "pet TP free 69")

-- open the window, browse
ns.UI.Show()
check(PetTrainingPlusActionButton and PetTrainingPlusActionButton:GetAttribute("type") == "spell", "browse mode: action button casts Beast Training")
check(PetTrainingPlusActionButton:GetAttribute("spell") == 5149, "spell 5149")
ns.UI.Select(ns.byKey.Bite)
check(ns.UI.state.ability == ns.byKey.Bite, "select Bite")

-- Beast Training opens (trainer window, no NPC)
local tf = M.makeTrainer()
M.services = {
  { name = "Bite", rankText = "Rank 1", status = "used", lvl = 1, tp = 1, id = 17253 },
  { name = "Bite", rankText = "Rank 2", status = "used", lvl = 8, tp = 4, id = 17255 },
  { name = "Bite", rankText = "Rank 3", status = "used", lvl = 16, tp = 7, id = 17256 },
  { name = "Bite", rankText = "Rank 4", status = "unavailable", lvl = 24, tp = 10, id = 17257 },
  { name = "Charge", rankText = "Rank 2", status = "used", lvl = 12, tp = 5, id = 26177 },
  { name = "Cower", rankText = "Rank 1", status = "available", lvl = 5, tp = 8, id = 1742 },
  { name = "Growl", rankText = "Rank 2", status = "used", lvl = 10, tp = 0, id = 14916 },
  { name = "Growl", rankText = "Rank 3", status = "available", lvl = 16, tp = 0, id = 14917 },
}
tf:Show()
M.rebuildRows()
M.fire("TRAINER_SHOW")
M.advance(2.5)
check(ns.T.beast, "Beast Training detected")
check(wrappedLook(), "framed: Blizzard's window untouched, one border around both")
local fp = { ns.UI.frame:GetPoint() }
check(fp[1] == "TOPLEFT" and fp[2] == ClassTrainerFrame and fp[3] == "TOPRIGHT", "our window attached to the right of Blizzard's")
check(ns.UI.attached and ns.UI.frame:GetFrameStrata() == "MEDIUM", "our window attached, MEDIUM like Blizzard's")
check(ns.char.scanned[5], "full read with all filters on (boar)")
check(M.filters.available and not M.filters.used and not M.filters.unavailable, "then the list shows what can be trained now")
check(ns.IsKnown(ns.byKey.Bite.rankBy[4]), "Bite 4 known (unavailable row)")
check(ns.IsKnown(ns.byKey.Cower.rankBy[1]), "Cower 1 known")
check(not ns.IsKnown(ns.byKey.Bite.rankBy[5]), "Bite 5 not known")
check(ns.HunterRankState(ns.byKey.Bite.rankBy[5]) == "missing", "Bite 5 = missing (boar list read in full)")
check(ns.HunterRankState(ns.byKey.Claw.rankBy[1]) == "missing" == false, "Claw (boars can't) not claimed missing from a boar read")
check(ns.RankPetState(ns.byKey.Bite.rankBy[3]) == "has", "pet has Bite 3")
check(ns.RankPetState(ns.byKey.Cower.rankBy[1]) == "trainable", "Cower 1 trainable")
check(ns.RankPetState(ns.byKey.Claw.rankBy[1]) == "family", "Claw: boar family can't")
check(ns.RankPetState(ns.byKey.Bite.rankBy[4]) == "level" or ns.RankPetState(ns.byKey.Bite.rankBy[4]) == "tp", "Bite 4 blocked (" .. tostring(ns.RankPetState(ns.byKey.Bite.rankBy[4])) .. ")")
check(PetTrainingPlusCloseTrainer:IsShown() and PetTrainingPlusCloseTrainer:GetAttribute("clickbutton") == ClassTrainerFrameCloseButton, "secure close points at Blizzard close")

-- train Cower 1 with the two-press button
ns.UI.Select(ns.byKey.Cower)
M.advance(0.5)
check(ns.T.target and ns.T.target.r == ns.byKey.Cower.rankBy[1], "target Cower 1")
check(M.filters.available and not M.filters.used and not M.filters.unavailable, "available-only filter for training")
local btn = PetTrainingPlusActionButton
local function press()
  btn._scripts.PreClick(btn)
  local cb = btn:GetAttribute("clickbutton")
  if cb then cb:Click() end
  btn._scripts.PostClick(btn)
  M.advance(0.4)
end
check(btn:GetAttribute("type") == "click" and btn:GetAttribute("clickbutton") ~= nil, "action button points at a row: " .. tostring(btn:GetText()))
press()
check(M.visible(M.selection) and M.visible(M.selection).name == "Cower", "press 1 selected the Cower row")
check(ns.T.mode == "train" and btn:GetAttribute("clickbutton") == ClassTrainerTrainButton, "now points at Train: " .. tostring(btn:GetText()))
press()
check(M.trained == "Cower Rank 1", "press 2 trained Cower Rank 1")
-- the game: pet learns it
M.petSpells = { 17256, 26177, 14916, 1742 }
M.services[6].status = "used"
M.rebuildRows()
M.fire("CHAT_MSG_SYSTEM", "Your pet has learned a new spell: Cower (Rank 1).")
M.fire("SPELLS_CHANGED")
M.advance(1.5)
check(ns.pet.ranks.Cower == 1, "pet now has Cower 1")
check(ns.RankPetState(ns.byKey.Cower.rankBy[1]) == "has", "Cower 1 shows as pet has")
check(ns.T.target == nil, "target cleared after training: " .. tostring(btn:GetText()))

-- close Beast Training with our X (secure click on Blizzard's close)
PetTrainingPlusCloseTrainer:GetAttribute("clickbutton"):Click()
M.advance(0.5)
check(not ns.T.beast, "Beast Training session ended")
check(plainLook(), "Blizzard window alpha restored")
check(M.filters.used == false and M.filters.available and M.filters.unavailable, "player's filters restored")
check(not ns.UI.attached, "window detached")

-- learning without a known origin (pet tamed before the addon)
M.fire("CHAT_MSG_SYSTEM", "You have learned a new spell: |cff71d5ff|Hspell:26185:0|h[Charge]|h|r.")
M.advance(0.5)
check(ns.IsKnown(ns.byKey.Charge.rankBy[3]), "Charge 3 learned from hunter spell link 26185")
local last = ns.char.log[#ns.char.log]
check(last.kind == "learn" and last.key == "Charge" and last.r == 3 and last.pet.name == "Fang", "log: Charge 3 via Fang")

-- a tame: Great Fleshripper (154), level 17, carrion bird
M.units.target = { name = "Greater Fleshripper", level = 17, guid = "Creature-0-1-2-3-154-000ABC", fam = 7, famName = "Carrion Bird" }
M.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "x", 1515)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "x", 1515)
M.advance(20)
M.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "x", 1515)
M.units.pet = { name = "Greater Fleshripper", level = 17, guid = "Pet-0-1-2-3-165189-0400AC", fam = 7, famName = "Carrion Bird" }
M.petSpells = {}
M.fire("UNIT_PET", "player")
M.advance(0.1)
M.petSpells = { 24423, 14916 } -- Demoralizing Screech 1 (+Growl)
M.fire("UNIT_PET", "player")
M.advance(3)
check(ns.pet.rec and ns.pet.rec.origin and ns.pet.rec.origin.npc == 154, "tame recorded: origin NPC 154")
check(ns.pet.rec.origin.teaches["Demoralizing Screech"] == 1, "origin teaches Screech 1")
-- fight; the hunter learns the rank (message without rank)
M.fire("CHAT_MSG_SYSTEM", "You have learned a new spell: |cff71d5ff|Hspell:999999:0|h[Demoralizing Screech]|h|r.")
M.advance(0.5)
last = ns.char.log[#ns.char.log]
check(last.key == "Demoralizing Screech" and last.r == 1, "Screech learned, rank from the pet (1)")
check(last.origin and last.origin.name == "Greater Fleshripper" and last.origin.level == 17, "log captures creature Greater Fleshripper (17)")
check(ns.SourceText(last):find("Westfall"), "source text: " .. ns.SourceText(last))
check(ns.IsKnown(ns.byKey["Demoralizing Screech"].rankBy[1]), "Screech 1 known")

-- message with rank in the name
M.fire("CHAT_MSG_SYSTEM", "You have learned a new spell: |cff71d5ff|Hspell:1264745:0|h[Pinch (Rank 1)]|h|r.")
M.advance(0.3)
check(ns.IsKnown(ns.byKey.Pinch.rankBy[1]), "Pinch 1 (hunter id 1264745)")

-- the window: log tab and skills tab render without errors
ns.UI.Show("log")
ns.UI.Refresh()
ns.UI.Show("skills")
ns.UI.Select(ns.byKey["Demoralizing Screech"])
ns.UI.Refresh()
for _, flt in ipairs({ "all", "known", "pet" }) do ns.db.opts.filter = flt; ns.UI.Refresh() end
ns.UI.Scroll(3); ns.UI.Scroll(-10)
check(#M.errors == 0, "no errors in timers")

-- in combat: the pet read waits
M.combat = true
M.fire("UNIT_PET", "player")
M.advance(1)
check(ns.pendingPetRead, "pet read deferred in combat")
M.combat = false
M.fire("PLAYER_REGEN_ENABLED")
M.advance(1)
check(not ns.pendingPetRead, "pet read after combat")

-- ESC closes our window while Beast Training is open: Blizzard's comes back
tf:Show(); M.filters.used = true; M.rebuildRows()
M.fire("TRAINER_SHOW"); M.advance(1)
check(wrappedLook(), "ghosted again")
ns.UI.Hide()
check(ns.UI.frame:IsShown() and wrappedLook(), "while Beast Training is open our window can't be closed on its own")
ns.UI.Hide(true)
check(plainLook(), "forced close (our own X without Blizzard's): border gone")
ns.UI.Show()
check(wrappedLook(), "shown again: framed again")

-- NPC pet trainer (has an NPC, no TP label): "used" rows are known ranks
ClassTrainerFrameCloseButton:Click(); M.advance(0.5)
M.units.npc = { name = "Hesuwa Thunderhorn" }
ClassTrainerFrameTrainingPointsLabel._shown = false
M.services = { { name = "Great Stamina", rankText = "Rank 4", status = "used", lvl = 0, tp = 100, id = 4190 },
               { name = "Great Stamina", rankText = "Rank 5", status = "available", lvl = 30, tp = 100, id = 4191 } }
M.filters = { used = true, available = true, unavailable = true }
tf:Show(); M.rebuildRows()
M.fire("TRAINER_SHOW"); M.advance(1.5)
check(not ns.T.beast and ns.T.npcTrainerOpen, "NPC trainer is not Beast Training")
check(plainLook(), "NPC trainer not ghosted")
check(ns.IsKnown(ns.byKey["Great Stamina"].rankBy[4]) and not ns.IsKnown(ns.byKey["Great Stamina"].rankBy[5]), "NPC trainer: used = known only")
M.fire("CHAT_MSG_SYSTEM", "You have learned a new spell: |cff71d5ff|Hspell:4199:0|h[Great Stamina (Rank 5)]|h|r.")
M.advance(0.3)
last = ns.char.log[#ns.char.log]
check(last.src == "trainer" and last.trainer == "Hesuwa Thunderhorn", "trainer learn logged with trainer name")
check(#M.errors == 0, "no errors")

-- Forever Bestiary link
C_AddOns = { IsAddOnLoaded = function(n) return n == "ForeverBestiaryPetHunter" end }
local fb = CreateFrame("Frame", "FBPetHunterFrame", UIParent); fb._shown = false
local nav = CreateFrame("Button", nil, fb); local nl = nav:CreateFontString(); nl._text = "Abilities"; nav:SetScript("OnClick", function() end)
local view = CreateFrame("Frame", nil, fb); view._shown = false
local navigated
for _, en in ipairs({ "Bite", "Demoralizing Screech", "Cower", "Charge" }) do
  local c = CreateFrame("Button", nil, view)
  local n = c:CreateFontString(); n._text = en
  c:SetScript("OnClick", function() navigated = en end)
end
SlashCmdList.FBPETHUNTER = function(msg) if msg == "abilities" then fb._shown = true; view._shown = true end end
check(ns.Bestiary.Available(), "Bestiary detected")
ns.Bestiary.ShowAbility(ns.byKey["Demoralizing Screech"])
check(navigated == "Demoralizing Screech", "right-click navigates the Bestiary to Demoralizing Screech")
-- right-click on a list row goes through rightClick
navigated = nil
local row
for _, f in ipairs(M.allFrames) do if f.a == ns.byKey.Cower and f._scripts.OnClick and f.sub then row = f end end
if not row then for _, f in ipairs(M.allFrames) do if f.a and f._scripts.OnClick then row = f; break end end end
local before = ns.UI.state.ability
row._scripts.OnClick(row, "RightButton")
M.advance(0.5)
check(navigated == row.a.key, "list row right-click -> Bestiary " .. tostring(navigated))
check(ns.UI.state.ability == before, "right-click does not change the selection")
ns.Bestiary.ShowAbility(ns.byKey["Fire Resistance"]); M.advance(1)
check(M.prints[#M.prints]:find("isn't listed"), "ability missing in Bestiary: message")
check(#M.errors == 0, "no errors")
-- v1.1.1 family corrections
local can = ns.FamilyCanLearn
check(can(2, ns.byKey.Dash) and can(1, ns.byKey.Dash) and can(25, ns.byKey.Dash) and can(12, ns.byKey.Dash) and can(5, ns.byKey.Dash), "Dash: Cat, Wolf, Hyena, Tallstrider, Boar")
check(can(4, ns.byKey.Dash) == false, "Dash: not Bear")
check(can(24, ns.byKey.Dive) and can(7, ns.byKey.Dive) and can(26, ns.byKey.Dive) and can(27, ns.byKey.Dive) and can(2, ns.byKey.Dive) == false, "Dive: Bat, Carrion Bird, Owl, Wind Serpent only")
check(can(2, ns.byKey.Prowl) and can(1, ns.byKey.Prowl) == false, "Prowl: Cat only")
check(can(9, ns.byKey.Thunderstomp) and can(5, ns.byKey.Thunderstomp) == false, "Thunderstomp: Gorilla only")
check(can(21, ns.byKey["Shell Shield"]) and can(8, ns.byKey["Shell Shield"]) == false, "Shell Shield: Turtle only")
check(ns.byKey["Cobra Reflexes"].kind == "general" and can(319, ns.byKey["Cobra Reflexes"]) and ns.RankLevel(ns.byKey["Cobra Reflexes"].rankBy[1]) == 30, "Cobra Reflexes: trainer, all families, pet level 30")
check(ns.byKey.Harass == nil and ns.byHunter[23163] == nil, "Harass removed")
M.fire("CHAT_MSG_SYSTEM", "You have learned a new spell: |cff71d5ff|Hspell:23163:0|h[Harass]|h|r.")
M.advance(0.3)
check(ns.char.log[#ns.char.log].key ~= "Harass", "a Harass learn message is ignored")
check(#M.errors == 0, "no errors")
-- 1.2 pet toggle: hide what the current pet can't learn
ns.UI.Show()
ns.db.opts.filter = "all"
M.units.npc = nil
M.units.pet = { name = "Fang", level = 17, guid = "Pet-0-1-2-3-165189-0400AB", fam = 5, famName = "Boar" }
M.petSpells = { 17256, 26177, 14916 }
M.fire("UNIT_PET", "player"); M.advance(2)
ns.db.opts.petOnly = true
local shown = ns.UI.ListedAbilities()
check(shown.Bite and shown.Charge and shown.Dash and shown.Growl and shown["Cobra Reflexes"], "toggle on (boar): Bite, Charge, Dash, Growl, Cobra Reflexes shown")
check(not shown.Claw and not shown.Prowl and not shown.Dive and not shown.Web, "toggle on (boar): Claw, Prowl, Dive, Web hidden")
ns.UI.Refresh()
check(ns.UI.frame.skills.toggle.title:GetText():find("Showing only what Fang"), "toggle label: " .. ns.UI.frame.skills.toggle.title:GetText())
ns.UI.frame.skills.toggle._scripts.OnClick(ns.UI.frame.skills.toggle)
check(ns.db.opts.petOnly == false, "click turns the toggle off")
shown = ns.UI.ListedAbilities()
check(shown.Claw and shown.Prowl and shown.Dive, "toggle off: everything shown")
check(ns.UI.frame.skills.toggle.title:GetText():find("Showing all skills"), "toggle label: all")
ns.UI.frame.skills.toggle._scripts.OnClick(ns.UI.frame.skills.toggle)
check(ns.db.opts.petOnly == true, "click turns it back on")
M.units.pet = nil; M.petSpells = {}
M.fire("UNIT_PET", "player"); M.advance(2)
shown = ns.UI.ListedAbilities()
check(ns.pet == nil and shown.Claw and shown.Prowl and shown.Bite, "no pet: everything shown even with the toggle on")
check(ns.UI.frame.skills.toggle.title:GetText():find("No pet summoned"), "toggle label without pet")
ns.UI.frame.skills.toggle._scripts.OnClick(ns.UI.frame.skills.toggle)
check(ns.db.opts.petOnly == true, "toggle does nothing without a pet")
check(ns.UI.frame._scale > 1.15 and ns.UI.frame._scale <= 1.3, "window scale up to 1.3, capped by a 16:9 screen's width (got " .. tostring(ns.UI.frame._scale) .. ")")
check(math.abs(PetTrainingPlusActionButton._scale - ns.UI.frame._scale) < 0.001, "secure button scaled with the window")
UIParent.GetHeight = function() return 600 end
ns.UI.ApplyScale()
check(ns.UI.frame._scale < 1.03, "scale capped to fit a short screen: " .. ns.UI.frame._scale)
check(#M.errors == 0, "no errors")
-- 1.2.1: after training a rank, the highlight and the Train button move to the next rank
M.units.npc = nil
ClassTrainerFrameTrainingPointsLabel._shown = true
M.units.pet = { name = "Fang", level = 40, guid = "Pet-0-1-2-3-165189-0400AB", fam = 5, famName = "Boar" }
M.petSpells = { 17256, 26177, 14916 }
M.tp = { 200, 41 }
M.fire("UNIT_PET", "player"); M.advance(2)
M.services = {
  { name = "Bite", rankText = "Rank 3", status = "used", lvl = 16, tp = 7, id = 17256 },
  { name = "Bite", rankText = "Rank 4", status = "available", lvl = 24, tp = 10, id = 17257 },
  { name = "Bite", rankText = "Rank 5", status = "available", lvl = 32, tp = 13, id = 17258 },
  { name = "Charge", rankText = "Rank 2", status = "used", lvl = 12, tp = 5, id = 26177 },
}
M.filters = { used = false, available = true, unavailable = true }
tf:Show(); M.rebuildRows()
M.fire("TRAINER_SHOW"); M.advance(2.5)
local bite = ns.byKey.Bite
ns.UI.Select(bite, bite.rankBy[4]); M.advance(0.5)
check(ns.T.target and ns.T.target.r == bite.rankBy[4], "target Bite 4")
press()
press()
check(M.trained == "Bite Rank 4", "trained Bite 4")
-- the game: the pet learns Bite 4, the list updates
M.petSpells = { 17257, 26177, 14916 }
M.services[2].status = "used"
M.rebuildRows()
M.fire("TRAINER_UPDATE")
M.fire("SPELLS_CHANGED")
M.advance(3)
check(ns.pet.ranks.Bite == 4, "pet has Bite 4")
check(ns.UI.state.rank == bite.rankBy[5], "highlight moved to Bite 5")
check(ns.T.target and ns.T.target.r == bite.rankBy[5], "Train button targets Bite 5")
check(btn:GetText() == "Select Bite 5" or btn:GetText() == "Train Bite 5", "button ready: " .. tostring(btn:GetText()))
if btn:GetText():find("^Train") then press() else press(); press() end
check(M.trained == "Bite Rank 5", "trained Bite 5 straight away")
M.petSpells = { 17258, 26177, 14916 }
M.services[3].status = "used"; M.rebuildRows()
M.fire("TRAINER_UPDATE"); M.fire("SPELLS_CHANGED"); M.advance(3)
check(ns.UI.state.rank == bite.rankBy[6], "no trainable rank left: highlight on the next rank (Bite 6)")
check(ns.T.target == nil, "Train button idle for a rank that can't be trained: " .. tostring(btn:GetText()))
check(#M.errors == 0, "no errors")
-- 1.3.0: drag anywhere, also over Beast Training (its own remembered spot); Bestiary comes to the front
local win = ns.UI.frame
check(ns.T.beast and ns.UI.attached, "Beast Training open, window attached")
check(win._scripts.OnDragStart ~= nil, "the whole window has a drag handler")
-- while attached, dragging moves Blizzard's window (ours hangs on it)
local tfMoved, tfStopped, winMoved = false, false, false
tf.StartMoving = function() tfMoved = true end
tf.StopMovingOrSizing = function() tfStopped = true end
win.StartMoving = function() winMoved = true end
win._scripts.OnDragStart(win)
win._scripts.OnDragStop(win)
check(tfMoved and tfStopped and not winMoved, "dragging moves Blizzard's window, ours follows")
tf.StartMoving, tf.StopMovingOrSizing, win.StartMoving = nil, nil, nil
local normalPos = ns.db.pos
ClassTrainerFrameCloseButton:Click(); M.advance(0.5)
check(ns.db.pos == normalPos, "normal position untouched")
tf:Show(); M.rebuildRows(); M.fire("TRAINER_SHOW"); M.advance(1)
local pt = { win:GetPoint() }
check(pt[2] == ClassTrainerFrame and pt[3] == "TOPRIGHT", "next Beast Training: beside Blizzard's window again")
M.combat = true
local movedInCombat = false
win.StartMoving = function() movedInCombat = true end
win._scripts.OnDragStart(win)
check(not movedInCombat, "no dragging in combat")
M.combat = false
SlashCmdList.PETTRAININGPLUS("resetpos"); M.advance(0.2)
pt = { win:GetPoint() }
check(ns.db.trainerPos == nil and pt[2] == ClassTrainerFrame, "/ptp resetpos: beside Blizzard's window")
-- Bestiary on top
ns.Bestiary.SendBack()
fb._strata, fb._level = "HIGH", 5
ns.Bestiary.ShowAbility(ns.byKey.Bite)
local act = PetTrainingPlusActionButton
check(fb:GetFrameStrata() == act:GetFrameStrata() and fb:GetFrameLevel() > act:GetFrameLevel(), "Bestiary raised above our window and buttons (" .. fb:GetFrameStrata() .. ")")
win._scripts.OnMouseDown(win)
check(fb:GetFrameStrata() == "HIGH" and fb:GetFrameLevel() == 5, "click on our window: Bestiary back to its own layer")
ns.Bestiary.ShowAbility(ns.byKey.Bite)
fb:Hide()
check(fb:GetFrameStrata() == "HIGH", "closing the Bestiary restores its layer")
check(#M.errors == 0, "no errors")
-- 1.3.1: the chosen rank is below the 7 rows Forever's list shows: peek, scroll, select, train
ns.Bestiary.SendBack()
ClassTrainerFrameCloseButton:Click(); M.advance(0.5)
ns.db.trainerPos = nil
ns.db.opts.replace = true
M.units.pet = { name = "Fang", level = 60, guid = "Pet-0-1-2-3-165189-0400AB", fam = 5, famName = "Boar" }
M.petSpells = { 17256, 26177, 14916 }
M.tp = { 300, 41 }
M.fire("UNIT_PET", "player"); M.advance(2)
M.services = {}
local function add(name, r, id, lvl, tp) table.insert(M.services, { name = name, rankText = "Rank " .. r, status = "available", lvl = lvl, tp = tp, id = id }) end
add("Arcane Resistance", 1, 24493, 20, 5); add("Fire Resistance", 1, 23992, 20, 5); add("Frost Resistance", 1, 24446, 20, 5)
add("Nature Resistance", 1, 24492, 20, 5); add("Shadow Resistance", 1, 24488, 20, 5); add("Great Stamina", 1, 4187, 1, 5)
add("Great Stamina", 2, 4188, 12, 10); add("Natural Armor", 1, 24545, 1, 1); add("Natural Armor", 2, 24549, 8, 5)
add("Growl", 3, 14917, 20, 0); add("Bite", 4, 17257, 24, 10); add("Bite", 5, 17258, 32, 13)
M.filters = { used = false, available = true, unavailable = true }
tf:Show(); M.rebuildRows()
M.fire("TRAINER_SHOW"); M.advance(2.5)
check(wrappedLook() and ns.T.wrapped, "wrapped")
ns.UI.Select(bite, bite.rankBy[5]); M.advance(0.3)
check(ns.T.state == "finding", "first moment: finding (" .. tostring(ns.T.state) .. ")")
M.advance(2)
check(ns.T.state == "scroll" and ns.T.scrollDir == "down", "Bite 5 is row 12 of 7 on screen: scroll down (" .. tostring(ns.T.state) .. ")")
check(wrappedLook(), "nothing moves aside: the list is in Blizzard's window, left")
check(btn:GetText() == "Scroll down to Bite 5" and not btn:IsEnabled(), "button: " .. tostring(btn:GetText()))
check(ns.UI.frame.footerText:GetText():find("mouse wheel"), "footer explains the scroll")
-- the player scrolls the Blizzard list with the mouse wheel
M.scroll = 5; M.rebuildRows(); M.advance(0.5)
M.trained = nil
check(ns.T.state == "select" and btn:GetAttribute("clickbutton") and btn:GetAttribute("clickbutton"):GetID() == 12, "row found after scrolling: " .. tostring(btn:GetText()))
press(); press()
check(M.trained == "Bite Rank 5", "trained Bite 5")
-- scrolled too far: target above the rows on screen
M.scroll = 0; M.rebuildRows()
ns.UI.Select(bite, bite.rankBy[4]); M.advance(2)
check(ns.T.state == "scroll" and ns.T.scrollDir == "down", "Bite 4 below: scroll down")
M.scroll = 5; M.rebuildRows(); M.advance(0.5)
check(ns.T.state == "select", "Bite 4 found")
ns.UI.Select(ns.byKey["Arcane Resistance"], ns.byKey["Arcane Resistance"].rankBy[1]); M.advance(2)
check(ns.T.state == "scroll" and ns.T.scrollDir == "up", "Arcane Resistance 1 above: scroll up")
-- "Unframe": two windows side by side, no shared border; again: framed
ns.UI.frame.blizz._scripts.OnClick(ns.UI.frame.blizz)
check(not ns.T.wrapped and plainLook() and ns.UI.attached, "Unframe: two windows, no border")
ns.UI.frame.blizz._scripts.OnClick(ns.UI.frame.blizz)
check(wrappedLook(), "Frame together: one border again")
ClassTrainerFrameCloseButton:Click(); M.advance(0.5)
check(not ns.T.wrapped and plainLook(), "closing Beast Training ends everything")
check(#M.errors == 0, "no errors")
-- 1.3.2: direct select. If the game answers SelectTrainerService with TRAINER_DESCRIPTION_UPDATE, the off-screen rank
-- is selected by Blizzard's own handler: no scrolling, straight to Train.
ns.db.opts.replace = true
tf:Show(); M.scroll = 0; M.filters = { used = false, available = true, unavailable = true }; M.rebuildRows()
M.services[12].status = "available"; M.trained = nil
M.fire("TRAINER_SHOW"); M.advance(2.5)
M.descEvent = true
ns.db.directNoEvent = 0
ns.UI.Select(bite, bite.rankBy[5]); M.advance(2)
check(wrappedLook(), "direct select: stays framed")
check(ns.T.state == "train" and btn:GetText() == "Train Bite 5", "direct select: straight to Train (" .. tostring(btn:GetText()) .. ")")
check(ns.T.directResult == "worked", "direct select recorded as working")
press()
check(M.trained == "Bite Rank 5", "trained Bite 5 without scrolling")
-- tainted selection: never press Train, fall back to the scroll view
ClassTrainerFrameCloseButton:Click(); M.advance(0.5)
M.services[12].status = "available"; M.trained = nil; tf.selectedService = nil
tf:Show(); M.rebuildRows(); M.fire("TRAINER_SHOW"); M.advance(2.5)
M.tainted = true
ns.UI.Select(bite, bite.rankBy[5]); M.advance(2.5)
check(ns.T.state == "scroll", "tainted window selection: scroll instead (" .. tostring(ns.T.state) .. ")")
check(ns.T.directResult and ns.T.directResult:find("tainted"), "result: " .. tostring(ns.T.directResult))
M.tainted = false; M.descEvent = false
-- no event at all: scroll view
ClassTrainerFrameCloseButton:Click(); M.advance(0.5)
tf.selectedService = nil
tf:Show(); M.rebuildRows(); M.fire("TRAINER_SHOW"); M.advance(2.5)
ns.UI.Select(bite, bite.rankBy[5]); M.advance(2.5)
check(ns.T.state == "scroll" and ns.T.directResult == "no event", "no event: scroll view (" .. tostring(ns.T.directResult) .. ")")
-- after two "no event" results on a client where it never worked, the attempt (and its wait) is skipped
ns.db.directWorked = nil
ns.db.directNoEvent = 2
ClassTrainerFrameCloseButton:Click(); M.advance(0.5)
tf.selectedService = nil; ns.T.directResult = nil
tf:Show(); M.rebuildRows(); M.fire("TRAINER_SHOW"); M.advance(2.5)
ns.UI.Select(bite, bite.rankBy[5]); M.advance(1)
check(ns.T.state == "scroll" and ns.T.directResult:find("skipped"), "known no-event client: scroll view right away (" .. tostring(ns.T.directResult) .. ")")
check(#M.errors == 0, "no errors")
-- 1.3.3: "available" but not affordable (seen in game: Cower 2 at 10 TP with 7 free) is not trainable
ClassTrainerFrameCloseButton:Click(); M.advance(0.5)
M.units.pet = { name = "Ursa", level = 22, guid = "Pet-0-1-2-3-165189-0400AD", fam = 4, famName = "Bear" }
M.petSpells = { 16829, 14916 }
M.tp = { 21, 14 }
M.fire("UNIT_PET", "player"); M.advance(2)
M.services = {
  { name = "Great Stamina", rankText = "Rank 1", status = "available", lvl = 1, tp = 5, id = 4187 },
  { name = "Natural Armor", rankText = "Rank 1", status = "available", lvl = 1, tp = 1, id = 24545 },
  { name = "Cower", rankText = "Rank 2", status = "available", lvl = 15, tp = 10, id = 1753 },
}
M.filters = { used = false, available = true, unavailable = true }
tf:Show(); M.scroll = 0; M.rebuildRows(); M.fire("TRAINER_SHOW"); M.advance(2.5)
check(ns.pet.tpFree == 7, "7 TP free")
check(ns.RankPetState(ns.byKey.Cower.rankBy[2]) == "tp", "Cower 2 (10 TP) is not trainable with 7 free: " .. tostring(ns.RankPetState(ns.byKey.Cower.rankBy[2])))
check(ns.RankPetState(ns.byKey["Natural Armor"].rankBy[1]) == "trainable", "Natural Armor 1 (1 TP) trainable")
ns.UI.Select(ns.byKey.Cower, ns.byKey.Cower.rankBy[2]); M.advance(0.5)
check(ns.T.target == nil and ns.T.state == "none", "unaffordable rank is never targeted")
check(ns.UI.frame.footerText:GetText():find("needs 10 training points"), "footer: " .. tostring(ns.UI.frame.footerText:GetText()))
check(#M.errors == 0, "no errors")
-- 1.5.0: framed. Blizzard's window untouched; ours beside it; one border; our window hidden drops the border
ClassTrainerFrameCloseButton:Click(); M.advance(0.5)
ns.db.opts.replace = true
M.units.pet = { name = "Fang", level = 60, guid = "Pet-0-1-2-3-165189-0400AB", fam = 5, famName = "Boar" }
M.petSpells = { 17256, 26177, 14916 }
M.tp = { 300, 41 }
M.fire("UNIT_PET", "player"); M.advance(2)
M.services = {}
add("Great Stamina", 1, 4187, 1, 5); add("Natural Armor", 1, 24545, 1, 1); add("Bite", 4, 17257, 24, 10)
M.filters = { used = false, available = true, unavailable = true }
tf:Show(); M.scroll = 0; M.rebuildRows(); M.fire("TRAINER_SHOW"); M.advance(2.5)
check(wrappedLook(), "framed on open, Blizzard's window untouched")
check(tf:GetFrameStrata() == "MEDIUM" and tf.ScrollBox:GetFrameStrata() ~= "LOW", "Blizzard's layers untouched")
check(PetTrainingPlusFrameBack:GetFrameStrata() == "LOW", "the shared border is below both windows")
-- you click a rank in Blizzard's list: our window follows, Train ready in one press
M.trained = nil
M.rows[3]:Click() -- Bite 4
M.advance(0.6)
check(ns.UI.state.ability == bite and ns.UI.state.rank == bite.rankBy[4], "clicking Bite 4 in Blizzard's list selects it here")
check(btn:GetText() == "Train Bite 4", "Train ready: " .. tostring(btn:GetText()))
press()
check(M.trained == "Bite Rank 4", "trained Bite 4")
ns.UI.Hide(true)
check(plainLook() and not ns.T.wrapped, "our window closed: border gone, Blizzard's window as it was")
ns.UI.Show()
check(wrappedLook(), "opened again: framed again")
ClassTrainerFrameCloseButton:Click(); M.advance(0.5)
check(plainLook() and not ns.UI.attached, "Beast Training closed: our window on its own again")
check(#M.errors == 0, "no errors")
-- 1.5.1: ESC. Outside Beast Training we're a UISpecialFrame; with it open we're not, ESC closes Blizzard's window and
-- ours goes with it.
local function inEsc() for _, n in ipairs(UISpecialFrames) do if n == "PetTrainingPlusFrame" then return true end end return false end
check(not ns.UI.attached and inEsc(), "on our own: ESC closes Pet Training+")
tf:Show(); M.rebuildRows(); M.fire("TRAINER_SHOW"); M.advance(1)
check(ns.UI.attached and ns.UI.frame:IsShown() and not inEsc(), "Beast Training open: ESC is left to Blizzard's window")
-- ESC: the game closes the special frames (not us), then the UI panels (Blizzard's window)
for _, n in ipairs(UISpecialFrames) do if _G[n] and _G[n].Hide then _G[n]:Hide() end end
check(ns.UI.frame:IsShown(), "ESC didn't close us out of step")
tf:Hide(); M.fire("TRAINER_CLOSED"); M.advance(0.5)
check(not ns.UI.frame:IsShown() and not backShown(), "Blizzard's window closed: Pet Training+ closed with it")
check(inEsc(), "back on the ESC list")
ns.UI.Show(); ns.UI.Hide()
check(not ns.UI.frame:IsShown(), "on our own, Hide works as before")
check(#M.errors == 0, "no errors")
-- 1.6.0: blue = you don't have this rank yet, but could at your level
M.units.player = { name = "Shannon", level = 30 }
M.fire("PLAYER_LEVEL_UP", 30); M.advance(0.3)
local claw = ns.byKey.Claw
ns.char.known.Claw = { [1] = { t = 1, src = "training" } }
check(ns.CanObtain(claw.rankBy[1]) == false, "known rank: not blue")
check(ns.CanObtain(claw.rankBy[4]) == true, "Claw 4 (pet level 24) at level 30: could get it")
check(ns.CanObtain(bite.rankBy[5]) == nil or ns.RankLevel(bite.rankBy[5]) ~= nil, "unknown level: can't tell")
ns.db.meta[claw.rankBy[5].pet] = { lvl = 32 }
check(ns.CanObtain(claw.rankBy[5]) == false, "Claw 5 (pet level 32) at level 30: not yet")
ns.UI.Show()
ns.UI.Select(claw)
ns.UI.Refresh()
check(ns.UI.RankStyle(claw.rankBy[4]) == "obtainable", "Claw 4 shows blue (" .. tostring(ns.UI.RankStyle(claw.rankBy[4])) .. ")")
check(ns.UI.RankStyle(claw.rankBy[1]) ~= "obtainable", "Claw 1 (known) not blue: " .. tostring(ns.UI.RankStyle(claw.rankBy[1])))
check(ns.UI.RankStyle(claw.rankBy[5]) ~= "obtainable", "Claw 5 (level 32) not blue at 30")
check(ns.UI.RankStyle(bite.rankBy[3]) == "has", "a rank the pet has stays green")
M.units.player.level = 40
M.fire("PLAYER_LEVEL_UP", 40); M.advance(0.3)
check(ns.CanObtain(claw.rankBy[5]) == true, "after levelling to 40, Claw 5 can be got")
check(#M.errors == 0, "no errors")
-- 1.6.1: striped boxes: your pet has a rank you haven't learned (green with your colour in stripes)
M.units.pet = { name = "Fang", level = 30, guid = "Pet-0-1-2-3-165189-0400AB", fam = 5, famName = "Boar" }
M.petSpells = { 17256, 26177, 14916 } -- Bite 3
M.fire("UNIT_PET", "player"); M.advance(2)
local savedBite = ns.char.known.Bite
ns.char.known.Bite = { [1] = { t = 1 }, [2] = { t = 1 } } -- you know Bite 1-2, not 3
local k1, _, _, k2 = ns.UI.RankStyle(bite.rankBy[3])
check(k1 == "has" and k2 == "obtainable", "pet has Bite 3, you could learn it: green + blue stripes (" .. tostring(k1) .. "/" .. tostring(k2) .. ")")
ns.char.known.Bite = { [1] = { t = 1 }, [2] = { t = 1 }, [3] = { t = 1 } }
k1, _, _, k2 = ns.UI.RankStyle(bite.rankBy[3])
check(k1 == "has" and k2 == nil, "pet has it and you know it: plain green")
ns.char.known.Bite = { [1] = { t = 1 } }
ns.db.meta[bite.rankBy[3].pet] = { lvl = 99 } -- a level you can't reach
k1, _, _, k2 = ns.UI.RankStyle(bite.rankBy[3])
check(k1 == "has" and (k2 == "missing" or k2 == "unknown"), "pet has it, you can't get it yet: green + red/grey stripes (" .. tostring(k2) .. ")")
ns.db.meta[bite.rankBy[3].pet] = nil
ns.char.known.Bite = { [1] = { t = 1 }, [2] = { t = 1 } }
k1, _, _, k2 = ns.UI.RankStyle(bite.rankBy[2])
check(k1 == "below" and k2 == nil, "a rank below the pet's: not striped")
-- the box itself shows the stripes
ns.UI.Show(); ns.db.opts.filter = "all"; ns.db.opts.petOnly = false; ns.UI.Refresh()
local box
for _, fr in ipairs(M.allFrames) do if rawget(fr, "r") == bite.rankBy[3] and rawget(fr, "stripes") then box = fr end end
check(box and box.stripes:IsShown() and box.second == "obtainable", "the Bite 3 box is striped")
ns.char.known.Bite = savedBite
check(#M.errors == 0, "no errors")
-- 1.7.0: loyalty. The game's readings, and the recorder measuring rate × time per level
local LY = ns.Loyalty
check(LY.LevelFromName("Unruly") == 2 and LY.LevelFromName("Best Friend") == 6, "loyalty names map to levels")
check(LY.LevelFromTP({ tpTotal = 44, level = 22 }) == 2, "TP 44 at pet level 22 = loyalty level 2 (Forever: TP = level × loyalty)")
-- a fresh tame: Rebellious, rate 20
M.units.target = { name = "Gray Bear", level = 21, guid = "Creature-0-1-2-3-1186-000ABC", fam = 4, famName = "Bear" }
M.loyalty = { name = "Rebellious", happiness = 3, damage = 125, rate = 20 }
M.tp = { 21, 0 }
M.fire("UNIT_SPELLCAST_CHANNEL_START", "player", "x", 1515)
M.advance(20)
M.fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", "x", 1515)
M.units.pet = { name = "Gray Bear", level = 21, guid = "Pet-0-1-2-3-165189-0400B0", fam = 4, famName = "Bear" }
M.petSpells = { 16829 }
M.fire("UNIT_PET", "player"); M.advance(0.1); M.fire("UNIT_PET", "player")
M.advance(3)
check(ns.pet.rec and ns.pet.rec.origin and ns.pet.rec.origin.npc == 1186, "tamed Gray Bear")
M.advance(6)
local st = LY.Status()
check(st and st.level == 1 and st.rate == 20 and st.fromStart, "Rebellious 1/6, rate 20, measured from the start")
M.advance(600) -- ten minutes out
st = LY.Status()
check(st.summonedSec >= 590 and math.abs(st.rateSec - 20 * st.summonedSec) < 1, "rate-seconds = 20 × time summoned (" .. math.floor(st.rateSec) .. ")")
-- the level goes up
M.loyalty.name = "Unruly"
M.advance(6)
local segs = ns.db.loyalty.segments
local last = segs[#segs]
check(last and last.from == 1 and last.to == 2 and last.complete and last.rateSec > 11500 and last.rateSec < 12500,
  "segment Rebellious > Unruly, complete, ~12000 rate-seconds (" .. tostring(last and last.rateSec) .. ")")
check(M.prints[#M.prints]:find("Unruly"), "chat: now Unruly")
-- next level: estimate from the measured one (pretend Unruly takes the same)
ns.db.loyalty.segments[#segs + 1] = { from = 2, to = 3, complete = true, rateSec = 24000 }
M.advance(300)
st = LY.Status()
check(st.level == 2 and st.progress and st.progress > 0.2 and st.progress < 0.3 and st.etaSec and st.etaSec > 800 and st.etaSec < 950,
  ("Unruly: your measurement (24,000) comes first: ~25%% after 5 min, ETA ~15 min (%.2f, %s s)"):format(st.progress or -1, tostring(st.etaSec and math.floor(st.etaSec))))
local n4, src4 = LY.Needed(4)
check(n4 == 122000 and src4 == "shipped" and LY.Needed(5) == nil and LY.Needed(6) == nil, "shipped table for unmeasured levels; level 5 not known yet")
-- dismissing the pet makes a gap: that time doesn't count
local before = LY.Status().summonedSec
M.units.pet = nil; M.fire("UNIT_PET", "player"); M.advance(120)
M.units.pet = { name = "Gray Bear", level = 21, guid = "Pet-0-1-2-3-165189-0400B0", fam = 4, famName = "Bear" }
M.fire("UNIT_PET", "player"); M.advance(8)
check(LY.Status().summonedSec - before < 30, "time with the pet dismissed is not counted")
-- export text
local txt = LY.ExportText()
check(txt:find("seg 1>2 complete=true rateSec=1") and txt:find("now ") , "export lists segments and the current run")
LY.ShowExport()
check(PetTrainingPlusLoyaltyExport and PetTrainingPlusLoyaltyExport:IsShown(), "export window opens")
SlashCmdList.PETTRAININGPLUS("loyalty")
check(M.prints[#M.prints]:find("level%-ups recorded"), "/ptp loyalty prints a report")
ns.UI.Show(); ns.UI.Refresh()
check(ns.UI.frame.petbar.info:GetText():find("Unruly") and ns.UI.frame.petbar.info:GetText():find("to Submissive"), "pet bar: " .. ns.UI.frame.petbar.info:GetText())
-- 1.7.2: time in combat counts, at the rate seen before the fight
M.units.pet = { name = "Gray Bear", level = 21, guid = "Pet-0-1-2-3-165189-0400B0", fam = 4, famName = "Bear" }
M.fire("UNIT_PET", "player"); M.advance(8)
local c0 = LY.Status()
M.combat = true
M.advance(90) -- a 90-second fight
M.combat = false
M.advance(6)
local c1 = LY.Status()
check(c1.summonedSec - c0.summonedSec >= 90 and c1.summonedSec - c0.summonedSec <= 100,
  "a 90 s fight is counted (" .. (c1.summonedSec - c0.summonedSec) .. " s)")
check(math.abs((c1.rateSec - c0.rateSec) - 20 * (c1.summonedSec - c0.summonedSec)) < 1, "fight time counted at the last rate")
local runNow = ns.db.loyalty.current[next(ns.db.loyalty.current) and (function()
  for k, r in pairs(ns.db.loyalty.current) do if r.petName == "Gray Bear" then return k end end end)()]
check(runNow and runNow.combatSec >= 90, "combat time kept separately (" .. tostring(runNow and runNow.combatSec) .. ")")
-- two samples in the same second are not a gap
local g0 = runNow.gaps or 0
M.fire("UNIT_HAPPINESS", "pet"); M.advance(0.6); M.fire("UNIT_HAPPINESS", "pet"); M.advance(0.6)
check((runNow.gaps or 0) == g0, "same-second samples are not gaps")
-- the pet dies in combat: time stops counting
M.combat = true
M.advance(10)
local dead = LY.Status().summonedSec
M.units.pet = nil
M.advance(60)
M.combat = false
M.units.pet = { name = "Gray Bear", level = 21, guid = "Pet-0-1-2-3-165189-0400B0", fam = 4, famName = "Bear" }
M.fire("UNIT_PET", "player"); M.advance(8)
check(LY.Status().summonedSec - dead < 20, "time after the pet is gone in combat is not counted")
-- a new pet matched to an old record (its level is lower): the run starts over
local key = (function() for k, r in pairs(ns.db.loyalty.current) do if r.petName == "Gray Bear" then return k end end end)()
local oldSum = ns.db.loyalty.current[key].summonedSec
M.units.pet = { name = "Gray Bear", level = 12, guid = "Pet-0-1-2-3-165189-0400B0", fam = 4, famName = "Bear" }
M.fire("UNIT_PET", "player"); M.advance(8)
local fresh = ns.db.loyalty.current[key]
check(fresh.summonedSec < oldSum and fresh.petLevelStart == 12 and not fresh.fromStart, "lower pet level: a new run, not complete")
check(LY.ExportText():find("combat="), "export shows combat time")
-- 1.7.4: what you were doing — resting, AFK, mounted, flying — and the experience you and your pet gained
local akey = (function() for k, r in pairs(ns.db.loyalty.current) do if r.petName == "Gray Bear" then return k end end end)()
local arun = ns.db.loyalty.current[akey]
M.xp, M.xpMax, M.petXp, M.petXpMax = 1000, 5000, 200, 3000
UnitXP = function() return M.xp end
UnitXPMax = function() return M.xpMax end
GetPetExperience = function() return M.petXp, M.petXpMax end
IsResting = function() return M.resting or false end
UnitIsAFK = function() return M.afk or false end
IsMounted = function() return M.mounted or false end
UnitOnTaxi = function() return false end
M.advance(6)
local x0 = arun.xp or 0
M.resting = true; M.advance(60); M.resting = false
check(arun.restSec >= 55 and arun.restSec <= 65, "resting time counted (" .. arun.restSec .. " s)")
M.afk = true; M.advance(30); M.afk = false
check(arun.afkSec >= 25 and arun.afkSec <= 35, "AFK time counted (" .. arun.afkSec .. " s)")
M.mounted = true; M.advance(20); M.mounted = false
check(arun.mountSec >= 15 and arun.mountSec <= 25, "mounted time counted")
M.xp = 1800; M.petXp = 500; M.advance(6)
check(arun.xp - x0 == 800 and arun.petXp >= 300, "experience gained: you 800, pet 300")
M.xp, M.xpMax = 4900, 5000; M.advance(6)
M.xp, M.xpMax = 300, 6000; M.advance(6) -- you levelled up in between
check(arun.xp - x0 == 800 + 3100 + 400, "experience across a level-up (" .. (arun.xp - x0) .. ")")
-- dismissed: neither time nor experience counts
M.units.pet = nil; M.fire("UNIT_PET", "player"); M.advance(6)
M.xp = 2300; M.advance(60)
M.units.pet = { name = "Gray Bear", level = 12, guid = "Pet-0-1-2-3-165189-0400B0", fam = 4, famName = "Bear" }
M.fire("UNIT_PET", "player"); M.advance(8)
check(arun.xp - x0 == 4300, "experience while dismissed is not counted")
-- the level goes up: the segment and export carry it all
M.loyalty.name = "Submissive"; M.advance(6)
local lastSeg = ns.db.loyalty.segments[#ns.db.loyalty.segments]
check(lastSeg.restSec >= 55 and lastSeg.afkSec >= 25 and lastSeg.xp >= 4300 and lastSeg.petXp >= 300, "segment keeps activity")
check(LY.ExportText():find("rest=%d+ afk=%d+ mount=%d+ taxi=%d+ xp=%d+ petXp=%d+"), "export shows activity")
check(#M.errors == 0, "no errors")
print(M.failed and "SOME TESTS FAILED" or "ALL PASSED")
