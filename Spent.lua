--[[
What each character spends at the auction house on writs, crates and what fills them,
for a later page to show. Nothing shows it yet.

Every purchase of such an item is counted, bought through the addon's buy window or in
the game's own auction house window: the auction house's purchase functions are hooked
(after the game's own call, so the purchase itself is untouched), and a purchase counts
once the auction house confirms it.

  - an item sold one auction at a time (writs on WoW Forever): PlaceBid(auction, amount)
    buys one, for amount, once AUCTION_HOUSE_PURCHASE_COMPLETED names the auction. Which
    item an auction is comes from the search results the auction house listed for it.
  - an item sold in bulk (a commodity): ConfirmCommoditiesPurchase(item, quantity), for
    the total COMMODITY_PRICE_UPDATED quoted, once COMMODITY_PURCHASE_SUCCEEDED comes. WoW
    Forever can report an error first and confirm after (Buy.lua), so a failure doesn't
    forget the purchase: the next one replaces it.

Saved per character and day: ns.db.spent[character]["2026-11-16"][item] = { count, copper }.
A bid below the buyout is not a purchase, and an auction won by bidding is not counted.
]]

local _, ns = ...
if not CreateFrame then return end

local AH = C_AuctionHouse

-- The items whose purchases count: writs, what they ask for, crates, what fills them.
local tracked
local function isTracked(id)
  if not tracked then
    tracked = {}
    for _, writ in ipairs(ns.writs) do
      tracked[writ.writItem], tracked[writ.item] = true, true
    end
    for _, crate in ipairs(ns.crates) do
      tracked[crate.item] = true
      for _, b in ipairs(crate.bundles) do tracked[b.item] = true end
    end
  end
  return id ~= nil and tracked[id] == true
end

--- Count a purchase: `count` of item `id` for `copper` in all, today, on this character.
function ns.RecordSpend(id, count, copper)
  local db = ns.db
  if not db or not isTracked(id) or not count or count <= 0 then return end
  db.spent = db.spent or {}
  local key = ns.Character()
  local character = db.spent[key] or {}
  db.spent[key] = character
  local day = date("%Y-%m-%d")
  local items = character[day] or {}
  character[day] = items
  local entry = items[id] or { 0, 0 }
  items[id] = entry
  entry[1] = entry[1] + count
  entry[2] = entry[2] + math.floor((copper or 0) + 0.5)
end

--- What was spent, from the saved purchases: { [item] = { count, copper } } and the
--- copper in all. `character` limits it to one ("Name-Realm"), `since` to the days from
--- that one on ("2026-11-16"); nil for all.
function ns.Spent(character, since)
  local items, total = {}, 0
  for key, days in pairs(ns.db and ns.db.spent or {}) do
    if not character or key == character then
      for day, bought in pairs(days) do
        if not since or day >= since then
          for id, e in pairs(bought) do
            local sum = items[id] or { 0, 0 }
            items[id] = sum
            sum[1], sum[2] = sum[1] + e[1], sum[2] + e[2]
            total = total + e[2]
          end
        end
      end
    end
  end
  return items, total
end

if not (AH and hooksecurefunc) then return end

local auctions = {}    -- auction id -> item id, from the search results listed
local bids = {}        -- auction id -> { item, copper }, bought and not yet confirmed
local quote            -- the total COMMODITY_PRICE_UPDATED last quoted
local commodity        -- { item, count, copper }, confirmed and not yet completed

local function listResults(itemKey)
  local id = type(itemKey) == "table" and itemKey.itemID
  if not isTracked(id) or not AH.GetNumItemSearchResults then return end
  for i = 1, AH.GetNumItemSearchResults(itemKey) or 0 do
    local r = AH.GetItemSearchResultInfo(itemKey, i)
    if r and r.auctionID then auctions[r.auctionID] = id end
  end
end

if AH.PlaceBid then
  hooksecurefunc(AH, "PlaceBid", function(auctionID, amount)
    local id = auctions[auctionID]
    if id then bids[auctionID] = { id, amount } end
  end)
end
if AH.StartCommoditiesPurchase then
  hooksecurefunc(AH, "StartCommoditiesPurchase", function() quote = nil end)
end
if AH.ConfirmCommoditiesPurchase then
  hooksecurefunc(AH, "ConfirmCommoditiesPurchase", function(id, count)
    if not isTracked(id) then commodity = nil return end
    local copper = quote or ((ns.Price(id) or 0) * (count or 0))
    commodity = { id, count, copper }
  end)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED",
  "AUCTION_HOUSE_PURCHASE_COMPLETED", "COMMODITY_PRICE_UPDATED", "COMMODITY_PURCHASE_SUCCEEDED",
  "AUCTION_HOUSE_CLOSED" }) do
  pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
  if event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
    listResults(...)
  elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
    local auctionID = ...
    local bid = bids[auctionID]
    if bid then
      bids[auctionID] = nil
      ns.RecordSpend(bid[1], 1, bid[2])  -- one per purchase on WoW Forever (Buy.lua)
    end
  elseif event == "COMMODITY_PRICE_UPDATED" then
    local _, total = ...
    quote = total
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    if commodity then
      ns.RecordSpend(commodity[1], commodity[2], commodity[3])
      commodity = nil
    end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    -- Auction ids are only good while the auction house is open; a confirmation can
    -- still come for a bid already placed.
    auctions = {}
  end
end)
