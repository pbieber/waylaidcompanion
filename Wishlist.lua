--[[
The wishlist: writs, crates and materials wanted on one character, the target. The target
is chosen on the Wishlist page and kept until another is chosen; without one it is the
character played.

While another character is the target, what it still lacks glows green in the bags, bank
and mailbox of the character played (the game's own frames), unless turned off under
Options.

A right-click adds to it (UI.lua): on a writ, its writ and material; on a crate, the crate
and its cheapest material; on one of a crate's materials, the crate and that material; on
a turn-in NPC or a zone, every writ handed in there and their material. Adding the same
again adds as much again. The page shows how many of each the target has in its bags,
bank and mailbox, and how many are still missing. A right-click on a writ or a crate there
takes it off with the material that came with it.

It is kept as sets, so a writ or crate comes off with its own material:

  ns.db.wishlist   { writs = { [writ item] = count },
                     crates = { [crate item] = { [material item] = count } } }
  ns.db.wishTarget the target's key ("Name Surname"), nil for the character played
  ns.db.wishGlow   false: no glow
]]

local _, ns = ...

local function say(text) print(ns.TITLE .. ": " .. text) end

-- Writs and crates by their item.
local writOf, crateOf
local function lookups()
  if not writOf then
    writOf, crateOf = {}, {}
    for _, writ in ipairs(ns.writs) do
      if not writOf[writ.writItem] or ns.ForPlayer(writ) then writOf[writ.writItem] = writ end
    end
    for _, crate in ipairs(ns.crates) do crateOf[crate.item] = crate end
  end
  return writOf, crateOf
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
    l = { writs = {}, crates = {} }
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
  return l
end

--- What is wanted, item by item: { [item] = count }, the writs and crates and the
--- material that came with them.
function ns.Wishlist()
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

--- Whether an item can come off the wishlist on its own: a writ or a crate (a material
--- comes off with them).
function ns.WishRemovable(id)
  local writs, crates = lookups()
  return writs[id] ~= nil or crates[id] ~= nil
end

--- Take a writ or a crate off the wishlist, every one of it, with the material that came
--- with it.
function ns.WishRemove(id)
  local l, writs, crates = list(), lookups()
  if writs[id] and l.writs[id] then
    local writ, count = writs[id], l.writs[id]
    l.writs[id] = nil
    say(("wishlist - %d x %s writ and %d x %s."):format(count, writ.name, count * writ.count,
      ns.Item(writ.item, writ.name)))
  elseif crates[id] and l.crates[id] then
    local crate, parts, n = crates[id], {}, 0
    for item, count in pairs(l.crates[id]) do
      local b = bundleOf(crate, item)
      n = n + count
      if b then parts[#parts + 1] = ("%d x %s"):format(count * b.count, ns.Item(b.item, b.name)) end
    end
    l.crates[id] = nil
    table.sort(parts)
    say(("wishlist - %d x %s crate and %s."):format(n, crate.name, table.concat(parts, ", ")))
  else
    return
  end
  ns.Changed()
end

--- Empty the wishlist (the target stays).
function ns.WishClear()
  ns.db.wishlist = { writs = {}, crates = {} }
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

local function glow(button)
  local g = glows[button]
  if not g then
    g = button:CreateTexture(nil, "OVERLAY")
    g:SetTexture("Interface/Buttons/UI-ActionButton-Border")
    g:SetBlendMode("ADD")
    g:SetVertexColor(0.2, 1, 0.3)
    local size = (button:GetWidth() or 37) * 1.85
    g:SetSize(size, size)
    g:SetPoint("CENTER")
    glows[button] = g
  end
  g:Show()
end

--- The items to glow: on the wishlist, and fewer of them on the target than wanted. nil
--- when the target is the character played (what it holds counts already), the glow is
--- off under Options, or nothing is missing.
local function wanted()
  if not ns.db or ns.db.wishGlow == false then return nil end
  local target = ns.WishTarget()
  if target == ns.Character() then return nil end
  local out, any = {}, false
  for id, count in pairs(ns.Wishlist()) do
    if ns.CharacterHoldings(target, id).total < count then
      out[id], any = true, true
    end
  end
  return any and out or nil
end

local function inboxItem(index, slot)
  local _, id = GetInboxItem(index, slot)
  if type(id) ~= "number" then
    local link = GetInboxItemLink and GetInboxItemLink(index, slot)
    id = link and tonumber(link:match("item:(%d+)"))
  end
  return id
end

--- Glow each shown button whose item is wanted, and only those.
local function update()
  for _, g in pairs(glows) do g:Hide() end
  local want = wanted()
  if not want then return end
  local function slot(button, bag, id)
    if button and button:IsShown() then
      id = id or (bag and GetItemID and GetItemID(bag, button:GetID()))
      if id and want[id] then glow(button) end
    end
  end
  -- The bags, and the bank's own bags: a frame per bag, its ID the bag.
  for i = 1, NUM_CONTAINER_FRAMES or 13 do
    local frame = _G["ContainerFrame" .. i]
    if frame and frame:IsShown() then
      local name, bag = frame:GetName(), frame:GetID()
      for j = 1, MAX_CONTAINER_ITEMS or 36 do
        local button = _G[name .. "Item" .. j]
        if not button then break end
        slot(button, bag)
      end
    end
  end
  -- The bank's own slots.
  if BankFrame and BankFrame:IsShown() then
    for i = 1, NUM_BANKGENERIC_SLOTS or 28 do
      slot(_G["BankFrameItem" .. i], BANK_CONTAINER or -1)
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
          if id and want[id] then
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
      slot(button, nil, button and button:IsShown() and inboxItem(InboxFrame.openMailID, s) or nil)
    end
  end
end

-- Redrawn soon after anything moves, and twice a second while bags, bank or mail are
-- open (pages turned, bags opened): only the shown buttons are looked at. The game's
-- default bag, bank and mail frames only; bag addons draw their own buttons.
local dirty, since = true, 0
local function soon() dirty = true end
local glower = CreateFrame("Frame")
glower:SetScript("OnUpdate", function(_, elapsed)
  since = since + elapsed
  -- At most ten a second however often the game reports (the inbox does, many times).
  if since < (dirty and 0.1 or 0.5) then return end
  local open = (ContainerFrame1 and ContainerFrame1:IsShown()) or (BankFrame and BankFrame:IsShown())
    or (MailFrame and MailFrame:IsShown())
  if not open then
    for i = 2, NUM_CONTAINER_FRAMES or 13 do
      local frame = _G["ContainerFrame" .. i]
      if frame and frame:IsShown() then open = true break end
    end
  end
  if not open and not dirty then return end
  dirty, since = false, 0
  update()
end)
for _, event in ipairs({ "BAG_UPDATE_DELAYED", "ITEM_LOCK_CHANGED", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED",
  "MAIL_SHOW", "MAIL_INBOX_UPDATE" }) do
  pcall(glower.RegisterEvent, glower, event)
end
glower:SetScript("OnEvent", soon)
if ns.OnChange then ns.OnChange(soon) end
for _, name in ipairs({ "ContainerFrame_Update", "InboxFrame_Update", "OpenMail_Update" }) do
  if type(_G[name]) == "function" then hooksecurefunc(name, soon) end
end
