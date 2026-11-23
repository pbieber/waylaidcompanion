--[[
The wishlist: writs, crates and materials wanted on one character, the target. The target
is chosen on the Wishlist page and kept until another is chosen; without one it is the
character played.

While another character is the target, what it still lacks glows green in the bags, bank
and mailbox of the character played (the game's own frames), unless turned off under
Options. Holding Alt makes the bags glow the writs handed in in the zone the player is in,
and an open mailbox everything on the wishlist.

A right-click adds to it (UI.lua): on a writ, its writ and material; on a crate, the crate
and its cheapest material; on one of a crate's materials, the crate and that material; on
a turn-in NPC or a zone, every writ handed in there and their material. Adding the same
again adds as much again. The page shows how many of each the target has in its bags,
bank and mailbox, and how many are still missing. A right-click there takes one off: a
writ or a crate with the material that came with it, a material on its own. Its foot buys
what is missing at the auction house, or mails what the bags hold of it to the target.

It is kept as sets, so a writ or crate comes off with its own material, and a material
taken off on its own is kept apart:

  ns.db.wishlist   { writs = { [writ item] = count },
                     crates = { [crate item] = { [material item] = count } },
                     less = { [material item] = count taken off } }
  ns.db.wishTarget the target's key ("Name Surname"), nil for the character played
  ns.db.wishGlow   false: no glow
]]

local _, ns = ...

local function say(text) print(ns.TITLE .. ": " .. text) end

-- Writs and crates by their item, and the data's names for the materials.
local writOf, crateOf, materialName
local function lookups()
  if not writOf then
    writOf, crateOf, materialName = {}, {}, {}
    for _, writ in ipairs(ns.writs) do
      if not writOf[writ.writItem] or ns.ForPlayer(writ) then writOf[writ.writItem] = writ end
      materialName[writ.item] = materialName[writ.item] or writ.name
    end
    for _, crate in ipairs(ns.crates) do
      crateOf[crate.item] = crate
      for _, b in ipairs(crate.bundles) do materialName[b.item] = materialName[b.item] or b.name end
    end
  end
  return writOf, crateOf
end

--- An item's name: the game's, else the data's (before the game has sent the item).
local function nameOf(id)
  lookups()
  return ns.Item(id, materialName[id])
end

local function bundleOf(crate, id)
  for _, b in ipairs(crate.bundles) do
    if b.item == id then return b end
  end
end

--- The saved list, in sets. One saved as items (before the sets, during 0.11.0's testing)
--- keeps its writs and crates (a crate with its cheapest material); its loose materials
--- go, as they came with those.
local function list()
  local l = ns.db.wishlist
  if type(l) ~= "table" or not (l.writs and l.crates) then
    local old = type(l) == "table" and l or {}
    l = { writs = {}, crates = {}, less = {} }
    ns.db.wishlist = l
    local writs, crates = lookups()
    for id, count in pairs(old) do
      if type(id) == "number" and type(count) == "number" then
        if writs[id] then
          l.writs[id] = count
        elseif crates[id] then
          local crate = crates[id]
          local b = ns.CrateCost(crate).cheapest or crate.bundles[1]
          if b then l.crates[id] = { [b.item] = count } end
        end
      end
    end
  end
  l.less = l.less or {}
  return l
end

--- What the sets want, item by item, before materials taken off on their own.
local function fromSets()
  local l, writs, crates = list(), lookups()
  local items = {}
  local function add(id, count) items[id] = (items[id] or 0) + count end
  for id, count in pairs(l.writs) do
    local writ = writs[id]
    if writ then
      add(id, count)
      add(writ.item, count * writ.count)
    end
  end
  for id, bundles in pairs(l.crates) do
    local crate = crates[id]
    if crate then
      for item, count in pairs(bundles) do
        local b = bundleOf(crate, item)
        if b then
          add(id, count)
          add(item, count * b.count)
        end
      end
    end
  end
  return items
end

--- Materials taken off on their own never take off more than the sets still want.
local function trimLess()
  local l, base = list(), fromSets()
  for id, n in pairs(l.less) do
    n = math.min(n, base[id] or 0)
    l.less[id] = n > 0 and n or nil
  end
end

--- What is wanted, item by item: { [item] = count }, the writs and crates and the
--- material that came with them, less the materials taken off on their own.
function ns.Wishlist()
  local l, items = list(), fromSets()
  for id, n in pairs(l.less) do
    if items[id] then
      items[id] = items[id] - n
      if items[id] <= 0 then items[id] = nil end
    end
  end
  return items
end

--- Whether character `key` has handed in a writ (by its writ item) today, on either side.
local function writDone(key, writItem)
  for _, writ in ipairs(ns.writs) do
    if writ.writItem == writItem and writ.quest and ns.CharacterDoneToday(key, writ.quest) then
      return true
    end
  end
  return false
end

--- What on the wishlist character `key` is done with for today. A writ is done once its
--- daily quest is handed in, and the material it came with is used up: `used` counts it,
--- and a material is done once nothing else on the list (another writ, a crate, which is
--- no daily) still wants any. Back at the daily reset.
--- Returns done { [item] = true }, used { [material] = count }.
function ns.WishDone(key)
  local l, writs = list(), lookups()
  local wanted = ns.Wishlist()
  local done, used = {}, {}
  for id, count in pairs(l.writs) do
    local writ = writs[id]
    if writ and writDone(key, id) then
      done[id] = true
      used[writ.item] = (used[writ.item] or 0) + count * writ.count
    end
  end
  for item, n in pairs(used) do
    if wanted[item] and n >= wanted[item] then done[item] = true end
  end
  return done, used
end

--- The wishlist less what the target is done with today.
local function stillWanted(target)
  local done, used = ns.WishDone(target)
  local out = {}
  for id, count in pairs(ns.Wishlist()) do
    count = count - (used[id] or 0)
    if not done[id] and count > 0 then out[id] = count end
  end
  return out
end

--- Add writs and their material: one writ each, and the material it asks for.
--- `where` names them in the chat line when there is more than one (an NPC or a zone).
function ns.WishWrits(writs, where)
  if #writs == 0 then return end
  local l = list()
  for _, writ in ipairs(writs) do
    l.writs[writ.writItem] = (l.writs[writ.writItem] or 0) + 1
  end
  if #writs == 1 then
    local writ = writs[1]
    say(("wishlist + %s writ and %d x %s."):format(writ.name, writ.count, ns.Item(writ.item, writ.name)))
  else
    say(("wishlist + %d writs for %s and their material."):format(#writs, where or "them"))
  end
  ns.Changed()
end

--- Add a crate and the material to fill it: `bundle`, else the crate's cheapest (by the
--- last AH prices), else its first.
function ns.WishCrate(crate, bundle)
  bundle = bundle or ns.CrateCost(crate).cheapest or crate.bundles[1]
  if not bundle then return end
  local l = list()
  local sets = l.crates[crate.item] or {}
  l.crates[crate.item] = sets
  sets[bundle.item] = (sets[bundle.item] or 0) + 1
  say(("wishlist + %s crate and %d x %s."):format(crate.name, bundle.count, ns.Item(bundle.item, bundle.name)))
  ns.Changed()
end

--- Take one off the wishlist: a writ with the material it asks for, a crate with one
--- crate's worth of the material it was added with (the one added most), or one of a
--- material on its own.
function ns.WishRemove(id)
  local l, writs, crates = list(), lookups()
  if writs[id] and l.writs[id] then
    local writ = writs[id]
    l.writs[id] = l.writs[id] > 1 and l.writs[id] - 1 or nil
    say(("wishlist - %s writ and %d x %s."):format(writ.name, writ.count, ns.Item(writ.item, writ.name)))
  elseif crates[id] and l.crates[id] then
    local crate, sets = crates[id], l.crates[id]
    local item, most = nil, 0
    for i, count in pairs(sets) do
      if count > most or (count == most and item and i < item) then item, most = i, count end
    end
    if not item then return end
    sets[item] = most > 1 and most - 1 or nil
    if next(sets) == nil then l.crates[id] = nil end
    local b = bundleOf(crate, item)
    say(("wishlist - %s crate%s."):format(crate.name,
      b and (" and %d x %s"):format(b.count, ns.Item(b.item, b.name)) or ""))
  elseif (ns.Wishlist()[id] or 0) > 0 then
    l.less[id] = (l.less[id] or 0) + 1
    say(("wishlist - 1 x %s."):format(nameOf(id)))
  else
    return
  end
  trimLess()
  ns.Changed()
end

--- What the wishlist is worth handed in: the reputation of its writs and the Merchant's
--- Favor of its crates, and how many crates pay favor nobody knows yet.
function ns.WishWorth()
  local writs, crates = lookups()
  local rep, favor, unknown = 0, 0, 0
  for id, count in pairs(ns.Wishlist()) do
    if writs[id] then
      rep = rep + count * (ns.WRIT_REP[writs[id].tier] or 0)
    elseif crates[id] then
      local pays = ns.CrateFavor(crates[id])
      if pays then favor = favor + count * pays else unknown = unknown + count end
    end
  end
  return rep, favor, unknown
end

--- What the target still lacks, beyond what the character played holds in its bags
--- (the character played as the target: what it lacks): { { id, need, name, material } },
--- writs first, then crates, then materials. For the auction house.
function ns.WishToBuy()
  local target, me = ns.WishTarget(), ns.Character()
  local writs, crates = lookups()
  local out = {}
  for id, count in pairs(stillWanted(target)) do
    local need = count - ns.CharacterHoldings(target, id).total
    if target ~= me then need = need - ns.Count(id) end
    if need > 0 then
      local rank = writs[id] and 1 or (crates[id] and 2 or 3)
      out[#out + 1] = { id = id, need = need, rank = rank, material = rank == 3 or nil,
        name = writs[id] and ("Writ: " .. writs[id].name) or (crates[id] and crates[id].name) or nameOf(id) }
    end
  end
  table.sort(out, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.id < b.id
  end)
  return out
end

--- What the character played can mail the target from its bags: of each item the target
--- still lacks, as many as the bags hold, up to what it lacks. { { id, count, name } }.
--- Empty while the target is the character played.
function ns.WishToMail()
  local target, me = ns.WishTarget(), ns.Character()
  local out = {}
  if target == me then return out end
  for id, count in pairs(stillWanted(target)) do
    local n = math.min(count - ns.CharacterHoldings(target, id).total, ns.Count(id))
    if n > 0 then out[#out + 1] = { id = id, count = n, name = nameOf(id) } end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

--- Buy what the target still lacks (the Wishlist page's Buy missing).
function ns.WishBuy()
  local list = ns.WishToBuy()
  if #list == 0 then return say("nothing missing to buy.") end
  if ns.BuyList then ns.BuyList("Wishlist", list) end
end

--- Mail the target what the bags hold of what it lacks (the Wishlist page's Mail
--- available).
function ns.WishMail()
  local target = ns.WishTarget()
  if target == ns.Character() then return say("the wishlist is for this character: pick another to mail to.") end
  local address = ns.MailAddress(target)
  if not address then return say(("%s's surname isn't known yet: log in on it once."):format(target)) end
  local list = ns.WishToMail()
  if #list == 0 then return say("nothing in the bags the target still needs.") end
  if ns.MailItems then ns.MailItems(address, list) end
end

--- Empty the wishlist (the target stays).
function ns.WishClear()
  ns.db.wishlist = { writs = {}, crates = {}, less = {} }
  ns.Changed()
end

--- The target's key: the one chosen, else the character played.
function ns.WishTarget()
  return ns.db.wishTarget or ns.Character()
end

function ns.SetWishTarget(key)
  ns.db.wishTarget = key
  ns.Changed()
end

--- Every character the account has saved, and the one played and the target: keys, the
--- one played first, then by name.
function ns.WishCharacters()
  local db, me, seen, out = ns.db, ns.Character(), {}, {}
  local function addKey(key)
    if key and not seen[key] then
      seen[key] = true
      out[#out + 1] = key
    end
  end
  addKey(me)
  addKey(db.wishTarget)
  for _, source in ipairs({ db.bags or {}, db.bank or {}, db.mail or {} }) do
    for key in pairs(source) do addKey(key) end
  end
  table.sort(out, function(a, b)
    if (a == me) ~= (b == me) then return a == me end
    return a < b
  end)
  return out
end

--- How many of an item a character has: { bags, bank, mail, total, mailSeen }. The one
--- played counts its bags now; another, as saved when it was last played (the mailbox as
--- it was when last open there).
function ns.CharacterHoldings(key, id)
  if key == ns.Character() then return ns.Holdings(id) end
  local db = ns.db
  local bags = db.bags[key] and db.bags[key][id] or 0
  local bank = db.bank[key] and db.bank[key][id] or 0
  local seen = db.mail[key]
  local mail = seen and seen[id] or 0
  return { bags = bags, bank = bank, mail = mail, total = bags + bank + mail, mailSeen = seen ~= nil }
end

-- ---------------------------------------------------------------------------
-- The glow: while another character is the target, what it still lacks glows green in
-- the bags, bank and mailbox of the character played, so it can be mailed over.
-- ---------------------------------------------------------------------------

if not CreateFrame then return end

local GetItemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
local ATTACHMENTS = ATTACHMENTS_MAX_RECEIVE or 16
local INBOX_ROWS = INBOXITEMS_TO_DISPLAY or 7

-- The glows, kept here by button (the game's buttons get no fields of ours).
local glows = {}

local GREEN = { 0.25, 1, 0.3 }
-- The edges of the frame drawn along a glowing button: where each runs, and whether it
-- stands upright.
local EDGES = {
  { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
  { "TOPLEFT", "BOTTOMLEFT", true }, { "TOPRIGHT", "BOTTOMRIGHT", true },
}

--- Make a button glow: a soft green glow, twice over for brightness, and a solid green
--- frame along its edge on top (writs already wear the game's yellow quest border, which
--- a soft glow alone was lost against).
local function glow(button)
  local g = glows[button]
  if not g then
    g = {}
    local size = (tonumber(button:GetWidth()) or 37) * 1.9
    for _ = 1, 2 do
      local t = button:CreateTexture(nil, "OVERLAY", nil, 6)
      t:SetTexture("Interface/Buttons/UI-ActionButton-Border")
      t:SetBlendMode("ADD")
      t:SetVertexColor(GREEN[1], GREEN[2], GREEN[3])
      t:SetSize(size, size)
      t:SetPoint("CENTER")
      g[#g + 1] = t
    end
    for _, e in ipairs(EDGES) do
      local t = button:CreateTexture(nil, "OVERLAY", nil, 7)
      t:SetColorTexture(GREEN[1], GREEN[2], GREEN[3], 1)
      t:SetPoint(e[1], button, e[1])
      t:SetPoint(e[2], button, e[2])
      if e[3] then t:SetWidth(2) else t:SetHeight(2) end
      g[#g + 1] = t
    end
    glows[button] = g
  end
  for _, t in ipairs(g) do t:Show() end
end

local function unglowAll()
  for _, g in pairs(glows) do
    for _, t in ipairs(g) do t:Hide() end
  end
end

--- Whether Alt is held: then the bags glow this zone's writs, and an open mailbox (its
--- window shown, the only place mail glows) the wishlist.
local function peeking()
  return IsAltKeyDown and IsAltKeyDown() or false
end

--- Mark in `out` the writs handed in in the zone the player is in (for their side): the
--- turn-in NPC on the player's map, or in a zone of the name the game gives this one.
--- Whether there were any.
local function hereWrits(out)
  local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local info = map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
  local names = {}
  for _, name in ipairs({ GetRealZoneText and GetRealZoneText() or false, GetZoneText and GetZoneText() or false,
      info and info.name or false }) do
    if type(name) == "string" and name ~= "" then names[name] = true end
  end
  local any = false
  for _, writ in ipairs(ns.writs) do
    if ns.ForPlayer(writ) then
      local npc = ns.WritNpc(writ)
      if npc and ((map and npc.map == map) or names[npc.zone]) then
        out[writ.writItem], any = true, true
      end
    end
  end
  return any
end

--- The items to glow, in the bags (and bank) and in the mailbox: on the wishlist, and
--- fewer of them on the target than wanted, the same in both. nil when the target is the
--- character played (what it holds counts already), the glow is off under Options, or
--- nothing is missing. With Alt held, the option on or off: in the bags the writs handed in
--- in this zone, in the mailbox everything on the wishlist (whoever the target and
--- whatever it holds).
local function wanted()
  if not ns.db then return nil end
  if peeking() then
    local bags, mail = {}, {}
    local inBags = hereWrits(bags)
    local inMail = next(ns.Wishlist()) ~= nil
    for id in pairs(ns.Wishlist()) do mail[id] = true end
    return inBags and bags or {}, inMail and mail or {}
  end
  if ns.db.wishGlow == false then return nil end
  local target = ns.WishTarget()
  if target == ns.Character() then return nil end
  local out, any = {}, false
  for id, count in pairs(stillWanted(target)) do
    if ns.CharacterHoldings(target, id).total < count then
      out[id], any = true, true
    end
  end
  if not any then return nil end
  return out, out
end

local function inboxItem(index, slot)
  local _, id = GetInboxItem(index, slot)
  if type(id) ~= "number" then
    local link = GetInboxItemLink and GetInboxItemLink(index, slot)
    id = link and tonumber(link:match("item:(%d+)"))
  end
  return id
end

--- The bag frames: the combined bag (where the client has one) and one per bag (the
--- bank's bags among them).
local function bagFrames()
  local frames = {}
  if ContainerFrameCombinedBags then frames[1] = ContainerFrameCombinedBags end
  for i = 1, NUM_CONTAINER_FRAMES or 13 do
    local frame = _G["ContainerFrame" .. i]
    if frame then frames[#frames + 1] = frame end
  end
  return frames
end

--- The item buttons in a frame: its children that are item slots (an ID and a click),
--- each with its bag: the button's own (this client's bag buttons know it), else the
--- frame's ID. Older clients name them "<frame>Item<n>" instead; those are taken too.
local function itemButtons(frame, fallbackBag)
  local out = {}
  for _, child in ipairs({ frame:GetChildren() }) do
    if child.GetID and child.GetBagID then
      out[#out + 1] = { child, child:GetBagID() }
    end
  end
  if #out == 0 then
    local name = frame:GetName()
    for j = 1, MAX_CONTAINER_ITEMS or 36 do
      local button = name and _G[name .. "Item" .. j]
      if not button then break end
      out[#out + 1] = { button, fallbackBag or frame:GetID() }
    end
  end
  return out
end

--- Glow each shown button whose item is wanted, and only those.
local function update()
  unglowAll()
  local forBags, forMail = wanted()
  if not forBags then return end
  local function slot(button, bag, id, want)
    if button and button:IsShown() then
      id = id or (bag and GetItemID and GetItemID(bag, button:GetID()))
      if id and (want or forBags)[id] then glow(button) end
    end
  end
  -- The bags, and the bank's own bags.
  for _, frame in ipairs(bagFrames()) do
    if frame:IsShown() then
      for _, b in ipairs(itemButtons(frame)) do slot(b[1], b[2]) end
    end
  end
  -- The bank's own slots.
  if BankFrame and BankFrame:IsShown() then
    local found = false
    for i = 1, NUM_BANKGENERIC_SLOTS or 28 do
      local button = _G["BankFrameItem" .. i]
      if button then
        found = true
        slot(button, BANK_CONTAINER or -1)
      end
    end
    if not found then
      for _, b in ipairs(itemButtons(BankFrame, BANK_CONTAINER or -1)) do slot(b[1], b[2]) end
    end
  end
  -- The inbox's rows (a mail with a wanted item glows), and the open mail's attachments.
  if GetInboxItem and InboxFrame and InboxFrame:IsShown() then
    local page = InboxFrame.pageNum or 1
    for i = 1, INBOX_ROWS do
      local button = _G["MailItem" .. i .. "Button"]
      if button and button:IsShown() then
        local index = button.index or ((page - 1) * INBOX_ROWS + i)
        for s = 1, ATTACHMENTS do
          local id = inboxItem(index, s)
          if id and forMail[id] then
            glow(button)
            break
          end
        end
      end
    end
  end
  if GetInboxItem and OpenMailFrame and OpenMailFrame:IsShown() and InboxFrame and InboxFrame.openMailID then
    for s = 1, ATTACHMENTS do
      local button = _G["OpenMailAttachmentButton" .. s]
      slot(button, nil, button and button:IsShown() and inboxItem(InboxFrame.openMailID, s) or nil, forMail)
    end
  end
end

-- Redrawn at once when the game redraws a bag or the inbox (a page turned) or Alt is
-- pressed or let go, soon after anything else moves, and twice a second while bags, bank
-- or mail are open. Only the shown buttons are looked at; with none of those windows open
-- the loop stops (nothing runs per frame). The game's default bag, bank and mail frames
-- only; bag addons draw their own buttons.
local dirty, since = true, 0
local glower = CreateFrame("Frame")
local function soon()
  dirty = true
  glower:Show()
end
local function now()
  dirty, since = false, 0
  glower:Show()
  -- Run inside the game's own redraws: an error here mustn't break its bags or mailbox.
  local ok, err = pcall(update)
  if not ok and not ns.glowError then
    ns.glowError = true
    print(ns.TITLE .. ": wishlist glow failed: " .. tostring(err))
  end
end
local function anyOpen()
  if (BankFrame and BankFrame:IsShown()) or (MailFrame and MailFrame:IsShown()) then return true end
  for _, frame in ipairs(bagFrames()) do
    if frame:IsShown() then return true end
  end
  return false
end
glower:SetScript("OnUpdate", function(self, elapsed)
  since = since + elapsed
  -- At most ten a second however often the game reports (the inbox does, many times).
  if since < (dirty and 0.1 or 0.5) then return end
  if not dirty and not anyOpen() then
    self:Hide()  -- nothing open: no more until a window opens or something changes
    return
  end
  now()
end)
for _, event in ipairs({ "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED",
  "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MODIFIER_STATE_CHANGED" }) do
  pcall(glower.RegisterEvent, glower, event)
end
glower:SetScript("OnEvent", function(_, event, key)
  -- Alt pressed or let go: at once, while the key is still down.
  if event == "MODIFIER_STATE_CHANGED" then
    if type(key) == "string" and key:find("ALT") then now() end
    return
  end
  soon()
end)
if ns.OnChange then ns.OnChange(soon) end
-- The game's own redraws: the glow follows in the same frame, so it never sits on the
-- wrong button.
for _, name in ipairs({ "ContainerFrame_Update", "ContainerFrame_UpdateAll", "InboxFrame_Update", "OpenMail_Update" }) do
  if type(_G[name]) == "function" then hooksecurefunc(name, now) end
end
for _, frame in ipairs(bagFrames()) do
  if type(frame.UpdateItems) == "function" then hooksecurefunc(frame, "UpdateItems", now) end
  frame:HookScript("OnShow", now)
end
for _, name in ipairs({ "InboxNextPageButton", "InboxPrevPageButton" }) do
  local button = _G[name]
  if button then button:HookScript("OnClick", now) end
end
for _, name in ipairs({ "InboxFrame", "OpenMailFrame", "BankFrame" }) do
  local frame = _G[name]
  if frame then frame:HookScript("OnShow", now) end
end
