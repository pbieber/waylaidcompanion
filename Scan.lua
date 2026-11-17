--[[
Scanning the auction house for the prices a page uses: from the writs page each writ and
what it asks for, from the crates page each crate and what fills it (/pwc scan: both).
The lowest price listed for each item is kept in the saved settings (ns.ScannedPrices),
with the time, and Core.lua weighs it against Auctionator's own price by which is newer.

Two auction houses, two ways to ask:

  - the modern one (C_AuctionHouse, which WoW Forever has): a browse search, whose
    results carry each item's lowest price (minPrice) already, one row per item. A search
    finds every item with the text in its name, so one word can price several items at
    once: "Leather" finds Light, Medium, Heavy, Thick and Rugged Leather. Each search
    takes the word of the next item's name that starts a word in the most other items
    still to scan; an item no word shares with another is searched by its whole name.
    Items a shared search lists none of are not listed: priced 0. When a word finds too
    much to read through, what it didn't reach is searched by name instead, and the word
    isn't shared again this session;
  - the old one (QueryAuctionItems), for clients that still have it: one exact-name
    search per item, sorted by price per item, reading buyouts page by page. Its results
    are one row per auction, so sharing a word would only mean more pages.

The auction house has to be open. Closing it stops the scan; what was found so far stays.
]]

local _, ns = ...
if not CreateFrame then return end

local PAGE_SIZE = 50  -- results the old auction house sends per page
local MAX_PAGES = 3   -- pages (or batches of browse results) read per item at most
local GROUP_PAGES = 5 -- batches of browse results read at most for a word several items share
local MIN_WORD = 4    -- letters a shared search word has at least
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
-- The auction house's own key for each item a scan (or a purchase's search) found, with
-- when: { key, at } (GetTime()).
local itemKeys = {}
-- When (GetTime()) a scan, or a purchase's search, last noted each item's price.
local priced = {}
-- Words (lower case) a shared search ran out of batches on this session: too broad to share.
local tooBroad = {}

--- The auction house's key for an item, as the last search saw it; nil if unseen, or if
--- seen more than maxAge seconds ago (when given).
function ns.ItemKey(id, maxAge)
  local seen = itemKeys[id]
  if not seen then return nil end
  if maxAge and GetTime and GetTime() - seen.at > maxAge then return nil end
  return seen.key
end

local function noteKey(id, key)
  if key then itemKeys[id] = { key = key, at = GetTime and GetTime() or 0 } end
end

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

--- An item's name as the game has it, else as the data does; nil if neither has one yet.
local function nameOf(item)
  return (GetItemInfo and GetItemInfo(item.id)) or item.name
end

--- Whether a word in `name` starts with `text` (both lower case): what a search for `text`
--- finds however the auction house matches inside words.
local function startsWord(name, text)
  local at = 1
  while true do
    local s = name:find(text, at, true)
    if not s then return false end
    if s == 1 or not name:sub(s - 1, s - 1):match("[%a']") then return true end
    at = s + 1
  end
end

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

--- A list ordered cheapest first by `cost(x)` = { value, partial } as last seen: whole
--- prices, then those missing a part, then none; ties as they were.
local function byCost(list, cost)
  local keyed = {}
  for i, x in ipairs(list) do
    local c = cost(x)
    keyed[i] = { x = x, i = i, value = c.value or 0, rank = c.value and (c.partial and 2 or 1) or 3 }
  end
  table.sort(keyed, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.value ~= b.value then return a.value < b.value end
    return a.i < b.i
  end)
  local out = {}
  for i, k in ipairs(keyed) do out[i] = k.x end
  return out
end

--- The items a scope prices, once each, with the name the data has for it: "writs" the
--- player's writs and what they ask for, "crates" the crates and what fills them, nil both.
--- With `cheapest`, the writs and crates go cheapest first by the prices known now (per
--- rep, per favor), a crate's materials too, so a scan reaches the ones worth buying first.
local function scopeItems(scope, cheapest)
  local list, seen = {}, {}
  local function add(id, name)
    if id and not seen[id] then
      seen[id] = true
      list[#list + 1] = { id = id, name = name }
    end
  end
  local writs, crates = ns.writs, ns.crates
  if cheapest then
    writs = byCost(writs, function(writ)
      local cost = ns.WritCost(writ)
      return { value = cost.perRep, partial = cost.partial }
    end)
    crates = byCost(crates, function(crate)
      local cost = ns.CrateCost(crate)
      return { value = cost.perFavor or cost.net, partial = cost.partial }
    end)
  end
  if scope ~= "crates" then
    for _, writ in ipairs(writs) do
      if ns.ForPlayer(writ) then
        add(writ.writItem)
        add(writ.item, writ.name)
      end
    end
  end
  if scope ~= "writs" then
    for _, crate in ipairs(crates) do
      add(crate.item)
      local bundles = crate.bundles
      if cheapest then
        local cost = ns.CrateCost(crate)
        bundles = byCost(bundles, function(bundle) return { value = cost.bundles[bundle].material } end)
      end
      for _, bundle in ipairs(bundles) do add(bundle.item, bundle.name) end
    end
  end
  return list
end

--- The items to scan for a scope, cheapest first, with the game asked to load each
--- one's name.
local function itemsToScan(scope)
  local list = scopeItems(scope, true)
  if C_Item and C_Item.RequestLoadItemDataByID then
    for _, item in ipairs(list) do pcall(C_Item.RequestLoadItemDataByID, item.id) end
  end
  return list
end

--- Whether the scan running has yet to settle an item: it is on its list and not done.
function ns.ScanPending(id)
  return scan ~= nil and scan.pos[id] ~= nil and not scan.settled[id]
end

--- When (GetTime()) a scan or a purchase's search last noted an item's price; nil if not
--- this session.
function ns.PricedAt(id)
  return priced[id]
end

--- { running, scope, done, total, item (name being searched), found, last } for the bar.
function ns.ScanProgress()
  if not scan then return { running = false, last = last } end
  local query, item = scan.query, scan.items[scan.index]
  local text
  if query and #query.ids > 1 then
    text = ('"%s": %d items'):format(query.text, #query.ids)
  elseif query then
    text = query.text
  else
    text = item and nameOf(item)
  end
  return {
    running = true, scope = scan.scope, done = scan.done, total = #scan.items, found = scan.found,
    item = text,
  }
end

local function finish(stopped)
  if not scan then return end
  local times = not stopped and ns.ScanTimes()
  if times then
    local now = time and time() or os.time()
    if scan.scope ~= "crates" then times.writs = now end
    if scan.scope ~= "writs" then times.crates = now end
  end
  last = { found = scan.found, total = #scan.items, done = scan.done, stopped = stopped }
  print(("%s: scan %s. %d of %d listed, %d searches."):format(ns.TITLE,
    stopped and "stopped" or "done", scan.found, scan.done, scan.searches))
  scan = nil
  notify()
  ns.Changed()
end

--- Done with an item; with keep, note what the scan found for it first (0 when nothing
--- was listed). Without it the item keeps whatever price it had.
local function settle(id, keep)
  if scan.settled[id] then return end
  scan.settled[id] = true
  scan.done = scan.done + 1
  local prices = ns.ScannedPrices()
  if keep and prices then
    local best = scan.best[id]
    prices[id] = { best or 0, time and time() or os.time() }
    priced[id] = GetTime and GetTime() or 0
    if best then scan.found = scan.found + 1 end
  end
end

--- On to the next search, from the first item not yet settled; or the end.
local function nextSearch()
  scan.query, scan.page, scan.state, scan.waited = nil, 0, "send", 0
  while scan.items[scan.index] and scan.settled[scan.items[scan.index].id] do
    scan.index = scan.index + 1
  end
  if scan.index > #scan.items then return finish(false) end
  notify()
end

--- Settle every item the search running is for, and move on.
local function advance(keep)
  for _, id in ipairs(scan.query and scan.query.ids or {}) do settle(id, keep) end
  nextSearch()
end

--- Read on (the next page or batch), or settle the search's items once each has a price,
--- the results ran out, or enough was read.
local function readOn(complete)
  local query, missing = scan.query, {}
  for _, id in ipairs(query.ids) do
    if not scan.best[id] then missing[#missing + 1] = id end
  end
  if #missing == 0 or complete then return advance(true) end
  if scan.page + 1 < query.pages then
    scan.page, scan.state, scan.waited = scan.page + 1, "send", 0
    return
  end
  if #query.ids == 1 then return advance(true) end
  -- The word finds too much: keep what turned up, search the rest by name.
  tooBroad[query.text:lower()] = true
  for _, id in ipairs(missing) do scan.solo[id] = true end
  for _, id in ipairs(query.ids) do
    if scan.best[id] then settle(id, true) end
  end
  nextSearch()
end

local function keep(id, price)
  if type(price) == "number" and price > 0 and (not scan.best[id] or price < scan.best[id]) then
    scan.best[id] = price
  end
end

--- The next search: { text, ids, want (set of ids), pages }. For the first item not yet
--- settled; with the modern auction house, by the word of its name that starts a word in
--- the most other items still to scan (the longest of equals), when one does. nil while
--- that item's name hasn't loaded.
local function nextQuery()
  local item = scan.items[scan.index]
  local name = nameOf(item)
  if not name then return nil end
  local query = { text = name, ids = { item.id }, pages = MAX_PAGES }
  if MODERN and not scan.solo[item.id] then
    local others = {}
    for i = scan.index + 1, #scan.items do
      local other = scan.items[i]
      local otherName = not scan.settled[other.id] and not scan.solo[other.id] and nameOf(other)
      if otherName then others[#others + 1] = { id = other.id, name = otherName:lower() } end
    end
    for word in name:gmatch("[%a']+") do
      local text = word:lower()
      if #text >= MIN_WORD and not tooBroad[text] then
        local ids = { item.id }
        for _, other in ipairs(others) do
          if startsWord(other.name, text) then ids[#ids + 1] = other.id end
        end
        if #ids > #query.ids or (#ids > 1 and #ids == #query.ids and #word > #query.text) then
          query = { text = word, ids = ids, pages = GROUP_PAGES }
        end
      end
    end
  end
  query.want = {}
  for _, id in ipairs(query.ids) do query.want[id] = true end
  return query
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
  local want = scan.query.want
  for _, result in ipairs(results or {}) do
    local key = result.itemKey
    local id = key and key.itemID
    if id and want[id] then
      keep(id, result.minPrice)
      noteKey(id, key)
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
  local want = scan.query.want
  local count = GetNumAuctionItems("list") or 0
  for i = 1, count do
    local info = { GetAuctionItemInfo("list", i) }
    local stack, buyout, id = info[3], info[10], info[17]
    if id and want[id] and type(buyout) == "number" and (stack or 0) > 0 then keep(id, buyout / stack) end
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
  if not scan.query then
    scan.query = nextQuery()
    if not scan.query then
      -- The game has not loaded this item yet: give it a moment, then skip it.
      if scan.waited > NAME_WAIT then
        settle(scan.items[scan.index].id, false)
        nextSearch()
      end
      return
    end
    scan.searches = scan.searches + 1
    notify()
  end
  if MODERN then modernSend(scan.query.text) else legacySend(scan.query.text) end
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

--- When a scan of a scope's items ("writs", "crates"; nil for both: the older) last ran
--- to its end; nil before the first. A scan of the other list doesn't count, though the
--- lists share materials. Before scans were timed per list: when the oldest price among
--- the scope's items was seen.
function ns.LastScanTime(scope)
  local times = ns.ScanTimes() or {}
  if scope then
    if times[scope] then return times[scope] end
  elseif times.writs and times.crates then
    return math.min(times.writs, times.crates)
  end
  local prices, oldest = ns.ScannedPrices() or {}, nil
  for _, item in ipairs(scopeItems(scope)) do
    local seen = prices[item.id]
    if seen and (not oldest or seen[2] < oldest) then oldest = seen[2] end
  end
  return oldest
end

--- Keep a price found outside a scan (buying searches the item again), as a scan would:
--- copper per item, 0 when nothing is listed; with the auction house's key when known.
function ns.RecordPrice(id, copper, key)
  local prices = ns.ScannedPrices()
  if prices and type(copper) == "number" then
    prices[id] = { math.floor(copper + 0.5), time and time() or os.time() }
    priced[id] = GetTime and GetTime() or 0
  end
  noteKey(id, key)
  notify()
  ns.Changed()
end

--- Start a scan of a scope ("writs", "crates", or nil for both); false and a reason when
--- it can't.
function ns.StartScan(scope)
  if scan then return false, "Scan running." end
  if not ns.CanScan() then return false, "No AH search on this client." end
  if not ahOpen then return false, "Open the AH." end
  if ns.Buying and ns.Buying() then return false, "Finish buying." end
  scan = {
    scope = scope, items = itemsToScan(scope), pos = {}, settled = {}, solo = {}, best = {},
    index = 1, done = 0, found = 0, searches = 0, page = 0, state = "send", waited = 0,
  }
  for i, item in ipairs(scan.items) do scan.pos[item.id] = i end
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
