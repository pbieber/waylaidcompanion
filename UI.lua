--[[
The window: a menu down the left, a page on the right.

  Overview           - rep and what is left today (Overview.lua)
  Craftsman's Writs  - every writ, by tier, profession or cost
  Waylaid Crates     - every crate and its material, by tier, profession or cost
  Turn-ins           - where writs and crates go; the same places Map.lua marks
  Rewards            - the quartermaster's items (Rewards.lua)
  Transfer           - mail, bank and buying (Transfer.lua)
  Options            - how costs and characters are shown (Options.lua), at the menu's foot

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

--- What a writ's Cost column shows, as the Options page has it: the cost per repScale
--- reputation, or the writ and its material in all. nil when nothing has a price.
local function writValue(cost)
  if not cost.perRep then return nil end
  if ns.db.writCost == "total" then return cost.total end
  return cost.perRep * ns.db.repScale
end

--- The Cost column's heading: "Cost / 100 rep", or "Cost" for the absolute cost.
local function writCostHeading()
  if ns.db.writCost == "total" then return "Cost" end
  return "Cost / " .. ns.ScaleLabel(ns.db.repScale, "rep")
end

--- The Cost column: the price, "+ ?" when a part of it has no price and "*" when a price
--- it is made of is old.
local function costText(cost)
  if not ns.HasPrices() then return "" end
  local value = writValue(cost)
  if not value then return ns.Color(GREY, "no price") end
  local text = ns.Coins(value)
  if cost.partial then text = text .. ns.Color(ORANGE, " + ?") end
  if cost.old then text = text .. ns.Color(ORANGE, " *") end
  return text
end

--- Tooltip lines for a writ's cost per reputation, and what is wrong with it if anything.
local function perRepLines(lines, cost, itemName)
  if not cost.perRep then return end
  lines[#lines + 1] = { ns.Color(GOLD, "Cost / " .. ns.ScaleLabel(ns.db.repScale, "rep")),
    ns.Coins(cost.perRep * ns.db.repScale) .. (cost.partial and " + ?" or "") }
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

-- Group header icons when sorted by profession: the writs' professions, and the trade
-- each kind of crate draws on.
local PROFESSION_HEADER_ICON = {
  Alchemy = "Interface/Icons/Trade_Alchemy",
  Blacksmithing = "Interface/Icons/Trade_BlackSmithing",
  Engineering = "Interface/Icons/Trade_Engineering",
  Leatherworking = "Interface/Icons/Trade_LeatherWorking",
  Tailoring = "Interface/Icons/Trade_Tailoring",
}
local CRATE_HEADER_ICON = {
  Herbs = "Interface/Icons/Trade_Herbalism",
  Ore = "Interface/Icons/Trade_Mining",
  Ingots = "Interface/Icons/Spell_Fire_FlameBlades",  -- Smelting
  Textiles = "Interface/Icons/INV_Misc_Pelt_Wolf_01",  -- Skinning
  Fabrics = "Interface/Icons/Trade_Tailoring",
  Curiosities = "Interface/Icons/Trade_Engraving",     -- Enchanting
  Parts = "Interface/Icons/Trade_Engineering",
}

--- A header's text with an icon before it, when there is one.
local function withIcon(icon, text)
  return icon and ("|T%s:16:16|t %s"):format(icon, text) or text
end

--- An item's name as the Options page has items coloured: by tier (tierHex, or plain
--- when nil), or in the game's colour for its rarity (plain until the game has the item).
local function itemColored(id, tierHex, text)
  if ns.db.itemColor == "rarity" then
    local quality = GetItemInfo and select(3, GetItemInfo(id))
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color and color.hex then return color.hex .. text .. "|r" end
    return text
  end
  return tierHex and ns.Color(tierHex, text) or text
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
    -- The profession wears the tier's colour, so the tier shows when names are in their
    -- rarity colour (Options).
    second = ns.Color(ns.WRIT_COLOR[writ.tier], ("%s %d"):format(writ.profession, writ.skill))
  end
  local tip = "Craftsman's Writ: " .. writ.name .. "\nDaily."
  if npc then
    tip = tip .. ("\nTurn in: %s, %s (%.1f, %.1f)"):format(npc.name, npc.zone, npc.x, npc.y)
  else
    tip = tip .. "\nTurn-in unknown. Saved when you accept the quest."
  end
  if writ.side and not ns.AnySide(writ.quest) then
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
      perRepLines(lines, now, itemName)
      lines[#lines + 1] = { " " }
      holdingLines(lines, "Owned: writ", writ.writItem)
      holdingLines(lines, "Owned: " .. itemName, writ.item, writ.count)
      return lines
    end,
    cells = {
      itemColored(writ.item, ns.WRIT_COLOR[writ.tier], name),
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

--- The Cost heading's tip, as the Options page has the cost shown.
local function writCostTip()
  local what = ns.db.writCost == "total" and "Writ and material"
    or ("Writ and material per " .. ns.ScaleLabel(ns.db.repScale, "rep"))
  return what .. ", at AH prices (your scan or Auctionator, newest).\n"
    .. "+ ?  a part has no price.\n"
    .. ("*  a price is %d+ days old.\n"):format(ns.OLD_PRICE_DAYS)
    .. "Per rep or absolute, and the scale: Options."
end
--- The Owned heading's tip, for writs or crates.
local function ownedTip(what)
  return what .. " on all characters: bags, bank, mail.\nA number alone: this character.\n"
    .. "Show both names (Options): first name and surname."
end

--- Where a writ goes when sorted by cost: 1 every part priced, 2 a part unpriced, 3 none.
local function costRank(cost)
  if not cost.perRep then return 3 end
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
        local x, y = writValue(costs[a]), writValue(costs[b])
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
          header = withIcon(PROFESSION_HEADER_ICON[writ.profession], writ.profession)
        else
          header = ("%s  +%d rep each"):format(ns.WRIT_TIERS[writ.tier], ns.WRIT_REP[writ.tier])
        end
        entries[#entries + 1], folded = groupHeader("writs", sort, group, header)
      end
      if not folded then entries[#entries + 1] = writEntry(writ, sort, costs[writ]) end
    end
    local headings = {
      "Writ", sort == "profession" and "Tier" or "Profession", "Rep",
      { writCostHeading(), writCostTip() },
      { "Owned", ownedTip("Writs") }, "Zone", "Today",
    }
    return entries, WRIT_COLUMNS, nil, headings
  end,
}

-- Crate, profession or level, favor, cost, owned.
local CRATE_COLUMNS = { 0, 270, 395, 455, 595, 710 }

local CHEAPEST = "|TInterface/RaidFrame/ReadyCheck-Ready:12:12|t "

--- Whether the crates page shows a cost per favor (the Options page), not the absolute.
local function perFavor()
  return ns.db.crateCost ~= "total"
end

--- The Cost column's heading: "Cost / favor", "Cost / 100 favor", or "Cost".
local function crateCostHeading()
  if not perFavor() then return "Cost" end
  return "Cost / " .. ns.ScaleLabel(ns.db.favorScale, "favor")
end

--- The Cost heading's tip, as the Options page has the cost shown.
local function crateCostTip()
  local what = "The crate and one material"
  if perFavor() then
    what = what .. " per " .. ns.ScaleLabel(ns.db.favorScale, "Merchant's Favor")
      .. " (the least the crate pays)"
  end
  return what .. ", at AH prices (your scan or Auctionator, newest).\n"
    .. "On a crate: its cheapest material. On a material: that one.\n"
    .. CHEAPEST .. " the crate's cheapest material.\n"
    .. "+ ?  a part has no price.\n"
    .. ("*  a price is %d+ days old.\n"):format(ns.OLD_PRICE_DAYS)
    .. "Per favor or absolute, and the scale: Options."
end

--- What a crate's or a bundle's Cost column shows: the cost per favorScale favor, or in
--- all. nil when nothing has a price, or per favor while the favor is unknown.
local function crateValue(part)
  if perFavor() then return part.perFavor and part.perFavor * ns.db.favorScale end
  return (part.total or 0) > 0 and part.total or nil
end

--- A crate's or a bundle's Cost column: the money, "+ ?" when a part of it has no price
--- and "*" when a price it is made of is old; per favor, "~" before it when the favor is
--- an estimate, and "favor ?" while the favor is unknown. `cost` is the crate's.
local function crateCostText(part, cost)
  if not ns.HasPrices() then return "" end
  local value = crateValue(part)
  if not value then
    if perFavor() and not cost.favor and (part.total or 0) > 0 then return ns.Color(GREY, "favor ?") end
    return ns.Color(GREY, "no price")
  end
  local text = ns.Coins(value)
  if perFavor() and cost.favorEstimated then text = ns.Color(GREY, "~") .. text end
  if part.partial then text = text .. ns.Color(ORANGE, " + ?") end
  if part.old then text = text .. ns.Color(ORANGE, " *") end
  return text
end

--- Tooltip lines for a crate filled with one bundle: what it costs, in all and by part,
--- and per favorScale favor at every amount its tier is known to pay.
local function crateCostLines(lines, crate, cost, bundle, name)
  local part = cost.bundles[bundle] or {}
  costLines(lines, { { "Crate", cost.crate }, { name, part.material } })
  if part.each and bundle.count > 1 then lines[#lines + 1] = { "  Each", ns.Coins(part.each) } end
  if not ns.HasPrices() then return end
  local label = "Cost / " .. ns.ScaleLabel(ns.db.favorScale, "favor")
  local amounts, estimated = ns.CrateFavor(crate.tier)
  if #amounts == 0 then
    lines[#lines + 1] = { ns.Color(GOLD, label), ns.Color(GREY, "favor unknown") }
  elseif part.perFavor then
    for _, amount in ipairs(amounts) do
      lines[#lines + 1] = { ns.Color(GOLD, ("%s (pays %s%d)"):format(label, estimated and "~" or "", amount)),
        ns.Coins(part.total / amount * ns.db.favorScale) .. (part.partial and " + ?" or "") }
    end
    if estimated then
      lines[#lines + 1] = { ns.Color(ORANGE, "  Favor estimated. Saved on turn-in.") }
    end
  end
  if part.partial and part.total and part.total > 0 then
    lines[#lines + 1] = { ns.Color(ORANGE, ("  No price: %s"):format(cost.crate and name or "crate")) }
  end
  if part.old then
    lines[#lines + 1] = { ns.Color(ORANGE, ("  Price %d days old"):format(part.age)) }
  end
end

--- Where a crate goes when sorted by cost: 1 priced, 2 a part unpriced, 3 the favor it
--- pays is unknown (per favor only), 4 no price at all.
local function crateRank(cost)
  if crateValue(cost) then return cost.partial and 2 or 1 end
  if perFavor() and not cost.favor and cost.total > 0 then return 3 end
  return 4
end
local CRATE_COST_GROUPS = { "priced", "partial", "favor", "none" }
local CRATE_COST_HEADERS = {
  priced = "Priced, cheapest first",
  partial = "Price incomplete",
  favor = "Merchant's Favor unknown, cheapest first",
  none = "No price",
}

--- The Merchant's Favor column for a crate tier, and the line for its tooltip.
local function favorText(tier)
  local amounts, estimated = ns.CrateFavor(tier)
  if #amounts == 0 then
    return ns.Color(GREY, "Unknown"), "Merchant's Favor unknown. Saved on turn-in."
  end
  if estimated then
    return ns.Color(GREY, "~" .. table.concat(amounts, " or ")),
      "Merchant's Favor estimated: " .. table.concat(amounts, " or ")
        .. ", by crate quality (twice the tier below). The real amount is saved on turn-in."
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
  sorts = { { "level", "By tier" }, { "profession", "By profession" }, { "cost", "By cost" } },
  footer = "scan",
  build = function()
    local sort = ns.db.crateSort
    local byCost = sort == "cost"
    local kindOrder = {}
    for i, kind in ipairs(ns.CRATE_KINDS) do kindOrder[kind] = i end
    local sorted, costs = {}, {}
    for _, crate in ipairs(ns.crates) do
      sorted[#sorted + 1] = crate
      costs[crate] = ns.CrateCost(crate)
    end
    table.sort(sorted, function(a, b)
      if byCost then
        -- Whole prices first, cheapest first (per favor or absolute, as shown); then those
        -- missing a part; then those whose favor nobody knows yet, by what they cost; then
        -- no price at all.
        local ca, cb = costs[a], costs[b]
        local ra, rb = crateRank(ca), crateRank(cb)
        if ra ~= rb then return ra < rb end
        local x, y = crateValue(ca), crateValue(cb)
        if ra == 3 then x, y = ca.total, cb.total end
        if x and y and x ~= y then return x < y end
      end
      if sort == "profession" then
        if a.kind ~= b.kind then return kindOrder[a.kind] < kindOrder[b.kind] end
        if a.tier ~= b.tier then return a.tier < b.tier end
      else
        if a.tier ~= b.tier then return a.tier < b.tier end
        if a.kind ~= b.kind then return kindOrder[a.kind] < kindOrder[b.kind] end
      end
      return a.name < b.name
    end)
    local camp = ns.Camp()
    local where = camp and ("Turn in: %s, %s (%.1f, %.1f)."):format(camp.name, camp.zone, camp.x, camp.y)
      or "Turn in: your faction's camp."
    local entries, last, folded = {}, nil, false
    for _, crate in ipairs(sorted) do
      local cost = costs[crate]
      local group
      if byCost then
        group = CRATE_COST_GROUPS[crateRank(cost)]
      elseif sort == "profession" then
        group = crate.kind
      else
        group = crate.tier
      end
      if group ~= last then
        last = group
        local header
        if byCost then
          header = CRATE_COST_HEADERS[group]
        elseif sort == "profession" then
          header = withIcon(CRATE_HEADER_ICON[crate.kind],
            ("%s  (%s)"):format(crate.kind, ns.CRATE_SKILL[crate.kind]))
        else
          header = ("%s  Level %d"):format(ns.CRATE_TIERS[crate.tier], ns.CRATE_LEVEL[crate.tier])
        end
        entries[#entries + 1], folded = groupHeader("crates", sort, group, header)
      end
      if not folded then
        local _, icon = ns.Item(crate.item)
        local favor, favorTip = favorText(crate.tier)
        -- By profession: the tier and the level it needs. Otherwise the profession, in the
        -- tier's colour, so the tier shows when names are in their rarity colour (Options).
        local tierColor = ns.CRATE_COLOR[crate.tier]
        local second
        if sort == "profession" then
          second = ns.Color(tierColor, ns.CRATE_TIERS[crate.tier]) .. ns.Color(GREY, "  Level " .. ns.CRATE_LEVEL[crate.tier])
        else
          second = ns.Color(tierColor, ns.CRATE_SKILL[crate.kind])
        end
        entries[#entries + 1] = {
          icon = icon,
          item = crate.item,
          tip = "Needs one material below.\n" .. favorTip .. "\n" .. where,
          lines = function()
            local lines = { { " " } }
            local now = ns.CrateCost(crate)
            local b = now.cheapest
            if b then
              crateCostLines(lines, crate, now, b,
                ("%d x %s (cheapest)"):format(b.count, ns.Item(b.item, b.name)))
            else
              costLines(lines, { { "Crate", now.crate }, { "Material", nil } })
            end
            return lines
          end,
          cells = {
            itemColored(crate.item, ns.CRATE_COLOR[crate.tier], "Waylaid Crate: " .. crate.name),
            second,
            favor,
            crateCostText(cost, cost),
            ownedText(crate.item),
          },
        }
        -- Sorted by cost, a crate's materials are too, cheapest first.
        local bundles = {}
        for _, bundle in ipairs(crate.bundles) do bundles[#bundles + 1] = bundle end
        if byCost then
          table.sort(bundles, function(a, b)
            local x, y = cost.bundles[a].material, cost.bundles[b].material
            if (x == nil) ~= (y == nil) then return x ~= nil end
            if x and y and x ~= y then return x < y end
            return a.name < b.name
          end)
        end
        for _, bundle in ipairs(bundles) do
          local name, bundleIcon = ns.Item(bundle.item, bundle.name)
          local label = ("%d x %s"):format(bundle.count, name)
          local have = ns.Count(bundle.item)
          local color = have >= bundle.count and GREEN or (have > 0 and GOLD or GREY)
          local part = cost.bundles[bundle]
          local cheapest = bundle == cost.cheapest
          entries[#entries + 1] = {
            icon = bundleIcon,
            item = bundle.item,
            indent = 22,
            lines = function()
              local lines = { { " " } }
              local now = ns.CrateCost(crate)
              crateCostLines(lines, crate, now, bundle, label)
              if now.cheapest == bundle then
                lines[#lines + 1] = { ns.Color(GREEN, "The cheapest material for this crate.") }
              elseif now.cheapest then
                local b = now.cheapest
                lines[#lines + 1] = { ns.Color(GREY, ("Cheapest: %d x %s"):format(b.count, ns.Item(b.item, b.name))),
                  ns.Color(GREY, ns.Coins(now.total)) }
              end
              return lines
            end,
            cells = {
              itemColored(bundle.item, nil, label),
              ns.Color(color, ("%d / %d"):format(have, bundle.count)),
              "",
              -- A material without a price can't say what filling the crate with it costs.
              part.material and ((cheapest and CHEAPEST or "") .. crateCostText(part, cost))
                or (ns.HasPrices() and ns.Color(GREY, "no price") or ""),
              "",
            },
          }
        end
      end
    end
    return entries, CRATE_COLUMNS, nil, {
      "Crate", sort == "profession" and "Tier" or "Profession", "Favor",
      { crateCostHeading(), crateCostTip() },
      { "Owned", ownedTip("Crates") },
    }
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

-- Recipes are item class 9; their subclass is the profession. Icons by subclass.
local RECIPE_CLASS = 9
local PROFESSION_ICON = {
  [1] = "Interface/Icons/Trade_LeatherWorking", [2] = "Interface/Icons/Trade_Tailoring",
  [3] = "Interface/Icons/Trade_Engineering", [4] = "Interface/Icons/Trade_BlackSmithing",
  [5] = "Interface/Icons/INV_Misc_Food_15", [6] = "Interface/Icons/Trade_Alchemy",
  [7] = "Interface/Icons/Spell_Holy_SealOfSacrifice", [8] = "Interface/Icons/Trade_Engraving",
  [9] = "Interface/Icons/Trade_Fishing", [10] = "Interface/Icons/INV_Misc_Gem_01",
}
-- The names, for a client that gives none (the game's own are in the player's language).
local PROFESSION_NAME = {
  "Leatherworking", "Tailoring", "Engineering", "Blacksmithing", "Cooking", "Alchemy",
  "First Aid", "Enchanting", "Fishing", "Jewelcrafting",
}
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

--- The profession a quartermaster's shop is for: its name and icon, going by the recipes
--- it sells (the game knows an item's kind without asking the server). nil for a shop
--- with no recipes.
local function shopProfession(shop)
  if not GetItemInfoInstant then return nil end
  local count, name, best = {}, {}, nil
  for _, item in ipairs(shop.items) do
    local _, _, subType, _, _, class, subclass = GetItemInfoInstant(item.id)
    if class == RECIPE_CLASS and subclass and PROFESSION_ICON[subclass] then
      count[subclass] = (count[subclass] or 0) + 1
      name[subclass] = subType
      if not best or count[subclass] > count[best] then best = subclass end
    end
  end
  if not best then return nil end
  return name[best] or PROFESSION_NAME[best], PROFESSION_ICON[best]
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
    -- One group per quartermaster, under its profession (by the NPC's name when it sells
    -- no recipes, after the professions); its items by standing, then name.
    local shops = {}
    for key, shop in pairs(saved) do
      local profession, icon = shopProfession(shop)
      shops[#shops + 1] = { key = key, shop = shop, profession = profession, icon = icon }
    end
    table.sort(shops, function(a, b)
      if (a.profession == nil) ~= (b.profession == nil) then return a.profession ~= nil end
      local x, y = a.profession or a.shop.npc or "", b.profession or b.shop.npc or ""
      if x ~= y then return x < y end
      return (a.shop.npc or "") < (b.shop.npc or "")
    end)
    local entries = {}
    for _, s in ipairs(shops) do
      local title = s.profession and ("|T%s:16:16|t %s"):format(s.icon, s.profession)
        or (s.shop.npc or "Quartermaster")
      local header, folded = groupHeader("rewards", "npc", s.key,
        ("%s (%d)"):format(title, #s.shop.items))
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
pages.options = { title = "Options", panel = "options" }

-- The pages down the menu; Options sits apart at its foot.
local MENU_ORDER = { "overview", "writs", "crates", "turnins", "rewards", "transfer", "options" }

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
    if key == "options" then
      button:SetPoint("BOTTOMLEFT", 14, 14)
    else
      button:SetPoint("TOPLEFT", 14, -34 - (i - 1) * 30)
    end
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

  -- The writs and crates pages' foot: the auction house scan and its progress.
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
  scanBar.bar:SetPoint("RIGHT", scanBar, "RIGHT", 0, 0)
  scanBar.bar:SetHeight(16)
  scanBar.bar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
  local back = scanBar.bar:CreateTexture(nil, "BACKGROUND")
  back:SetAllPoints()
  back:SetColorTexture(0, 0, 0, 0.5)
  scanBar.bar.text = scanBar.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  scanBar.bar.text:SetPoint("LEFT", 6, 0)
  scanBar.bar.text:SetPoint("RIGHT", -6, 0)
  scanBar.bar.text:SetJustifyH("LEFT")
  scanBar.bar.text:SetWordWrap(false)

  -- The pages that aren't lists.
  panels.overview = ns.BuildOverview(window, WIDTH - MENU - 22)
  panels.transfer = ns.BuildTransfer(window, WIDTH - MENU - 22)
  panels.options = ns.BuildOptions(window, WIDTH - MENU - 22)
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
