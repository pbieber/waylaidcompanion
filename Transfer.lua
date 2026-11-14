--[[
The Transfer page: moving writs and their material.

A "set" is one writ and the material it asks for (the writ's count).

  - Mail: one set of each writ in the bags to a character ("Name Surname": an alt, or a
    name typed in, which can be saved as a one-click target). Packed into mails of up to
    12 attachments; each mail is sent with a click on Send.
  - Bank: Bank to bags and Bags to bank, each with 1 of each (a writ of each kind and
    its material), Extra (all but one writ of each kind) and All writs.
  - Buying: the missing material for the writs in the bags (Buy.lua).

Items move with the cursor (pick up or split a stack, put it in an empty slot or a mail
attachment), one stack at a time, waiting for the game to unlock the slots in between.
]]

local _, ns = ...
if not CreateFrame then return end

local Container = C_Container
local GetSlots = (Container and Container.GetContainerNumSlots) or GetContainerNumSlots
local Pickup = (Container and Container.PickupContainerItem) or PickupContainerItem
local Split = (Container and Container.SplitContainerItem) or SplitContainerItem
local MAX_ATTACH = ATTACHMENTS_MAX_SEND or 12
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local LOCK_TIMEOUT = 6   -- seconds to wait for the game to unlock moved items
local SEND_TIMEOUT = 15  -- seconds to wait for a mail to be confirmed
local RED, GREY = "ffff4040", "ff808080"

local mailOpen, bankOpen = false, false

function ns.MailboxOpen() return mailOpen end
function ns.BankOpen() return bankOpen end

-- ---------------------------------------------------------------------------
-- Bags and bank
-- ---------------------------------------------------------------------------

--- itemID, count, locked of a container slot; nil when it is empty.
local function slotInfo(bag, slot)
  if Container and Container.GetContainerItemInfo then
    local i = Container.GetContainerItemInfo(bag, slot)
    if i then return i.itemID, i.stackCount or 1, i.isLocked end
    return nil
  end
  if GetContainerItemInfo then
    local _, count, locked, _, _, _, _, _, _, id = GetContainerItemInfo(bag, slot)
    return id, count, locked
  end
end

local reagentBag = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag

--- The containers of the bags or the character's bank.
local function containers(kind)
  local ids, B = {}, Enum and Enum.BagIndex
  if B then
    for name, id in pairs(B) do
      if kind == "bags" and (name == "Backpack" or name:match("^Bag_%d+$") or name == "ReagentBag") then
        ids[#ids + 1] = id
      elseif kind == "bank" and (name == "Bank" or name:match("^BankBag_%d+$") or name:match("^CharacterBankTab_%d+$")) then
        ids[#ids + 1] = id
      end
    end
  end
  if #ids == 0 then
    if kind == "bags" then
      for i = 0, NUM_BAG_SLOTS or 4 do ids[#ids + 1] = i end
    else
      ids[1] = BANK_CONTAINER or -1
      local first = (NUM_BAG_SLOTS or 4) + 1
      for i = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do ids[#ids + 1] = i end
    end
  end
  table.sort(ids)
  return ids
end

--- Every filled slot: { bag, slot, id, count, locked }.
local function slots(kind)
  local out = {}
  for _, bag in ipairs(containers(kind)) do
    for slot = 1, (GetSlots and GetSlots(bag)) or 0 do
      local id, count, locked = slotInfo(bag, slot)
      if id then out[#out + 1] = { bag = bag, slot = slot, id = id, count = count, locked = locked } end
    end
  end
  return out
end

--- How many of each item: itemID -> count.
local function counts(kind)
  local out = {}
  for _, s in ipairs(slots(kind)) do out[s.id] = (out[s.id] or 0) + s.count end
  return out
end

local function slotKey(bag, slot) return bag .. ":" .. slot end

--- The stacks of an item, largest first; with `free`, only those not locked (an item
--- attached to the mail being written stays in its slot, locked, until it is sent).
local function stacks(kind, id, free)
  local out = {}
  for _, s in ipairs(slots(kind)) do
    if s.id == id and not (free and s.locked) then out[#out + 1] = s end
  end
  table.sort(out, function(a, b) return a.count > b.count end)
  return out
end

--- An empty slot to put a stack in (never the reagent bag, which takes reagents only).
local function emptySlot(kind)
  for _, bag in ipairs(containers(kind)) do
    if bag ~= reagentBag then
      for slot = 1, (GetSlots and GetSlots(bag)) or 0 do
        if not slotInfo(bag, slot) then return { bag = bag, slot = slot } end
      end
    end
  end
end

--- Whether a slot is still settling: locked, and not because it is attached to the mail.
local function anyLocked(kind, attached)
  for _, s in ipairs(slots(kind)) do
    if s.locked and not (attached and attached[slotKey(s.bag, s.slot)]) then return true end
  end
  return false
end

local function freeAttachment()
  for i = 1, MAX_ATTACH do
    if not (GetSendMailItem and GetSendMailItem(i)) then return i end
  end
end

local function cursorBusy()
  return GetCursorInfo and GetCursorInfo() ~= nil
end

--- Every kind of writ once (the data lists some writs for both factions).
local function writKinds()
  local out, seen = {}, {}
  for _, writ in ipairs(ns.writs) do
    if not seen[writ.writItem] then
      seen[writ.writItem] = true
      out[#out + 1] = writ
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

local function itemName(id, fallback)
  return (GetItemInfo and GetItemInfo(id)) or fallback or ("item " .. id)
end

-- ---------------------------------------------------------------------------
-- Moving items
-- ---------------------------------------------------------------------------

local job = nil  -- { moves = { { id, left, from, to } }, i, wait, locked, done, fail }

local function stopJob(message)
  local j = job
  job = nil
  if j and j.fail then j.fail(message) end
end

--- Whether the place a move needs is still open.
local function placeOpen(where)
  if where == "bank" then return bankOpen end
  if where == "mail" then return mailOpen end
  return true
end

local mover = CreateFrame("Frame")
mover:SetScript("OnUpdate", function(_, elapsed)
  if not job then return end
  job.wait = job.wait - elapsed
  if job.wait > 0 then return end
  if InCombatLockdown and InCombatLockdown() then job.wait = 0.5 return end
  if cursorBusy() then job.wait = 0.2 return end
  local m = job.moves[job.i]
  if not m then
    local j = job
    job = nil
    return j.done()
  end
  if not placeOpen(m.from) or not placeOpen(m.to) then
    return stopJob(m.to == "mail" and "The mailbox closed." or "The bank closed.")
  end
  -- Wait for the last move to settle (items attached to the mail stay locked: those
  -- don't count).
  if anyLocked(m.from, job.attached) or (m.to ~= "mail" and anyLocked(m.to)) then
    job.locked = job.locked + elapsed + 0.1
    job.wait = 0.1
    if job.locked > LOCK_TIMEOUT then stopJob("The game kept the items locked.") end
    return
  end
  job.locked = 0
  if m.left <= 0 then
    job.i = job.i + 1
    return
  end

  local function placed(n)
    if cursorBusy() then
      if ClearCursor then ClearCursor() end
      stopJob("The game wouldn't take the item there.")
      return false
    end
    m.left, m.moved = m.left - n, (m.moved or 0) + n
    job.wait = 0.25
    return true
  end

  if m.to == "mail" then
    -- A whole stack is attached; part of one is split into an empty bag slot first and
    -- attached from there once it has settled.
    local target = freeAttachment()
    if not target then return stopJob("No free attachment slot in the mail.") end
    local src
    if m.staged then
      local id, count, locked = slotInfo(m.staged.bag, m.staged.slot)
      if id ~= m.id or locked then
        job.wait = 0.1
        return
      end
      src, m.staged = { bag = m.staged.bag, slot = m.staged.slot, count = count }, nil
    else
      src = stacks(m.from, m.id, true)[1]
    end
    if not src then
      m.short = (m.short or 0) + m.left  -- not there any more
      m.left = 0
      return
    end
    local n = math.min(m.left, src.count)
    if n < src.count then
      local empty = emptySlot(m.from)
      if not empty then return stopJob("Your bags need a free slot to split a stack.") end
      Split(src.bag, src.slot, n)
      Pickup(empty.bag, empty.slot)
      if cursorBusy() then
        if ClearCursor then ClearCursor() end
        return stopJob("The game wouldn't split the stack.")
      end
      m.staged = empty
      job.wait = 0.25
      return
    end
    Pickup(src.bag, src.slot)
    ClickSendMailItemButton(target)
    if placed(n) then job.attached[slotKey(src.bag, src.slot)] = true end
    return
  end

  local src = stacks(m.from, m.id, true)[1]
  if not src then
    m.short = (m.short or 0) + m.left  -- not there any more
    m.left = 0
    return
  end
  local n = math.min(m.left, src.count)
  local target = emptySlot(m.to)
  if not target then return stopJob(m.to == "bank" and "The bank is full." or "Your bags are full.") end
  if n == src.count then Pickup(src.bag, src.slot) else Split(src.bag, src.slot, n) end
  Pickup(target.bag, target.slot)
  placed(n)
end)

--- Run moves one stack at a time; done() when finished, fail(message) when stopped.
local function runMoves(moves, done, fail)
  job = { moves = moves, i = 1, wait = 0, locked = 0, done = done, fail = fail, attached = {} }
end

--- "2 writs and 400 material": what a list of moves moved.
local function moved(moves)
  local writ, material, short = 0, 0, 0
  for _, m in ipairs(moves) do
    if m.writ then writ = writ + (m.moved or 0) else material = material + (m.moved or 0) end
    short = short + (m.short or 0)
  end
  local text = ("%d writ%s and %d material"):format(writ, writ == 1 and "" or "s", material)
  if short > 0 then text = text .. (" (%d not found)"):format(short) end
  return text
end

-- ---------------------------------------------------------------------------
-- The bank
-- ---------------------------------------------------------------------------

--- Moves between bank and bags. way: "in" (bank to bags) or "out" (bags to bank).
--- mode:
---   "one"   one of each: a writ of each kind and the material for it. In, only kinds the
---           bags have none of (and the material the bags lack for one of each); out,
---           one writ of each kind in the bags and its material.
---   "extra" every writ but one of each kind (the one stays where it is). Writs only.
---   "all"   every writ. Writs only.
function ns.PlanBank(way, mode)
  local from, to = "bank", "bags"
  if way == "out" then from, to = "bags", "bank" end
  local have, there = counts(from), counts(to)
  local moves, material = {}, {}
  local function move(id, n, writ)
    if n > 0 then moves[#moves + 1] = { id = id, left = n, from = from, to = to, writ = writ } end
  end
  for _, writ in ipairs(writKinds()) do
    local n = have[writ.writItem] or 0
    if mode == "all" then
      move(writ.writItem, n, true)
    elseif mode == "extra" then
      move(writ.writItem, n - 1, true)
    elseif way == "in" then
      local bags = there[writ.writItem] or 0
      local take = (bags == 0 and n > 0) and 1 or 0
      move(writ.writItem, take, true)
      if bags + take > 0 then material[writ.item] = (material[writ.item] or 0) + writ.count end
    elseif n > 0 then
      move(writ.writItem, 1, true)
      material[writ.item] = (material[writ.item] or 0) + writ.count
    end
  end
  for id, want in pairs(material) do
    if way == "in" then want = want - (there[id] or 0) end
    move(id, math.min(want, have[id] or 0), false)
  end
  return moves
end

local function say(text) print(ns.TITLE .. ": " .. text) end

--- Run a bank move: ns.Bank("in" or "out", "one", "extra" or "all").
function ns.Bank(way, mode)
  if not bankOpen then return say("Open the bank.") end
  if job then return say("A transfer is running.") end
  local moves = ns.PlanBank(way, mode)
  if #moves == 0 then return say("Nothing to move.") end
  runMoves(moves, function()
    say("Moved " .. moved(moves) .. ".")
    ns.Changed()
  end, function(message)
    say(("Stopped: %s Moved %s."):format(message, moved(moves)))
    ns.Changed()
  end)
end

-- ---------------------------------------------------------------------------
-- Buying what the writs in the bags are missing
-- ---------------------------------------------------------------------------

--- { { id, need, name }, ... }: the material the writs in the bags ask for, less what
--- the bags hold.
function ns.MissingMaterials()
  local bags = counts("bags")
  local need, order = {}, {}
  for _, writ in ipairs(writKinds()) do
    local writs = bags[writ.writItem] or 0
    if writs > 0 then
      if not need[writ.item] then order[#order + 1] = writ end
      need[writ.item] = (need[writ.item] or 0) + writs * writ.count
    end
  end
  local out = {}
  for _, writ in ipairs(order) do
    local missing = need[writ.item] - (bags[writ.item] or 0)
    if missing > 0 then out[#out + 1] = { id = writ.item, need = missing, name = writ.name } end
  end
  return out
end

function ns.BuyMissing()
  local list = ns.MissingMaterials()
  if #list == 0 then return say("No material missing.") end
  ns.BuyMaterials(list)
end

-- ---------------------------------------------------------------------------
-- Mail
-- ---------------------------------------------------------------------------

local mail = nil  -- { to, name, prefix, mails = { { pieces, sets } }, i, state, waited }
local window

--- The bags' stacks as a plan uses them up: total(id) what is left of an item, and
--- take(id, count) the attachments `count` takes, one per stack used, largest first (the
--- way the mover takes them).
local function bagPool()
  local pool = {}  -- itemID -> stack counts left
  local function stackList(id)
    if not pool[id] then
      pool[id] = {}
      for _, s in ipairs(stacks("bags", id)) do pool[id][#pool[id] + 1] = s.count end
    end
    return pool[id]
  end
  local function total(id)
    local n = 0
    for _, c in ipairs(stackList(id)) do n = n + c end
    return n
  end
  local function take(id, count)
    local pieces, list = {}, stackList(id)
    while count > 0 and #list > 0 do
      table.sort(list, function(a, b) return a > b end)
      local n = math.min(count, list[1])
      pieces[#pieces + 1] = n
      list[1], count = list[1] - n, count - n
      if list[1] == 0 then table.remove(list, 1) end
    end
    return pieces
  end
  return total, take
end

--- Attachments for `count` of an item from the bags: one move per stack used.
local function attach(take, pieces, id, count, isLead)
  for _, n in ipairs(take(id, count)) do
    pieces[#pieces + 1] = { id = id, left = n, from = "bags", to = "mail", writ = isLead }
  end
end

--- Groups of attachments ({ name, pieces }) packed into mails of at most MAX_ATTACH:
--- { { pieces = { moves }, sets = { names } }, ... }. A group starts a new mail when it
--- won't fit in the one being packed; one too big for any mail runs on into the next.
local function pack(groups)
  local mails, current = {}, nil
  local function newMail()
    current = { pieces = {}, sets = {} }
    mails[#mails + 1] = current
  end
  for _, g in ipairs(groups) do
    if not current or #current.pieces + #g.pieces > MAX_ATTACH then newMail() end
    for _, p in ipairs(g.pieces) do
      if #current.pieces >= MAX_ATTACH then newMail() end
      current.pieces[#current.pieces + 1] = p
    end
    current.sets[#current.sets + 1] = g.name
  end
  return mails
end

--- Sets in the bags (one per writ, when there is material enough for it), packed into
--- mails (see pack).
function ns.PlanMail()
  local total, take = bagPool()
  local groups = {}
  for _, writ in ipairs(writKinds()) do
    if total(writ.writItem) >= 1 and total(writ.item) >= writ.count then
      local pieces = {}
      attach(take, pieces, writ.writItem, 1, true)
      attach(take, pieces, writ.item, writ.count)
      groups[#groups + 1] = { name = writ.name, pieces = pieces }
    end
  end
  return pack(groups)
end

--- Every unfilled crate in the bags, each kind with the material in the bags to fill
--- them: its materials cheapest first by the prices the crates page shows (the last AH
--- scan), the next one where the cheapest runs short; those without a price last. A
--- crate the bags hold no material for goes alone. Packed into mails (see pack); each
--- mail's sets name "3 x Apprentice Ore", and the plan also says { crates, filled }.
function ns.PlanCrateMail()
  local total, take = bagPool()
  local groups, crates, filled = {}, 0, 0
  for _, crate in ipairs(ns.crates) do
    local n = total(crate.item)
    if n > 0 then
      local pieces = {}
      attach(take, pieces, crate.item, n, true)
      local cost = ns.CrateCost(crate)
      local bundles = {}
      for _, b in ipairs(crate.bundles) do bundles[#bundles + 1] = b end
      table.sort(bundles, function(a, b)
        local x, y = cost.bundles[a].each, cost.bundles[b].each
        if (x == nil) ~= (y == nil) then return x ~= nil end
        if x and y and x ~= y then return x < y end
        return a.count < b.count  -- unpriced: the one that takes fewer first
      end)
      local left = n
      for _, b in ipairs(bundles) do
        if left <= 0 then break end
        local fills = math.min(left, math.floor(total(b.item) / b.count))
        if fills > 0 then
          attach(take, pieces, b.item, fills * b.count)
          left = left - fills
        end
      end
      crates, filled = crates + n, filled + (n - left)
      groups[#groups + 1] = { name = ("%d x %s"):format(n, crate.name), pieces = pieces }
    end
  end
  local mails = pack(groups)
  mails.crates, mails.filled = crates, filled
  return mails
end

--- What the Transfer page mails, as chosen there: "writs" (one set of each) or "crates".
local function mailWhat()
  return ns.db and ns.db.mailWhat == "crates" and "crates" or "writs"
end

function ns.SetMailWhat(what)
  ns.db.mailWhat = what
  ns.Changed()
end

local function money(copper)
  if GetMoneyString then
    local ok, text = pcall(GetMoneyString, copper, true)
    if ok and text then return text end
  end
  return ns.Money(copper)
end

local function showMail(text, action)
  window.heading:SetText(("To %s  |cff808080(%d of %d)|r"):format(mail.name, mail.i, #mail.mails))
  window.text:SetText(text)
  if action then
    window.go:SetText(action)
    window.go:Enable()
  else
    window.go:SetText("Send")
    window.go:Disable()
  end
  window:Show()
end

local function endMail(message)
  if job then job = nil end
  local done = mail
  mail = nil
  if window then window:Hide() end
  if message and done then say(message) end
  ns.Changed()
end

local attachNext

local function subjectOf(m)
  local subject = mail.prefix .. table.concat(m.sets, ", ")
  if #subject > 60 then subject = subject:sub(1, 57) .. "..." end
  return subject
end

--- Put the recipient and subject in the game's own Send Mail fields, so they show.
local function fillFields(m)
  if SendMailNameEditBox and SendMailNameEditBox.SetText then
    pcall(SendMailNameEditBox.SetText, SendMailNameEditBox, mail.to)
  end
  if SendMailSubjectEditBox and SendMailSubjectEditBox.SetText then
    pcall(SendMailSubjectEditBox.SetText, SendMailSubjectEditBox, subjectOf(m))
  end
end

local function attachments()
  local n = 0
  for i = 1, MAX_ATTACH do if GetSendMailItem and GetSendMailItem(i) then n = n + 1 end end
  return n
end

--- The mail is packed: say what is in it and wait for Send.
local function ready()
  local m = mail.mails[mail.i]
  mail.state = "ready"
  fillFields(m)
  local postage = GetSendMailPrice and GetSendMailPrice() or 0
  showMail(table.concat(m.sets, ", ") .. "\n"
    .. ns.Color(GREY, ("%d attachment%s. Postage %s."):format(#m.pieces, #m.pieces == 1 and "" or "s", money(postage))), "Send")
end

function attachNext()
  local m = mail.mails[mail.i]
  mail.state, mail.recover = "attach", false
  showMail("Attaching...")
  runMoves(m.pieces, ready, function(message)
    mail.state = "failed"
    showMail(ns.Color(RED, "Stopped: " .. message), nil)
  end)
end

--- Send: in the click, so the game takes it as the player's.
local function onSend()
  if not mail or mail.state ~= "ready" then return end
  local m = mail.mails[mail.i]
  mail.state, mail.waited, mail.recover = "sending", 0, true
  -- As other mail addons do: no money and no cash on delivery, then send.
  if SetSendMailMoney then pcall(SetSendMailMoney, 0) end
  if SetSendMailCOD then pcall(SetSendMailCOD, 0) end
  SendMail(mail.to, subjectOf(m), "")
  if mail and mail.state == "sending" then showMail("Sending...") end
end

--- The mail went: on to the next, or done.
local function sentOne()
  mail.sent = mail.sent + 1
  if mail.i >= #mail.mails then
    return endMail(("Sent %d mail%s to %s."):format(mail.sent, mail.sent == 1 and "" or "s", mail.name))
  end
  mail.i = mail.i + 1
  mail.wait = 0.5  -- let the bags settle before attaching the next
  mail.state = "between"
end

local ADDON = ...
local mailEvents = CreateFrame("Frame")
for _, event in ipairs({ "MAIL_SHOW", "MAIL_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_SUCCESS", "MAIL_FAILED",
  "UI_ERROR_MESSAGE", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
  "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do
  pcall(mailEvents.RegisterEvent, mailEvents, event)
end
mailEvents:SetScript("OnEvent", function(_, event, ...)
  if event == "MAIL_SHOW" then
    mailOpen = true
    ns.Changed()
  elseif event == "MAIL_CLOSED" then
    mailOpen = false
    if mail then endMail(mail.sent > 0 and ("Mailbox closed. Sent %d."):format(mail.sent) or nil) end
    ns.Changed()
  elseif event == "BANKFRAME_OPENED" or event == "BANKFRAME_CLOSED" then
    bankOpen = event == "BANKFRAME_OPENED"
    ns.Changed()
  elseif event == "AUCTION_HOUSE_SHOW" or event == "AUCTION_HOUSE_CLOSED" then
    ns.Changed()
  elseif mail and mail.state == "sending" then
    -- WoW Forever says MAIL_SUCCESS (as other mail addons expect); some clients
    -- MAIL_SEND_SUCCESS.
    if event == "MAIL_SEND_SUCCESS" or event == "MAIL_SUCCESS" then
      sentOne()
    elseif event == "MAIL_FAILED" then
      mail.state = "failed"
      showMail(ns.Color(RED, "Not sent."), nil)
    elseif event == "UI_ERROR_MESSAGE" then
      local _, message = ...
      if type(message) == "string" then
        mail.state = "failed"
        showMail(ns.Color(RED, "Not sent: " .. message), nil)
      end
    elseif (event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN") and ... == ADDON then
      mail.state = "failed"
      showMail(ns.Color(RED, "Blocked. Press Send in the mailbox."), nil)
    end
  end
end)
mailEvents:SetScript("OnUpdate", function(_, elapsed)
  if not mail then return end
  if mail.state == "between" then
    mail.wait = mail.wait - elapsed
    if mail.wait <= 0 then attachNext() end
  elseif mail.state == "sending" then
    mail.waited = mail.waited + elapsed
    -- The game empties the mail once it has gone, event or not.
    if mail.waited > 1 and attachments() == 0 then return sentOne() end
  elseif mail.state == "failed" and mail.recover and attachments() == 0 then
    -- Sent after all, with the mailbox's own Send button.
    return sentOne()
  end
  if mail and mail.state == "sending" then
    if mail.waited > SEND_TIMEOUT then
      mail.state = "failed"
      showMail(ns.Color(RED, "No answer. Check sent mail before retrying."), nil)
    end
  end
end)

local function makeWindow()
  local parent = MailFrame or UIParent
  window = ns.Skin.Window("PuggerWaylaidCompanionMail", parent, 380, 130, "Mail")
  if parent == MailFrame then
    window:SetPoint("TOPLEFT", parent, "TOPRIGHT", 8, 0)
  else
    window:SetPoint("CENTER", 0, 120)
  end
  window:SetFrameStrata("DIALOG")
  window:SetToplevel(true)
  window:EnableMouse(true)
  window:Hide()

  window.heading = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  window.heading:SetPoint("TOPLEFT", 16, -36)
  window.heading:SetPoint("TOPRIGHT", -16, -36)
  window.heading:SetJustifyH("LEFT")
  window.heading:SetTextColor(unpack(ns.Skin.color.accent))

  window.text = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  window.text:SetPoint("TOPLEFT", window.heading, "BOTTOMLEFT", 0, -8)
  window.text:SetPoint("TOPRIGHT", window.heading, "BOTTOMRIGHT", 0, -8)
  window.text:SetJustifyH("LEFT")
  window.text:SetJustifyV("TOP")

  window.go = ns.Skin.Button(window, "", 110, 22)
  window.go:SetPoint("BOTTOMLEFT", 16, 14)
  window.go:SetScript("OnClick", onSend)

  window.cancel = ns.Skin.Button(window, "Close", 90, 22)
  window.cancel:SetPoint("BOTTOMRIGHT", -16, 14)
  window.cancel:SetScript("OnClick", function() endMail(nil) end)

  window:SetScript("OnHide", function() if mail then endMail(nil) end end)
end

--- One-click mail targets: the account's other characters on this realm, then the names
--- saved by hand. { { name, address, saved }, ... }; address is the full "Name Surname",
--- nil for a character the addon hasn't seen played yet.
function ns.MailRecipients()
  local db, me, seen, out = ns.db, ns.Character(), {}, {}
  for _, source in ipairs({ db.bags or {}, db.bank or {}, db.mail or {} }) do
    for key in pairs(source) do
      local name = ns.CharacterName(key)
      if key ~= me and not seen[key] and not name:find("-", 1, true) then
        seen[key] = true
        local address = ns.MailAddress(key)
        out[#out + 1] = { name = address or name, address = address }
        if address then seen[address:lower()] = true end
      end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  for _, address in ipairs(db.mailTargets or {}) do
    if not seen[address:lower()] then
      seen[address:lower()] = true
      out[#out + 1] = { name = address, address = address, saved = true }
    end
  end
  return out
end

--- A typed name, tidied: spaces trimmed and doubled spaces made single.
local function tidy(text)
  return ((text or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " "))
end

--- Keep a typed name as a one-click target.
function ns.SaveMailTarget(address)
  address = tidy(address)
  if address == "" then return end
  ns.db.mailTargets = ns.db.mailTargets or {}
  for _, a in ipairs(ns.db.mailTargets) do if a:lower() == address:lower() then return end end
  table.insert(ns.db.mailTargets, address)
  ns.Changed()
end

function ns.ForgetMailTarget(address)
  for i, a in ipairs(ns.db.mailTargets or {}) do
    if a == address then table.remove(ns.db.mailTargets, i) break end
  end
  ns.Changed()
end

--- How many sets the bags hold for mail.
function ns.MailSetCount()
  local n = 0
  for _, m in ipairs(ns.PlanMail()) do n = n + #m.sets end
  return n
end

--- Bring up the mailbox's Send Mail tab, as a click on the tab would; whether it shows.
local function showSendTab()
  if not (SendMailFrame and SendMailFrame.IsShown) or SendMailFrame:IsShown() then return true end
  local tab = MailFrameTab2
  if tab and tab.Click then pcall(tab.Click, tab) end
  if not SendMailFrame:IsShown() and MailFrameTab_OnClick then pcall(MailFrameTab_OnClick, tab, 2) end
  return SendMailFrame:IsShown()
end

--- Mail to "Name Surname" what the Transfer page has chosen: one set of each writ in the
--- bags, or every crate with the material to fill it. On the inbox tab, it switches to
--- Send Mail first.
function ns.MailSets(address)
  address = tidy(address)
  if address == "" then return say("Enter a name.") end
  if not mailOpen then return say("Open a mailbox.") end
  if job or mail then return say("A transfer is running.") end
  local crates = mailWhat() == "crates"
  local mails = crates and ns.PlanCrateMail() or ns.PlanMail()
  if #mails == 0 then return say(crates and "No crate in bags." or "No full set in bags.") end
  if not showSendTab() then return say("Open the Send Mail tab.") end
  if attachments() > 0 then return say("Clear the mail's attachments.") end
  if not window then makeWindow() end
  mail = { to = address, name = address, prefix = crates and "Crates: " or "Writs: ", mails = mails,
    i = 1, sent = 0, waited = 0 }
  attachNext()
end

-- ---------------------------------------------------------------------------
-- The Transfer page
-- ---------------------------------------------------------------------------

local function sum(moves)
  local writs, material = 0, 0
  for _, m in ipairs(moves) do
    if m.writ then writs = writs + m.left else material = material + m.left end
  end
  return writs, material
end

local OPEN, SHUT = "ff40d040", "ff808080"

local function stateText(open, what)
  return open and ns.Color(OPEN, what .. " open") or ns.Color(SHUT, what .. " closed")
end

--- The page: Mail, Bank and Buying, each a heading, a state line and its buttons.
--- UI.lua places it and calls Refresh.
function ns.BuildTransfer(parent, width)
  local f = CreateFrame("Frame", nil, parent)
  local PER_ROW, BUTTON_W = 3, math.floor((width - 40) / 3)

  local function heading(text, top)
    local h = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    h:SetPoint("TOPLEFT", 10, top)
    h:SetText(text)
    ns.Skin.Plain(h)
    return h
  end
  local function line(top, font)
    local l = f:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
    l:SetPoint("TOPLEFT", 10, top)
    l:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    l:SetJustifyH("LEFT")
    return l
  end
  local function button(text, w, onClick)
    local b = ns.Skin.Button(f, text, w, 22)
    b:SetScript("OnClick", onClick)
    return b
  end

  -- Mail
  heading("Mail", -4)
  f.mailState = line(-28)
  f.mailNote = line(-44, "GameFontDisableSmall")
  -- What the buttons below mail: writ sets or crates.
  f.whatLabel = line(-70)
  f.whatLabel:SetText("Mail")
  f.what = {}
  for i, w in ipairs({ { "writs", "Writ sets" }, { "crates", "Crates" } }) do
    local c = ns.Skin.Choice(f, 100, 22)
    c:SetText(w[2])
    c:SetPoint("TOPLEFT", 60 + (i - 1) * 106, -64)
    c:SetScript("OnClick", function() ns.SetMailWhat(w[1]) end)
    c.what = w[1]
    f.what[i] = c
  end
  f.targets = {}
  f.forget = {}
  f.custom = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  f.custom:SetSize(BUTTON_W - 10, 20)
  f.custom:SetAutoFocus(false)
  f.custom:SetMaxLetters(40)
  f.custom.hint = f.custom:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  f.custom.hint:SetPoint("LEFT", 4, 0)
  f.custom.hint:SetText("Name Surname")
  f.custom:SetScript("OnTextChanged", function(self)
    if (self:GetText() or "") == "" then self.hint:Show() else self.hint:Hide() end
  end)
  f.custom:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  f.custom:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    ns.MailSets(self:GetText())
  end)
  f.send = button("Send", 80, function() f.custom:ClearFocus() ns.MailSets(f.custom:GetText()) end)
  f.save = button("Save", 80, function()
    ns.SaveMailTarget(f.custom:GetText())
    f.custom:SetText("")
    f.custom:ClearFocus()
  end)

  -- Bank and Buying sit under the mail targets; Refresh places them.
  f.bankHeading = heading("Bank", 0)
  f.bankState = line(0)
  f.bankNote = line(0, "GameFontDisableSmall")
  -- Two rows, Bank to bags and Bags to bank, each with 1 of each, Extra and All writs.
  local MODES = { { "one", "1 of each" }, { "extra", "Extra" }, { "all", "All writs" } }
  local SMALL_W = math.floor((width - 150) / 3) - 6
  f.bankRows = {}
  for r, way in ipairs({ { "in", "Bank to bags" }, { "out", "Bags to bank" } }) do
    local row = { way = way[1], label = line(0), buttons = {} }
    row.label:SetText(way[2])
    for i, m in ipairs(MODES) do
      row.buttons[i] = button(m[2], SMALL_W, function() ns.Bank(way[1], m[1]) end)
      row.buttons[i].mode, row.buttons[i].label = m[1], m[2]
    end
    f.bankRows[r] = row
  end
  f.buyHeading = heading("Buying", 0)
  f.buyState = line(0)
  f.buy = button("Buy missing material", BUTTON_W, ns.BuyMissing)
  f.buyNote = line(0, "GameFontDisableSmall")

  local function place(region, top, left)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", left or 10, top)
  end

  function f:Refresh()
    -- Mail
    local what = mailWhat()
    for _, c in ipairs(self.what) do c:SetActive(c.what == what) end
    local sets, note
    if what == "crates" then
      local plan = ns.PlanCrateMail()
      sets = plan.crates
      self.mailState:SetText(stateText(mailOpen, "Mailbox")
        .. ("   Crates in bags: %d, material for %d"):format(plan.crates, plan.filled))
      note = "Every crate, with the material in the bags to fill it: cheapest first, by the last AH prices."
    else
      sets = ns.MailSetCount()
      self.mailState:SetText(stateText(mailOpen, "Mailbox") .. ("   Sets in bags: %d"):format(sets))
      note = "One set per writ: the writ and its material."
    end
    self.mailNote:SetText(note)
    local targets = ns.MailRecipients()
    local unknown = false
    for _, b in ipairs(self.targets) do b:Hide() end
    for _, b in ipairs(self.forget) do b:Hide() end
    local top = -94
    for i, t in ipairs(targets) do
      local b = self.targets[i]
      if not b then
        b = button("", BUTTON_W, nil)
        self.targets[i] = b
      end
      local col, rowN = (i - 1) % PER_ROW, math.floor((i - 1) / PER_ROW)
      place(b, top - rowN * 26, 10 + col * (BUTTON_W + 10))
      b:SetText(t.name)
      b:SetEnabled(mailOpen and sets > 0 and t.address ~= nil)
      b:SetScript("OnClick", function() ns.MailSets(t.address) end)
      b:Show()
      if not t.address then unknown = true end
      if t.saved then
        local x = self.forget[i]
        if not x then
          x = ns.Skin.Cross(f, ns.Skin.Classic() and 20 or 18, 9)
          self.forget[i] = x
        end
        x:ClearAllPoints()
        if ns.Skin.Classic() then
          x:SetPoint("LEFT", b, "RIGHT", -4, 0)
        else
          -- Inside the name's button, at its right end: the gap to the next is narrow.
          x:SetPoint("RIGHT", b, "RIGHT", -2, 0)
        end
        x:SetFrameLevel(b:GetFrameLevel() + 2)
        x:SetScript("OnClick", function() ns.ForgetMailTarget(t.address) end)
        x:Show()
      end
    end
    local rows = math.ceil(#targets / PER_ROW)
    top = top - rows * 26
    if unknown then
      self.mailNote:SetText(note .. " Grey: log in once to learn the surname.")
    end
    place(self.custom, top - 2, 16)
    self.send:ClearAllPoints()
    self.send:SetPoint("LEFT", self.custom, "RIGHT", 8, 0)
    self.save:ClearAllPoints()
    self.save:SetPoint("LEFT", self.send, "RIGHT", 6, 0)
    self.send:SetEnabled(mailOpen and sets > 0)
    top = top - 40

    -- Bank
    place(self.bankHeading, top)
    place(self.bankState, top - 24)
    self.bankState:SetText(stateText(bankOpen, "Bank"))
    place(self.bankNote, top - 40)
    self.bankNote:SetText("1 of each: writ and material. Extra: all but one of each. All writs: every writ.")
    for r, row in ipairs(self.bankRows) do
      local y = top - 58 - (r - 1) * 28
      place(row.label, y - 4)
      for i, b in ipairs(row.buttons) do
        place(b, y, 130 + (i - 1) * (b:GetWidth() + 6))
        local writs, material = sum(bankOpen and ns.PlanBank(row.way, b.mode) or {})
        b:SetText(bankOpen and ("%s (%d)"):format(b.label, writs + material) or b.label)
        b:SetEnabled(bankOpen and writs + material > 0)
      end
    end
    top = top - 124

    -- Buying
    local ah = ns.AuctionHouseOpen and ns.AuctionHouseOpen()
    local missing = ns.MissingMaterials()
    place(self.buyHeading, top)
    place(self.buyState, top - 24)
    self.buyState:SetText(stateText(ah, "Auction house"))
    place(self.buy, top - 42)
    self.buy:SetEnabled(ah and ns.CanBuy() and #missing > 0)
    place(self.buyNote, top - 68)
    local names = {}
    for _, m in ipairs(missing) do names[#names + 1] = ("%d x %s"):format(m.need, m.name) end
    self.buyNote:SetText(#missing > 0 and ("Missing for writs in bags: " .. table.concat(names, ", ") .. ".")
      or "No material missing for writs in bags.")
  end

  return f
end
