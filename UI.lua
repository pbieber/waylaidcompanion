--[[
The window: a menu down the left, a page on the right.

  Overview           - rep and what is left today (Overview.lua)
  Craftsman's Writs  - every writ, by tier, profession or cost
  Waylaid Crates     - every crate and its material, by tier, profession or cost
  Fastcraft          - the crates in the bags and what in the bags fills them
  Turn-ins           - where writs and crates go; the same places Map.lua marks
  Rewards            - the quartermaster's items (Rewards.lua)
  Transfer           - mail, bank and buying (Transfer.lua)
  Options            - how costs and characters are shown (Options.lua), at the menu's foot

Each list page builds plain entries ({ header = ... } or { cells = {...} }) and hands them
to one shared list, which draws them with pooled rows.
]]

local ADDON, ns = ...
if not CreateFrame then return end

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local Skin = ns.Skin
local WIDTH, HEIGHT, MENU = 920, 640, 170
local ROW, CELLS, HEAD = 22, 7, 20
local GREY, GOLD, GREEN, ORANGE = "ff808080", "ffffd100", "ff40d040", "ffff8040"

local window, list, sortBar, note, scanBar, fillBar
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

-- A folding header's mark in the classic style.
local FOLDED = "|TInterface/Buttons/UI-PlusButton-Up:14:14|t "
local UNFOLDED = "|TInterface/Buttons/UI-MinusButton-Up:14:14|t "

local function makeRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(ROW)
  row.stripe = row:CreateTexture(nil, "BACKGROUND")
  row.stripe:SetAllPoints()
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ROW - 4, ROW - 4)
  -- A group header's colour bar on its left, and its fold arrow (modern style).
  row.bar = row:CreateTexture(nil, "BORDER")
  row.bar:SetPoint("TOPLEFT")
  row.bar:SetPoint("BOTTOMLEFT")
  row.bar:SetWidth(3)
  row.bar:Hide()
  row.arrow = row:CreateTexture(nil, "ARTWORK")
  row.arrow:SetTexture("Interface/ChatFrame/ChatFrameExpandArrow")
  row.arrow:SetSize(12, 12)
  row.arrow:Hide()
  row.cells = {}
  for i = 1, CELLS do
    local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    row.cells[i] = text
  end
  -- A header's right-hand side: a name, and left of the portrait when there is one.
  row.right = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  row.right:SetJustifyH("RIGHT")
  row.right:SetWordWrap(false)
  if Skin.Classic() then
    row:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")
  else
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- without the icon's own border
    row.right:SetTextColor(Skin.color.dim[1], Skin.color.dim[2], Skin.color.dim[3])
    local hover = Skin.Fill(row, Skin.color.hover, "HIGHLIGHT")
    hover:SetAllPoints()
  end
  row:SetScript("OnEnter", showTooltip)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:SetScript("OnClick", function(self)
    if self.entry and self.entry.click then self.entry.click() end
  end)
  return row
end

--- The order a page's columns are shown in: the one the player dragged them into, else
--- the page's own, else as the page lists them. A list of column numbers, 1 to n.
local function columnOrder(key, n, default)
  local saved = key and ns.db.columns and ns.db.columns[key]
  for _, order in ipairs({ saved or false, default or false }) do
    if order and #order == n then
      local seen, whole = {}, true
      for _, c in ipairs(order) do
        if type(c) ~= "number" or c < 1 or c > n or c % 1 ~= 0 or seen[c] then whole = false end
        seen[c] = true
      end
      if whole then return order end
    end
  end
  local order = {}
  for c = 1, n do order[c] = c end
  return order
end

--- Show a creature's face on a header row, from its NPC id: a 3D model zoomed to the
--- head, like the game's own portraits (a flat portrait needs the NPC to be there).
local function setPortrait(row, creature)
  if not creature then
    if row.portrait then row.portrait.wanted = false; row.portrait:Hide() end
    return
  end
  if not row.portrait then
    local model = CreateFrame("PlayerModel", nil, row)
    model:SetSize(ROW - 2, ROW - 2)
    model:SetPoint("RIGHT", -4, 0)
    -- The zoom again once the model is in: some clients reset the camera then.
    if model:HasScript("OnModelLoaded") then
      model:SetScript("OnModelLoaded", function(self) self:SetPortraitZoom(1) end)
    end
    row.portrait = model
  end
  local model = row.portrait
  if model.creature ~= creature then
    model.creature = creature
    if model.ClearModel then model:ClearModel() end
    if model.SetCreature then pcall(model.SetCreature, model, creature) end
    if model.SetPortraitZoom then model:SetPortraitZoom(1) end
  end
  model.wanted = true
end

local function makeList(parent)
  local l = {}
  l.scroll = CreateFrame("ScrollFrame", "PuggerWaylaidCompanionScroll", parent, "UIPanelScrollFrameTemplate")
  l.child = CreateFrame("Frame", nil, l.scroll)
  l.child:SetSize(10, 10)
  l.scroll:SetScrollChild(l.child)
  l.rows = {}

  -- The column headings, a row of their own above the list that does not scroll. A
  -- heading with a tip explains itself on hover; dragging one onto another moves its
  -- column there, which the page then remembers.
  local classic = Skin.Classic()
  l.head = CreateFrame("Frame", nil, parent)
  l.head:SetHeight(HEAD)
  local shade = l.head:CreateTexture(nil, "BACKGROUND")
  shade:SetAllPoints()
  shade:SetColorTexture(0, 0, 0, classic and 0.4 or 0.3)
  if not classic then
    local under = Skin.Fill(l.head, Skin.color.line, "BORDER")
    under:SetPoint("BOTTOMLEFT")
    under:SetPoint("BOTTOMRIGHT")
    under:SetHeight(1)
  end
  -- Where a dragged column would land.
  l.marker = Skin.Fill(l.head, Skin.color.accent, "OVERLAY")
  l.marker:SetSize(2, HEAD)
  l.marker:Hide()

  --- Where in the order column `c` is.
  local function place(c)
    for pos, other in ipairs(l.order or {}) do
      if other == c then return pos end
    end
  end
  --- The place in the order of the column the cursor is over, by its left-to-right
  --- position alone.
  local function placeUnderCursor()
    local x = GetCursorPosition() / l.head:GetEffectiveScale() - (l.head:GetLeft() or 0)
    local found
    for pos, c in ipairs(l.order or {}) do
      found = pos
      if x < l.lefts[c] + l.widths[c] then break end
    end
    return found
  end

  l.head.cells = {}
  for i = 1, CELLS do
    local cell = CreateFrame("Button", nil, l.head)
    cell:SetHeight(HEAD)
    cell.text = cell:CreateFontString(nil, "ARTWORK", classic and "GameFontNormalSmall" or "GameFontHighlightSmall")
    if not classic then
      cell.text:SetTextColor(Skin.color.dim[1], Skin.color.dim[2], Skin.color.dim[3])
    end
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
    cell:RegisterForDrag("LeftButton")
    cell:SetScript("OnDragStart", function(self)
      if not l.key then return end
      GameTooltip:Hide()
      self.text:SetAlpha(0.4)
      l.head:SetScript("OnUpdate", function()
        local from, to = place(i), placeUnderCursor()
        if not from or not to or from == to then
          l.marker:Hide()
          return
        end
        -- Moved right it lands after the column under the cursor, moved left before it.
        local over = l.order[to]
        local x = l.lefts[over] + (to > from and l.widths[over] - 4 or -3)
        l.marker:ClearAllPoints()
        l.marker:SetPoint("LEFT", l.head, "LEFT", math.max(0, x), 0)
        l.marker:Show()
      end)
    end)
    cell:SetScript("OnDragStop", function(self)
      l.head:SetScript("OnUpdate", nil)
      l.marker:Hide()
      self.text:SetAlpha(1)
      local from, to = place(i), placeUnderCursor()
      if not l.key or not from or not to or from == to then return end
      local order = {}
      for pos, c in ipairs(l.order) do order[pos] = c end
      table.remove(order, from)
      table.insert(order, to, i)
      ns.db.columns[l.key] = order
      refresh()
    end)
    l.head.cells[i] = cell
  end

  --- Show the portraits of rows that are wholly in view. A model is drawn over
  --- everything, and isn't cut off at the edge of the scrolling list like the rest of a
  --- row, so one partly out of view is hidden.
  function l:Portraits()
    local top, height = self.scroll:GetVerticalScroll() or 0, self.scroll:GetHeight() or 0
    for i, row in ipairs(self.rows) do
      local model = row.portrait
      if model then
        local y = (i - 1) * ROW
        local inView = row:IsShown() and y >= top - 1 and y + ROW <= top + height + 1
        model:SetShown(model.wanted == true and inView)
      end
    end
  end
  l.scroll:HookScript("OnVerticalScroll", function() l:Portraits() end)
  l.scroll:HookScript("OnSizeChanged", function() l:Portraits() end)

  --- Draw entries. `columns` is the left edge of each cell as the page lists them, the
  --- last entry the width; `headings` names the columns, each a text or { text, tip }.
  --- `key` names the page, for the order its columns were dragged into, and `default`
  --- is the page's own order. The first column carries the row's icon wherever it is.
  --- A header entry may have `right`, a text for its right-hand side, and `portrait`,
  --- an NPC id.
  function l:Set(entries, columns, headings, key, default)
    local width = columns[#columns]
    local order = columnOrder(key, #columns - 1, default)
    local lefts, widths, x = {}, {}, 0
    for _, c in ipairs(order) do
      widths[c] = columns[c + 1] - columns[c]
      lefts[c] = x
      x = x + widths[c]
    end
    self.key, self.order, self.lefts, self.widths = key, order, lefts, widths
    for c, cell in ipairs(self.head.cells) do
      local heading = headings and headings[c]
      if heading and c < #columns then
        local label, tip = heading, nil
        if type(heading) == "table" then label, tip = heading[1], heading[2] end
        local left = lefts[c] + (c == 1 and ROW + 4 or 0)
        cell:ClearAllPoints()
        cell:SetPoint("LEFT", left, 0)
        cell:SetWidth(lefts[c] + widths[c] - left - 6)
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
        local left, text = 6 + indent, entry.header
        if classic then
          -- The yellow band, with a plus or minus when the group folds.
          row.stripe:SetColorTexture(1, 0.82, 0, 0.12)
          if entry.sub then text = text .. "  " .. entry.sub end
          if entry.folded ~= nil then text = (entry.folded and FOLDED or UNFOLDED) .. text end
        else
          -- A dark band with a bar in the group's colour (the accent without one), a fold
          -- arrow when it folds, and the quiet part of the title in grey.
          row.stripe:SetColorTexture(unpack(Skin.color.band))
          local r, g, b = Skin.RGB(entry.color or Skin.ACCENT_HEX)
          row.bar:SetColorTexture(r, g, b, 1)
          row.bar:Show()
          left = 12 + indent
          if entry.folded ~= nil then
            row.arrow:ClearAllPoints()
            row.arrow:SetPoint("LEFT", 10 + indent, 0)
            row.arrow:SetRotation(entry.folded and 0 or -math.pi / 2)
            row.arrow:Show()
            left = left + 14
          else
            row.arrow:Hide()
          end
          if entry.sub then text = text .. "  " .. ns.Color(GREY, entry.sub) end
        end
        row.icon:Hide()
        local rightWidth = entry.right and 220 or 0
        row.cells[1]:ClearAllPoints()
        row.cells[1]:SetPoint("LEFT", left, 0)
        row.cells[1]:SetWidth(width - left - 6 - rightWidth)
        row.cells[1]:SetFontObject(classic and "GameFontNormal" or "GameFontHighlight")
        row.cells[1]:SetText(text)
        for c = 2, CELLS do row.cells[c]:SetText("") end
        row.right:ClearAllPoints()
        row.right:SetPoint("RIGHT", entry.portrait and -(ROW + 8) or -6, 0)
        row.right:SetWidth(rightWidth)
        row.right:SetText(entry.right or "")
        setPortrait(row, entry.portrait)
      else
        row.stripe:SetColorTexture(1, 1, 1, i % 2 == 0 and (classic and 0.04 or 0.03) or 0)
        row.bar:Hide()
        row.arrow:Hide()
        row.right:SetText("")
        setPortrait(row, nil)
        if entry.icon then
          row.icon:SetTexture(entry.icon)
          row.icon:ClearAllPoints()
          row.icon:SetPoint("LEFT", lefts[1] + 4 + indent, 0)
          row.icon:Show()
        else
          row.icon:Hide()
        end
        for c = 1, CELLS do
          local cell = row.cells[c]
          local value = entry.cells[c]
          if lefts[c] and value then
            local left = lefts[c] + (c == 1 and indent + ROW + 4 or 0)
            cell:ClearAllPoints()
            cell:SetPoint("LEFT", left, 0)
            cell:SetWidth(lefts[c] + widths[c] - left - 6)
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
    self:Portraits()
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
--- reputation, or the writ and its material in all, either less the coin pouch's average
--- silver while that option is on (below 0 when the pouch pays more). nil when nothing has
--- a price.
local function writValue(cost)
  if not cost.perRep then return nil end
  if ns.db.writCost == "total" then return cost.net end
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
  local text = ns.SignedCoins(value)
  if cost.partial then text = text .. ns.Color(ORANGE, " + ?") end
  if cost.old then text = text .. ns.Color(ORANGE, " *") end
  return text
end

--- Tooltip lines for a writ's cost per reputation, less its coin pouch's average silver
--- while that option is on, and what is wrong with it if anything.
local function perRepLines(lines, cost, itemName, tier)
  if not cost.perRep then return end
  if cost.pouch > 0 then
    lines[#lines + 1] = { "  Coin pouch (average)",
      "-" .. ns.Coins(cost.pouch) .. (ns.WRIT_POUCH[tier].unconfirmed and " *" or "") }
  end
  lines[#lines + 1] = { ns.Color(GOLD, "Cost / " .. ns.ScaleLabel(ns.db.repScale, "rep")),
    ns.SignedCoins(cost.perRep * ns.db.repScale) .. (cost.partial and " + ?" or "") }
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
--- which character has them where. `indent` goes before each line (the map's tooltip).
local function holdingLines(lines, label, id, need, indent)
  indent = indent or ""
  local held = ns.AccountHoldings(id)
  local count = tostring(held.total)
  if need then
    count = ns.Color(held.total >= need and GREEN or (held.total > 0 and GOLD or GREY), ("%d / %d"):format(held.total, need))
  end
  lines[#lines + 1] = { indent .. ns.Color(GOLD, label), count }
  for _, h in ipairs(held.chars) do
    lines[#lines + 1] = { indent .. ns.Color(GREY, ("  %s: bags %d, bank %d, mail %s"):format(h.name,
      h.bags, h.bank, h.mailSeen and tostring(h.mail) or "?")) }
  end
end
ns.HoldingLines = holdingLines  -- also the map's tooltip (Map.lua)

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

--- A group's header row, which folds the group away or opens it again on a click, and
--- whether the group is folded. Remembered per page, sort and group; a group that starts
--- folded stays so until opened. `color` is the bar on its left (the accent without
--- one); `sub` follows the title in grey.
local function groupHeader(page, sort, group, text, startFolded, color, sub)
  local key = ("%s:%s:%s"):format(page, sort, tostring(group))
  local stored = ns.db.collapsed[key]
  local folded
  if stored == nil then folded = startFolded == true else folded = stored == true end
  return {
    header = text,
    color = color,
    sub = sub,
    folded = folded,
    click = function()
      if startFolded then
        ns.db.collapsed[key] = not folded
      else
        ns.db.collapsed[key] = (not folded) or nil
      end
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
      perRepLines(lines, now, itemName, writ.tier)
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
  if ns.db.writPouch ~= false then what = what .. ", less the coin pouch's average silver" end
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
  order = { 1, 2, 4, 5, 6, 7, 3 },  -- the reputation at the end of the row
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
    local entries, last, folded, head = {}, nil, false, nil
    local total, done = 0, 0
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
        if sort == "cost" then
          head, folded = groupHeader("writs", sort, group, COST_HEADERS[group])
        elseif sort == "profession" then
          head, folded = groupHeader("writs", sort, group,
            withIcon(PROFESSION_HEADER_ICON[writ.profession], writ.profession))
        else
          head, folded = groupHeader("writs", sort, group, ns.WRIT_TIERS[writ.tier], nil,
            ns.WRIT_COLOR[writ.tier], ("+%d rep each"):format(ns.WRIT_REP[writ.tier]))
        end
        entries[#entries + 1] = head
        total, done = 0, 0
      end
      -- The header counts its group, folded or not.
      total = total + 1
      if ns.WritState(writ) == "done" then done = done + 1 end
      head.right = ("%d / %d done"):format(done, total)
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
      .. (ns.db.crateRefund ~= false and ", less the quest reward silver" or "")
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
  return (part.total or 0) > 0 and part.net or nil
end

--- A crate's or a bundle's Cost column: the money, "+ ?" when a part of it has no price
--- and "*" when a price it is made of is old; per favor, "favor ?" while the favor is
--- unknown. `cost` is the crate's.
local function crateCostText(part, cost)
  if not ns.HasPrices() then return "" end
  local value = crateValue(part)
  if not value then
    if perFavor() and not cost.favor and (part.total or 0) > 0 then return ns.Color(GREY, "favor ?") end
    return ns.Color(GREY, "no price")
  end
  local text = ns.SignedCoins(value)
  if part.partial then text = text .. ns.Color(ORANGE, " + ?") end
  if part.old then text = text .. ns.Color(ORANGE, " *") end
  return text
end

--- Tooltip lines for a crate filled with one bundle: what it costs, in all and by part,
--- the silver its quest reward pays, and per favorScale favor.
local function crateCostLines(lines, crate, cost, bundle, name)
  local part = cost.bundles[bundle] or {}
  costLines(lines, { { "Crate", cost.crate }, { name, part.material } })
  if part.each and bundle.count > 1 then lines[#lines + 1] = { "  Each", ns.Coins(part.each) } end
  if not ns.HasPrices() then return end
  local label = "Cost / " .. ns.ScaleLabel(ns.db.favorScale, "favor")
  if cost.refund > 0 and part.net then
    lines[#lines + 1] = { "  Quest reward", "-" .. ns.Coins(cost.refund) }
  end
  if not cost.favor then
    lines[#lines + 1] = { ns.Color(GOLD, label), ns.Color(GREY, "favor unknown") }
  elseif part.perFavor then
    lines[#lines + 1] = {
      ns.Color(GOLD, ("%s (pays %d)"):format(label, cost.favor)),
      ns.SignedCoins(part.perFavor * ns.db.favorScale) .. (part.partial and " + ?" or "") }
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

--- The Merchant's Favor column for a crate, the amount in its quality's colour (white
--- or green), and the line for its tooltip.
local function favorText(crate)
  local favor = ns.CrateFavor(crate)
  if not favor then return ns.Color(GREY, "Unknown"), "Merchant's Favor unknown." end
  return ns.Color(ns.CRATE_QUALITY_COLOR[crate.quality], tostring(favor)),
    ("Merchant's Favor: %d (a %s crate), and %s back."):format(
      favor, ns.CRATE_QUALITIES[crate.quality], ns.Coins(ns.CrateRefund(crate)))
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
        if byCost then
          entries[#entries + 1], folded = groupHeader("crates", sort, group, CRATE_COST_HEADERS[group])
        elseif sort == "profession" then
          entries[#entries + 1], folded = groupHeader("crates", sort, group,
            withIcon(CRATE_HEADER_ICON[crate.kind], crate.kind), nil, nil, ns.CRATE_SKILL[crate.kind])
        else
          entries[#entries + 1], folded = groupHeader("crates", sort, group, ns.CRATE_TIERS[crate.tier],
            nil, ns.CRATE_COLOR[crate.tier], "Level " .. ns.CRATE_LEVEL[crate.tier])
        end
      end
      if not folded then
        local _, icon = ns.Item(crate.item)
        local favor, favorTip = favorText(crate)
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
          tip = function()
            local tip = "Needs one material below.\n" .. favorTip .. "\n" .. where
            if ns.AuctionHouseOpen() and ns.CanBuy() then
              return tip .. "\n|cff40d040Click: buy, with its cheapest material.|r"
            end
            return tip
          end,
          -- At the auction house: buy crates and their cheapest material (Buy.lua).
          click = function()
            if ns.AuctionHouseOpen() and ns.CanBuy() then ns.BuyForCrate(crate) end
          end,
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
          -- A click opens the window that fills crates with it and, for a crafted
          -- material, queues its crafting (Craft.lua).
          local crafted = ns.CRATE_CRAFTED[crate.kind] and ns.CanCraft()
          entries[#entries + 1] = {
            icon = bundleIcon,
            item = bundle.item,
            indent = 22,
            tip = crafted and "Click: fill crates with it, or craft it." or "Click: fill crates with it.",
            click = function() ns.Craft(crate, bundle) end,
            lines = function()
              local lines = { { " " } }
              local now = ns.CrateCost(crate)
              crateCostLines(lines, crate, now, bundle, label)
              if now.cheapest == bundle then
                lines[#lines + 1] = { ns.Color(GREEN, "The cheapest material for this crate.") }
              elseif now.cheapest then
                local b = now.cheapest
                lines[#lines + 1] = { ns.Color(GREY, ("Cheapest: %d x %s"):format(b.count, ns.Item(b.item, b.name))),
                  ns.Color(GREY, ns.SignedCoins(now.net or now.total)) }
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

-- Crate or material, in bags, crates it fills.
local FAST_COLUMNS = { 0, 400, 520, 710 }

--- How many crates the bags can fill now, over every kind.
local function fastFills()
  local total = 0
  for _, p in ipairs(ns.FillPlan(ns.Count)) do total = total + p.fills end
  return total
end

pages.fastcraft = {
  title = "Fastcraft",
  footer = "fill",
  build = function()
    -- What the Craft button will fill, by crate and by material.
    local byCrate, byBundle = {}, {}
    for _, p in ipairs(ns.FillPlan(ns.Count)) do
      byCrate[p.crate] = (byCrate[p.crate] or 0) + p.fills
      byBundle[p.bundle] = p.fills
    end
    local entries = {}
    for _, crate in ipairs(ns.crates) do
      local held = ns.Count(crate.item)
      if held > 0 then
        local _, icon = ns.Item(crate.item)
        local fills = byCrate[crate] or 0
        entries[#entries + 1] = {
          icon = icon,
          item = crate.item,
          tip = "Click: fill from this crate down the list, then the ones above.",
          click = function() ns.FillAll(crate) end,
          cells = {
            itemColored(crate.item, ns.CRATE_COLOR[crate.tier], "Waylaid Crate: " .. crate.name),
            tostring(held),
            fills > 0 and ns.Color(fills >= held and GREEN or GOLD, ("%d of %d"):format(fills, held))
              or ns.Color(GREY, "no material in bags"),
          },
        }
        for _, bundle in ipairs(crate.bundles) do
          local have = ns.Count(bundle.item)
          if have > 0 then
            local name, bundleIcon = ns.Item(bundle.item, bundle.name)
            local could = math.floor(have / bundle.count)
            local n = byBundle[bundle]
            local text
            if n then
              text = ns.Color(GREEN, tostring(n))
            elseif could > 0 then
              text = ns.Color(GREY, "not needed")  -- another material fills them all
            else
              text = ns.Color(GREY, ("needs %d"):format(bundle.count))
            end
            entries[#entries + 1] = {
              icon = bundleIcon,
              item = bundle.item,
              indent = 22,
              tip = "Click: fill crates with this one only.",
              click = function() ns.Craft(crate, bundle) end,
              cells = { itemColored(bundle.item, nil, ("%d x %s"):format(bundle.count, name)), tostring(have), text },
            }
          end
        end
      end
    end
    if #entries == 0 then
      entries[1] = { header = "No unfilled crate in the bags." }
    end
    return entries, FAST_COLUMNS, nil, {
      "Crate", "In bags", { "Fills", "Crates the bags can fill now, and with which material." },
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
      local tip = npc.name .. "\n" .. table.concat(names, "\n")
      entries[#entries + 1] = {
        icon = "Interface/Icons/INV_Misc_Note_01",
        tip = function()
          if ns.AuctionHouseOpen() and ns.CanBuy() then
            return tip .. "\n|cff40d040Click: buy the writs open today and their material.|r"
          end
          return tip .. "\nClick: map."
        end,
        cells = { npc.name, npc.zone, ("%.1f, %.1f"):format(npc.x, npc.y), status },
        -- At the auction house: buy this recipient's writs and material (Buy.lua).
        click = function()
          if ns.AuctionHouseOpen() and ns.CanBuy() then ns.BuyForStop(stop) else ns.OpenMap(npc.map) end
        end,
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
-- The heading icon of a quartermaster that sells no recipes ("Misc").
local MISC_ICON = "Interface/Icons/INV_Misc_Bag_10"

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

--- The Merchant's Favor a reward costs, or nil when it costs none.
local function favorCost(item)
  local total
  for _, c in ipairs(item.costs or {}) do
    if type(c.name) == "string" and c.name:find("Favor") then total = (total or 0) + c.value end
  end
  return total
end

-- "Requires %s (%d)" as a pattern capturing the skill and the level.
local REQUIRES_SKILL = "^" .. (ITEM_MIN_SKILL or "Requires %s (%d)")
  :gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)") .. "$"

local skillTip
--- An item's tooltip lines, as text; empty while the game has no data for it yet.
local function itemLines(id)
  local out = {}
  if C_TooltipInfo and C_TooltipInfo.GetItemByID then
    local ok, data = pcall(C_TooltipInfo.GetItemByID, id)
    for _, line in ipairs(ok and type(data) == "table" and data.lines or {}) do
      if type(line.leftText) == "string" then out[#out + 1] = line.leftText end
    end
    if #out > 0 then return out end
  end
  if not skillTip then
    skillTip = CreateFrame("GameTooltip", "PuggerWaylaidCompanionSkillTip", nil, "GameTooltipTemplate")
  end
  skillTip:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE")
  skillTip:ClearLines()
  skillTip:SetItemByID(id)
  for i = 1, skillTip:NumLines() do
    local left = _G["PuggerWaylaidCompanionSkillTipTextLeft" .. i]
    local text = left and left:GetText()
    if type(text) == "string" then out[#out + 1] = text end
  end
  skillTip:Hide()
  return out
end

local skills = {}
--- The skill a recipe needs in its profession ("Requires Alchemy (65)": 65), or nil while
--- unknown. A recipe's tooltip shows what it makes too, which can need the same skill, so
--- the highest is the recipe's own. Kept once known.
local function recipeSkill(id, profession)
  if skills[id] ~= nil then return skills[id] or nil end
  if not profession then return nil end
  local best
  for _, text in ipairs(itemLines(id)) do
    local skill, level = text:match(REQUIRES_SKILL)
    level = tonumber(level)
    if skill == profession and level and (not best or level > best) then best = level end
  end
  -- None, once the game has the item: false, so it isn't read again.
  if best or (GetItemInfo and GetItemInfo(id)) then skills[id] = best or false end
  return best
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
    -- One group per quartermaster, under its profession ("Misc" when it sells no
    -- recipes, after the professions): what it sells for Merchant's Favor, cheapest
    -- first and then by the skill the recipe needs, and below it, folded, the rest.
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
      local title = ("|T%s:16:16|t %s"):format(s.icon or MISC_ICON, s.profession or "Misc")
      local header, folded = groupHeader("rewards", "npc", s.key, title, nil, nil,
        ("(%d)"):format(#s.shop.items))
      -- The quartermaster on the right, a shop without recipes ("Misc") too.
      header.right = s.shop.npc
      header.portrait = type(s.key) == "number" and s.key or nil
      entries[#entries + 1] = header
      if not folded then
        local forFavor, other, info = {}, {}, {}
        for _, item in ipairs(s.shop.items) do
          local name = ns.Item(item.id, item.name)
          info[item] = { name = name, favor = favorCost(item), skill = recipeSkill(item.id, s.profession) }
          table.insert(info[item].favor and forFavor or other, item)
        end
        -- Unknown amounts and skills (the game has not sent the item yet) last.
        local function order(a, b)
          local x, y = info[a], info[b]
          if x.favor ~= y.favor then return (x.favor or math.huge) < (y.favor or math.huge) end
          if x.skill ~= y.skill then return (x.skill or math.huge) < (y.skill or math.huge) end
          return x.name < y.name
        end
        table.sort(forFavor, order)
        table.sort(other, order)
        local function add(item)
          local name, icon = info[item].name, select(2, ns.Item(item.id, item.name))
          local quality = GetItemInfo and select(3, GetItemInfo(item.id))
          local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
          if color and color.hex then name = color.hex .. name .. "|r" end
          if (item.quantity or 1) > 1 then name = item.quantity .. " x " .. name end
          if info[item].skill then name = name .. ns.Color(GREY, (" (%d)"):format(info[item].skill)) end
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
        for _, item in ipairs(forFavor) do add(item) end
        if #other > 0 then
          local sub, subFolded = groupHeader("rewards", "other", s.key,
            "Not for Merchant's Favor", true, GREY, ("(%d)"):format(#other))
          sub.indent = 16
          entries[#entries + 1] = sub
          if not subFolded then
            for _, item in ipairs(other) do add(item) end
          end
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
local MENU_ORDER = { "overview", "writs", "crates", "fastcraft", "turnins", "rewards", "transfer", "options" }
local MENU_ICON = {
  fastcraft = "Interface/Icons/INV_Box_01",
  overview = "Interface/Icons/INV_Misc_Book_09",
  writs = "Interface/Icons/INV_Scroll_03",
  crates = "Interface/Icons/INV_Crate_01",
  turnins = "Interface/Icons/INV_Misc_Map_01",
  rewards = "Interface/Icons/INV_Misc_Coin_01",
  transfer = "Interface/Icons/INV_Letter_15",
  options = "Interface/Icons/INV_Misc_Gear_01",
}

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

local SCAN_NAMES = { writs = "Writs", crates = "Crates", all = "Writs and crates" }

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
    bar:SetStatusBarColor(0.2, 0.55, 0.25)
    -- Name what is being scanned when it isn't this page's items.
    local what = p.scope ~= scanBar.scope and (SCAN_NAMES[p.scope or "all"] .. ": ") or ""
    bar.text:SetText(("%s%d / %d  %s"):format(what, p.done, p.total, p.item or ""))
    return
  end
  button:SetText("Scan AH")
  button:SetEnabled(ns.CanScan() and ns.AuctionHouseOpen())
  local lastScan = ns.LastScanTime(scanBar.scope)
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(lastScan and 1 or 0)
  bar:SetStatusBarColor(0.22, 0.22, 0.25)
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
    button:SetSelected(id == key)
  end

  for name, panel in pairs(panels) do
    if name ~= page.panel then panel:Hide() end
  end
  if page.build then
    local entries, columns, text, headings = page.build()
    list:Set(entries, columns, headings, pages[key] and key or "overview", page.order)
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
    -- The scan button scans the items this page prices.
    scanBar.scope = key
    note:Hide()
    fillBar:Hide()
    scanBar:Show()
    updateScanBar()
  elseif page.footer == "fill" then
    -- The Craft button fills every crate the bags can, one kind after the other.
    local fills = fastFills()
    scanBar:Hide()
    note:Hide()
    fillBar:Show()
    fillBar.button:SetEnabled(fills > 0)
    fillBar.text:SetText(fills > 0
      and ("The bags can fill %d crate%s. One click per crate."):format(fills, fills == 1 and "" or "s")
      or "Nothing to fill: no crate in the bags with its material.")
  else
    scanBar:Hide()
    fillBar:Hide()
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
        button:SetActive(current == sort[1])
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
  window = Skin.Window("PuggerWaylaidCompanionWindow", UIParent, WIDTH, HEIGHT,
    (ns.TITLE:gsub("^Pugger", ns.Color(Skin.ACCENT_HEX, "Pugger"))))
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

  -- The version, at the right of the title bar beside the close button.
  local metadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local version = metadata and metadata(ADDON, "Version")
  if version then
    local text = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if window.closeButton then
      text:SetPoint("RIGHT", window.closeButton, "LEFT", -6, 0)
    else
      text:SetPoint("TOPRIGHT", -34, -7)
    end
    text:SetText("v" .. version)
    text:SetTextColor(unpack(Skin.color.dim))
  end

  -- The menu, an entry a page. Modern: a darker column down the left, the page shown
  -- with the accent bar and a lighter fill. Classic: the game's buttons.
  local classic = Skin.Classic()
  if not classic then
    local side = Skin.Fill(window, Skin.color.side, "BACKGROUND", -6)
    side:SetPoint("TOPLEFT", 1, -Skin.TITLE_HEIGHT - 2)
    side:SetPoint("BOTTOMLEFT", 1, 1)
    side:SetWidth(MENU - 4)
    local sideEdge = Skin.Fill(window, Skin.color.line, "BORDER")
    sideEdge:SetPoint("TOPLEFT", side, "TOPRIGHT")
    sideEdge:SetPoint("BOTTOMLEFT", side, "BOTTOMRIGHT")
    sideEdge:SetWidth(1)
  end

  local dim = Skin.color.dim
  window.menu = {}
  for i, key in ipairs(MENU_ORDER) do
    local button
    if classic then
      button = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
      button:SetSize(MENU - 20, 26)
      if key == "options" then
        button:SetPoint("BOTTOMLEFT", 14, 14)
      else
        button:SetPoint("TOPLEFT", 14, -34 - (i - 1) * 30)
      end
      button:SetText(pages[key].title)
      function button:SetSelected(on)
        if on then self:LockHighlight() else self:UnlockHighlight() end
      end
    else
      button = CreateFrame("Button", nil, window)
      button:SetSize(MENU - 4, 30)
      if key == "options" then
        button:SetPoint("BOTTOMLEFT", 1, 8)
      else
        button:SetPoint("TOPLEFT", 1, -36 - (i - 1) * 32)
      end
      local hover = Skin.Fill(button, Skin.color.hover, "HIGHLIGHT")
      hover:SetAllPoints()
      button.fill = Skin.Fill(button, Skin.color.selected, "BACKGROUND")
      button.fill:SetAllPoints()
      button.bar = Skin.Fill(button, Skin.color.accent, "BORDER")
      button.bar:SetPoint("TOPLEFT")
      button.bar:SetPoint("BOTTOMLEFT")
      button.bar:SetWidth(3)
      button.icon = button:CreateTexture(nil, "ARTWORK")
      button.icon:SetTexture(MENU_ICON[key])
      button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      button.icon:SetSize(18, 18)
      button.icon:SetPoint("LEFT", 14, 0)
      button.label = button:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
      button.label:SetPoint("LEFT", button.icon, "RIGHT", 9, 0)
      button.label:SetText(pages[key].title)
      function button:SetSelected(on)
        if on then
          self.fill:Show()
          self.bar:Show()
          self.icon:SetDesaturated(false)
          self.icon:SetAlpha(1)
          self.label:SetTextColor(1, 1, 1)
        else
          self.fill:Hide()
          self.bar:Hide()
          self.icon:SetDesaturated(true)
          self.icon:SetAlpha(0.7)
          self.label:SetTextColor(dim[1], dim[2], dim[3])
        end
      end
    end
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
  Skin.Plain(window.heading)

  -- Sort buttons, right-aligned; a page lists the ones it has in `sorts`.
  sortBar = CreateFrame("Frame", nil, window)
  sortBar:SetSize(3 * 104, 24)
  sortBar:SetPoint("TOPRIGHT", -34, -34)
  sortBar.buttons = {}
  for i = 1, 3 do
    local button = Skin.Tab(sortBar, 100, 24)
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

  -- The writs and crates pages' foot: the auction house scan of the page's items, and
  -- its progress.
  scanBar = CreateFrame("Frame", nil, window)
  scanBar:SetPoint("BOTTOMLEFT", MENU + 8, 12)
  scanBar:SetPoint("BOTTOMRIGHT", -14, 12)
  scanBar:SetHeight(26)
  scanBar:Hide()

  scanBar.button = Skin.Button(scanBar, "", 150, 22)
  scanBar.button:SetPoint("LEFT", 0, 0)
  scanBar.button:SetScript("OnClick", function() ns.ToggleScan(scanBar.scope) end)

  scanBar.bar = CreateFrame("StatusBar", nil, scanBar)
  scanBar.bar:SetPoint("LEFT", scanBar.button, "RIGHT", 10, 0)
  scanBar.bar:SetPoint("RIGHT", scanBar, "RIGHT", 0, 0)
  scanBar.bar:SetHeight(16)
  scanBar.bar:SetStatusBarTexture(Skin.Bar())
  local back = scanBar.bar:CreateTexture(nil, "BACKGROUND")
  back:SetAllPoints()
  back:SetColorTexture(0, 0, 0, 0.5)
  if not Skin.Classic() then Skin.Border(scanBar.bar, Skin.color.line, "OVERLAY") end
  scanBar.bar.text = scanBar.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  scanBar.bar.text:SetPoint("LEFT", 6, 0)
  scanBar.bar.text:SetPoint("RIGHT", -6, 0)
  scanBar.bar.text:SetJustifyH("LEFT")
  scanBar.bar.text:SetWordWrap(false)

  -- The Fastcraft page's foot: the button that fills every crate the bags can.
  fillBar = CreateFrame("Frame", nil, window)
  fillBar:SetPoint("BOTTOMLEFT", MENU + 8, 12)
  fillBar:SetPoint("BOTTOMRIGHT", -14, 12)
  fillBar:SetHeight(26)
  fillBar:Hide()
  fillBar.button = Skin.Button(fillBar, "Craft", 150, 22)
  fillBar.button:SetPoint("LEFT", 0, 0)
  fillBar.button:SetScript("OnClick", function() ns.FillAll() end)
  fillBar.text = fillBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fillBar.text:SetPoint("LEFT", fillBar.button, "RIGHT", 10, 0)
  fillBar.text:SetPoint("RIGHT", fillBar, "RIGHT", 0, 0)
  fillBar.text:SetJustifyH("LEFT")

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
