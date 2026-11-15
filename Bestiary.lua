-- Pet Training+ · Forever Bestiary (Pet Hunter) link: show a skill there as if you had clicked it in its Abilities tab.
-- Forever Bestiary keeps its functions private, so this opens its Abilities tab (its own /bestiary abilities) and
-- clicks the card of the ability, which runs exactly what a click of yours would.
local _, ns = ...
local B = {}
ns.Bestiary = B
local clean = ns.clean

local ADDON = "ForeverBestiaryPetHunter"

local function loaded()
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    local ok, v = pcall(C_AddOns.IsAddOnLoaded, ADDON)
    if ok then return v and true or false end
  end
  return IsAddOnLoaded and IsAddOnLoaded(ADDON) and true or false
end

function B.Available()
  return loaded() and SlashCmdList and SlashCmdList.FBPETHUNTER ~= nil
end

local function strip(s)
  s = clean(s)
  if type(s) ~= "string" then return nil end
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("^%s+", ""):gsub("%s+$", "")
  return s:lower()
end

local function texts(frame, out, depth)
  for _, r in ipairs({ frame:GetRegions() }) do
    if r.GetText then
      local t = strip(r:GetText())
      if t and t ~= "" then out[#out + 1] = t end
    end
  end
  if depth < 1 then
    for _, c in ipairs({ frame:GetChildren() }) do texts(c, out, depth + 1) end
  end
  return out
end

-- The visible button in the Bestiary window whose own text is this ability's name.
local function findCard(names)
  local root = _G.FBPetHunterFrame
  if not root then return nil end
  local found
  local function scan(fr, depth)
    if found or depth > 14 then return end
    if not fr:IsVisible() then return end
    if fr:IsObjectType("Button") and fr:GetScript("OnClick") then
      for _, t in ipairs(texts(fr, {}, 0)) do
        if names[t] then found = fr; return end
      end
    end
    for _, c in ipairs({ fr:GetChildren() }) do scan(c, depth + 1) end
  end
  scan(root, 0)
  return found
end

function B.ShowAbility(a)
  if not a then return end
  if not B.Available() then
    ns.Print("Forever Bestiary (Pet Hunter) is not loaded.")
    return
  end
  local names = { [a.key:lower()] = true }
  local loc = ns.AbilityName(a)
  if loc then names[loc:lower()] = true end
  local ok = pcall(SlashCmdList.FBPETHUNTER, "abilities")
  if not ok then ns.Print("Forever Bestiary could not open its Abilities tab."); return end
  local tries = 0
  local function attempt()
    tries = tries + 1
    local card = findCard(names)
    if card then
      pcall(card.Click, card, "LeftButton")
    elseif tries < 4 then
      ns.After(0.1, attempt)
    else
      ns.Print(("Opened Forever Bestiary's Abilities tab: %s isn't listed there."):format(loc or a.key))
    end
  end
  attempt()
end
