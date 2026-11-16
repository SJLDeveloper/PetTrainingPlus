-- Minimal WoW API mock for exercising Pet Training+ flows outside the game.
local M = {}
M.clock = 1000
M.timers = {}
M.prints = {}
M.errors = {}

function GetTime() return M.clock end
local realtime = os.time
time = function() return 1794700000 + math.floor(M.clock) end
date = os.date
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
strsplit = function(sep, s)
  local out = {}
  for piece in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
  return unpack(out)
end
issecretvalue = function() return false end
C_Timer = { After = function(sec, fn) table.insert(M.timers, { due = M.clock + sec, fn = fn }) end }
function M.advance(sec)
  local target = M.clock + sec
  while true do
    table.sort(M.timers, function(a, b) return a.due < b.due end)
    local t = M.timers[1]
    if not t or t.due > target then break end
    table.remove(M.timers, 1)
    M.clock = t.due
    local ok, err = pcall(t.fn)
    if not ok then table.insert(M.errors, err); print("TIMER ERROR: " .. tostring(err)) end
  end
  M.clock = target
end

-- frames
local Frame = {}
Frame.__index = function(self, k)
  local v = rawget(Frame, k)
  if v ~= nil then return v end
  return function() return nil end -- any other method: no-op
end
local allFrames = {}
function CreateFrame(kind, name, parent, template)
  local f = setmetatable({ _kind = kind, _name = name, _parent = parent, _shown = true, _alpha = 1, _scripts = {},
    _attr = {}, _children = {}, _regions = {}, _strata = "MEDIUM", _level = 1, _template = template, _events = {} }, Frame)
  if kind ~= "Frame" or name then end
  if parent and parent._children then table.insert(parent._children, f) end
  if name then _G[name] = f end
  table.insert(allFrames, f)
  return f
end
function Frame:Show() local was = self:IsShown(); self._shown = true; if not was and self._scripts.OnShow then self._scripts.OnShow(self) end end
function Frame:Hide() local was = self._shown; self._shown = false; if was and self._scripts.OnHide then self._scripts.OnHide(self) end end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return self._shown end
function Frame:IsVisible()
  if not self._shown then return false end
  local p = rawget(self, "_parent")
  if p then return p:IsVisible() end
  return true
end
function Frame:SetAlpha(a) self._alpha = a end
function Frame:GetAlpha() return self._alpha end
function Frame:GetFrameLevel() return self._level end
function Frame:SetFrameLevel(l) self._level = l end
function Frame:GetFrameStrata() return self._strata end
function Frame:SetFrameStrata(s) self._strata = s end
function Frame:SetScript(k, fn) self._scripts[k] = fn end
function Frame:GetScript(k) return self._scripts[k] end
function Frame:HookScript(k, fn)
  local old = self._scripts[k]
  self._scripts[k] = function(...) if old then old(...) end fn(...) end
end
function Frame:SetAttribute(k, v) self._attr[k] = v end
function Frame:GetAttribute(k) return self._attr[k] end
function Frame:RegisterEvent(e) self._events[e] = true; M.eventFrames = M.eventFrames or {}; M.eventFrames[self] = true end
function Frame:IsObjectType(t) return self._kind == t end
function Frame:GetChildren() return unpack(self._children) end
function Frame:GetRegions() return unpack(self._regions) end
function Frame:GetPoint() local p = rawget(self, "_point"); if p then return unpack(p) end end
function Frame:SetPoint(...) self._point = { ... } end
function Frame:CreateTexture() local t = setmetatable({ _kind = "Texture", _shown = true, _scripts = {}, _parent = self }, Frame); return t end
function Frame:CreateFontString()
  local t = setmetatable({ _kind = "FontString", _shown = true, _scripts = {}, _text = "", _parent = self }, Frame)
  table.insert(self._regions, t)
  return t
end
function Frame:SetText(t) self._text = t end
function Frame:GetText() return self._text end
function Frame:GetStringWidth() return #(self._text or "") * 6 end
function Frame:IsEnabled() return self._enabled ~= false end
function Frame:Enable() self._enabled = true end
function Frame:Disable() self._enabled = false end
function Frame:GetHeight() return rawget(self, "_h") or 900 end
function Frame:SetScale(v) self._scale = v end
function Frame:GetScale() return rawget(self, "_scale") or 1 end
function Frame:Click()
  if self._scripts.OnClick then self._scripts.OnClick(self, "LeftButton") end
end
M.allFrames = allFrames

function M.fire(event, ...)
  for f in pairs(M.eventFrames or {}) do
    if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end

-- environment
UIParent = CreateFrame("Frame", "UIParent")
UISpecialFrames = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(M.prints, m); print("CHAT: " .. m) end }
GameTooltip = setmetatable({ _shown = false, _scripts = {}, _children = {}, _regions = {} }, Frame)
SlashCmdList = {}
Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 } }
ERR_LEARN_SPELL_S = "You have learned a new spell: %s."
ERR_LEARN_ABILITY_S = "You have learned a new ability: %s."
ERR_PET_LEARN_SPELL_S = "Your pet has learned a new spell: %s."
function InCombatLockdown() return M.combat or false end
function GetCVarBool() return false end
function GetRealZoneText() return M.zone or "Westfall" end
function GetSubZoneText() return M.subzone or "" end
C_Map = { GetBestMapForUnit = function() return 1436 end,
  GetPlayerMapPosition = function() return { GetXY = function() return 0.455, 0.321 end } end }

-- units
M.units = {}
function UnitExists(u) return M.units[u] ~= nil end
function UnitName(u) return M.units[u] and M.units[u].name end
function UnitLevel(u) return M.units[u] and M.units[u].level end
function UnitGUID(u) return M.units[u] and M.units[u].guid end
function UnitCreatureFamily(u) local x = M.units[u]; if x and x.fam then return x.famName, x.fam end end
function UnitClassification() return "normal" end
function SetPortraitTexture() end

-- spells
M.spellNames = {}
C_Spell = {
  GetSpellName = function(id) return M.spellNames[id] end,
  GetSpellTexture = function(id) return 136000 + (id % 100) end,
  GetSpellDescription = function() return "Does a thing." end,
}
M.petSpells = {}
C_SpellBook = {
  HasPetSpells = function() return #M.petSpells > 0 and #M.petSpells or nil end,
  GetSpellBookItemInfo = function(i, bank) return { spellID = M.petSpells[i], name = M.spellNames[M.petSpells[i]] } end,
}
function IsSpellKnown(id, pet) return false end
function IsPlayerSpell(id) return id == 5149 end
M.tp = { 110, 41 }
C_PetInfo = { GetPetTrainingPoints = function() return M.tp[1], M.tp[2] end }

-- trainer
M.services = {}
M.filters = { used = false, available = true, unavailable = true }
M.selection = 0
function GetNumTrainerServices()
  local n = 0
  for _, s in ipairs(M.services) do if M.filters[s.status] then n = n + 1 end end
  return n
end
local function visible(i)
  local k = 0
  for _, s in ipairs(M.services) do
    if M.filters[s.status] then k = k + 1; if k == i then return s end end
  end
end
M.visible = visible
function GetTrainerServiceInfo(i) local s = visible(i); if s then return s.name, s.status, 1, s.lvl, s.rankText end end
function GetTrainerServiceCost(i) local s = visible(i); return s and s.tp end
function GetTrainerServiceTypeFilter(k) return M.filters[k] end
function SetTrainerServiceTypeFilter(k, v)
  assert(type(v) == "boolean", "filter value must be boolean")
  M.filters[k] = v
  M.rebuildRows()
end
function GetTrainerSelectionIndex() return M.selection end
C_TooltipInfo = { GetTrainerService = function(i) local s = visible(i); return s and { id = s.id } end }
function BuyTrainerService() error("ADDON_ACTION_FORBIDDEN BuyTrainerService") end

function M.makeTrainer()
  local f = CreateFrame("Frame", "ClassTrainerFrame", UIParent)
  f._shown = false
  local label = CreateFrame("Frame", "ClassTrainerFrameTrainingPointsLabel", f)
  f.ScrollBox = CreateFrame("Frame", nil, f)
  local train = CreateFrame("Button", "ClassTrainerTrainButton", f)
  train:SetScript("OnClick", function()
    local s = visible(M.selection)
    M.trained = s and (s.name .. " " .. s.rankText)
  end)
  local close = CreateFrame("Button", "ClassTrainerFrameCloseButton", f)
  close:SetScript("OnClick", function() f:Hide(); M.fire("TRAINER_CLOSED") end)
  M.rows = {}
  for i = 1, 8 do
    local b = CreateFrame("Button", nil, f.ScrollBox)
    b.nameFS = b:CreateFontString(); b.rankFS = b:CreateFontString()
    b:SetScript("OnClick", function(self) M.selection = self.index end)
    M.rows[i] = b
  end
  return f
end
function M.rebuildRows()
  if not M.rows then return end
  for i, b in ipairs(M.rows) do
    local s = visible(i)
    if s then b._shown = true; b.index = i; b.nameFS._text = s.name; b.rankFS._text = s.rankText
    else b._shown = false end
  end
end

return M
