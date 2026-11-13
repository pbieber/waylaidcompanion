--[[
The window: a menu down the left, a page on the right.

  Overview           - rep and what is left today (Overview.lua)
  Craftsman's Writs  - every writ, by tier, profession or cost
  Waylaid Crates     - every crate and its material, by tier or profession
  Turn-ins           - where writs and crates go; the same places Map.lua marks
  Rewards            - the quartermaster's items (Rewards.lua)
  Transfer           - mail, bank and buying (Transfer.lua)

Each list page builds plain entries ({ header = ... } or { cells = {...} }) and hands them
to one shared list, which draws them with pooled rows.
]]

local _, ns = ...
if not CreateFrame then return end

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local WIDTH, HEIGHT, MENU = 920, 560, 170
local ROW, CELLS, HEAD = 20, 7, 18
local GREY, GOLD, GREEN, ORANGE = "ff808080", "ffffd100", "ff40d040", "ffff8040"

local window, list, sortBar, note, scanBar
local panels = {}  -- the pages that aren't lists: overview, transfer
local refresh
local pages = {}

-- ---------------------------------------------------------------------------
-- The shared list
-- ---------------------------------------------------------------------------

local function showTooltip(row)
  local entry = row.entry
  if not entry then return end
  -- A tip can be worked out at the hover, when it depends on where the player is.
  local tip = entry.tip
  if type(tip) == "function" then tip = tip() end
  if entry.item then
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then
      GameTooltip:SetItemByID(entry.item)
    else
      GameTooltip:SetHyperlink("item:" .. entry.item)
    end
    if tip then GameTooltip:AddLine(tip, 0.8, 0.8, 0.8, true) end
    -- Costs and holdings, worked out now so they are as fresh as the hover.
    for _, line in ipairs(entry.lines and entry.lines() or {}) do
      if line[2] then
        GameTooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 1, 1, 1)
      else
        GameTooltip:AddLine(line[1], 1, 1, 1)
      end
    end
    GameTooltip:Show()
  elseif tip then
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(tip, 1, 1, 1, true)
    GameTooltip:Show()
  end
end

local function makeRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(ROW)
  row.stripe = row:CreateTexture(nil, "BACKGROUND")
  row.stripe:SetAllPoints()
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ROW - 4, ROW - 4)
  row.cells = {}
  for i = 1, CELLS do
    local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    row.cells[i] = text
  end
  row:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")
  row:SetScript("OnEnter", showTooltip)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:SetScript("OnClick", function(self)
    if self.entry and self.entry.click then self.entry.click() end
  end)
  return row
end

local function makeList(parent)
  local l = {}
  l.scroll = CreateFrame("ScrollFrame", "PuggerWaylaidCompanionScroll", parent, "UIPanelScrollFrameTemplate")
  l.child = CreateFrame("Frame", nil, l.scroll)
  l.child:SetSize(10, 10)
  l.scroll:SetScrollChild(l.child)
  l.rows = {}

  -- The column headings, a row of their own above the list that does not scroll. A
  -- heading with a tip explains itself on hover.
  l.head = CreateFrame("Frame", nil, parent)
  l.head:SetHeight(HEAD)
  local shade = l.head:CreateTexture(nil, "BACKGROUND")
  shade:SetAllPoints()
  shade:SetColorTexture(0, 0, 0, 0.4)
  l.head.cells = {}
  for i = 1, CELLS do
    local cell = CreateFrame("Button", nil, l.head)
    cell:SetHeight(HEAD)
    cell.text = cell:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    cell.text:SetAllPoints()
    cell.text:SetJustifyH("LEFT")
    cell.text:SetWordWrap(false)
    cell:SetScript("OnEnter", function(self)
      if not self.tip then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(self.label, 1, 0.82, 0)
      GameTooltip:AddLine(self.tip, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    l.head.cells[i] = cell
  end

  --- Draw entries. `columns` is the left edge of each cell, the last entry the width;
  --- `headings` names the columns, each a text or { text, tip }.
  function l:Set(entries, columns, headings)
    local width = columns[#columns]
    for c, cell in ipairs(self.head.cells) do
      local heading = headings and headings[c]
      if heading and c < #columns then
        local label, tip = heading, nil
        if type(heading) == "table" then label, tip = heading[1], heading[2] end
        local left = columns[c] + (c == 1 and ROW + 4 or 0)
        cell:ClearAllPoints()
        cell:SetPoint("LEFT", left, 0)
        cell:SetWidth(columns[c + 1] - left - 6)
        cell.text:SetText(tip and (label .. " |cff808080(?)|r") or label)
        cell.label, cell.tip = label, tip
        cell:Show()
      else
        cell:Hide()
      end
    end
    self.child:SetWidth(width)
    for i, entry in ipairs(entries) do
      local row = self.rows[i]
      if not row then
        row = makeRow(self.child)
        self.rows[i] = row
      end
      row.entry = entry
      row:SetWidth(width)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
      local indent = entry.indent or 0
      if entry.header then
        row.stripe:SetColorTexture(1, 0.82, 0, 0.12)
        row.icon:Hide()
        row.cells[1]:ClearAllPoints()
        row.cells[1]:SetPoint("LEFT", 6, 0)
        row.cells[1]:SetWidth(width - 12)
        row.cells[1]:SetFontObject("GameFontNormal")
        row.cells[1]:SetText(entry.header)
        for c = 2, CELLS do row.cells[c]:SetText("") end
      else
        row.stripe:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
        if entry.icon then
          row.icon:SetTexture(entry.icon)
          row.icon:ClearAllPoints()
          row.icon:SetPoint("LEFT", 4 + indent, 0)
          row.icon:Show()
        else
          row.icon:Hide()
        end
        for c = 1, CELLS do
          local cell = row.cells[c]
          local x = columns[c]
          local value = entry.cells[c]
          if x and c < #columns and value then
            local left = x + (c == 1 and indent + ROW + 4 or 0)
            cell:ClearAllPoints()
            cell:SetPoint("LEFT", left, 0)
            cell:SetWidth(columns[c + 1] - left - 6)
            cell:SetFontObject("GameFontHighlightSmall")
            cell:SetText(value)
          else
            cell:SetText("")
          end
        end
      end
      row:EnableMouse(not entry.header or entry.click ~= nil)
      row:Show()
    end
    for i = #entries + 1, #self.rows do self.rows[i]:Hide() end
    self.child:SetHeight(math.max(1, #entries * ROW))
  end
  return l
end

-- ---------------------------------------------------------------------------
-- Pages
-- ---------------------------------------------------------------------------

local STATE_TEXT = {
  done = ns.Color(GREY, "Done"),
  ready = ns.Color(GREEN, "Ready"),
  holding = ns.Color(GOLD, "In bags"),
  open = "",
}

--- The cost per 100 reputation column: the price, "+ ?" when a part of it has no price
--- and "*" when a price it is made of is old.
local function costText(cost)
  if not ns.HasPrices() then return "" end
  if not cost.per100 then return ns.Color(GREY, "no price") end
  local text = ns.Coins(cost.per100)
  if cost.partial then text = text .. ns.Color(ORANGE, " + ?") end
  if cost.old then text = text .. ns.Color(ORANGE, " *") end
  return text
end

--- Tooltip lines for a writ's cost per 100 reputation, and what is wrong with it if anything.
local function per100Lines(lines, cost, itemName)
  if not cost.per100 then return end
  lines[#lines + 1] = { ns.Color(GOLD, "Cost / 100 rep"),
    ns.Coins(cost.per100) .. (cost.partial and " + ?" or "") }
  if cost.partial then
    lines[#lines + 1] = { ns.Color(ORANGE, ("  No price: %s"):format(cost.writ and itemName or "writ")) }
  end
  if cost.old then
    lines[#lines + 1] = { ns.Color(ORANGE, ("  Price %d days old"):format(cost.age)) }
  end
end

--- Tooltip lines for a cost: the total, then its parts ({ label, copper or nil }) when
--- there is more than one.
local function costLines(lines, parts)
  if not ns.HasPrices() then
    lines[#lines + 1] = { ns.Color(GOLD, "Cost"), ns.Color(GREY, "Scan the AH.") }
    return
  end
  local total, known, missing = 0, false, false
  for _, part in ipairs(parts) do
    if part[2] then total, known = total + part[2], true else missing = true end
  end
  local text = known and (ns.Coins(total) .. (missing and " + ?" or "")) or ns.Color(GREY, "no price")
  lines[#lines + 1] = { ns.Color(GOLD, "Cost"), text }
  if #parts > 1 then
    for _, part in ipairs(parts) do
      lines[#lines + 1] = { "  " .. part[1], part[2] and ns.Coins(part[2]) or ns.Color(GREY, "no price") }
    end
  end
end

--- Tooltip lines for how many of an item the account has (of `need`, when given), and
--- which character has them where.
local function holdingLines(lines, label, id, need)
  local held = ns.AccountHoldings(id)
  local count = tostring(held.total)
  if need then
    count = ns.Color(held.total >= need and GREEN or (held.total > 0 and GOLD or GREY), ("%d / %d"):format(held.total, need))
  end
  lines[#lines + 1] = { ns.Color(GOLD, label), count }
  for _, h in ipairs(held.chars) do
    lines[#lines + 1] = { ns.Color(GREY, ("  %s: bags %d, bank %d, mail %s"):format(h.name,
      h.bags, h.bank, h.mailSeen and tostring(h.mail) or "?")) }
  end
end

--- The Owned column: how many writs the account has. Those on this character show as a
--- bare number; of the other characters the first is named with its count, or the first
--- two with the option on, and the rest are added up after them.
local function ownedText(id)
  local held = ns.AccountHoldings(id)
  if held.total == 0 then return "" end
  local parts, rest, named = {}, held.total, 0
  local names = 1
  for _, h in ipairs(held.chars) do
    if h.current then
      parts[#parts + 1] = tostring(h.total)
    elseif named < names then
      parts[#parts + 1] = h.name .. " " .. h.total
      named = named + 1
    else
      break
    end
    rest = rest - h.total
  end
  local text = ns.Color(GOLD, table.concat(parts, ", "))
  if rest > 0 then text = text .. ns.Color(GREY, " +" .. rest) end
  return text
end

local FOLDED = "|TInterface/Buttons/UI-PlusButton-Up:14:14|t "
local UNFOLDED = "|TInterface/Buttons/UI-MinusButton-Up:14:14|t "

--- A group's header row, which folds the group away or opens it again on a click, and
--- whether the group is folded. Remembered per page, sort and group.
local function groupHeader(page, sort, group, text)
  local key = ("%s:%s:%s"):format(page, sort, tostring(group))
  local folded = ns.db.collapsed[key] == true
  return {
    header = (folded and FOLDED or UNFOLDED) .. text,
    click = function()
      ns.db.collapsed[key] = (not folded) or nil
      refresh()
    end,
  }, folded
end

local function writEntry(writ, sort, cost)
  local name, icon = ns.Item(writ.item, writ.name)
  local itemName = name
  if writ.count > 1 then name = writ.count .. " x " .. name end
  local npc = ns.WritNpc(writ)
  local second
  if sort == "profession" then
    second = ns.Color(ns.WRIT_COLOR[writ.tier], ns.WRIT_TIERS[writ.tier]) .. " " .. writ.skill
  else
    second = ("%s %d"):format(writ.profession, writ.skill)
  end
  local tip = "Craftsman's Writ: " .. writ.name .. "\nDaily."
  if npc then
    tip = tip .. ("\nTurn in: %s, %s (%.1f, %.1f)"):format(npc.name, npc.zone, npc.x, npc.y)
  else
    tip = tip .. "\nTurn-in unknown. Saved when you accept the quest."
  end
  if writ.side then
    tip = tip .. "\n" .. (writ.side == "A" and "Alliance only." or "Horde only.")
  end
  return {
    icon = icon,
    item = writ.item,
    tip = function()
      if ns.AuctionHouseOpen() and ns.CanBuy() then
        return tip .. "\n|cff40d040Click: buy.|r"
      end
      return npc and (tip .. "\nClick: map.") or tip
    end,
    lines = function()
      local lines = { { " " } }
      local now = ns.WritCost(writ)
      costLines(lines, { { "Writ", now.writ }, { name, now.material } })
      per100Lines(lines, now, itemName)
      lines[#lines + 1] = { " " }
      holdingLines(lines, "Owned: writ", writ.writItem)
      holdingLines(lines, "Owned: " .. itemName, writ.item, writ.count)
      return lines
    end,
    cells = {
      ns.Color(ns.WRIT_COLOR[writ.tier], name),
      second,
      "+" .. ns.WRIT_REP[writ.tier],
      costText(cost),
      ownedText(writ.writItem),
      npc and npc.zone or ns.Color(GREY, "Unknown"),
      STATE_TEXT[ns.WritState(writ)],
    },
    click = function()
      if ns.AuctionHouseOpen() and ns.CanBuy() then
        ns.BuyForWrit(writ)
      elseif npc then
        ns.OpenMap(npc.map)
      end
    end,
  }
end

-- Writ, profession or tier, rep, cost per 100 rep, owned, zone, today.
local WRIT_COLUMNS = { 0, 195, 290, 328, 432, 548, 655, 710 }

local COST_TIP = "Writ and material per 100 rep, at AH prices (your scan or Auctionator, newest).\n"
  .. "+ ?  a part has no price.\n"
  .. "*  a price is %d+ days old."
--- The Owned heading's tip, for writs or crates.
local function ownedTip(what)
  return what .. " on all characters: bags, bank, mail.\nA number alone: this character.\n"
    .. "Show both names: first name and surname."
end

--- Where a writ goes when sorted by cost: 1 every part priced, 2 a part unpriced, 3 none.
local function costRank(cost)
  if not cost.per100 then return 3 end
  return cost.partial and 2 or 1
end
local COST_GROUPS = { "priced", "partial", "none" }
local COST_HEADERS = {
  priced = "Priced",
  partial = "Price incomplete",
  none = "No price",
}

pages.writs = {
  title = "Craftsman's Writs",
  sortKey = "writSort",
  sorts = { { "level", "By tier" }, { "profession", "By profession" }, { "cost", "By cost" } },
  footer = "scan",
  build = function()
    local sort = ns.db.writSort
    local sorted, costs = {}, {}
    for _, writ in ipairs(ns.writs) do
      if ns.ForPlayer(writ) then
        sorted[#sorted + 1] = writ
        costs[writ] = ns.WritCost(writ)
      end
    end
    table.sort(sorted, function(a, b)
      if sort == "cost" then
        -- Complete prices first, then those with a part unpriced, then none at all: a
        -- figure missing the writ or its material would look cheaper than it is.
        local ra, rb = costRank(costs[a]), costRank(costs[b])
        if ra ~= rb then return ra < rb end
        local x, y = costs[a].per100, costs[b].per100
        if x and y and x ~= y then return x < y end
      end
      if sort == "profession" then
        if a.profession ~= b.profession then return a.profession < b.profession end
        if a.tier ~= b.tier then return a.tier < b.tier end
      else
        if a.tier ~= b.tier then return a.tier < b.tier end
        if a.profession ~= b.profession then return a.profession < b.profession end
      end
      if a.skill ~= b.skill then return a.skill < b.skill end
      return a.name < b.name
    end)
    local entries, last, folded = {}, nil, false
    for _, writ in ipairs(sorted) do
      local group
      if sort == "cost" then
        group = COST_GROUPS[costRank(costs[writ])]
      elseif sort == "profession" then
        group = writ.profession
      else
        group = writ.tier
      end
      if group ~= last then
        last = group
        local header
        if sort == "cost" then
          header = COST_HEADERS[group]
        elseif sort == "profession" then
          header = writ.profession
        else
          header = ("%s  +%d rep each"):format(ns.WRIT_TIERS[writ.tier], ns.WRIT_REP[writ.tier])
        end
        entries[#entries + 1], folded = groupHeader("writs", sort, group, header)
      end
      if not folded then entries[#entries + 1] = writEntry(writ, sort, costs[writ]) end
    end
    local headings = {
      "Writ", sort == "profession" and "Tier" or "Profession", "Rep",
      { "Cost / 100 rep", COST_TIP:format(ns.OLD_PRICE_DAYS) },
      { "Owned", ownedTip("Writs") }, "Zone", "Today",
    }
    return entries, WRIT_COLUMNS, nil, headings
  end,
}

local CRATE_COLUMNS = { 0, 290, 400, 500, 710 }

--- The Merchant's Favor column for a crate tier, and the line for its tooltip.
local function favorText(tier)
  local amounts = ns.CrateFavor(tier)
  if #amounts == 0 then
    return ns.Color(GREY, "Unknown"), "Merchant's Favor unknown. Saved on turn-in."
  end
  local text = table.concat(amounts, " or ")
  if #amounts > 1 then
    return text, "Merchant's Favor: " .. table.concat(amounts, " or ") .. ", by crate quality."
  end
  return text, "Merchant's Favor: " .. amounts[1] .. "."
end

pages.crates = {
  title = "Waylaid Crates",
  sortKey = "crateSort",
  sorts = { { "level", "By tier" }, { "profession", "By profession" } },
  build = function()
    local byLevel = ns.db.crateSort == "level"
    local kindOrder = {}
    for i, kind in ipairs(ns.CRATE_KINDS) do kindOrder[kind] = i end
    local sorted = {}
    for _, crate in ipairs(ns.crates) do sorted[#sorted + 1] = crate end
    table.sort(sorted, function(a, b)
      if byLevel then
        if a.tier ~= b.tier then return a.tier < b.tier end
        if a.kind ~= b.kind then return kindOrder[a.kind] < kindOrder[b.kind] end
      else
        if a.kind ~= b.kind then return kindOrder[a.kind] < kindOrder[b.kind] end
        if a.tier ~= b.tier then return a.tier < b.tier end
      end
      return a.name < b.name
    end)
    local entries, last, folded = {}, nil, false
    for _, crate in ipairs(sorted) do
      local group = byLevel and crate.tier or crate.kind
      if group ~= last then
        last = group
        local header
        if byLevel then
          header = ("%s  Level %d"):format(ns.CRATE_TIERS[crate.tier], ns.CRATE_LEVEL[crate.tier])
        else
          header = ("%s  (%s)"):format(crate.kind, ns.CRATE_SKILL[crate.kind])
        end
        entries[#entries + 1], folded = groupHeader("crates", ns.db.crateSort, group, header)
      end
      if not folded then
        local _, icon = ns.Item(crate.item)
        local favor, favorTip = favorText(crate.tier)
        entries[#entries + 1] = {
          icon = icon,
          item = crate.item,
          tip = "Needs one material below.\n" .. favorTip,
          lines = function()
            local lines = { { " " } }
            local cost = ns.CrateCost(crate)
            local b = cost.bundle
            costLines(lines, {
              { "Crate", cost.crate },
              { b and ("%d x %s (cheapest)"):format(b.count, ns.Item(b.item, b.name)) or "Material", cost.material },
            })
            return lines
          end,
          cells = {
            ns.Color(ns.CRATE_COLOR[crate.tier], "Waylaid Crate: " .. crate.name),
            byLevel and ns.CRATE_SKILL[crate.kind] or ("Level " .. ns.CRATE_LEVEL[crate.tier]),
            ownedText(crate.item),
            favor,
          },
        }
        for _, bundle in ipairs(crate.bundles) do
          local name, bundleIcon = ns.Item(bundle.item, bundle.name)
          local have = ns.Count(bundle.item)
          local color = have >= bundle.count and GREEN or (have > 0 and GOLD or GREY)
          entries[#entries + 1] = {
            icon = bundleIcon,
            item = bundle.item,
            indent = 22,
            lines = function()
              local lines = { { " " } }
              local each = ns.Price(bundle.item)
              costLines(lines, { { name, each and each * bundle.count } })
              if each and bundle.count > 1 then lines[#lines + 1] = { "  Each", ns.Coins(each) } end
              return lines
            end,
            cells = {
              ("%d x %s"):format(bundle.count, name),
              ns.Color(color, ("%d / %d"):format(have, bundle.count)),
              "",
            },
          }
        end
      end
    end
    local camp = ns.Camp()
    local where = camp and ("Turn in: %s, %s (%.1f, %.1f)."):format(camp.name, camp.zone, camp.x, camp.y)
      or "Turn in: your faction's camp."
    return entries, CRATE_COLUMNS, "One material per crate. " .. where,
      { "Crate", byLevel and "Profession" or "Level", { "Owned", ownedTip("Crates") }, "Merchant's Favor" }
  end,
}

local STOP_COLUMNS = { 0, 230, 400, 480, 710 }

pages.turnins = {
  title = "Turn-ins",
  build = function()
    local entries = {}
    local camp = ns.Camp()
    if camp then
      entries[#entries + 1] = { header = "Waylaid Crates" }
      entries[#entries + 1] = {
        icon = "Interface/Icons/INV_Crate_01",
        tip = camp.faction .. "\nClick: map.",
        cells = { camp.name, camp.zone, ("%.1f, %.1f"):format(camp.x, camp.y), "All crates" },
        click = function() ns.OpenMap(camp.map) end,
      }
    end
    -- Writ turn-ins, a continent at a time.
    local stops = ns.Stops()
    local order = {}
    for i, stop in ipairs(stops) do
      stop.continent = ns.Continent(stop.npc.map)
      order[stop] = i
    end
    table.sort(stops, function(x, y)
      if x.continent ~= y.continent then
        -- Whatever the game can't place goes last.
        if x.continent == "Elsewhere" then return false end
        if y.continent == "Elsewhere" then return true end
        return x.continent < y.continent
      end
      return order[x] < order[y]
    end)
    local continent
    for _, stop in ipairs(stops) do
      if stop.continent ~= continent then
        continent = stop.continent
        entries[#entries + 1] = { header = "Craftsman's Writs: " .. continent }
      end
      local npc = stop.npc
      local names = {}
      for _, writ in ipairs(stop.writs) do
        local state = ns.WritState(writ)
        names[#names + 1] = ns.Color(ns.WRIT_COLOR[writ.tier], writ.name)
          .. (state == "done" and ns.Color(GREY, " (done)") or "")
      end
      local status
      if stop.open == 0 then
        status = ns.Color(GREY, "Done")
      elseif stop.held > 0 then
        status = ns.Color(GREEN, ("%d in bags"):format(stop.held))
      else
        status = ("%d of %d open"):format(stop.open, #stop.writs)
      end
      entries[#entries + 1] = {
        icon = "Interface/Icons/INV_Misc_Note_01",
        tip = npc.name .. "\n" .. table.concat(names, "\n") .. "\nClick: map.",
        cells = { npc.name, npc.zone, ("%.1f, %.1f"):format(npc.x, npc.y), status },
        click = function() ns.OpenMap(npc.map) end,
      }
    end
    local known, total = ns.KnownTurnIns()
    return entries, STOP_COLUMNS,
      ("On the world map (/pwc map). Known turn-ins: %d of %d."):format(known, total),
      { "NPC", "Zone", "Location", "Today" }
  end,
}

local REWARD_COLUMNS = { 0, 300, 420, 600, 710 }

--- A reward's price: money, then other costs ("5 Merchant's Favor").
local function rewardCost(item)
  local parts = {}
  if item.price and item.price > 0 then parts[#parts + 1] = ns.Coins(item.price) end
  for _, c in ipairs(item.costs or {}) do
    local icon = c.icon and ("|T%s:0|t "):format(tostring(c.icon)) or ""
    parts[#parts + 1] = ("%s%d %s"):format(icon, c.value, c.name)
  end
  return #parts > 0 and table.concat(parts, ", ") or ns.Color(GREY, "Free")
end

pages.rewards = {
  title = "Rewards",
  build = function()
    local saved, rep = ns.Rewards()
    local headings = { "Item", "Standing", "Cost", "Status" }
    if not rep then return {}, REWARD_COLUMNS, "Faction unknown.", headings end
    if not saved then
      return {}, REWARD_COLUMNS, "Not seen yet. Open each quartermaster's shop once.", headings
    end
    -- One group per quartermaster, by name; its items by standing, then name.
    local shops = {}
    for key, shop in pairs(saved) do shops[#shops + 1] = { key = key, shop = shop } end
    table.sort(shops, function(a, b) return (a.shop.npc or "") < (b.shop.npc or "") end)
    local entries = {}
    for _, s in ipairs(shops) do
      local header, folded = groupHeader("rewards", "npc", s.key,
        ("%s (%d)"):format(s.shop.npc or "Quartermaster", #s.shop.items))
      entries[#entries + 1] = header
      if not folded then
        local items = {}
        for _, item in ipairs(s.shop.items) do items[#items + 1] = item end
        table.sort(items, function(a, b)
          local x, y = a.standing or 0, b.standing or 0
          if x ~= y then return x < y end
          return (a.name or "") < (b.name or "")
        end)
        for _, item in ipairs(items) do
          local name, icon = ns.Item(item.id, item.name)
          local quality = GetItemInfo and select(3, GetItemInfo(item.id))
          local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
          if color and color.hex then name = color.hex .. name .. "|r" end
          if (item.quantity or 1) > 1 then name = item.quantity .. " x " .. name end
          local open = not item.standing or rep.standing >= item.standing
          entries[#entries + 1] = {
            icon = icon or item.icon,
            item = item.id,
            cells = {
              name,
              item.standing and ns.StandingName(item.standing) or ns.Color(GREY, "None"),
              rewardCost(item),
              open and ns.Color(GREEN, "Available") or ns.Color(GREY, "Locked"),
            },
          }
        end
      end
    end
    local note = ("%d quartermaster%s seen. Open another's shop to add it.")
      :format(#shops, #shops == 1 and "" or "s")
    return entries, REWARD_COLUMNS, note, headings
  end,
}

pages.overview = { title = "Overview", panel = "overview" }
pages.transfer = { title = "Transfer", panel = "transfer" }

local MENU_ORDER = { "overview", "writs", "crates", "turnins", "rewards", "transfer" }

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

--- Open the world map on a zone.
function ns.OpenMap(mapID)
  if InCombatLockdown and InCombatLockdown() then
    print(ns.TITLE .. ": no map in combat.")
    return
  end
  if not WorldMapFrame:IsShown() then ToggleWorldMap() end
  if WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(mapID) end
end

--- "5 min", "3 h" or "2 days" since a time.
local function ago(when)
  local seconds = math.max(0, (time and time() or os.time()) - when)
  if seconds < 3600 then return ("%d min"):format(math.max(1, math.floor(seconds / 60))) end
  if seconds < 86400 then return ("%d h"):format(math.floor(seconds / 3600)) end
  local days = math.floor(seconds / 86400)
  return ("%d day%s"):format(days, days == 1 and "" or "s")
end

--- Bring the scan button and progress bar up to date.
local function updateScanBar()
  if not scanBar then return end
  local p = ns.ScanProgress()
  local bar, button = scanBar.bar, scanBar.button
  if p.running then
    button:SetText("Stop scan")
    button:Enable()
    bar:SetMinMaxValues(0, math.max(1, p.total))
    bar:SetValue(p.done)
    bar:SetStatusBarColor(0.1, 0.6, 0.1)
    bar.text:SetText(("%d / %d  %s"):format(p.done, p.total, p.item or ""))
    return
  end
  button:SetText("Scan AH")
  button:SetEnabled(ns.CanScan() and ns.AuctionHouseOpen())
  local lastScan = ns.LastScanTime()
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(lastScan and 1 or 0)
  bar:SetStatusBarColor(0.35, 0.35, 0.35)
  local text
  if not ns.CanScan() then
    text = "No AH search on this client."
  elseif ns.AuctionHouseOpen() then
    text = "Ready to scan."
  else
    text = "Open the AH to scan."
  end
  if lastScan then text = text .. " Last scan: " .. ago(lastScan) .. " ago." end
  bar.text:SetText(text)
end

function refresh()
  if not window or not window:IsShown() then return end
  local key = ns.db.page
  local page = pages[key] or pages.overview
  window.heading:SetText(page.title)
  for id, button in pairs(window.menu) do
    if id == key then button:LockHighlight() else button:UnlockHighlight() end
  end

  for name, panel in pairs(panels) do
    if name ~= page.panel then panel:Hide() end
  end
  if page.build then
    local entries, columns, text, headings = page.build()
    list:Set(entries, columns, headings)
    note:SetText(text or "")
    list.head:Show()
    list.scroll:Show()
  else
    list.head:Hide()
    list.scroll:Hide()
    note:SetText("")
    panels[page.panel]:Show()
    panels[page.panel]:Refresh()
  end

  if page.footer == "scan" then
    note:Hide()
    scanBar.names:SetChecked(ns.db.ownerNames == 2)
    scanBar:Show()
    updateScanBar()
  else
    scanBar:Hide()
    note:Show()
  end

  if page.sorts then
    sortBar.key = page.sortKey
    local current = ns.db[page.sortKey]
    for i, button in ipairs(sortBar.buttons) do
      local sort = page.sorts[i]
      if sort then
        button.value = sort[1]
        button:SetText(sort[2])
        button:SetEnabled(current ~= sort[1])
        button:ClearAllPoints()
        button:SetPoint("RIGHT", sortBar, "RIGHT", -(#page.sorts - i) * 104, 0)
        button:Show()
      else
        button:Hide()
      end
    end
    sortBar:Show()
  else
    sortBar:Hide()
  end
end

local function build()
  window = CreateFrame("Frame", "PuggerWaylaidCompanionWindow", UIParent, "BasicFrameTemplateWithInset")
  window:SetSize(WIDTH, HEIGHT)
  window:SetPoint("CENTER")
  window:SetFrameStrata("HIGH")
  window:SetMovable(true)
  window:EnableMouse(true)
  window:SetClampedToScreen(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", window.StopMovingOrSizing)
  window:Hide()
  tinsert(UISpecialFrames, "PuggerWaylaidCompanionWindow")

  local title = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", 0, -5)
  title:SetText(ns.TITLE)

  -- The menu.
  window.menu = {}
  for i, key in ipairs(MENU_ORDER) do
    local button = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
    button:SetSize(MENU - 20, 26)
    button:SetPoint("TOPLEFT", 14, -34 - (i - 1) * 30)
    button:SetText(pages[key].title)
    button:SetScript("OnClick", function()
      ns.db.page = key
      list.scroll:SetVerticalScroll(0)
      refresh()
    end)
    window.menu[key] = button
  end

  -- The page.
  window.heading = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  window.heading:SetPoint("TOPLEFT", MENU + 10, -38)

  -- Sort buttons, right-aligned; a page lists the ones it has in `sorts`.
  sortBar = CreateFrame("Frame", nil, window)
  sortBar:SetSize(3 * 104, 24)
  sortBar:SetPoint("TOPRIGHT", -34, -34)
  sortBar.buttons = {}
  for i = 1, 3 do
    local button = CreateFrame("Button", nil, sortBar, "UIPanelButtonTemplate")
    button:SetSize(100, 22)
    button:SetScript("OnClick", function(self)
      ns.db[sortBar.key] = self.value
      list.scroll:SetVerticalScroll(0)
      refresh()
    end)
    sortBar.buttons[i] = button
  end

  list = makeList(window)
  list.head:SetPoint("TOPLEFT", MENU + 8, -66)
  list.head:SetPoint("TOPRIGHT", -34, -66)
  list.scroll:SetPoint("TOPLEFT", MENU + 8, -66 - HEAD - 2)
  list.scroll:SetPoint("BOTTOMRIGHT", -34, 44)

  note = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  note:SetPoint("BOTTOMLEFT", MENU + 10, 12)
  note:SetPoint("BOTTOMRIGHT", -14, 12)
  note:SetHeight(26)
  note:SetJustifyH("LEFT")
  note:SetJustifyV("MIDDLE")

  -- The writs page's foot: the auction house scan and its progress, and how many
  -- characters the Owned column names.
  scanBar = CreateFrame("Frame", nil, window)
  scanBar:SetPoint("BOTTOMLEFT", MENU + 8, 12)
  scanBar:SetPoint("BOTTOMRIGHT", -14, 12)
  scanBar:SetHeight(26)
  scanBar:Hide()

  scanBar.button = CreateFrame("Button", nil, scanBar, "UIPanelButtonTemplate")
  scanBar.button:SetSize(150, 22)
  scanBar.button:SetPoint("LEFT", 0, 0)
  scanBar.button:SetScript("OnClick", ns.ToggleScan)

  scanBar.bar = CreateFrame("StatusBar", nil, scanBar)
  scanBar.bar:SetPoint("LEFT", scanBar.button, "RIGHT", 10, 0)
  scanBar.bar:SetSize(380, 16)
  scanBar.bar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
  local back = scanBar.bar:CreateTexture(nil, "BACKGROUND")
  back:SetAllPoints()
  back:SetColorTexture(0, 0, 0, 0.5)
  scanBar.bar.text = scanBar.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  scanBar.bar.text:SetPoint("LEFT", 6, 0)
  scanBar.bar.text:SetPoint("RIGHT", -6, 0)
  scanBar.bar.text:SetJustifyH("LEFT")
  scanBar.bar.text:SetWordWrap(false)

  scanBar.names = CreateFrame("CheckButton", nil, scanBar, "UICheckButtonTemplate")
  scanBar.names:SetSize(22, 22)
  scanBar.names:SetPoint("LEFT", scanBar.bar, "RIGHT", 10, 0)
  local namesLabel = scanBar.names:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  namesLabel:SetPoint("LEFT", scanBar.names, "RIGHT", 2, 0)
  namesLabel:SetText("Show both names")
  scanBar.names:SetScript("OnClick", function(self)
    ns.db.ownerNames = self:GetChecked() and 2 or 1
    refresh()
  end)
  -- The pages that aren't lists.
  panels.overview = ns.BuildOverview(window, WIDTH - MENU - 22)
  panels.transfer = ns.BuildTransfer(window, WIDTH - MENU - 22)
  for _, panel in pairs(panels) do
    panel:SetPoint("TOPLEFT", MENU + 8, -66)
    panel:SetPoint("BOTTOMRIGHT", -14, 14)
    panel:Hide()
  end

  window:SetScript("OnShow", refresh)
end

--- Show or hide the window; with a page name ("writs", "crates", "turnins"), show that page.
function ns.Toggle(page)
  if not ns.db then return end
  if not window then build() end
  if page and pages[page] then
    ns.db.page = page
    window:Show()
    refresh()
  elseif window:IsShown() then
    window:Hide()
  else
    window:Show()
  end
end

ns.OnChange(refresh)
if ns.OnScan then ns.OnScan(updateScanBar) end
