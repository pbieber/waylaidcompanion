--[[
Buying writs or crates and what fills them at the auction house, from the writs and
crates pages: with the auction house open, clicking a writ's or a crate's row opens a
small window inside the auction house window. It goes through two steps:

  1. the writ or crate (the lead): how many to buy (Max: every one listed), or the
     reputation or favor to buy. The material is searched first, so this step can say
     how many writs or crates, with their material, are listed near the price the pages
     showed, and warn when the count asked for would cost more than that;
  2. the material: as many as those and the ones in the bags ask for, less what the bags
     hold. For a crate, its cheapest material, and the crates the bags' other materials
     fill already need none.

From the turn-ins page, clicking a writ recipient buys every writ of theirs not held or
handed in today, one each, then the material those writs ask for, less what the bags hold.
Clicking a zone does the same for every recipient in it.

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
-- A browse for an item's key (the first look at an item): the pages asked for when it isn't
-- on the first, and the seconds to wait for an answer before searching with a made key.
-- (The browse used to wait the whole TIMEOUT for an item on a later page: a slow first look.)
local BROWSE_PAGES, BROWSE_WAIT = 5, 3
local PAY_TIMEOUT = 20  -- seconds to wait for a purchase to be confirmed
-- Seconds to wait, after the auction house reports an error while paying, for the
-- purchase to be confirmed anyway: WoW Forever reports error 10 for purchases that go
-- through.
local ERROR_GRACE = 4
-- Seconds after which what the auction house said about an item counts as old: an item
-- last searched longer ago is searched again (a browse first, like Scan AH, for a fresh
-- key) before it is offered, and a Buy clicked on an offer this old searches again and
-- offers the new price instead of buying.
local STALE = 180
-- How far above the price the pages showed a listing may be and still count as at that
-- price, for the warning on a writ's or crate's step.
local NEAR = 1.1
local ADDON = ...
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local RED, GREY = "ffff4040", "ff808080"

local buy = nil       -- the purchase under way, or nil
local dialog
-- The window's layout: its height, where the notes start, and the height of the favor
-- or reputation row the writ or crate step adds above them.
local DIALOG_HEIGHT, NOTES_TOP, GAIN_ROW = 230, -132, 30

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
---   edit    the quantity is the writ or crate count the player sets (with Max), or the
---           favor or reputation it buys, below it
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

  -- The favor or reputation the writs or crates buy, on their step. Left alone while
  -- typed in, so the count it comes to doesn't overwrite it; set right when the box is
  -- left. The window keeps one height through the purchase.
  local gain = s.lead and buy.gain
  if gain then
    dialog.gain.label:SetText(gain.label .. ":")
    dialog.gain.each:SetText(ns.Color(GREY, ("%d per %s"):format(gain.each, buy.noun)))
    if not dialog.gain.box:HasFocus() then dialog.gain.box:SetText(tostring((view.qty or 0) * gain.each)) end
    if dialog.gain.box.SetEnabled then dialog.gain.box:SetEnabled(view.edit == true) end
    dialog.gain.box:SetAlpha(view.edit and 1 or 0.5)
    dialog.gain:Show()
  else
    dialog.gain:Hide()
  end
  local notesTop = gain and NOTES_TOP - GAIN_ROW or NOTES_TOP
  dialog.notes:ClearAllPoints()
  dialog.notes:SetPoint("TOPLEFT", 16, notesTop)
  dialog.notes:SetPoint("TOPRIGHT", -16, notesTop)

  local notes = {}
  local given = view.notes or {}
  for i = 1, table.maxn(given) do  -- lines may be nil (a warning that doesn't apply)
    if given[i] then notes[#notes + 1] = given[i] end
  end
  dialog.notes:SetText(table.concat(notes, "\n"))
  -- Taller when the notes need it, never shorter than the purchase started.
  local height = buy.gain and DIALOG_HEIGHT + GAIN_ROW or DIALOG_HEIGHT
  local text = dialog.notes.GetStringHeight and dialog.notes:GetStringHeight()
  if type(text) == "number" then height = math.max(height, -notesTop + text + 48) end
  dialog:SetHeight(height)

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

local search, handOff, offer, matDone

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

--- How many writs or crates want the material: those held when the window opened plus
--- those bought (or planned) here, less the crates the bags' other materials fill.
local function leadsToFill()
  local w = buy.leadStep
  return math.max(0, buy.leadHeld + (w and (w.planned or 0) or 0) - (buy.otherFills or 0))
end

--- How many of the material those ask for, beyond what the bags hold.
local function materialNeed()
  return math.max(0, leadsToFill() * buy.count - buy.materialHeld)
end

--- "writ" or "writs", "crate" or "crates".
local function noun(n)
  return buy.noun .. (n == 1 and "" or "s")
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
  s.kind, s.auction, s.qty, s.queue, s.list, s.searchedAt = nil, nil, nil, nil, nil, nil
  -- The auction house's own key, from a scan or search in the last few minutes. An older
  -- one goes unanswered or answers with old listings: then browse for the item again.
  s.key = ns.ItemKey and ns.ItemKey(s.id, STALE)
  buy.waited, buy.seen, buy.late = 0, {}, false
  if s.material and buy.leadStep then
    s.need = materialNeed()
    if s.need == 0 then
      buy.state = "enough"
      return show({ status = "Nothing to buy.", qty = 0, action = "Done",
        notes = { ("In bags: %d. Enough."):format(buy.materialHeld) } })
    end
  end
  if s.forWrits then
    -- A recipient's material: only for the writs held, or bought in this window.
    local writs, count = 0, 0
    for _, f in ipairs(s.forWrits) do
      -- A writ handed to the game's window counts as bought: its purchase goes by mail.
      local w = f.step
      if not w or (w.got or 0) > 0 or w.handedOff then writs, count = writs + 1, count + f.count end
    end
    s.need = math.max(0, count - s.held)
    s.forNote = ns.Color(GREY, ("For %d writ%s: %d, minus %d in bags."):format(
      writs, writs == 1 and "" or "s", count, s.held))
    if s.need == 0 then
      buy.state = "enough"
      return show({ status = "Nothing to buy.", qty = 0, action = "Next", notes = {
        writs == 0 and "None of its writs were bought." or ("In bags: %d. Enough."):format(s.held) } })
    end
  end
  if s.target then s.need = s.target - s.got end  -- partway through: what is left
  -- A writ's or crate's step looks at its material's listings first (again once they
  -- are old): its own search then comes last, and stays the one its purchase goes by.
  -- Not where searches need a click each: that would cost the player one more.
  local m = s.lead and buy.matStep
  if m and (not buy.matAt or GetTime() - buy.matAt > STALE) and not searchNeedsClick then
    buy.matList = nil
    -- Without a fresh key of the auction house's own, browse for one first.
    buy.matKey = ns.ItemKey and ns.ItemKey(m.id, STALE)
    show({ status = "Searching...", qty = s.need })
    local ready = not AH.IsThrottledMessageSystemReady or AH.IsThrottledMessageSystemReady()
    if not buy.matKey then
      buy.state, buy.waited = "matbrowse0", 0
    elseif fromClick and ready then
      buy.state, buy.waited, buy.clickSent = "matwait", 0, true
      AH.SendSearchQuery(buy.matKey, sorts(), true)
    else
      buy.state, buy.waited = "matsend", 0
    end
    return
  end
  if not s.key then
    buy.state = "browse0"
    return show({ status = "Searching...", qty = s.need })
  end
  if fromClick then return sendSearch() end
  if searchNeedsClick then
    buy.state = "ask"
    return show({ status = "Click Look up.", qty = s.need, action = "Look up" })
  end
  buy.state = "send"
  show({ status = "Searching...", qty = s.need })
end

-- ---------------------------------------------------------------------------
-- Answers from the auction house
-- ---------------------------------------------------------------------------

--- What `want` costs from listings, cheapest first: { quantity, price, low, high }.
--- Every listing is { quantity, each }: for commodities the units at that price, for
--- items the writs listed at that price (each bought with its own click).
local function planList(list, want)
  local p = { quantity = 0, price = 0 }
  for _, l in ipairs(list or {}) do
    if p.quantity >= want then break end
    local take = math.min(want - p.quantity, l.quantity)
    p.quantity, p.price = p.quantity + take, p.price + take * l.each
    p.low = p.low or l.each
    p.high = l.each
  end
  return p
end

--- What `want` of the current step's item costs from its listings.
local function plan(s, want)
  return planList(s.list, want)
end

--- A commodity's listings, cheapest first, without the player's own; and how many in all.
local function commodityList(id)
  local list, listed = {}, 0
  for i = 1, AH.GetNumCommoditySearchResults(id) or 0 do
    local r = AH.GetCommoditySearchResultInfo(id, i)
    if r and r.unitPrice then
      local free = math.max(0, (r.quantity or 0) - (r.numOwnerItems or 0))
      if free > 0 then
        list[#list + 1] = { quantity = free, each = r.unitPrice }
        listed = listed + free
      end
    end
  end
  return list, listed
end

--- An item's auctions with a buyout, cheapest first, without the player's own; and how
--- many in all. On WoW Forever a result row stands for the writs listed at one price:
--- buyoutAmount is the price of one, quantity how many there are, and PlaceBid buys one
--- (a 47s row of 7 bought one writ for 47s).
local function itemList(itemKey)
  local list, listed = {}, 0
  for i = 1, AH.GetNumItemSearchResults(itemKey) or 0 do
    local r = AH.GetItemSearchResultInfo(itemKey, i)
    if r and r.buyoutAmount and r.buyoutAmount > 0 and not r.containsOwnerItem then
      local quantity = math.max(1, r.quantity or 1)
      list[#list + 1] = { auctionID = r.auctionID, each = r.buyoutAmount, quantity = quantity }
      listed = listed + quantity
    end
  end
  table.sort(list, function(a, b) return a.each < b.each end)
  return list, listed
end

--- How many of the listings are within NEAR of `expect` each.
local function nearCount(list, expect)
  local n = 0
  for _, l in ipairs(list) do
    if l.each <= expect * NEAR then n = n + l.quantity end
  end
  return n
end

--- The material to buy for `leads` writs or crates bought here: theirs and the ones in
--- the bags, less the crates other materials fill and the material in the bags.
local function materialFor(leads)
  return math.max(0, (buy.leadHeld + leads - (buy.otherFills or 0)) * buy.count - buy.materialHeld)
end

--- On a writ's or crate's step, from its listings and its material's: how many of them
--- are listed near the price the pages showed (`leadsNear`); how much of the material is
--- (`matNear`) and how many writs or crates that and the bags fill (`byMaterial`);
--- whether `want` of them needs more material than is listed near its price (`short`);
--- and what they would cost over those prices (`extra`), with `need` material of which
--- `matListed` are listed. nil while the material's listings are unknown.
local function materialCheck(s, want, p)
  local list = buy.matList
  if not list or not s.list or #s.list == 0 then return nil end
  local leadExpect = buy.leadExpect or s.list[1].each
  local matExpect = buy.matExpect or (list[1] and list[1].each)
  local leadsNear = nearCount(s.list, leadExpect)
  local matNear = matExpect and nearCount(list, matExpect) or 0
  -- The most writs or crates whose material the near listings (and the bags) cover.
  local byMaterial = math.floor((matNear + buy.materialHeld) / buy.count) - buy.leadHeld
    + (buy.otherFills or 0)
  local need = materialFor(want)
  local m = planList(list, need)
  local expected = p.quantity * leadExpect + m.quantity * (matExpect or 0)
  return {
    leadsNear = leadsNear,
    matNear = matNear,
    byMaterial = math.max(0, byMaterial),
    short = need > matNear,
    extra = p.price + m.price - expected,
    need = need,
    matListed = m.quantity,
  }
end

--- "35s each", or "35s to 1g each" when the prices differ.
local function eachRange(low, high)
  if not low then return nil end
  if math.floor(low) == math.floor(high) then return coins(low) .. " each" end
  return ("%s to %s each"):format(coins(low), coins(high))
end

--- After an old offer was searched again: the price it showed, when it changed.
local function wasNote(s, price)
  if not s.was then return nil end
  if price and math.floor(price) == math.floor(s.was) then
    return ns.Color(GREY, "Searched again: same price.")
  end
  return ns.Color(RED, ("Searched again: was %s."):format(coins(s.was)))
end

--- Keep the lowest price a purchase's search found as the item's price, the one the
--- pages compare (0: none listed).
local function record(s, key)
  local low
  for _, l in ipairs(s.list or {}) do
    if not low or l.each < low then low = l.each end
  end
  s.searchedAt = GetTime()
  if ns.RecordPrice then ns.RecordPrice(s.id, low or 0, key) end
end

--- Offer the current step from its listings.
function offer()
  local s = step()
  buy.state = "offer"
  local want = s.lead and s.want or s.need
  local p = plan(s, want)
  s.plan = p
  local notes = {}
  local check = s.lead and materialCheck(s, want, p)
  if check then
    local matName = buy.matStep.name
    notes[#notes + 1] = ns.Color(GREY, ("%d listed, %d at the scanned price."):format(
      s.listed, check.leadsNear))
    notes[#notes + 1] = ns.Color(GREY, ("%d %s at the scanned price (enough for %d %s)."):format(
      check.matNear, matName, check.byMaterial, noun(check.byMaterial)))
    if buy.leadHeld > 0 then
      notes[#notes + 1] = ns.Color(GREY, ("In bags: %d %s."):format(buy.leadHeld, noun(buy.leadHeld)))
    end
    if check.short and want > 0 then
      local warn = check.matListed < check.need
        and ("Not enough %s: %d listed, %d needed."):format(matName, check.matListed, check.need)
        or ("Not enough %s near the scanned price."):format(matName)
      if check.extra >= 1 then
        warn = warn .. (" %s more than expected."):format(coins(check.extra))
      end
      notes[#notes + 1] = ns.Color(RED, warn)
    end
  elseif s.lead then
    notes[#notes + 1] = ns.Color(GREY, ("%d listed. In bags: %d."):format(s.listed, buy.leadHeld))
  elseif p.quantity < want then
    notes[#notes + 1] = ns.Color(RED, ("Only %d listed."):format(p.quantity))
  end
  if s.kind == "item" and p.quantity > 1 then
    notes[#notes + 1] = ns.Color(GREY, "One click each.")
  end
  local each = p.quantity > 0 and eachRange(p.low, p.high)
  if each then notes[#notes + 1] = ns.Color(GREY, each) end
  notes[#notes + 1] = wasNote(s, p.quantity > 0 and p.price)
  notes[#notes + 1] = s.forNote
  notes[#notes + 1] = purse(p.price)
  if not s.lead and buy.leadStep then
    local leads = leadsToFill()
    notes[#notes + 1] = ns.Color(GREY, ("%d %s x %d, minus %d in bags."):format(
      leads, noun(leads), buy.count, buy.materialHeld))
    if (buy.otherFills or 0) > 0 then
      notes[#notes + 1] = ns.Color(GREY, ("Other materials in bags fill %d %s."):format(
        buy.otherFills, noun(buy.otherFills)))
    end
  end
  local action
  if p.quantity > 0 then
    action = (s.kind == "item" and p.quantity > 1) and ("Buy (1 of %d)"):format(p.quantity) or "Buy"
  end
  show({ pay = p.quantity > 0 and p.price or nil, about = s.kind == "commodity",
    status = "Set an amount.", qty = s.lead and want or p.quantity,
    edit = s.lead, notes = notes, action = action })
end

--- Listings of a commodity, cheapest first.
local function commodityResults()
  local s = step()
  s.kind = "commodity"
  s.list, s.listed = commodityList(s.id)
  record(s, s.key)
  if s.listed == 0 then
    buy.state = "none"
    return show({ status = ns.Color(GREY, "None listed."), qty = s.need, action = "Skip" })
  end
  if s.lead then s.want = math.min(s.want, s.listed) end
  offer()
end

--- Auctions of an item sold one at a time, cheapest first (see itemList).
local function itemResults(itemKey)
  local s = step()
  s.kind = "item"
  s.list, s.listed = itemList(itemKey)
  record(s, itemKey)
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
        wasNote(s, a.each), purse(a.each) } })
  end
  if s.lead then s.want = math.min(s.want, s.listed) end
  if bidBlocked then return handOff(s) end
  offer()
end

--- Hand an item sold one auction at a time to the game's own window, where the player
--- buys it with the game's Buyout button.
function handOff(s)
  buy.state = "handoff"
  s.handedOff = true
  if s.lead then s.planned = s.want end
  local want = s.lead and s.want or s.need
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
  s.auction, s.note, s.was = a, nil, nil
  buy.state, buy.waited, buy.seen, buy.error = "paying", 0, {}, nil
  -- The purchase first, the window after: nothing runs between the click and the
  -- protected call.
  C_AuctionHouse.PlaceBid(a.auctionID, a.each)
  if buy and buy.state == "paying" then
    show({ pay = a.each, qty = 1,
      notes = { ns.Color(GREY, ("Buying %d of %d..."):format(s.got + 1, s.target)) } })
  end
end

--- The price an offer shows: what Buy (or Confirm) would pay.
local function shownPrice(s, state)
  if state == "offer" then return s.plan and s.plan.quantity > 0 and s.plan.price or nil end
  if state == "confirm" then return s.total end
  if state == "next" then return s.nextAuction and s.nextAuction.each end
end

--- The Buy (or Confirm, Look up, Next, Done) button.
local function onBuy()
  local s = step()
  if not buy or not s then return end
  local state = buy.state
  if (state == "offer" or state == "confirm" or state == "next") and s.searchedAt
    and GetTime() - s.searchedAt > STALE then
    -- The listings are minutes old: search again and offer what is listed now.
    s.was = shownPrice(s, state)
    release()
    return search(true)
  end
  if state == "none" or state == "failed" or state == "handoff" or state == "enough" then
    return nextStep(true)
  elseif state == "ask" then
    return sendSearch()
  elseif state == "offer" and s.kind == "commodity" then
    local p = s.plan
    s.qty, s.estimate, s.was = p.quantity, p.price, nil
    if s.lead then s.planned = s.want end
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
    if s.lead then s.planned = s.want end
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

--- After the last purchase of a step: the listings the search found, less the `quantity`
--- just bought from the cheapest up. When that took every one at the lowest price, the
--- next price up (0: none left) is the item's price now, so the pages show it without
--- another search.
local function reprice(s, quantity)
  if not s.list or not ns.RecordPrice then return end
  local oldLow, newLow, left = nil, nil, quantity
  for _, l in ipairs(s.list) do  -- cheapest first
    if not oldLow or l.each < oldLow then oldLow = l.each end
    local take = math.min(left, l.quantity)
    left = left - take
    if l.quantity > take and (not newLow or l.each < newLow) then newLow = l.each end
  end
  if oldLow and newLow == oldLow then return end  -- more still listed at that price
  ns.RecordPrice(s.id, newLow or 0, s.key)
end

--- A purchase went through: count it; for auctions bought one at a time, search again
--- for the next while more are wanted.
local function bought(quantity)
  local s = step()
  buy.bought = buy.bought + quantity
  s.got = (s.got or 0) + quantity
  print(("%s: bought %d x %s."):format(ns.TITLE, quantity, s.name))
  if s.kind == "item" and s.target and s.got < s.target then return search() end
  reprice(s, quantity)
  nextStep()
end

--- The browse answer: the auction house's own key for the item, which the search then
--- uses (a key made with MakeItemKey can differ from it, and go unanswered).
local function browseResults(results)
  local s = step()
  local found
  for _, r in ipairs(results or {}) do
    if r.itemKey and r.itemKey.itemID == s.id then
      s.key, found = r.itemKey, r
      break
    end
  end
  if not s.key then
    if AH.HasFullBrowseResults and not AH.HasFullBrowseResults() then
      -- More pages: ask for the next (the driver sends it when the AH is ready); after a
      -- few, search with a made key instead.
      if AH.RequestMoreBrowseResults and (buy.pages or 0) < BROWSE_PAGES then
        buy.state, buy.waited = "browsemore", 0
      else
        buy.state, buy.waited, buy.seen = "send", 0, {}
      end
      return
    end
    if ns.RecordPrice then ns.RecordPrice(s.id, 0) end
    buy.state = "none"
    return show({ status = ns.Color(GREY, "None listed."), qty = s.need, action = "Skip" })
  end
  -- The price as a scan sees it; the search that follows refines it.
  if ns.RecordPrice then ns.RecordPrice(s.id, found.minPrice, s.key) end
  if searchNeedsClick then
    buy.state = "ask"
    return show({ status = "Click Look up.", qty = s.need, action = "Look up" })
  end
  buy.state, buy.waited, buy.seen = "send", 0, {}
end

--- The material's listings for a writ's or crate's step are in (nil: none came): keep
--- them, and their lowest price as the material's price, then search the writ or crate.
function matDone(list)
  buy.matList, buy.matAt = list, GetTime()
  if list and ns.RecordPrice then
    ns.RecordPrice(buy.matStep.id, list[1] and list[1].each or 0, buy.matKey)
  end
  search(false)
end

--- The browse answer for the material: its key, for the search; none listed when the
--- whole answer is in without it.
local function matBrowsed(results)
  local m = buy.matStep
  for _, r in ipairs(results or {}) do
    if r.itemKey and r.itemKey.itemID == m.id then
      buy.matKey, buy.state, buy.waited = r.itemKey, "matsend", 0
      return
    end
  end
  if AH.HasFullBrowseResults and not AH.HasFullBrowseResults() then
    if AH.RequestMoreBrowseResults and (buy.pages or 0) < BROWSE_PAGES then
      buy.state, buy.waited = "matbrowsemore", 0
    else
      buy.state, buy.waited = "matsend", 0
    end
    return
  end
  matDone({})
end

--- The material's listings, read straight from the auction house; for when the event
--- doesn't come.
local function pollMaterial()
  local m = buy.matStep
  if AH.GetNumCommoditySearchResults and (AH.GetNumCommoditySearchResults(m.id) or 0) > 0 then
    matDone((commodityList(m.id)))
  elseif AH.GetNumItemSearchResults and (AH.GetNumItemSearchResults(buy.matKey) or 0) > 0 then
    matDone((itemList(buy.matKey)))
  end
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
local SEARCHING = { browse0 = true, browse = true, browsemore = true, send = true, wait = true }
-- Looking at a writ's or crate's material before its own search.
local MATERIAL = { matbrowse0 = true, matbrowse = true, matbrowsemore = true, matsend = true, matwait = true }
local STAGES = {
  offer = "offering", quote = "asking the price", confirm = "confirming",
  paying = "buying", next = "between auctions", failed = "stopped", none = "nothing listed",
  wait = "searching", send = "searching", browse = "browsing", browse0 = "browsing", ask = "searching",
  browsemore = "browsing", matbrowsemore = "browsing the material",
  matbrowse0 = "browsing the material", matbrowse = "browsing the material",
  matsend = "searching the material", matwait = "searching the material",
}

local events = CreateFrame("Frame")
for _, event in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
  "COMMODITY_SEARCH_RESULTS_ADDED", "ITEM_SEARCH_RESULTS_ADDED",
  "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "AUCTION_HOUSE_BROWSE_FAILURE",
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
    if MATERIAL[where] then
      -- The material's search was blocked: go on without it.
      if not buy.clickSent then searchNeedsClick = true end
      return matDone(nil)
    end
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
  elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
    -- (A page asked for arrives as ADDED: the whole list so far is read either way.)
    if buy.state == "browse" then
      browseResults(AH.GetBrowseResults())
    elseif buy.state == "matbrowse" then
      matBrowsed(AH.GetBrowseResults())
    end
  elseif event == "AUCTION_HOUSE_BROWSE_FAILURE" then
    if buy.state == "browse" then buy.state, buy.waited = "send", 0 end
    if buy.state == "matbrowse" then buy.state, buy.waited = "matsend", 0 end
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
    if buy.state == "wait" and ... == s.id then
      commodityResults()
    elseif buy.state == "matwait" and ... == buy.matStep.id then
      matDone((commodityList(buy.matStep.id)))
    end
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
    local key = ...
    if buy.state == "wait" and type(key) == "table" and key.itemID == s.id then
      itemResults(key)
    elseif buy.state == "matwait" and type(key) == "table" and key.itemID == buy.matStep.id then
      matDone((itemList(key)))
    end
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
    local message = ns.Readable((select(2, ...)))
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
    buy.state, buy.waited, buy.clickSent, buy.pages = "browse", 0, false, 0
    local name = GetItemInfo and GetItemInfo(s.id)  -- the real name, not a stand-in
    if AH.SendBrowseQuery and name then
      s.name = name
      AH.SendBrowseQuery({ searchString = name, sorts = {}, filters = {}, itemClassFilters = {} })
    else
      buy.state = "send"
    end
  elseif buy.state == "matbrowse0" or buy.state == "matsend" then
    if not ready then
      if buy.waited > TIMEOUT then matDone(nil) end
      return
    end
    local m = buy.matStep
    local name = buy.state == "matbrowse0" and GetItemInfo and GetItemInfo(m.id)
    buy.waited, buy.clickSent = 0, false
    if name and AH.SendBrowseQuery then
      buy.state, buy.pages = "matbrowse", 0
      AH.SendBrowseQuery({ searchString = name, sorts = {}, filters = {}, itemClassFilters = {} })
    else
      buy.matKey = buy.matKey or AH.MakeItemKey(m.id)
      buy.state = "matwait"
      AH.SendSearchQuery(buy.matKey, sorts(), true)
    end
  elseif buy.state == "browsemore" or buy.state == "matbrowsemore" then
    local material = buy.state == "matbrowsemore"
    if not ready then
      if buy.waited > BROWSE_WAIT then buy.state, buy.waited = material and "matsend" or "send", 0 end
      return
    end
    buy.pages = (buy.pages or 0) + 1
    buy.state, buy.waited = material and "matbrowse" or "browse", 0
    AH.RequestMoreBrowseResults()
  elseif buy.state == "matbrowse" and buy.waited > BROWSE_WAIT then
    buy.state, buy.waited = "matsend", 0  -- no browse answer: search with a made key
  elseif buy.state == "matwait" then
    if buy.waited > 1.5 then pollMaterial() end
    if buy.state == "matwait" and buy.waited > TIMEOUT then matDone(nil) end
  elseif buy.state == "browse" and buy.waited > BROWSE_WAIT then
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

--- The writ or crate count typed in: kept between 0 and what is listed, and the offer redone.
local function setWant(value)
  local s = step()
  if not buy or buy.state ~= "offer" or not s or not s.lead then return end
  s.want = math.max(0, math.min(math.floor(tonumber(value) or 0), s.listed or 0))
  s.was = nil  -- another amount: the earlier price no longer compares
  offer()
end

--- The favor or reputation typed in: as many writs or crates as reach it.
local function setGain(value)
  local gain = buy and buy.gain
  if not gain then return end
  setWant(math.ceil((tonumber(value) or 0) / gain.each))
end

local function makeDialog()
  -- A child of the game's auction house window, like the buy buttons of other auction
  -- addons.
  local parent = AuctionHouseFrame or UIParent
  dialog = ns.Skin.Window("PuggerWaylaidCompanionBuy", parent, 440, DIALOG_HEIGHT, "Buy")
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

  -- The item: quantity (typed in for the lead), "x", icon, name, and Max for the lead.
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
    if s and s.lead then
      dialog.qty:ClearFocus()
      setWant(s.listed or 0)
    end
  end)

  dialog.name = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  dialog.name:SetPoint("LEFT", dialog.item, "RIGHT", 8, 0)
  dialog.name:SetPoint("RIGHT", dialog.max, "LEFT", -8, 0)
  dialog.name:SetJustifyH("LEFT")

  -- Below the item, for writs and crates: the reputation or favor they buy, typed in
  -- to buy as many as reach it.
  dialog.gain = CreateFrame("Frame", nil, dialog)
  dialog.gain:SetPoint("TOPLEFT", 16, NOTES_TOP + 4)
  dialog.gain:SetPoint("TOPRIGHT", -16, NOTES_TOP + 4)
  dialog.gain:SetHeight(GAIN_ROW)
  dialog.gain:Hide()
  dialog.gain.label = dialog.gain:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  dialog.gain.label:SetPoint("LEFT", 0, 0)
  dialog.gain.box = CreateFrame("EditBox", nil, dialog.gain, "InputBoxTemplate")
  dialog.gain.box:SetSize(60, 20)
  dialog.gain.box:SetPoint("LEFT", dialog.gain.label, "RIGHT", 12, 0)
  dialog.gain.box:SetAutoFocus(false)
  dialog.gain.box:SetNumeric(true)
  dialog.gain.box:SetMaxLetters(6)
  dialog.gain.box:SetJustifyH("CENTER")
  dialog.gain.box:SetScript("OnTextChanged", function(self, userInput)
    if userInput then setGain(self:GetText()) end
  end)
  dialog.gain.box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  dialog.gain.box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  -- Left: what the count it came to buys (fewer when not that many are listed).
  dialog.gain.box:SetScript("OnEditFocusLost", function(self)
    local s = step()
    if buy and buy.gain and s and s.lead then self:SetText(tostring((s.want or 0) * buy.gain.each)) end
  end)
  dialog.gain.each = dialog.gain:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  dialog.gain.each:SetPoint("LEFT", dialog.gain.box, "RIGHT", 10, 0)

  dialog.notes = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  dialog.notes:SetPoint("TOPLEFT", 16, NOTES_TOP)
  dialog.notes:SetPoint("TOPRIGHT", -16, NOTES_TOP)
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

-- Asked when a buy is clicked while a scan runs: stop the scan and buy, or keep scanning.
-- The addon's own small window, not the game's StaticPopup: those frames are shared with
-- the game's protected popups, and an addon's entry there can taint them.
local confirm

--- Ask whether to stop the scan and buy `what`; `again` starts the buy. Its button is a
--- click, as a purchase needs.
local function askStopScan(what, again)
  if not confirm then
    local Skin = ns.Skin
    confirm = Skin.Window("PuggerWaylaidCompanionStopScan", UIParent, 340, 124, "Scan running")
    confirm:SetPoint("CENTER", 0, 160)
    confirm:SetToplevel(true)
    confirm:SetFrameStrata("FULLSCREEN_DIALOG")
    confirm:EnableMouse(true)
    confirm:SetClampedToScreen(true)
    confirm:Hide()
    tinsert(UISpecialFrames, "PuggerWaylaidCompanionStopScan")
    confirm.text = confirm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    confirm.text:SetPoint("TOPLEFT", 16, -42)
    confirm.text:SetPoint("TOPRIGHT", -16, -42)
    confirm.text:SetJustifyH("CENTER")
    confirm.stop = Skin.Button(confirm, "Stop and buy", 140, 22)
    confirm.stop:SetPoint("BOTTOMLEFT", 16, 14)
    confirm.stop:SetScript("OnClick", function()
      local go = confirm.again
      confirm:Hide()
      if ns.StopScan then ns.StopScan() end
      if go then go() end
    end)
    confirm.keep = Skin.Button(confirm, "Keep scanning", 140, 22)
    confirm.keep:SetPoint("BOTTOMRIGHT", -16, 14)
    confirm.keep:SetScript("OnClick", function() confirm:Hide() end)
    confirm:SetScript("OnHide", function() confirm.again = nil end)
  end
  confirm.text:SetText(("The AH scan is still running.\nStop it to buy %s?"):format(what))
  confirm.again = again
  confirm:Show()
end

--- Whether buying can start now; says why not. While a scan runs, asks whether to stop it
--- and buy `what` (`again` starts the buy once it has stopped).
local function canStart(what, again)
  if not CAN then
    print(ns.TITLE .. ": no AH buying on this client.")
    return false
  end
  if not ns.AuctionHouseOpen() then
    print(ns.TITLE .. ": open the AH.")
    return false
  end
  if ns.ScanProgress().running then
    if again then
      askStopScan(what or "this", again)
    else
      print(ns.TITLE .. ": stop the scan.")
    end
    return false
  end
  if buy then finish(nil) end
  return true
end

--- Buy a list of materials, one step each: { { id, need, name }, ... }.
function ns.BuyMaterials(list)
  if not canStart("the missing material", function() ns.BuyMaterials(list) end) then return end
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

--- Buy a list of items, each as many as `need`, one step each: { { id, need, name,
--- material }, ... }, material true for those sold in bulk. `title` heads the window (the
--- Wishlist page's Buy missing).
function ns.BuyList(title, list)
  if not canStart(title:lower() .. " items", function() ns.BuyList(title, list) end) then return end
  local steps = {}
  for _, m in ipairs(list) do
    local name, icon = ns.Item(m.id, m.name)
    steps[#steps + 1] = { id = m.id, material = m.material or nil, name = name, icon = icon, need = m.need }
  end
  if #steps == 0 then return end
  if not dialog then makeDialog() end
  buy = { title = title, steps = steps, index = 1, bought = 0, waited = 0 }
  search(true)  -- the click on the button
end

--- Buy what writ recipients (stops from ns.Stops) want: one of each of their writs not
--- handed in today and not in the bags, then the material for those and the writs held,
--- less what the bags hold (writs asking for the same material share it, across
--- recipients too). `title` heads the window.
function ns.BuyForStops(stops, title)
  if not canStart("for " .. title, function() ns.BuyForStops(stops, title) end) then return end
  local writs = {}
  for _, stop in ipairs(stops) do
    for _, writ in ipairs(stop.writs) do writs[#writs + 1] = writ end
  end
  local steps, materials, order = {}, {}, {}
  for _, writ in ipairs(writs) do
    if ns.WritState(writ) ~= "done" then
      local writStep
      if ns.Count(writ.writItem) == 0 then
        local name, icon = ns.Item(writ.writItem, "Writ: " .. writ.name)
        writStep = { id = writ.writItem, name = name, icon = icon, need = 1 }
        steps[#steps + 1] = writStep
      end
      local m = materials[writ.item]
      if not m then
        local name, icon = ns.Item(writ.item, writ.name)
        m = { id = writ.item, name = name, icon = icon, held = ns.Count(writ.item), forWrits = {}, need = 0 }
        materials[writ.item] = m
        order[#order + 1] = m
      end
      m.forWrits[#m.forWrits + 1] = { step = writStep, count = writ.count }
    end
  end
  for _, m in ipairs(order) do
    local want = 0
    for _, f in ipairs(m.forWrits) do want = want + f.count end
    if want > m.held then steps[#steps + 1] = m end  -- else: the bags hold enough
  end
  if #steps == 0 then
    return print(("%s: everything for %s is in the bags."):format(ns.TITLE, title))
  end
  if not dialog then makeDialog() end
  buy = { title = title, steps = steps, index = 1, bought = 0, waited = 0 }
  search(true)  -- the click on the recipient's row or zone
end

--- Buy what one writ recipient wants (ns.BuyForStops).
function ns.BuyForStop(stop)
  ns.BuyForStops({ stop }, stop.npc.name)
end

--- Buy a writ or crate (the lead) and its material: the lead's count is set in the
--- window (one to start with when the bags hold none), the material follows it.
--- lead { id, name }, material { id, name, count (per lead) }; otherFills: leads that
--- other material in the bags fills already; gain { label, each }: the reputation or favor
--- one lead gives, nil when unknown.
local function buyWithMaterial(title, word, lead, material, otherFills, gain)
  local function again() buyWithMaterial(title, word, lead, material, otherFills, gain) end
  if not canStart(word == "writ" and ("the " .. title .. " writ") or title, again) then return end
  local held = ns.Count(lead.id)
  local leadName, leadIcon = ns.Item(lead.id, lead.name)
  local matName, matIcon = ns.Item(material.id, material.name)
  local leadStep = { id = lead.id, lead = true, name = leadName, icon = leadIcon,
    want = held == 0 and 1 or 0, need = held == 0 and 1 or 0 }
  local matStep = { id = material.id, material = true, name = matName, icon = matIcon, need = 0 }

  if not dialog then makeDialog() end
  buy = { title = title, noun = word, steps = { leadStep, matStep }, index = 1, bought = 0,
    waited = 0, leadStep = leadStep, leadHeld = held, materialHeld = ns.Count(material.id),
    count = material.count, otherFills = otherFills or 0, gain = gain, matStep = matStep,
    -- The prices the pages showed, which the searches here then replace.
    leadExpect = ns.Price(lead.id), matExpect = ns.Price(material.id) }
  search(true)  -- the click on the row
end

--- Buy writs and their material.
function ns.BuyForWrit(writ)
  buyWithMaterial(writ.name, "writ", { id = writ.writItem, name = "Writ: " .. writ.name },
    { id = writ.item, name = writ.name, count = writ.count }, nil,
    { label = "Reputation", each = ns.WRIT_REP[writ.tier] })
end

--- Buy crates and a material: `bundle` when given, else the cheapest by the prices known
--- now (the search for it then finds what it costs). The crates the bags' other materials
--- fill need none.
function ns.BuyForCrate(crate, bundle)
  bundle = bundle or ns.CrateCost(crate).cheapest
  if not bundle then
    -- No material has a price yet: the one the bags hold most crates' worth of, else
    -- the first.
    for _, b in ipairs(crate.bundles) do
      if not bundle or math.floor(ns.Count(b.item) / b.count) > math.floor(ns.Count(bundle.item) / bundle.count) then
        bundle = b
      end
    end
  end
  if not bundle then return end
  local favor = ns.CrateFavor(crate)
  local others = 0
  for _, b in ipairs(crate.bundles) do
    if b ~= bundle then others = others + math.floor(ns.Count(b.item) / b.count) end
  end
  buyWithMaterial("Waylaid Crate: " .. crate.name, "crate",
    { id = crate.item, name = "Waylaid Crate: " .. crate.name },
    { id = bundle.item, name = bundle.name, count = bundle.count }, others,
    (favor or 0) > 0 and { label = "Merchant's Favor", each = favor } or nil)
end
