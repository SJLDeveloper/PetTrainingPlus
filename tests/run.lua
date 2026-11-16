package.path = "./tests/?.lua;" .. package.path
local M = require("mock")
local DIR = "./"
local ns = {}
for _, file in ipairs({ "Data.lua", "Core.lua", "Trainer.lua", "Bestiary.lua", "UI.lua" }) do
  local chunk = assert(loadfile(DIR .. file))
  chunk("PetTrainingPlus", ns)
end
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
check(tf:GetAlpha() == 0, "Blizzard window ghosted (alpha 0)")
check(ns.UI.attached, "window attached on top of Blizzard's")
check(M.filters.used and M.filters.available and M.filters.unavailable, "all filters on while reading")
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
check(tf:GetAlpha() == 1, "Blizzard window alpha restored")
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
check(tf:GetAlpha() == 0, "ghosted again")
ns.UI.Hide()
check(tf:GetAlpha() == 1, "hiding our window gives the Blizzard window back")
ns.UI.Show()
check(tf:GetAlpha() == 0, "showing it again takes over again")

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
check(tf:GetAlpha() == 1, "NPC trainer not ghosted")
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
check(math.abs(ns.UI.frame._scale - 1.3) < 0.01, "window scale 1.3 (got " .. tostring(ns.UI.frame._scale) .. ")")
check(math.abs(PetTrainingPlusActionButton._scale - 1.3) < 0.01, "secure button scaled with the window")
UIParent.GetHeight = function() return 600 end
ns.UI.ApplyScale()
check(ns.UI.frame._scale < 1.03, "scale capped to fit a short screen: " .. ns.UI.frame._scale)
check(#M.errors == 0, "no errors")
print(M.failed and "SOME TESTS FAILED" or "ALL PASSED")
