--[[
The trade faction's rewards: what its quartermaster sells, learned in game.

When a merchant's shop opens and any of its items requires the player's trade faction
(the tooltip's "Requires <faction> - <standing>"), every item of that shop is saved,
account-wide, by faction name: { npc, time, items = { { id, name, icon, price, quantity,
standing (1 Hated .. 8 Exalted, nil when none is required), costs = { { value, name,
icon } } } } }. The next visit replaces the list. UI.lua shows it on the Rewards page.
]]

local _, ns = ...
if not CreateFrame then return end

-- "Requires %s - %s" as a pattern capturing the faction and the standing.
local REQUIRES = (ITEM_REQ_REPUTATION or "Requires %s - %s")
  :gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)")
REQUIRES = "^" .. REQUIRES .. "$"

local scanTip

--- The tooltip lines of a merchant item, as text.
local function tooltipLines(index)
  local out = {}
  if C_TooltipInfo and C_TooltipInfo.GetMerchantItem then
    local data = C_TooltipInfo.GetMerchantItem(index)
    for _, line in ipairs(data and data.lines or {}) do
      if type(line.leftText) == "string" then out[#out + 1] = line.leftText end
    end
    return out
  end
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "PuggerWaylaidCompanionScanTip", nil, "GameTooltipTemplate")
  end
  scanTip:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE")
  scanTip:SetMerchantItem(index)
  for i = 1, scanTip:NumLines() do
    local left = _G["PuggerWaylaidCompanionScanTipTextLeft" .. i]
    local text = left and left:GetText()
    if type(text) == "string" then out[#out + 1] = text end
  end
  return out
end

local function standingNumber(name)
  for i = 1, 8 do
    if ns.StandingName(i) == name then return i end
  end
end

--- The reputation an item requires: faction name and standing number, or nil.
local function required(index)
  for _, text in ipairs(tooltipLines(index)) do
    local faction, standing = text:match(REQUIRES)
    if faction then return faction, standingNumber(standing) end
  end
end

local function itemInfo(index)
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local i = C_MerchantFrame.GetItemInfo(index)
    if i then return i.name, i.texture, i.price, i.stackCount end
  end
  if GetMerchantItemInfo then
    local name, texture, price, quantity = GetMerchantItemInfo(index)
    return name, texture, price, quantity
  end
end

--- Other costs than money: currencies, or items like Merchant's Favor.
local function costs(index)
  local out = {}
  for j = 1, (GetMerchantItemCostInfo and GetMerchantItemCostInfo(index)) or 0 do
    local icon, value, link, name = GetMerchantItemCostItem(index, j)
    if not name and link then name = link:match("%[(.-)%]") end
    if value and value > 0 then out[#out + 1] = { value = value, name = name or "?", icon = icon } end
  end
  return out
end

local function scan()
  local rep = ns.Reputation()
  if not rep or not ns.db or not GetMerchantNumItems then return end
  local items, ours = {}, false
  for index = 1, GetMerchantNumItems() or 0 do
    local id = GetMerchantItemID and GetMerchantItemID(index)
    if id then
      local faction, standing = required(index)
      if faction == rep.name then ours = true end
      local name, icon, price, quantity = itemInfo(index)
      items[#items + 1] = {
        id = id, name = name, icon = icon, price = price or 0, quantity = quantity or 1,
        standing = faction == rep.name and standing or nil, costs = costs(index),
      }
    end
  end
  if not ours then return end
  ns.db.rewards = ns.db.rewards or {}
  ns.db.rewards[rep.name] = {
    npc = UnitName and UnitName("npc"), time = time and time() or os.time(), items = items,
  }
  ns.Changed()
end

--- The rewards saved for the player's trade faction, or nil before its shop was seen.
function ns.Rewards()
  local rep = ns.Reputation()
  return rep and ns.db and ns.db.rewards and ns.db.rewards[rep.name], rep
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE" }) do
  pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function()
  -- The shop's items fill in a moment after it opens.
  C_Timer.After(0.5, scan)
end)
