--[[
Buying writs and what they ask for at the auction house, from the writs page: with the
auction house open, clicking a writ's row opens a small window inside the auction house
window. It goes through two steps:

  1. the writ: how many to buy (Max: every one listed);
  2. the material: as many as those writs and the ones in the bags ask for, less what
     the bags hold.

Each step shows the item and "Paying <price> for:" above it.

The game only lets an addon buy from a click, and one click buys one thing, so:

  - an item sold in bulk (a commodity): Buy asks the auction house for the exact price
    of the quantity, Confirm pays it. Two clicks, the way the game's own window does it.
  - an item sold one auction at a time (writs, on WoW Forever): one click per auction.

The protected call comes first in the click, before the window changes: WoW Forever
blocked the purchase when the window was updated first.

Only the modern auction house (C_AuctionHouse, which WoW Forever has).
]]

local _, ns = ...
if not CreateFrame then return end

local AH = C_AuctionHouse
local CAN = AH ~= nil and AH.SendSearchQuery ~= nil and AH.MakeItemKey ~= nil
  and AH.StartCommoditiesPurchase ~= nil and AH.PlaceBid ~= nil
local TIMEOUT = 8       -- seconds to wait for the auction house before giving up
local PAY_TIMEOUT = 20  -- seconds to wait for a purchase to be confirmed
-- Seconds to wait, after the auction house reports an error while paying, for the
-- purchase to be confirmed anyway: WoW Forever reports error 10 for purchases that go
-- through.
local ERROR_GRACE = 4
local ADDON = ...
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local RED, GREY = "ffff4040", "ff808080"

local buy = nil       -- the purchase under way, or nil
local dialog

--- Whether this client lets the addon buy at the auction house.
function ns.CanBuy()
  return CAN
end

--- Whether a purchase is under way.
function ns.Buying()
  return buy ~= nil
end

local function sorts()
  if Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price then
    return { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
  end
  return {}
end

local function step()
  return buy and buy.steps[buy.index]
end

--- Money with the game's coin icons: "1 [gold] 20 [silver]".
local function coins(copper)
  copper = math.floor((copper or 0) + 0.5)
  if GetMoneyString then
    local ok, text = pcall(GetMoneyString, copper, true)
    if ok and text then return text end
  end
  if GetCoinTextureString then
    local ok, text = pcall(GetCoinTextureString, copper)
    if ok and text then return text end
  end
  return ns.Money(copper)
end

--- What the player has, in red when it is less than `cost`; "" when it is enough.
local function purse(cost)
  local have = GetMoney and GetMoney()
  if not have or have >= cost then return nil end
  return ns.Color(RED, "You have only " .. coins(have) .. ".")
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

--- The item's name in its quality colour.
local function itemName(s)
  local name, _, quality = nil, nil, nil
  if GetItemInfo then name, _, quality = GetItemInfo(s.id) end
  name = name or s.name
  local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
  if color and color.hex then return color.hex .. name .. "|r" end
  return name
end

--- Show the window for the current step. view:
---   pay     copper to show as "Paying <pay> for:" (nil: show `status` instead)
---   about   the price is an estimate from the listings
---   status  a line in place of the price
---   qty     the quantity beside the item
---   edit    the quantity is the writ count the player sets (with Max)
---   notes   lines under the item
---   action  the Buy button's label (nil disables it)
local function show(view)
  local s = step()
  dialog.heading:SetText(("%s  |cff808080(%d of %d)|r"):format(buy.title, buy.index, #buy.steps))
  if view.pay then
    dialog.pay:SetText(("Paying %s%s for:"):format(view.about and "about " or "", coins(view.pay)))
  else
    dialog.pay:SetText(view.status or "")
  end

  dialog.item.id = s.id
  dialog.item.icon:SetTexture(s.icon)
  dialog.name:SetText(itemName(s))
  if view.edit then
    dialog.count:Hide()
    dialog.qty:Show()
    if (tonumber(dialog.qty:GetText() or "") or -1) ~= view.qty then dialog.qty:SetText(tostring(view.qty)) end
    dialog.max:Show()
    dialog.max:SetText(("Max %d"):format(s.listed or 0))
  else
    dialog.qty:Hide()
    dialog.max:Hide()
    dialog.count:Show()
    dialog.count:SetText(tostring(view.qty or s.need or 0))
  end

  local notes = {}
  local given = view.notes or {}
  for i = 1, table.maxn(given) do  -- lines may be nil (a warning that doesn't apply)
    if given[i] then notes[#notes + 1] = given[i] end
  end
  dialog.notes:SetText(table.concat(notes, "\n"))

  if view.action then
    dialog.buy:SetText(view.action)
    dialog.buy:Enable()
  else
    dialog.buy:SetText("Buy")
    dialog.buy:Disable()
  end
  dialog:Show()
end

--- Leave a commodity purchase the auction house is holding a price for.
local function release()
  if buy and buy.holding and AH.CancelCommoditiesPurchase then
    pcall(AH.CancelCommoditiesPurchase)
  end
  if buy then buy.holding = false end
end

local function finish(message)
  release()
  local done = buy
  buy = nil
  if dialog then dialog:Hide() end
  if message and done then print(ns.TITLE .. ": " .. message) end
  ns.Changed()
end

local search, handOff, offer

-- Learned in play: whether this client blocks a search the addon sends outside a click.
-- Once it has, every search waits for a click on Look up.
local searchNeedsClick = false

-- Learned in play: whether this client blocks the addon from buying out an auction. Such
-- items are then bought in the game's own auction house window.
local bidBlocked = false

--- Put a name in the game's own auction house search box, if there is one.
local function fillSearchBox(name)
  local bar = AuctionHouseFrame and AuctionHouseFrame.SearchBar
  local box = bar and bar.SearchBox
  if box and box.SetText then return (pcall(box.SetText, box, name)) end
  return false
end

--- How many of the material the writs ask for, beyond what the bags hold: the writs
--- held when the window opened plus those bought (or planned) here.
local function materialNeed()
  local w = buy.writStep
  local writs = buy.writsHeld + (w and (w.planned or 0) or 0)
  return math.max(0, writs * buy.count - buy.materialHeld)
end

--- Move on to the next item; fromClick when a click led here, so the search can go out
--- at once.
local function nextStep(fromClick)
  release()
  buy.index = buy.index + 1
  if buy.index > #buy.steps then
    return finish(buy.bought > 0 and ("done: %s."):format(buy.title) or nil)
  end
  search(fromClick)
end

--- Send the search for the current item now; the answer arrives as an event.
local function sendSearch()
  local s = step()
  buy.state, buy.waited, buy.seen, buy.clickSent = "wait", 0, {}, true
  AH.SendSearchQuery(s.key or AH.MakeItemKey(s.id), sorts(), true)
  if buy and buy.state == "wait" then show({ status = "Searching...", qty = s.need }) end
end

--- Look the current item up. Inside a click the search goes out at once; otherwise on
--- the next frame, or (where the game wants a click for it) behind a Look up button.
function search(fromClick)
  local s = step()
  s.kind, s.auction, s.qty, s.queue, s.list = nil, nil, nil, nil, nil
  s.key = ns.ItemKey and ns.ItemKey(s.id)  -- the auction house's own key, from a scan
  buy.waited, buy.seen, buy.late = 0, {}, false
  if s.material and buy.writStep then
    s.need = materialNeed()
    if s.need == 0 then
      buy.state = "enough"
      return show({ status = "Nothing to buy.", qty = 0, action = "Done",
        notes = { ("In bags: %d. Enough."):format(buy.materialHeld) } })
    end
  end
  if s.target then s.need = s.target - s.got end  -- partway through: what is left
  if fromClick then return sendSearch() end
  if searchNeedsClick then
    buy.state = "ask"
    return show({ status = "Click Look up.", qty = s.need, action = "Look up" })
  end
  buy.state = s.key and "send" or "browse0"
  show({ status = "Searching...", qty = s.need })
end

-- ---------------------------------------------------------------------------
-- Answers from the auction house
-- ---------------------------------------------------------------------------

--- What `want` costs from the listings, cheapest first: { quantity, price, low, high }.
--- Every listing is { quantity, each }: for commodities the units at that price, for
--- items the writs listed at that price (each bought with its own click).
local function plan(s, want)
  local p = { quantity = 0, price = 0 }
  for _, l in ipairs(s.list or {}) do
    if p.quantity >= want then break end
    local take = math.min(want - p.quantity, l.quantity)
    p.quantity, p.price = p.quantity + take, p.price + take * l.each
    p.low = p.low or l.each
    p.high = l.each
  end
  return p
end

--- "35s each", or "35s to 1g each" when the prices differ.
local function eachRange(low, high)
  if not low then return nil end
  if math.floor(low) == math.floor(high) then return coins(low) .. " each" end
  return ("%s to %s each"):format(coins(low), coins(high))
end

--- Offer the current step from its listings.
function offer()
  local s = step()
  buy.state = "offer"
  local want = s.writ and s.want or s.need
  local p = plan(s, want)
  s.plan = p
  local notes = {}
  if s.writ then
    notes[#notes + 1] = ns.Color(GREY, ("Listed: %d. In bags: %d."):format(s.listed, buy.writsHeld))
  elseif p.quantity < want then
    notes[#notes + 1] = ns.Color(RED, ("Only %d listed."):format(p.quantity))
  end
  if s.kind == "item" and p.quantity > 1 then
    notes[#notes + 1] = ns.Color(GREY, "One click each.")
  end
  local each = p.quantity > 0 and eachRange(p.low, p.high)
  if each then notes[#notes + 1] = ns.Color(GREY, each) end
  notes[#notes + 1] = purse(p.price)
  if not s.writ and buy.writStep then
    local writs = buy.writsHeld + (buy.writStep.planned or 0)
    notes[#notes + 1] = ns.Color(GREY, ("%d writ%s x %d, minus %d in bags."):format(
      writs, writs == 1 and "" or "s", buy.count, buy.materialHeld))
  end
  local action
  if p.quantity > 0 then
    action = (s.kind == "item" and p.quantity > 1) and ("Buy (1 of %d)"):format(p.quantity) or "Buy"
  end
  show({ pay = p.quantity > 0 and p.price or nil, about = s.kind == "commodity",
    status = "Set an amount.", qty = s.writ and want or p.quantity,
    edit = s.writ, notes = notes, action = action })
end

--- Listings of a commodity, cheapest first.
local function commodityResults()
  local s = step()
  s.kind, s.list, s.listed = "commodity", {}, 0
  for i = 1, AH.GetNumCommoditySearchResults(s.id) or 0 do
    local r = AH.GetCommoditySearchResultInfo(s.id, i)
    if r and r.unitPrice then
      local free = math.max(0, (r.quantity or 0) - (r.numOwnerItems or 0))
      if free > 0 then
        s.list[#s.list + 1] = { quantity = free, each = r.unitPrice }
        s.listed = s.listed + free
      end
    end
  end
  if s.listed == 0 then
    buy.state = "none"
    return show({ status = ns.Color(GREY, "None listed."), qty = s.need, action = "Skip" })
  end
  if s.writ then s.want = math.min(s.want, s.listed) end
  offer()
end

--- Auctions of an item sold one at a time, cheapest first. On WoW Forever a result row
--- stands for the writs listed at one price: buyoutAmount is the price of one, quantity
--- how many there are, and PlaceBid buys one (a 47s row of 7 bought one writ for 47s).
local function itemResults(itemKey)
  local s = step()
  s.kind, s.list, s.listed = "item", {}, 0
  for i = 1, AH.GetNumItemSearchResults(itemKey) or 0 do
    local r = AH.GetItemSearchResultInfo(itemKey, i)
    if r and r.buyoutAmount and r.buyoutAmount > 0 and not r.containsOwnerItem then
      local quantity = math.max(1, r.quantity or 1)
      s.list[#s.list + 1] = { auctionID = r.auctionID, each = r.buyoutAmount, quantity = quantity }
      s.listed = s.listed + quantity
    end
  end
  table.sort(s.list, function(a, b) return a.each < b.each end)
  if #s.list == 0 then
    buy.state = "none"
    return show({ status = ns.Color(GREY, "None listed with a buyout."), qty = s.need, action = "Skip" })
  end
  if s.target then
    -- Partway through: the cheapest auction from this fresh search is the next one.
    local a = s.list[1]
    s.nextAuction, buy.state = a, "next"
    return show({ pay = a.each, qty = 1, action = ("Buy (%d of %d)"):format(s.got + 1, s.target),
      notes = { s.note, ns.Color(GREY, ("Bought %d of %d."):format(s.got, s.target)),
        purse(a.each) } })
  end
  if s.writ then s.want = math.min(s.want, s.listed) end
  if bidBlocked then return handOff(s) end
  offer()
end

--- Hand an item sold one auction at a time to the game's own window, where the player
--- buys it with the game's Buyout button.
function handOff(s)
  buy.state = "handoff"
  if s.writ then s.planned = s.want end
  local want = s.writ and s.want or s.need
  local p = plan(s, want)
  show({ pay = p.price, qty = p.quantity, action = "Next", notes = {
    ns.Color(RED, "Blocked by the game."),
    fillSearchBox(s.name) and "Buy it in the AH window (name in search box), then Next."
      or "Buy it in the AH window, then Next.",
  } })
end

--- Buy one from the cheapest listing. After it the auction house is searched again: the
--- rest of the first search can't be bought any more ("item not found").
local function payAuction(s, a)
  s.auction, s.note = a, nil
  buy.state, buy.waited, buy.seen, buy.error = "paying", 0, {}, nil
  -- The purchase first, the window after: nothing runs between the click and the
  -- protected call.
  C_AuctionHouse.PlaceBid(a.auctionID, a.each)
  if buy and buy.state == "paying" then
    show({ pay = a.each, qty = 1,
      notes = { ns.Color(GREY, ("Buying %d of %d..."):format(s.got + 1, s.target)) } })
  end
end

--- The Buy (or Confirm, Look up, Next, Done) button.
local function onBuy()
  local s = step()
  if not buy or not s then return end
  local state = buy.state
  if state == "none" or state == "failed" or state == "handoff" or state == "enough" then
    return nextStep(true)
  elseif state == "ask" then
    return sendSearch()
  elseif state == "offer" and s.kind == "commodity" then
    local p = s.plan
    s.qty, s.estimate = p.quantity, p.price
    if s.writ then s.planned = s.want end
    buy.state, buy.waited, buy.holding, buy.seen = "quote", 0, true, {}
    C_AuctionHouse.StartCommoditiesPurchase(s.id, s.qty)
    if buy and buy.state == "quote" then
      show({ status = "Getting the price...", qty = s.qty })
    end
  elseif state == "confirm" then
    buy.state, buy.waited, buy.holding, buy.seen, buy.error = "paying", 0, false, {}, nil
    C_AuctionHouse.ConfirmCommoditiesPurchase(s.id, s.qty)
    if buy and buy.state == "paying" then
      show({ pay = s.total, qty = s.qty, notes = { ns.Color(GREY, "Buying...") } })
    end
  elseif state == "offer" and s.kind == "item" then
    if s.writ then s.planned = s.want end
    s.target, s.got = s.plan.quantity, 0
    payAuction(s, s.list[1])
  elseif state == "next" then
    payAuction(s, s.nextAuction)
  end
end

--- An auction house error code as text: "AH error 10 (DatabaseError)."
local function errorText(code)
  local name
  for k, v in pairs(Enum and Enum.AuctionHouseError or {}) do
    if v == code then name = k end
  end
  return ("AH error %s%s."):format(tostring(code), name and (" (" .. name .. ")") or "")
end

--- Fail with a reason; the events seen while waiting go along, in grey, so a report from
--- the game says where it stopped.
local function failed(why)
  local s = step()
  local notes = { ns.Color(RED, why) }
  if buy.seen and #buy.seen > 0 then
    notes[2] = ns.Color(GREY, "Seen: " .. table.concat(buy.seen, ", "))
  end
  buy.state, buy.holding = "failed", false
  show({ status = ns.Color(RED, "Stopped."), qty = s and (s.qty or s.need), notes = notes, action = "Skip" })
end

--- A purchase went through: count it; for auctions bought one at a time, search again
--- for the next while more are wanted.
local function bought(quantity)
  local s = step()
  buy.bought = buy.bought + quantity
  s.got = (s.got or 0) + quantity
  print(("%s: bought %d x %s."):format(ns.TITLE, quantity, s.name))
  if s.kind == "item" and s.target and s.got < s.target then return search() end
  nextStep()
end

--- The browse answer: the auction house's own key for the item, which the search then
--- uses (a key made with MakeItemKey can differ from it, and go unanswered).
local function browseResults(results)
  local s = step()
  for _, r in ipairs(results or {}) do
    if r.itemKey and r.itemKey.itemID == s.id then
      s.key = r.itemKey
      break
    end
  end
  if not s.key then
    if AH.HasFullBrowseResults and not AH.HasFullBrowseResults() then return end
    buy.state = "none"
    return show({ status = ns.Color(GREY, "None listed."), qty = s.need, action = "Skip" })
  end
  buy.state, buy.waited, buy.seen = "send", 0, {}
end

--- Whether the answer to the search is in, read straight from the auction house; for
--- when the event doesn't come.
local function pollResults()
  local s = step()
  local key = s.key or AH.MakeItemKey(s.id)
  if AH.GetNumCommoditySearchResults and (AH.GetNumCommoditySearchResults(s.id) or 0) > 0 then
    commodityResults()
  elseif AH.GetNumItemSearchResults and (AH.GetNumItemSearchResults(key) or 0) > 0 then
    itemResults(key)
  end
end

local BLOCKED = { ADDON_ACTION_BLOCKED = true, ADDON_ACTION_FORBIDDEN = true }
local SEARCHING = { browse0 = true, browse = true, send = true, wait = true }
local STAGES = {
  offer = "offering", quote = "asking the price", confirm = "confirming",
  paying = "buying", next = "between auctions", failed = "stopped", none = "nothing listed",
  wait = "searching", send = "searching", browse = "browsing", browse0 = "browsing", ask = "searching",
}

local events = CreateFrame("Frame")
for _, event in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
  "COMMODITY_SEARCH_RESULTS_ADDED", "ITEM_SEARCH_RESULTS_ADDED",
  "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_FAILURE",
  "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED",
  "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_PURCHASE_COMPLETED", "AUCTION_HOUSE_CLOSED",
  "AUCTION_HOUSE_SHOW_ERROR", "BIDS_UPDATED", "UI_ERROR_MESSAGE",
  "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
  pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, ...)
  if not buy then return end
  local s = step()
  if buy.seen and #buy.seen < 8 and event ~= "AUCTION_HOUSE_CLOSED" then
    buy.seen[#buy.seen + 1] = event
  end
  if event == "AUCTION_HOUSE_CLOSED" then
    return finish(buy.bought > 0 and "AH closed. Rest not bought." or nil)
  elseif BLOCKED[event] then
    local addon, fn = ...
    if addon ~= ADDON then return end
    local where = buy.state
    if SEARCHING[where] and not buy.clickSent then
      -- A search sent outside a click: from now on, ask for one.
      searchNeedsClick = true
      buy.state = "ask"
      return show({ status = "Click to search.", qty = s.need, action = "Look up" })
    end
    if where == "paying" and s.kind == "item" then
      bidBlocked = true
      return handOff(s)
    end
    failed(("Blocked: %s while %s."):format(
      tostring(fn or "?"), STAGES[where] or tostring(where)))
  elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
    if buy.state == "browse" then browseResults(AH.GetBrowseResults()) end
  elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" then
    if buy.state == "browse" then buy.state, buy.waited = "send", 0 end
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
    if buy.state == "wait" and ... == s.id then commodityResults() end
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
    local key = ...
    if buy.state == "wait" and type(key) == "table" and key.itemID == s.id then itemResults(key) end
  elseif event == "AUCTION_HOUSE_SHOW_ERROR" and (buy.state == "paying" or buy.state == "quote") then
    local code = ...
    local errors = Enum and Enum.AuctionHouseError
    local notFound = (errors and errors.ItemNotFound) or 4
    if code == notFound and buy.state == "paying" and s.kind == "item" and s.target then
      -- Sold to someone else, or no longer in this client's results: look again.
      s.note = ns.Color(RED, "Sold. Next cheapest:")
      return search()
    end
    if buy.state == "paying" then
      -- It may still go through: wait a moment for the confirmation (see the driver).
      if not buy.error then buy.error = { code = code, at = buy.waited } end
      return
    end
    failed(errorText(code))
  elseif event == "COMMODITY_PRICE_UPDATED" and buy.state == "quote" then
    local unit, total = ...
    s.total, buy.state = total, "confirm"
    show({ pay = total, qty = s.qty, action = "Confirm", notes = {
      ns.Color(GREY, coins(unit) .. " each"),
      s.estimate and total > s.estimate * 1.1 and ns.Color(RED, "Price went up.") or nil,
      purse(total),
    } })
  elseif event == "COMMODITY_PRICE_UNAVAILABLE" and buy.state == "quote" then
    failed("No price for that amount now.")
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" and buy.state == "paying" then
    bought(s.qty)
  elseif event == "COMMODITY_PURCHASE_FAILED" and buy.state == "paying" then
    failed(buy.error and errorText(buy.error.code) or "Purchase failed.")
  elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" and s.kind == "item" and s.auction
    and (buy.state == "paying" or (buy.state == "failed" and buy.late)) then
    -- A late answer still counts: the purchase went through.
    if ... == s.auction.auctionID then
      buy.late = false
      bought(1)  -- one per purchase, whatever the listing's quantity
    end
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" and buy.state == "failed" and buy.late then
    buy.late = false
    bought(s.qty)
  elseif event == "UI_ERROR_MESSAGE" and buy.state == "paying" then
    local _, message = ...
    failed(type(message) == "string" and message or "Purchase failed.")
  end
end)

-- Sending searches when the auction house is ready, and giving up on silence.
local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, elapsed)
  if not buy then return end
  buy.waited = buy.waited + elapsed
  local ready = not AH.IsThrottledMessageSystemReady or AH.IsThrottledMessageSystemReady()
  local s = step()
  if buy.state == "browse0" then
    if not ready then
      if buy.waited > TIMEOUT then failed("AH busy. Try again.") end
      return
    end
    buy.state, buy.waited, buy.clickSent = "browse", 0, false
    local name = GetItemInfo and GetItemInfo(s.id)  -- the real name, not a stand-in
    if AH.SendBrowseQuery and name then
      s.name = name
      AH.SendBrowseQuery({ searchString = name, sorts = {}, filters = {}, itemClassFilters = {} })
    else
      buy.state = "send"
    end
  elseif buy.state == "browse" and buy.waited > TIMEOUT then
    buy.state, buy.waited = "send", 0  -- no browse answer: search with a made key
  elseif buy.state == "send" then
    if not ready then
      if buy.waited > TIMEOUT then failed("AH busy. Try again.") end
      return
    end
    buy.state, buy.waited, buy.clickSent = "wait", 0, false
    AH.SendSearchQuery(s.key or AH.MakeItemKey(s.id), sorts(), true)
  elseif buy.state == "wait" then
    if buy.waited > 1.5 then pollResults() end
    if buy.state == "wait" and buy.waited > TIMEOUT then
      failed("No search answer.")
    end
  elseif buy.state == "quote" and buy.waited > TIMEOUT then
    failed("No price answer.")
  elseif buy.state == "paying" and buy.error and buy.waited - buy.error.at > ERROR_GRACE then
    -- An error and no confirmation since. A confirmation that still comes counts.
    failed(errorText(buy.error.code))
    buy.late = true
  elseif buy.state == "paying" and buy.waited > PAY_TIMEOUT then
    -- It may or may not have gone through: say so rather than buy twice. A late
    -- confirmation still counts.
    failed("No confirmation. Check mail before retrying.")
    buy.late = true
  end
end)

--- The writ count typed in: kept between 0 and what is listed, and the offer redone.
local function setWant(value)
  local s = step()
  if not buy or buy.state ~= "offer" or not s or not s.writ then return end
  s.want = math.max(0, math.min(math.floor(tonumber(value) or 0), s.listed or 0))
  offer()
end

local function makeDialog()
  -- A child of the game's auction house window, like the buy buttons of other auction
  -- addons.
  local parent = AuctionHouseFrame or UIParent
  dialog = ns.Skin.Window("PuggerWaylaidCompanionBuy", parent, 440, 230, "Buy")
  dialog:SetPoint("CENTER", parent, "CENTER", 0, 0)
  dialog:SetToplevel(true)
  dialog:SetFrameStrata("DIALOG")
  dialog:SetMovable(true)
  dialog:EnableMouse(true)
  dialog:SetClampedToScreen(true)
  dialog:RegisterForDrag("LeftButton")
  dialog:SetScript("OnDragStart", dialog.StartMoving)
  dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
  dialog:Hide()

  dialog.heading = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  dialog.heading:SetPoint("TOPLEFT", 16, -36)
  dialog.heading:SetPoint("TOPRIGHT", -16, -36)
  dialog.heading:SetJustifyH("LEFT")
  dialog.heading:SetTextColor(unpack(ns.Skin.color.accent))

  -- "Paying 1 [gold] 20 [silver] for:"
  dialog.pay = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  dialog.pay:SetPoint("TOPLEFT", 16, -58)
  dialog.pay:SetPoint("TOPRIGHT", -16, -58)
  dialog.pay:SetJustifyH("LEFT")

  -- The item: quantity (typed in for the writ), "x", icon, name, and Max for the writ.
  local ROW = -104
  dialog.qty = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
  dialog.qty:SetSize(44, 20)
  dialog.qty:SetPoint("LEFT", dialog, "TOPLEFT", 24, ROW)
  dialog.qty:SetAutoFocus(false)
  dialog.qty:SetNumeric(true)
  dialog.qty:SetMaxLetters(4)
  dialog.qty:SetJustifyH("CENTER")
  dialog.qty:SetScript("OnTextChanged", function(self, userInput)
    if userInput then setWant(self:GetText()) end
  end)
  dialog.qty:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  dialog.qty:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  dialog.count = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  dialog.count:SetPoint("RIGHT", dialog, "TOPLEFT", 66, ROW)
  dialog.count:SetJustifyH("RIGHT")

  local times = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  times:SetPoint("LEFT", dialog, "TOPLEFT", 74, ROW)
  times:SetText("x")

  dialog.item = CreateFrame("Button", nil, dialog)
  dialog.item:SetSize(36, 36)
  dialog.item:SetPoint("LEFT", dialog, "TOPLEFT", 90, ROW)
  dialog.item.icon = dialog.item:CreateTexture(nil, "ARTWORK")
  dialog.item.icon:SetAllPoints()
  dialog.item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  ns.Skin.Border(dialog.item, ns.Skin.color.edge, "OVERLAY")
  dialog.item:SetScript("OnEnter", function(self)
    if not self.id then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.id)
    GameTooltip:Show()
  end)
  dialog.item:SetScript("OnLeave", function() GameTooltip:Hide() end)

  dialog.max = ns.Skin.Button(dialog, "", 70, 22)
  dialog.max:SetPoint("RIGHT", dialog, "TOPRIGHT", -16, ROW)
  dialog.max:SetScript("OnClick", function()
    local s = step()
    if s and s.writ then
      dialog.qty:ClearFocus()
      setWant(s.listed or 0)
    end
  end)

  dialog.name = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  dialog.name:SetPoint("LEFT", dialog.item, "RIGHT", 8, 0)
  dialog.name:SetPoint("RIGHT", dialog.max, "LEFT", -8, 0)
  dialog.name:SetJustifyH("LEFT")

  dialog.notes = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  dialog.notes:SetPoint("TOPLEFT", 16, -132)
  dialog.notes:SetPoint("TOPRIGHT", -16, -132)
  dialog.notes:SetJustifyH("LEFT")
  dialog.notes:SetJustifyV("TOP")

  dialog.buy = ns.Skin.Button(dialog, "", 110, 22)
  dialog.buy:SetPoint("BOTTOMLEFT", 16, 14)
  dialog.buy:SetScript("OnClick", function() onBuy() end)

  dialog.cancel = ns.Skin.Button(dialog, "Cancel", 90, 22)
  dialog.cancel:SetPoint("BOTTOMRIGHT", -16, 14)
  dialog.cancel:SetScript("OnClick", function() finish(nil) end)

  dialog.skip = ns.Skin.Button(dialog, "Skip", 90, 22)
  dialog.skip:SetPoint("RIGHT", dialog.cancel, "LEFT", -6, 0)
  dialog.skip:SetScript("OnClick", function() if buy then nextStep(true) end end)

  -- Closing the dialog any way at all ends the purchase.
  dialog:SetScript("OnHide", function() if buy then finish(nil) end end)
end

--- Whether buying can start now; says why not.
local function canStart()
  if not CAN then
    print(ns.TITLE .. ": no AH buying on this client.")
    return false
  end
  if not ns.AuctionHouseOpen() then
    print(ns.TITLE .. ": open the AH.")
    return false
  end
  if ns.ScanProgress().running then
    print(ns.TITLE .. ": stop the scan.")
    return false
  end
  if buy then finish(nil) end
  return true
end

--- Buy a list of materials, one step each: { { id, need, name }, ... }.
function ns.BuyMaterials(list)
  if not canStart() then return end
  local steps = {}
  for _, m in ipairs(list) do
    local name, icon = ns.Item(m.id, m.name)
    steps[#steps + 1] = { id = m.id, material = true, name = name, icon = icon, need = m.need }
  end
  if #steps == 0 then return end
  if not dialog then makeDialog() end
  buy = { title = "Missing material", steps = steps, index = 1, bought = 0, waited = 0 }
  search(true)  -- the click in the Transfer menu
end

--- Buy writs and their material: the writ count is set in the window (one to start with
--- when the bags hold none), the material follows it.
function ns.BuyForWrit(writ)
  if not canStart() then return end

  local writsHeld = ns.Count(writ.writItem)
  local writName, writIcon = ns.Item(writ.writItem, "Writ: " .. writ.name)
  local matName, matIcon = ns.Item(writ.item, writ.name)
  local writStep = { id = writ.writItem, writ = true, name = writName, icon = writIcon,
    want = writsHeld == 0 and 1 or 0, need = writsHeld == 0 and 1 or 0 }
  local matStep = { id = writ.item, material = true, name = matName, icon = matIcon, need = 0 }

  if not dialog then makeDialog() end
  buy = { title = writ.name, steps = { writStep, matStep }, index = 1, bought = 0, waited = 0,
    writStep = writStep, writsHeld = writsHeld, materialHeld = ns.Count(writ.item), count = writ.count }
  search(true)  -- the click on the writ's row
end
