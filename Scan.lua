--[[
Scanning the auction house for the prices a page uses: from the writs page each writ and
what it asks for, from the crates page each crate and what fills it (/pwc scan: both). One
search per item, by name, the way Auctionator searches;
the lowest price listed for that exact item is kept in the saved settings
(ns.ScannedPrices), with the time, and Core.lua weighs it against Auctionator's own price
by which is newer.

Two auction houses, two ways to ask:

  - the modern one (C_AuctionHouse, which WoW Forever has): a browse search, whose
    results carry each item's lowest price (minPrice) already;
  - the old one (QueryAuctionItems), for clients that still have it: an exact-name
    search sorted by price per item, reading buyouts page by page.

The auction house has to be open. Closing it stops the scan; what was found so far stays.
]]

local _, ns = ...
if not CreateFrame then return end

local PAGE_SIZE = 50  -- results the old auction house sends per page
local MAX_PAGES = 3   -- pages (or batches of browse results) read per item at most
local SETTLE = 0.3    -- old auction house: seconds to wait after the last list update
local TIMEOUT = 8     -- seconds to wait for an answer before moving on
local NAME_WAIT = 3   -- seconds to wait for the game to load an item's name

local AH = C_AuctionHouse
local MODERN = AH ~= nil and AH.SendBrowseQuery ~= nil and AH.GetBrowseResults ~= nil
  and not (IsUsingLegacyAuctionClient and IsUsingLegacyAuctionClient())
local LEGACY = not MODERN and QueryAuctionItems ~= nil and GetNumAuctionItems ~= nil
  and GetAuctionItemInfo ~= nil

local ahOpen = false
local scan = nil      -- the scan running, or nil
local last = nil      -- { found, total, stopped } of the last scan, for the bar's text
local listeners = {}
local itemKeys = {}   -- the auction house's own key for each item a scan found

--- The auction house's key for an item, as the last scan saw it; nil if unseen.
function ns.ItemKey(id)
  return itemKeys[id]
end

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

--- Call fn whenever the scan's progress changes.
function ns.OnScan(fn)
  listeners[#listeners + 1] = fn
end

local function notify()
  for _, fn in ipairs(listeners) do fn() end
end

function ns.AuctionHouseOpen()
  return ahOpen
end

--- Whether this client has an auction house search the scan knows how to use.
function ns.CanScan()
  return MODERN or LEGACY
end

--- The items a scope prices, once each, with the name the data has for it: "writs" the
--- player's writs and what they ask for, "crates" the crates and what fills them, nil both.
local function scopeItems(scope)
  local list, seen = {}, {}
  local function add(id, name)
    if id and not seen[id] then
      seen[id] = true
      list[#list + 1] = { id = id, name = name }
    end
  end
  if scope ~= "crates" then
    for _, writ in ipairs(ns.writs) do
      if ns.ForPlayer(writ) then
        add(writ.writItem)
        add(writ.item, writ.name)
      end
    end
  end
  if scope ~= "writs" then
    for _, crate in ipairs(ns.crates) do
      add(crate.item)
      for _, bundle in ipairs(crate.bundles) do add(bundle.item, bundle.name) end
    end
  end
  return list
end

--- The items to scan for a scope, with the game asked to load each one's name.
local function itemsToScan(scope)
  local list = scopeItems(scope)
  if C_Item and C_Item.RequestLoadItemDataByID then
    for _, item in ipairs(list) do pcall(C_Item.RequestLoadItemDataByID, item.id) end
  end
  return list
end

--- { running, scope, done, total, item (name being searched), found, last } for the bar.
function ns.ScanProgress()
  if not scan then return { running = false, last = last } end
  local item = scan.items[scan.index]
  return {
    running = true, scope = scan.scope, done = scan.index - 1, total = #scan.items, found = scan.found,
    item = item and ((GetItemInfo and GetItemInfo(item.id)) or item.name),
  }
end

local function finish(stopped)
  if not scan then return end
  last = { found = scan.found, total = #scan.items, done = scan.index - 1, stopped = stopped }
  print(("%s: scan %s. %d of %d listed."):format(ns.TITLE,
    stopped and "stopped" or "done", scan.found, scan.index - 1))
  scan = nil
  notify()
  ns.Changed()
end

--- Move on to the next item; with keep, note what was found for this one first (0 when
--- nothing was listed). Without it the item keeps whatever price it had.
local function advance(keep)
  local item = scan.items[scan.index]
  local prices = ns.ScannedPrices()
  if keep and prices and item then
    prices[item.id] = { scan.best or 0, time and time() or os.time() }
    if scan.best then scan.found = scan.found + 1 end
  end
  scan.index, scan.page, scan.best, scan.state, scan.waited = scan.index + 1, 0, nil, "send", 0
  if scan.index > #scan.items then return finish(false) end
  notify()
end

--- Read on (the next page or batch), or settle the item once a price turned up, the
--- results ran out, or enough was read.
local function readOn(complete)
  if scan.best or complete or scan.page + 1 >= MAX_PAGES then
    advance(true)
  else
    scan.page, scan.state, scan.waited = scan.page + 1, "send", 0
  end
end

local function keep(price)
  if type(price) == "number" and price > 0 and (not scan.best or price < scan.best) then
    scan.best = price
  end
end

-- ---------------------------------------------------------------------------
-- The modern auction house
-- ---------------------------------------------------------------------------

local function modernSend(name)
  if AH.IsThrottledMessageSystemReady and not AH.IsThrottledMessageSystemReady() then return end
  scan.state, scan.waited = "wait", 0
  if scan.page == 0 then
    AH.SendBrowseQuery({ searchString = name, sorts = {}, filters = {}, itemClassFilters = {} })
  else
    AH.RequestMoreBrowseResults()
  end
end

--- Browse results: { itemKey = { itemID, ... }, minPrice, totalQuantity, ... }. minPrice
--- is the lowest price per item listed.
local function modernRead(results)
  local item = scan.items[scan.index]
  for _, result in ipairs(results or {}) do
    local key = result.itemKey
    if key and key.itemID == item.id then
      keep(result.minPrice)
      itemKeys[item.id] = key
    end
  end
  readOn(not AH.HasFullBrowseResults or AH.HasFullBrowseResults())
end

-- ---------------------------------------------------------------------------
-- The old auction house
-- ---------------------------------------------------------------------------

local function legacySend(name)
  if CanSendAuctionQuery and not CanSendAuctionQuery() then return end
  if SortAuctionClearSort then pcall(SortAuctionClearSort, "list") end
  if SortAuctionSetSort then pcall(SortAuctionSetSort, "list", "unitprice") end
  scan.state, scan.waited, scan.updated = "wait", 0, nil
  QueryAuctionItems(name, nil, nil, scan.page, nil, nil, false, true, nil)
end

local function legacyRead()
  local item = scan.items[scan.index]
  local count = GetNumAuctionItems("list") or 0
  for i = 1, count do
    local info = { GetAuctionItemInfo("list", i) }
    local stack, buyout, id = info[3], info[10], info[17]
    if id == item.id and type(buyout) == "number" and (stack or 0) > 0 then keep(buyout / stack) end
  end
  readOn(count < PAGE_SIZE)
end

--- Whether every result on the page has its seller filled in; the game sends those late.
local function ownersIn()
  for i = 1, GetNumAuctionItems("list") or 0 do
    if select(14, GetAuctionItemInfo("list", i)) == nil then return false end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Driving the scan
-- ---------------------------------------------------------------------------

local function send()
  local item = scan.items[scan.index]
  local name = (GetItemInfo and GetItemInfo(item.id)) or item.name
  if not name then
    -- The game has not loaded this item yet: give it a moment, then skip it.
    if scan.waited > NAME_WAIT then advance(false) end
    return
  end
  if MODERN then modernSend(name) else legacySend(name) end
end

local driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", function(self, elapsed)
  if not scan then return self:Hide() end
  scan.waited = scan.waited + elapsed
  if scan.state == "send" then
    send()
  elseif scan.state == "wait" then
    if LEGACY and scan.updated then
      scan.updated = scan.updated + elapsed
      if scan.updated >= SETTLE and (ownersIn() or scan.updated >= 2) then legacyRead() end
    elseif scan.waited >= TIMEOUT then
      advance(false)  -- no answer: leave this item's price as it was
    end
  end
end)

--- When the newest price our own scans found was seen, among a scope's items (see
--- scopeItems; nil for all); nil before the first scan.
function ns.LastScanTime(scope)
  local prices, newest = ns.ScannedPrices() or {}, nil
  for _, item in ipairs(scopeItems(scope)) do
    local seen = prices[item.id]
    if seen and (not newest or seen[2] > newest) then newest = seen[2] end
  end
  return newest
end

--- Start a scan of a scope ("writs", "crates", or nil for both); false and a reason when
--- it can't.
function ns.StartScan(scope)
  if scan then return false, "Scan running." end
  if not ns.CanScan() then return false, "No AH search on this client." end
  if not ahOpen then return false, "Open the AH." end
  if ns.Buying and ns.Buying() then return false, "Finish buying." end
  scan = { scope = scope, items = itemsToScan(scope), index = 1, page = 0, found = 0, state = "send", waited = 0 }
  driver:Show()
  notify()
  return true
end

function ns.StopScan()
  if scan then finish(true) end
end

--- Start a scan of a scope, or stop the one running; says why when it can't start.
function ns.ToggleScan(scope)
  if scan then return ns.StopScan() end
  local ok, why = ns.StartScan(scope)
  if not ok then print(ns.TITLE .. ": " .. why) end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_ITEM_LIST_UPDATE",
  "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "AUCTION_HOUSE_BROWSE_FAILURE" }) do
  pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
  if event == "AUCTION_HOUSE_SHOW" then
    ahOpen = true
    notify()
  elseif event == "AUCTION_HOUSE_CLOSED" then
    ahOpen = false
    if scan then finish(true) else notify() end
  elseif not scan or scan.state ~= "wait" then
    return
  elseif event == "AUCTION_ITEM_LIST_UPDATE" and LEGACY then
    scan.updated = 0
  elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" and MODERN then
    modernRead(AH.GetBrowseResults())
  elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" and MODERN then
    modernRead(...)
  elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" and MODERN then
    advance(false)
  end
end)
