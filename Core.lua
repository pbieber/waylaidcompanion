--[[
Pugger Waylaid Companion: Craftsman's Writs, Waylaid Crates and where they go.

This file is the part with no frames in it: the lists the pages and the map draw from,
what the player holds, and what is done for today. UI.lua is the window, Overview.lua its
first page, Map.lua the world map markers, Minimap.lua the minimap button, and Learn.lua
notes down turn-ins the shipped data does not know yet.
]]

local ADDON, ns = ...

ns.TITLE = "Pugger Waylaid Companion"
ns.ICON = "Interface/AddOns/PuggerWaylaidCompanion/Media/pugger"

--- The value, or nil when the game hands it out as a secret. Newer clients do that for
--- unit GUIDs and names in some windows and for chat text in combat, and an addon that
--- so much as indexes one is stopped with an error.
function ns.Readable(v)
  if v == nil then return nil end
  if issecretvalue and issecretvalue(v) then return nil end
  if canaccessvalue and not canaccessvalue(v) then return nil end
  return v
end

-- Writ tiers by index, as Data/Writs.lua stores them.
ns.WRIT_TIERS = { "Journeyman", "Expert", "Artisan" }
ns.WRIT_REP = { 75, 125, 200 }
-- Each writ turn-in gives a Coin Pouch (one item per tier, all named the same). What a pouch
-- pays, in copper, by tier: { low, high, average }. Rounded from 75 pouches opened in
-- November 2026 (Journeyman 20.62s to 48.81s, Expert 54.96s to 99.97s); the Artisan figures
-- rest on one pouch (1g 58s 78c) and are not confirmed yet.
ns.WRIT_POUCH = {
  { 2000, 5000, 3500 },
  { 5000, 10000, 7500 },
  { 10000, 20000, 15000, unconfirmed = true },
}
-- Crate tiers have one more rung below.
ns.CRATE_TIERS = { "Apprentice", "Journeyman", "Expert", "Artisan" }

ns.PROFESSIONS = { "Alchemy", "Blacksmithing", "Engineering", "Leatherworking", "Tailoring" }

-- Tier colours: the game's uncommon, rare and epic for the three writ tiers.
ns.WRIT_COLOR = { "ff1eff00", "ff0070dd", "ffa335ee" }
ns.CRATE_COLOR = { "ffffffff", "ff1eff00", "ff0070dd", "ffa335ee" }

function ns.Color(hex, text)
  return "|c" .. hex .. text .. "|r"
end

-- ---------------------------------------------------------------------------
-- The game's functions, under whichever name this client has them
-- ---------------------------------------------------------------------------

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local GetItemIcon = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
local IsQuestDone = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted

--- An item's name and icon. The name is the game's once it has loaded the item, until
--- then the one from the data.
function ns.Item(id, fallback)
  local name, _, _, _, _, _, _, _, _, icon
  if GetItemInfo then name, _, _, _, _, _, _, _, _, icon = GetItemInfo(id) end
  if not icon and GetItemIcon then icon = GetItemIcon(id) end
  return name or fallback or ("item " .. id), icon or "Interface/Icons/INV_Misc_QuestionMark"
end

--- How many of an item are in the bags (not the bank).
function ns.Count(id)
  return GetItemCount and GetItemCount(id) or 0
end

-- A character is saved by its name, "Name Surname" on WoW Forever (UnitName gives the
-- surname where other clients give the realm). The realm is left out: on WoW Forever it
-- is a layer ("CAMWOW EU5 Realm 6 PvP"), and a character moves between them.
local me  -- this character's key, once its surname has been read

--- This character's key: "Name Surname", or the name alone while the surname can't be
--- read (in combat, say) or the client has none.
local function character()
  if me then return me end
  local name, surname
  if UnitName then name, surname = UnitName("player") end
  name, surname = ns.Readable(name), ns.Readable(surname)
  if type(name) ~= "string" or name == "" then return "?" end
  if type(surname) == "string" and surname ~= "" then
    me = name .. " " .. surname
    return me
  end
  return name
end
ns.Character = character

--- A saved character key as shown: the first name.
function ns.CharacterName(key)
  return key:match("^(%S+)") or key
end

local bankOpen = false

--- How many of an item this character has, and where: { bags, bank, mail, total,
--- mailSeen }. The bank is what it held when last open, or the game's own count before
--- that. The mailbox is what was in it when it was last open; mailSeen is false until
--- it has been opened.
function ns.Holdings(id)
  local bags = ns.Count(id)
  local kept = ns.db and ns.db.bank and ns.db.bank[character()]
  local bank
  if kept and not bankOpen then
    bank = kept[id] or 0
  else
    bank = math.max(0, (GetItemCount and GetItemCount(id, true) or bags) - bags)
  end
  local seen = ns.db and ns.db.mail and ns.db.mail[character()]
  local mail = seen and seen[id] or 0
  return { bags = bags, bank = bank, mail = mail, total = bags + bank + mail, mailSeen = seen ~= nil }
end

-- The items whose count is kept for every character: the writs and what they ask for,
-- and the crates and their materials (the wishlist counts them on any character).
local tracked
local function trackedItems()
  if not tracked then
    tracked = {}
    for _, writ in ipairs(ns.writs) do
      tracked[writ.writItem], tracked[writ.item] = true, true
    end
    for _, crate in ipairs(ns.crates) do
      tracked[crate.item] = true
      for _, bundle in ipairs(crate.bundles) do tracked[bundle.item] = true end
    end
  end
  return tracked
end

--- Note what this character holds of the tracked items, so other characters on the
--- account can count it: the bags always, the bank while it is open.
function ns.SaveHoldings()
  local db = ns.db
  if not db or not GetItemCount then return end
  local key = character()
  local bags, bank = {}, bankOpen and {} or nil
  for id in pairs(trackedItems()) do
    local inBags = GetItemCount(id) or 0
    if inBags > 0 then bags[id] = inBags end
    if bank then
      local inBank = math.max(0, (GetItemCount(id, true) or inBags) - inBags)
      if inBank > 0 then bank[id] = inBank end
    end
  end
  db.bags[key] = bags
  if bank then db.bank[key] = bank end
  -- Saved before its surname was known (by an older version): the same character.
  local first = ns.CharacterName(key)
  if first ~= key then ns.AbsorbCharacter(db, first, key) end
end

--- A character's name as the game writes it to address mail: "Name Surname" on WoW
--- Forever; nil while its surname is unknown (until it is played with this addon).
function ns.MailAddress(key)
  if key:find(" ", 1, true) then return key end
end

--- Fold what is saved for one character under key `old` into key `new`: the bags, bank
--- and mailbox kept from `new` when it has its own (they are newer), the purchases added
--- up.
function ns.AbsorbCharacter(db, old, new)
  if old == new then return end
  for _, saved in ipairs({ db.bags, db.bank, db.mail }) do
    if saved[old] ~= nil then
      if saved[new] == nil then saved[new] = saved[old] end
      saved[old] = nil
    end
  end
  local from = db.spent[old]
  if not from then return end
  local to = db.spent[new] or {}
  db.spent[new] = to
  for day, items in pairs(from) do
    local into = to[day] or {}
    to[day] = into
    for id, entry in pairs(items) do
      local sum = into[id] or { 0, 0 }
      into[id] = sum
      sum[1], sum[2] = sum[1] + entry[1], sum[2] + entry[2]
    end
  end
  db.spent[old] = nil
end

--- Fold the scopes named "<realm>-<side>" in `saved` into "<side>", keeping the newer of
--- each entry (`newer(a, b)`: whether a is newer than b).
local function foldSides(saved, newer)
  local scopes = {}
  for scope in pairs(saved) do scopes[#scopes + 1] = scope end
  for _, scope in ipairs(scopes) do
    local side = type(scope) == "string" and scope:match("%-([^%-]+)$")
    if side then
      local into = saved[side] or {}
      saved[side] = into
      for k, v in pairs(saved[scope]) do
        if into[k] == nil or newer(v, into[k]) then into[k] = v end
      end
      saved[scope] = nil
    end
  end
end

--- Saved data from before 0.11.0, keyed by realm: characters by "Name-Realm" become
--- "Name Surname" (the name alone where the surname wasn't seen), prices and scan times
--- by "Realm-H" become "H", the newest of each realm's kept.
local function dropRealms(db)
  local old = {}
  for _, saved in ipairs({ db.bags, db.bank, db.mail, db.spent, db.surnames or {} }) do
    for key in pairs(saved) do
      if type(key) == "string" and key:find("-", 1, true) then old[key] = true end
    end
  end
  for key in pairs(old) do
    local name = key:match("^(.-)%-")
    local surname = db.surnames and db.surnames[key]
    ns.AbsorbCharacter(db, key, surname and (name .. " " .. surname) or name)
  end
  db.surnames = nil
  foldSides(db.prices, function(a, b) return a[2] > b[2] end)
  foldSides(db.scanTimes, function(a, b) return a > b end)
end

--- Whether another character the account has saved shares this one's first name (on
--- another realm, say).
local function nameShared(key)
  local db = ns.db
  if not db then return false end
  local name = ns.CharacterName(key)
  for _, source in ipairs({ db.bags or {}, db.bank or {}, db.mail or {} }) do
    for other in pairs(source) do
      if other ~= key and ns.CharacterName(other) == name then return true end
    end
  end
  return false
end

--- A character as the pages show it: first name, or first name and surname with "Show
--- both names" ticked or when another character has the same first name (where the
--- surname is known).
function ns.ShownName(key)
  if ns.db and (ns.db.ownerNames == 2 or nameShared(key)) then
    return ns.MailAddress(key) or ns.CharacterName(key)
  end
  return ns.CharacterName(key)
end

--- How many of an item the whole account has: { total, chars = { { key, name, bags,
--- bank, mail, total, mailSeen, current }, ... } }, holding characters only, this one
--- first and then the most first. Other characters count as they were last logged in.
function ns.AccountHoldings(id)
  local me = character()
  local result = { total = 0, chars = {} }
  local function add(key, h)
    if h.total <= 0 then return end
    h.key, h.name, h.current = key, ns.ShownName(key), key == me
    result.total = result.total + h.total
    result.chars[#result.chars + 1] = h
  end
  add(me, ns.Holdings(id))
  local db = ns.db
  if db then
    local keys = {}
    for _, source in ipairs({ db.bags, db.bank, db.mail }) do
      for key in pairs(source) do
        if key ~= me then keys[key] = true end
      end
    end
    for key in pairs(keys) do
      local bags = db.bags[key] and db.bags[key][id] or 0
      local bank = db.bank[key] and db.bank[key][id] or 0
      local seen = db.mail[key]
      local mail = seen and seen[id] or 0
      add(key, { bags = bags, bank = bank, mail = mail, total = bags + bank + mail, mailSeen = seen ~= nil })
    end
  end
  table.sort(result.chars, function(a, b)
    if a.current ~= b.current then return a.current end
    if a.total ~= b.total then return a.total > b.total end
    return a.key < b.key
  end)
  return result
end

local mailOpen = false
--- Whether two { [item] = count } tables hold the same.
local function sameCounts(a, b)
  if not a or not b then return a == b end
  for id, n in pairs(a) do if b[id] ~= n then return false end end
  for id in pairs(b) do if a[id] == nil then return false end end
  return true
end

--- Note what the open mailbox holds, per item. Only the mails the game lists are counted.
--- Whether that changed: the game sends the inbox update many times a second while the
--- mailbox is open, and redrawing the pages each time stalls the game.
local function scanMail()
  if not mailOpen or not ns.db or not GetInboxNumItems or not GetInboxItem then return false end
  local held = {}
  for index = 1, GetInboxNumItems() or 0 do
    for slot = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
      local _, id, _, count = GetInboxItem(index, slot)
      if type(id) ~= "number" then
        local link = GetInboxItemLink and GetInboxItemLink(index, slot)
        id = link and tonumber(link:match("item:(%d+)"))
      end
      if id then held[id] = (held[id] or 0) + (tonumber(count) or 1) end
    end
  end
  local key = character()
  if sameCounts(ns.db.mail[key], held) then return false end
  ns.db.mail[key] = held
  return true
end

-- ---------------------------------------------------------------------------
-- Prices
-- ---------------------------------------------------------------------------

local function auctionator()
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  return api and api.GetAuctionPriceByItemID and api or nil
end

-- A price last seen this many days ago, or longer, counts as old.
ns.OLD_PRICE_DAYS = 3

local function now()
  return time and time() or os.time()
end

--- The prices this addon's own auction house scans found, for the auction house the
--- player uses (each side has its own; WoW Forever's realms are layers): { [item] =
--- { copper, when } }, where copper 0 means nothing was listed.
function ns.ScannedPrices()
  local db = ns.db
  if not db then return nil end
  local scope = ns.Side() or "?"
  db.prices[scope] = db.prices[scope] or {}
  return db.prices[scope]
end

--- When a scan of each list last ran to its end, for the auction house the player uses:
--- { writs = when, crates = when }.
function ns.ScanTimes()
  local db = ns.db
  if not db then return nil end
  local scope = ns.Side() or "?"
  db.scanTimes[scope] = db.scanTimes[scope] or {}
  return db.scanTimes[scope]
end

--- Whether there is anywhere to get prices: Auctionator, or a scan of our own.
function ns.HasPrices()
  return auctionator() ~= nil or next(ns.ScannedPrices() or {}) ~= nil
end

--- What one of an item costs on the auction house, in copper, and how many days ago that
--- price was seen (nil when unknown). The newer of our own scan and Auctionator's;
--- nil when neither has seen one listed.
function ns.PriceInfo(id)
  local own = (ns.ScannedPrices() or {})[id]
  local ownPrice = own and own[1] > 0 and own[1] or nil
  local ownDays = own and math.max(0, math.floor((now() - own[2]) / 86400)) or nil

  local api, aucPrice, aucDays = auctionator(), nil, nil
  if api then
    local ok, price = pcall(api.GetAuctionPriceByItemID, ADDON, id)
    if ok and type(price) == "number" and price > 0 then aucPrice = price end
    if aucPrice and api.GetAuctionAgeByItemID then
      local okAge, days = pcall(api.GetAuctionAgeByItemID, ADDON, id)
      if okAge and type(days) == "number" and days >= 0 then aucDays = days end
    end
  end

  if ownPrice and (not aucPrice or aucDays == nil or ownDays <= aucDays) then
    return ownPrice, ownDays
  end
  if aucPrice then return aucPrice, aucDays end
  return nil, nil
end

--- What one of an item costs on the auction house, in copper; nil when there is no price.
function ns.Price(id)
  return (ns.PriceInfo(id))
end

--- How many days ago an item's price was seen (0 for today); nil when it can't say.
function ns.PriceAge(id)
  local _, days = ns.PriceInfo(id)
  return days
end

--- Copper as coloured "12g 34s 56c", leaving out the parts that are zero.
--- Money with the game's coin icons: "1 [gold] 20 [silver]"; plain text where the game
--- has no such string.
function ns.Coins(copper)
  copper = math.floor((copper or 0) + 0.5)
  if GetMoneyString then
    local ok, text = pcall(GetMoneyString, copper, true)
    if ok and type(text) == "string" then return text end
  end
  return ns.Money(copper)
end

function ns.Money(copper)
  copper = math.floor(copper + 0.5)
  local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local parts = {}
  if gold > 0 then parts[#parts + 1] = ns.Color("ffffd100", gold .. "g") end
  if silver > 0 then parts[#parts + 1] = ns.Color("ffc7c7cf", silver .. "s") end
  if rest > 0 or #parts == 0 then parts[#parts + 1] = ns.Color("ffeda55f", rest .. "c") end
  return table.concat(parts, " ")
end

--- ns.Coins, with a green "-" in front of an amount below 0: a writ whose Coin Pouch, or a
--- crate whose quest reward silver, pays more than it and its material cost.
function ns.SignedCoins(copper)
  if copper and copper <= -0.5 then return ns.Color("ff40d040", "-") .. ns.Coins(-copper) end
  return ns.Coins(math.max(0, copper or 0))
end

--- What a writ costs to do from nothing: { writ, each, material (each x count), total
--- (of the parts with a price), partial (a part has none), age (days since the oldest
--- of its prices was seen, nil when unknown), old (that is OLD_PRICE_DAYS or more),
--- pouch (the Coin Pouch's average silver; 0 with that option off), net (total less the
--- pouch, below 0 when the pouch pays more; nil when no part has a price),
--- perRep (net for each point of reputation; nil when no part has a price) }.
function ns.WritCost(writ)
  local paper, paperAge = ns.PriceInfo(writ.writItem)
  local each, eachAge = ns.PriceInfo(writ.item)
  local material = each and each * writ.count
  local age
  for _, days in ipairs({ paper and paperAge or false, each and eachAge or false }) do
    if days and (not age or days > age) then age = days end
  end
  local total = (paper or 0) + (material or 0)
  local pouch = (not ns.db or ns.db.writPouch ~= false) and ns.WRIT_POUCH[writ.tier][3] or 0
  local net = (paper or material) and total - pouch or nil
  return {
    writ = paper, each = each, material = material,
    total = total, partial = not (paper and material),
    age = age, old = age ~= nil and age >= ns.OLD_PRICE_DAYS,
    pouch = pouch, net = net,
    perRep = net and net / ns.WRIT_REP[writ.tier] or nil,
  }
end

--- What a crate costs to fill from nothing with each of its bundles, and with the
--- cheapest of them that has a price.
---
--- { crate (the empty crate's price), favor (the Merchant's Favor it pays), refund (the
---   quest reward silver; 0 with that option off),
---   bundles = { [bundle] = part }, cheapest (the cheapest bundle,
---   nil when none has a price), and the cheapest's part fields }
---
--- Each part: { each, material (each x count), total (crate and material, of what has a
--- price), partial (the crate or the material has no price), age (days since the older
--- of the two prices was seen), old (that is OLD_PRICE_DAYS or more), net (total less
--- the refund, below 0 when the refund pays more; nil without a price), perFavor (net for each Merchant's
--- Favor; nil without a price or a favor amount) }.
function ns.CrateCost(crate)
  local box, boxAge = ns.PriceInfo(crate.item)
  local favor = ns.CrateFavor(crate)
  local refund = (not ns.db or ns.db.crateRefund ~= false) and ns.CrateRefund(crate) or 0
  local cost = { crate = box, favor = favor, refund = refund, bundles = {} }
  for _, b in ipairs(crate.bundles) do
    local each, eachAge = ns.PriceInfo(b.item)
    local material = each and each * b.count
    local age
    for _, days in ipairs({ box and boxAge or false, each and eachAge or false }) do
      if days and (not age or days > age) then age = days end
    end
    local total = (box or 0) + (material or 0)
    local part = {
      each = each, material = material, total = total, partial = not (box and material),
      age = age, old = age ~= nil and age >= ns.OLD_PRICE_DAYS,
      net = (box or material) and total - refund or nil,
    }
    part.perFavor = favor and part.net and part.net / favor or nil
    cost.bundles[b] = part
    if material and (not cost.cheapest or material < cost.bundles[cost.cheapest].material) then
      cost.cheapest = b
    end
  end
  local best = cost.cheapest and cost.bundles[cost.cheapest]
  if best then
    for key, value in pairs(best) do cost[key] = value end
  else
    -- No material has a price: the crate alone, if that has one.
    cost.total, cost.partial = box or 0, true
    cost.age = box and boxAge or nil
    cost.old = cost.age ~= nil and cost.age >= ns.OLD_PRICE_DAYS
    cost.net = box and box - refund or nil
    cost.perFavor = favor and cost.net and cost.net / favor or nil
  end
  return cost
end

--- True once a writ's quest has been handed in today. The writs are daily quests, so
--- the game's "completed" flag for one clears at the daily reset.
function ns.DoneToday(quest)
  return IsQuestDone and IsQuestDone(quest) and true or false
end

-- "A" or "H", nil before the game knows (or for a neutral character).
function ns.Side()
  local group = UnitFactionGroup and UnitFactionGroup("player")
  if group == "Alliance" then return "A" end
  if group == "Horde" then return "H" end
  return nil
end

-- ---------------------------------------------------------------------------
-- Writs
-- ---------------------------------------------------------------------------

ns.writs = {}
ns.writByQuest = {}
for _, row in ipairs(ns.WRITS) do
  local writ = {
    quest = row[1], writItem = row[2], item = row[3], count = row[4],
    profession = row[5], tier = row[6], skill = row[7], npc = row[8], side = row[9],
    name = row[10],
  }
  ns.writs[#ns.writs + 1] = writ
  ns.writByQuest[writ.quest] = writ
end

-- What players have recorded in game and scripts/bake_waylaid.py has written into
-- Data/Recorded.lua: places (an NPC id, or "at:map:x:y" for a spot nobody has named yet)
-- and which writ goes to which.
for id, place in pairs(ns.RECORDED_NPCS or {}) do
  if not ns.WRIT_NPCS[id] then ns.WRIT_NPCS[id] = place end
end
for quest, id in pairs(ns.RECORDED_WRITS or {}) do
  local writ = ns.writByQuest[quest]
  if writ and not writ.npc and ns.WRIT_NPCS[id] then writ.npc = id end
end

--- Whether a writ the data limits to one side has been had on the other: by this account,
--- by a player who shared it, or as recorded in Data/Recorded.lua.
function ns.AnySide(quest)
  return (ns.db ~= nil and ns.db.anySide[quest] == true)
    or (ns.RECORDED_ANYSIDE ~= nil and ns.RECORDED_ANYSIDE[quest] == true)
end

--- Whether the player's side can do a writ. A few are limited to one side, going by data
--- that is not always right: a writ had on the other side counts too (ns.AnySide).
function ns.ForPlayer(writ)
  local side = ns.Side()
  if writ.side == nil or side == nil or writ.side == side then return true end
  return ns.AnySide(writ.quest)
end

--- Where a writ is handed in: { id, name, map, x, y, zone }, from the shipped data or
--- from what this account has recorded; nil when neither knows.
function ns.WritNpc(writ)
  local db = ns.db
  -- A shipped NPC first, then what this account recorded, then a shipped unnamed spot.
  local id = (type(writ.npc) == "number" and writ.npc) or (db and db.writNpc[writ.quest]) or writ.npc
  if not id then return nil end
  local n = (db and db.npcs[id]) or ns.WRIT_NPCS[id]
  if not n then return nil end
  return { id = id, name = n[1], map = n[2], x = n[3], y = n[4], zone = n[5] }
end

local continents = {}
--- The continent a map is on: its name and map id ("Elsewhere", 0 when the game can't say).
function ns.Continent(map)
  local known = continents[map]
  if known then return known[1], known[2] end
  local name, id = "Elsewhere", 0
  local at, steps = map, 0
  while at and at > 0 and steps < 10 and C_Map and C_Map.GetMapInfo do
    local info = C_Map.GetMapInfo(at)
    if not info then break end
    if info.mapType == 2 then
      name, id = info.name, at
      break
    end
    at, steps = info.parentMapID, steps + 1
  end
  if id ~= 0 then continents[map] = { name, id } end
  return name, id
end

--- "holding" the writ, and "ready" when the requested items are in the bags too.
function ns.WritState(writ)
  if ns.DoneToday(writ.quest) then return "done" end
  if ns.Count(writ.writItem) > 0 then
    if ns.Count(writ.item) >= writ.count then return "ready" end
    return "holding"
  end
  return "open"
end

--- Every place writs are handed in, each with its writs (the player's side only),
--- sorted by zone then name: { npc = {...}, writs = {...}, open = n, held = n }.
function ns.Stops()
  local byId, stops = {}, {}
  for _, writ in ipairs(ns.writs) do
    local npc = ns.ForPlayer(writ) and ns.WritNpc(writ)
    if npc then
      local stop = byId[npc.id]
      if not stop then
        stop = { npc = npc, writs = {}, open = 0, held = 0 }
        byId[npc.id] = stop
        stops[#stops + 1] = stop
      end
      stop.writs[#stop.writs + 1] = writ
      local state = ns.WritState(writ)
      if state ~= "done" then stop.open = stop.open + 1 end
      if state == "holding" or state == "ready" then stop.held = stop.held + 1 end
    end
  end
  for _, stop in ipairs(stops) do
    table.sort(stop.writs, function(a, b)
      if a.tier ~= b.tier then return a.tier < b.tier end
      return a.name < b.name
    end)
  end
  table.sort(stops, function(a, b)
    if a.npc.zone ~= b.npc.zone then return a.npc.zone < b.npc.zone end
    return a.npc.name < b.npc.name
  end)
  return stops
end

--- How many of the player's writs have a known turn-in, and how many there are.
function ns.KnownTurnIns()
  local known, total = 0, 0
  for _, writ in ipairs(ns.writs) do
    if ns.ForPlayer(writ) then
      total = total + 1
      if ns.WritNpc(writ) then known = known + 1 end
    end
  end
  return known, total
end

-- ---------------------------------------------------------------------------
-- Crates
-- ---------------------------------------------------------------------------

ns.crates = {}
for _, row in ipairs(ns.CRATES) do
  local crate = { item = row[1], tier = row[2], kind = row[3], name = row[4], bundles = {},
    quality = ns.CRATE_QUALITY[row[3]] or 1 }
  for _, b in ipairs(row[5]) do
    crate.bundles[#crate.bundles + 1] = { item = b[1], count = b[2], name = b[3] }
  end
  ns.crates[#ns.crates + 1] = crate
end

--- The Merchant's Favor a crate pays when handed in filled: its tier's amount for its
--- quality (white or green). nil when unknown.
function ns.CrateFavor(crate)
  local pays = ns.CRATE_FAVOR[crate.tier]
  return pays and pays[crate.quality] or nil
end

--- The money handing in a filled crate pays, in copper: half its favor in silver.
function ns.CrateRefund(crate)
  return (ns.CrateFavor(crate) or 0) * ns.CRATE_COPPER_PER_FAVOR
end

--- The player's crate turn-in: { id, name, map, x, y, zone, faction }, nil for no side.
function ns.Camp()
  local c = ns.CAMPS[ns.Side() or ""]
  if not c then return nil end
  return { id = c[1], name = c[2], map = c[3], x = c[4], y = c[5], zone = c[6], faction = c[7] }
end

-- ---------------------------------------------------------------------------
-- Reputation
-- ---------------------------------------------------------------------------

-- The trade factions' ids, and how much reputation each standing (1 Hated .. 7 Revered)
-- holds before the next.
local FACTION_ID = { A = 2586, H = 2587 }
local STANDING_SIZE = { 36000, 3000, 3000, 3000, 6000, 12000, 21000 }
local STANDING_NAME = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
local EXALTED = 8

local function readFaction(id)
  if not id then return nil end
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local d = C_Reputation.GetFactionDataByID(id)
    if d and d.name then
      return d.name, d.reaction, d.currentReactionThreshold, d.nextReactionThreshold, d.currentStanding
    end
  end
  if GetFactionInfoByID then
    local name, _, standing, low, high, value = GetFactionInfoByID(id)
    if name then return name, standing, low, high, value end
  end
  return nil
end

function ns.StandingName(standing)
  return _G["FACTION_STANDING_LABEL" .. standing] or STANDING_NAME[standing] or "?"
end

--- The player's standing with their trade faction: { name, standing, low, high, value
--- (reputation in total, with low and high the ends of the current standing), toNext,
--- toExalted, exalted, unknown (the game has no standing yet) }. nil for no side.
function ns.Reputation()
  local camp = ns.Camp()
  if not camp then return nil end
  -- The side's own id first; the other one in case the ids are the other way round.
  local side = ns.Side()
  local standing, low, high, value
  for _, id in ipairs({ FACTION_ID[side], FACTION_ID[side == "A" and "H" or "A"] }) do
    local n, s, l, h, v = readFaction(id)
    if n == camp.faction then
      standing, low, high, value = s, l, h, v
      break
    end
  end
  local rep = { name = camp.faction }
  if standing and low and high and value then
    rep.standing, rep.low, rep.high, rep.value = standing, low, high, value
  else
    rep.standing, rep.low, rep.high, rep.value, rep.unknown = 4, 0, 3000, 0, true
  end
  rep.exalted = rep.standing >= EXALTED
  if rep.exalted then
    rep.toNext, rep.toExalted = 0, 0
  else
    rep.toNext = math.max(0, rep.high - rep.value)
    rep.toExalted = rep.toNext
    for s = rep.standing + 1, EXALTED - 1 do rep.toExalted = rep.toExalted + STANDING_SIZE[s] end
  end
  return rep
end

--- What is left to hand in today, per writ tier and in all:
--- { [tier] = { open, total, rep }, open = n, total = n, rep = n }.
function ns.Today()
  local today = { open = 0, total = 0, rep = 0 }
  for tier = 1, #ns.WRIT_TIERS do today[tier] = { open = 0, total = 0, rep = 0 } end
  for _, writ in ipairs(ns.writs) do
    if ns.ForPlayer(writ) then
      local t = today[writ.tier]
      t.total, today.total = t.total + 1, today.total + 1
      if not ns.DoneToday(writ.quest) then
        local gain = ns.WRIT_REP[writ.tier]
        t.open, today.open = t.open + 1, today.open + 1
        t.rep, today.rep = t.rep + gain, today.rep + gain
      end
    end
  end
  return today
end

--- What reaching `goal` reputation through writs roughly costs, handing in at most
--- `perDay` writs a day (nil: every writ there is), the cheapest per rep first.
---
--- Each writ is a daily, so a day offers each of the player's writs once; the first day
--- only those not handed in today. A day takes the perDay cheapest, and the last day
--- only as many of those as the goal still needs. Writs with a whole price go first,
--- then those with a price for one part, then those with none. A writ's cost is what
--- ns.WritCost nets: the writ and its material, less the coin pouch while that option
--- is on.
---
--- { cost (copper), days, writs (handed in), rep, daily (the rep a full day brings),
---   partial (a writ used has no price, or a price for one part only), old (a price
---   used is OLD_PRICE_DAYS or more old), none (no writ to hand in) }
function ns.WritPlan(goal, perDay)
  local list = {}
  for _, writ in ipairs(ns.writs) do
    if ns.ForPlayer(writ) then
      local c = ns.WritCost(writ)
      local rank = (not c.net and 3) or (c.partial and 2) or 1
      list[#list + 1] = { writ = writ, cost = c, rank = rank, rep = ns.WRIT_REP[writ.tier],
        perRep = c.perRep or 0, done = ns.DoneToday(writ.quest) }
    end
  end
  table.sort(list, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.perRep ~= b.perRep then return a.perRep < b.perRep end
    return a.writ.quest < b.writ.quest
  end)
  local plan = { cost = 0, days = 0, writs = 0, rep = 0, daily = 0, partial = false, old = false }
  local take = perDay and math.min(perDay, #list) or #list
  for i = 1, take do plan.daily = plan.daily + list[i].rep end
  if goal <= 0 then return plan end
  if plan.daily == 0 then plan.none = true return plan end
  local function hand(e)
    plan.writs, plan.rep = plan.writs + 1, plan.rep + e.rep
    plan.cost = plan.cost + (e.cost.net or 0)
    if e.rank > 1 then plan.partial = true end
    if e.cost.old then plan.old = true end
  end
  -- The first day: the writs still open today.
  plan.days = 1
  local n = 0
  for _, e in ipairs(list) do
    if plan.rep >= goal or (perDay and n >= perDay) then break end
    if not e.done then
      hand(e)
      n = n + 1
    end
  end
  -- Then whole days of the cheapest `take`, while the goal is more than a day away...
  local dayCost, dayOld, dayPartial = 0, false, false
  for i = 1, take do
    local e = list[i]
    dayCost = dayCost + (e.cost.net or 0)
    dayOld = dayOld or e.cost.old
    dayPartial = dayPartial or e.rank > 1
  end
  if plan.rep < goal then
    local whole = math.floor((goal - plan.rep) / plan.daily)
    if whole > 0 then
      plan.days = plan.days + whole
      plan.writs = plan.writs + whole * take
      plan.rep = plan.rep + whole * plan.daily
      plan.cost = plan.cost + whole * dayCost
      plan.old = plan.old or dayOld
      plan.partial = plan.partial or dayPartial
    end
  end
  -- ...and a last day of as many as are still needed.
  if plan.rep < goal then
    plan.days = plan.days + 1
    for i = 1, take do
      if plan.rep >= goal then break end
      hand(list[i])
    end
  end
  return plan
end

-- ---------------------------------------------------------------------------
-- Saved settings, and telling the pages something changed
-- ---------------------------------------------------------------------------

-- ownerNames: 2 shows characters by first name and surname ("Show both names"), 1 by first name.
-- writCost and crateCost: "per" shows a cost per repScale reputation or per favorScale
-- Merchant's Favor, "total" what a writ or crate costs in all. crateRefund: a crate's cost
-- is less its quest reward silver. writPouch: a writ's cost is less its Coin Pouch's
-- average silver (ns.WRIT_POUCH). itemColor: "tier" colours
-- writ and crate names by tier, "rarity" in the game's colour for the item. theme: "modern"
-- draws the windows flat and dark, "classic" with the game's own frames (Theme.lua).
-- pins: the world map's turn-in markers are shown (also the minimap button's right-click);
-- pinSize their size, 1 the normal; pinZoom: they grow as the map zooms in (Map.lua).
-- ttWrit, ttCrate and ttWrit*/ttCrate* (Tooltips.lua): the tooltip lines, on unless false.
local DEFAULTS = { page = "overview", writSort = "level", crateSort = "level", turninSort = "name", pins = true, ownerNames = 1,
  pinSize = 1, pinZoom = true,
  writCost = "per", crateCost = "per", repScale = 100, favorScale = 1, crateRefund = true, writPouch = true,
  itemColor = "tier", wishClick = "right", turninRows = "npc",
  theme = "modern", mailWhat = "writs" }

local listeners = {}
--- Call fn whenever what the pages show may have changed (bags, quests, item names).
function ns.OnChange(fn)
  listeners[#listeners + 1] = fn
end

local pending = false
--- Tell the listeners, once, shortly: bag and item events come in bursts.
function ns.Changed()
  if pending then return end
  pending = true
  C_Timer.After(0.2, function()
    pending = false
    ns.SaveHoldings()
    for _, fn in ipairs(listeners) do fn() end
  end)
end

local loaded = {}
--- Call fn once the saved settings are in ns.db.
function ns.WhenLoaded(fn)
  loaded[#loaded + 1] = fn
end

if not CreateFrame then return end

-- Events that mean a writ's quest, or its point on the map, may have just arrived.
local QUEST_EVENTS = { PLAYER_ENTERING_WORLD = true, QUEST_ACCEPTED = true, QUEST_LOG_UPDATE = true, QUEST_POI_UPDATE = true }

local events = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "BAG_UPDATE", "QUEST_TURNED_IN", "GET_ITEM_INFO_RECEIVED",
  "UPDATE_FACTION", "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED", "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE",
  "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_CLOSED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED" }) do
  -- Registering an event this client does not have is an error.
  pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    PuggerWaylaidCompanionDB = PuggerWaylaidCompanionDB or {}
    local db = PuggerWaylaidCompanionDB
    -- Map markers sized pinScale (0.9.0 before release) were half again as big at 1: the
    -- same size on the map in pinSize, whose normal (1) is the old 65%.
    if db.pinScale and not db.pinSize then
      db.pinSize = math.max(0.25, math.min(2, math.floor(db.pinScale / 0.65 * 20 + 0.5) / 20))
    end
    db.pinScale = nil
    for key, value in pairs(DEFAULTS) do
      if db[key] == nil then db[key] = value end
    end
    db.npcs = db.npcs or {}
    db.writNpc = db.writNpc or {}
    db.minimap = db.minimap or { angle = 215, hide = false }
    -- What crates were seen to pay, kept before the amounts were shipped (0.6.0).
    db.favor = nil
    db.mail = db.mail or {}
    db.anySide = db.anySide or {}
    -- Per character ("Name Surname"): the tracked items in the bags, and in the bank as it
    -- was when last open. Prices are per auction house ("A" / "H").
    db.bags = db.bags or {}
    db.bank = db.bank or {}
    db.prices = db.prices or {}
    db.scanTimes = db.scanTimes or {}
    -- Folded groups on the list pages, by "page:sort:group".
    db.collapsed = db.collapsed or {}
    -- The order a page's columns were dragged into, by page: { [page] = { 3, 1, 2, ... } }.
    db.columns = db.columns or {}
    -- What each character spent at the auction house on writs, crates and their
    -- materials, by day (Spent.lua): { ["Name Surname"] = { ["2026-11-16"] = { [item] = { count, copper } } } }.
    db.spent = db.spent or {}
    dropRealms(db)
    ns.db = db
    for _, fn in ipairs(loaded) do fn() end
    return
  end
  -- The inbox only fills in after MAIL_SHOW, and reads as empty once it is closed.
  if event == "MAIL_SHOW" then mailOpen = true return end
  if event == "MAIL_CLOSED" then mailOpen = false return end
  -- The bank is noted while it is open; closing it keeps what was noted.
  if event == "BANKFRAME_OPENED" then bankOpen = true end
  if event == "BANKFRAME_CLOSED" then
    ns.SaveHoldings()
    bankOpen = false
    return
  end
  if event == "MAIL_INBOX_UPDATE" and not scanMail() then return end
  if QUEST_EVENTS[event] and ns.LocateSoon then ns.LocateSoon() end
  if event == "QUEST_TURNED_IN" and ns.Learn then ns.Learn(arg1) end
  ns.Changed()
  -- The completed flag can trail the turn-in by a moment.
  if event == "QUEST_TURNED_IN" then C_Timer.After(1.5, ns.Changed) end
end)

SLASH_PUGGERWAYLAID1 = "/pwc"
SLASH_PUGGERWAYLAID2 = "/waylaid"
SlashCmdList.PUGGERWAYLAID = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "map" or msg == "pins" then
    ns.db.pins = not ns.db.pins
    print(ns.TITLE .. ": map markers " .. (ns.db.pins and "shown" or "hidden") .. ".")
    ns.Changed()
  elseif msg == "minimap" then
    ns.db.minimap.hide = not ns.db.minimap.hide
    print(ns.TITLE .. ": minimap button " .. (ns.db.minimap.hide and "hidden" or "shown") .. ".")
    if ns.MinimapRefresh then ns.MinimapRefresh() end
  elseif msg == "names" then
    ns.db.ownerNames = ns.db.ownerNames == 2 and 1 or 2
    print(ns.TITLE .. ": " .. (ns.db.ownerNames == 2 and "first name and surname." or "first name only."))
    ns.Changed()
  elseif msg == "scan" or msg == "scan writs" or msg == "scan crates" then
    -- Both pages' items, or one page's.
    if ns.ToggleScan then ns.ToggleScan(msg:match("^scan (%a+)$")) end
  elseif msg == "export" then
    if ns.ShowExport then ns.ShowExport() end
  elseif msg == "import" then
    if ns.ShowImport then ns.ShowImport() end
  elseif msg == "shop" then
    if ns.ShopReport then ns.ShopReport() end
  elseif msg == "where" then
    ns.Where()
  elseif ns.Toggle then
    ns.Toggle(msg ~= "" and msg or nil)
  end
end

function PuggerWaylaidCompanion_OnAddonCompartmentClick()
  if ns.Toggle then ns.Toggle() end
end
