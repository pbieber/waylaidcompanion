--[[
The trade faction's rewards: what its quartermasters sell, learned in game. Each
profession has its own quartermaster.

When a merchant's shop opens and any of its items costs Merchant's Favor or requires the
player's trade faction, every item of that shop is saved, account-wide, by faction name
and quartermaster (the NPC id, or its name without one): { [npc] = { npc (name), time,
items = { { id, name, icon, price, quantity, standing (1 Hated .. 8 Exalted, nil when none
is required), costs = { { value, name, icon } } } } } }. The next visit to that
quartermaster replaces its list. Lists other players shared (Share.lua) and the shipped
ones in Data/Recorded.lua (ns.RECORDED_REWARDS, the same shape) fill in the
quartermasters this account has not seen. UI.lua shows them on the Rewards page.

The quartermasters' items say "Requires Honored with this faction." Other merchants' may
name the faction: "Requires <faction> - <standing>". Items the client has not seen before
have neither line until their data arrives, so the shop is scanned again as it does, for
as long as it is open.
]]

local _, ns = ...
if not CreateFrame then return end

-- "Requires %s - %s" as a pattern capturing the faction and the standing.
local REQUIRES = (ITEM_REQ_REPUTATION or "Requires %s - %s")
  :gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)")
REQUIRES = "^" .. REQUIRES .. "$"
-- The merchant's own faction: "Requires Honored with this faction."
local REQUIRES_OWN = "^Requires (.+) with this faction%.?$"

local scanTip

--- The tooltip lines of a merchant item, as text, from the tooltip data API.
local function dataLines(index)
  local out = {}
  if not (C_TooltipInfo and C_TooltipInfo.GetMerchantItem) then return out end
  local ok, data = pcall(C_TooltipInfo.GetMerchantItem, index)
  if not ok or type(data) ~= "table" then return out end
  if TooltipUtil and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, data) end
  for _, line in ipairs(data.lines or {}) do
    if TooltipUtil and TooltipUtil.SurfaceArgs then pcall(TooltipUtil.SurfaceArgs, line) end
    if type(line.leftText) == "string" then out[#out + 1] = line.leftText end
  end
  return out
end

--- The tooltip lines of a merchant item, as text, from a hidden tooltip.
local function frameLines(index)
  local out = {}
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "PuggerWaylaidCompanionScanTip", nil, "GameTooltipTemplate")
  end
  scanTip:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE")
  scanTip:ClearLines()
  scanTip:SetMerchantItem(index)
  for i = 1, scanTip:NumLines() do
    local left = _G["PuggerWaylaidCompanionScanTipTextLeft" .. i]
    local text = left and left:GetText()
    if type(text) == "string" then out[#out + 1] = text end
  end
  scanTip:Hide()
  return out
end

local function standingNumber(name)
  for i = 1, 8 do
    if ns.StandingName(i) == name then return i end
  end
end

--- The reputation an item requires: the faction's name (true for the merchant's own
--- faction) and the standing number, or nil.
local function required(index)
  for _, read in ipairs({ dataLines, frameLines }) do
    for _, text in ipairs(read(index)) do
      local faction, standing = text:match(REQUIRES)
      if faction then return faction, standingNumber(standing) end
      standing = text:match(REQUIRES_OWN)
      if standing then return true, standingNumber(standing) end
    end
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

--- Whether an item's costs include Merchant's Favor, which only the trade factions take.
local function paysFavor(list)
  for _, c in ipairs(list) do
    if type(c.name) == "string" and c.name:find("Favor") then return true end
  end
  return false
end

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

--- Ask the client for every shop item's data; true when some of it is still missing.
local function requestItems()
  local missing = false
  for index = 1, (GetMerchantNumItems and GetMerchantNumItems()) or 0 do
    local id = GetMerchantItemID and GetMerchantItemID(index)
    if id and not (GetItemInfo and GetItemInfo(id)) then
      missing = true
      if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    end
  end
  return missing
end

--- What the open shop holds: its items, and whether any requires the trade faction.
local function read(rep, saved)
  local old = {}
  for _, item in ipairs(saved and saved.items or {}) do old[item.id] = item end
  local items, ours = {}, false
  for index = 1, GetMerchantNumItems() or 0 do
    local id = GetMerchantItemID and GetMerchantItemID(index)
    if id then
      local faction, standing = required(index)
      local paid = costs(index)
      if faction == rep.name or paysFavor(paid) then ours = true end
      -- A tooltip still loading has no requirement line: keep what an earlier visit saw.
      if faction ~= rep.name and faction ~= true then standing = old[id] and old[id].standing end
      local name, icon, price, quantity = itemInfo(index)
      items[#items + 1] = {
        id = id, name = name, icon = icon, price = price or 0, quantity = quantity or 1,
        standing = standing, costs = paid,
      }
    end
  end
  return items, ours
end

--- The quartermasters' saved shops for a faction: { [npc] = shop }, created if needed.
local function shops(faction)
  ns.db.rewards = ns.db.rewards or {}
  local list = ns.db.rewards[faction]
  -- Before 0.5.1 a faction held a single shop.
  if list and list.items then list = { [list.npc or "?"] = list } end
  list = list or {}
  ns.db.rewards[faction] = list
  return list
end

--- A unit value the addon may read, or nil (newer clients hide some as secret).
local function readable(v)
  if v == nil then return nil end
  if issecretvalue and issecretvalue(v) then return nil end
  if canaccessvalue and not canaccessvalue(v) then return nil end
  return v
end

--- The open shop's key in shops(): its NPC id, or its name.
local function shopKey()
  local guid = readable(UnitGUID and UnitGUID("npc"))
  local id = type(guid) == "string" and tonumber((select(6, strsplit("-", guid))))
  local name = readable(UnitName and UnitName("npc"))
  return id or (type(name) == "string" and name) or "?"
end

local function scan()
  local rep = ns.Reputation()
  if not rep or not ns.db or not GetMerchantNumItems then return end
  ns.db.shopDump = nil -- left by a test build of /pwc shop
  local list, key = shops(rep.name), shopKey()
  local shipped = ns.RECORDED_REWARDS and ns.RECORDED_REWARDS[rep.name]
  local items, ours = read(rep, list[key] or (shipped and shipped[key]))
  if not ours then return end
  local npc = readable(UnitName and UnitName("npc"))
  -- The same quartermaster saved under another key: by name, before 0.5.1.
  for k, shop in pairs(list) do
    if k ~= key and npc and shop.npc == npc then list[k] = nil end
  end
  list[key] = { npc = npc, time = time and time() or os.time(), items = items }
  ns.Changed()
end

--- The quartermasters' shops saved for the player's trade faction ({ [npc] = shop }, nil
--- before any was seen), and the player's standing.
function ns.Rewards()
  local rep = ns.Reputation()
  if not (rep and ns.db) then return nil, rep end
  -- The shipped lists, then this account's where it saw the shop since.
  local list = {}
  for key, shop in pairs(ns.RECORDED_REWARDS and ns.RECORDED_REWARDS[rep.name] or {}) do list[key] = shop end
  for key, shop in pairs(shops(rep.name)) do
    local old = list[key]
    if not old or (shop.time or 0) >= (old.time or 0) then list[key] = shop end
  end
  -- A shop kept by name (before 0.5.1) that is also there by NPC id.
  local byId = {}
  for key, shop in pairs(list) do
    if type(key) == "number" and shop.npc then byId[shop.npc] = true end
  end
  for key, shop in pairs(list) do
    if type(key) == "string" and byId[shop.npc] then list[key] = nil end
  end
  return next(list) and list or nil, rep
end

--- Print what the open shop shows the rewards scan (/pwc shop).
function ns.ShopReport()
  local say = function(text) print(ns.TITLE .. ": " .. text) end
  local rep = ns.Reputation()
  if not rep then return say("trade faction unknown.") end
  local count = GetMerchantNumItems and GetMerchantNumItems() or 0
  if count == 0 then return say("open a shop first.") end
  local ours, own, favor, others, loading, lines = 0, 0, 0, {}, 0, 0
  for index = 1, count do
    local id = GetMerchantItemID and GetMerchantItemID(index)
    local faction = required(index)
    if faction == rep.name then
      ours = ours + 1
    elseif faction == true then
      own = own + 1
    elseif faction then
      others[faction] = true
    end
    if paysFavor(costs(index)) then favor = favor + 1 end
    lines = lines + #dataLines(index) + #frameLines(index)
    if id and not (GetItemInfo and GetItemInfo(id)) then loading = loading + 1 end
  end
  say(("%d items, %d require %s, %d require this merchant's faction, %d cost Merchant's Favor, %d still loading, %d tooltip lines read.")
    :format(count, ours, rep.name, own, favor, loading, lines))
  for faction in pairs(others) do say("also requires: " .. faction) end
  local saved = shops(rep.name)[shopKey()]
  say(saved and ("saved: %d items from %s."):format(#saved.items, saved.npc or "?") or "nothing saved for this merchant.")
end

local open, pending = false, false
--- Scan shortly, once: the shop's items and their data come in bursts.
local function scanSoon()
  if pending then return end
  pending = true
  C_Timer.After(0.5, function()
    pending = false
    if not open then return end
    requestItems()
    scan()
  end)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED", "GET_ITEM_INFO_RECEIVED" }) do
  pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event)
  if event == "MERCHANT_CLOSED" then
    open = false
    return
  end
  if event == "MERCHANT_SHOW" then open = true end
  if open then scanSoon() end
end)
