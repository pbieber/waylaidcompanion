--[[
The Options page: how the writs and crates pages show cost, and how characters are named.

  - Craftsman's Writs: a cost per reputation is per 1, 10, 100 or 1000 rep; whether the
    coin pouch's average silver comes off the cost.
  - Waylaid Crates: a cost per Merchant's Favor is per 1, 10, 100 or 1000 favor; whether
    the quest reward silver comes off the cost.
  Per rep or favor, or in all: the Cost button at the foot of the writs and crates pages.
  - Items: names coloured by writ or crate tier, or by the item's rarity as in game.
  - World map: the turn-in markers' size (a slider, 25 to 200%, with a marker drawn at
    that size beside it; on OpenMap's map times its Icon size), whether they show (the same setting as the minimap button's right-click), and
    whether they grow as the map zooms in.
  - Tooltips: what is added to a writ's and a crate's tooltip (Tooltips.lua), each kind on
    or off, and each line.
  - Characters: "Show both names" (first name and surname) in the Owned columns.
  - Window: the modern or the classic style (after a reload), and the columns' order.

ns.BuildOptions makes the frame; UI.lua places it and calls its Refresh. The page is
taller than the window, so it scrolls.
]]

local _, ns = ...

-- What a cost per reputation or favor can be shown for.
ns.COST_SCALES = { 1, 10, 100, 1000 }

--- "rep", "10 rep", "100 favor": the amount a cost is shown per.
function ns.ScaleLabel(scale, unit)
  return scale == 1 and unit or (scale .. " " .. unit)
end

if not CreateFrame then return end

local ROW = 28
local LABEL_W = 110
local BUTTON_W = 116
local PIN_SIZES = { 0.25, 2, 0.05 } -- the world map markers' size: least, most, step

function ns.BuildOptions(parent, width)
  -- The page is taller than the window: what's on it scrolls (f), inside the panel.
  local panel = CreateFrame("Frame", nil, parent)
  local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT")
  scroll:SetPoint("BOTTOMRIGHT", -24, 0)
  local f = CreateFrame("Frame", nil, scroll)
  f:SetSize(width - 24, 10)
  scroll:SetScrollChild(f)
  local controls = {}  -- each with a Refresh

  local function heading(text, top)
    local h = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    h:SetPoint("TOPLEFT", 10, top)
    h:SetText(text)
    ns.Skin.Plain(h)
  end
  local function note(text, top)
    local n = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    n:SetPoint("TOPLEFT", 10 + LABEL_W, top)
    n:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    n:SetJustifyH("LEFT")
    n:SetText(text)
  end

  --- A row of boxes, one per choice, for a saved setting; the chosen one is filled in
  --- the accent colour (classic: pressed in). `choices` are { value, text },
  --- text a string or a function giving one.
  local function choice(label, top, key, choices)
    local text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 10, top - 4)
    text:SetText(label)
    local buttons = {}
    for i, c in ipairs(choices) do
      local b = ns.Skin.Choice(f, BUTTON_W, 22)
      b:SetPoint("TOPLEFT", 10 + LABEL_W + (i - 1) * (BUTTON_W + 4), top)
      b:SetScript("OnClick", function()
        ns.db[key] = c[1]
        panel:Refresh()
        ns.Changed()
      end)
      buttons[i] = b
    end
    controls[#controls + 1] = {
      Refresh = function()
        for i, c in ipairs(choices) do
          local b = buttons[i]
          b:SetText(type(c[2]) == "function" and c[2]() or c[2])
          b:SetActive(ns.db[key] == c[1])
        end
      end,
    }
  end

  local function scales(unit)
    local list = {}
    for i, scale in ipairs(ns.COST_SCALES) do
      list[i] = { scale, "Per " .. ns.ScaleLabel(scale, unit) }
    end
    return list
  end

  --- A box for a setting that is on unless set to false, with a "(?)" after its label:
  --- hover it for `fill`, which writes the tooltip. At the row's start, or `left` further in.
  local function checkbox(top, key, label, fill, left)
    local box = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    box:SetSize(24, 24)
    box:SetPoint("TOPLEFT", 6 + LABEL_W + (left or 0), top + 2)
    local text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", box, "RIGHT", 2, 0)
    text:SetText(label)
    local help = CreateFrame("Frame", nil, f)
    help:SetPoint("LEFT", text, "RIGHT", 4, 0)
    local helpText = help:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    helpText:SetPoint("CENTER")
    helpText:SetText("(?)")
    help:SetSize(helpText:GetStringWidth() + 4, 18)
    help:EnableMouse(true)
    help:SetScript("OnEnter", function(self)
      helpText:SetTextColor(1, 1, 1)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      fill()
      GameTooltip:Show()
    end)
    help:SetScript("OnLeave", function()
      helpText:SetTextColor(0.5, 0.5, 0.5)
      GameTooltip:Hide()
    end)
    box:SetScript("OnClick", function(self)
      ns.db[key] = self:GetChecked() and true or false
      ns.Changed()
    end)
    controls[#controls + 1] = { Refresh = function() box:SetChecked(ns.db[key] ~= false) end }
  end

  --- A plain box for a setting that is on unless set to false, `left` into the row. With
  --- `master`, greyed out while that setting is off.
  local function toggle(top, left, key, label, master)
    local box = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    box:SetSize(24, 24)
    box:SetPoint("TOPLEFT", 6 + LABEL_W + left, top + 2)
    local text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", box, "RIGHT", 2, 0)
    text:SetText(label)
    box:SetScript("OnClick", function(self)
      ns.db[key] = self:GetChecked() and true or false
      panel:Refresh()  -- (the lines under a kind grey out now, not when the pages next refresh)
      ns.Changed()
    end)
    controls[#controls + 1] = {
      Refresh = function()
        box:SetChecked(ns.db[key] ~= false)
        local enabled = not master or ns.db[master] ~= false
        box:SetEnabled(enabled)
        if enabled then text:SetTextColor(1, 1, 1) else text:SetTextColor(0.5, 0.5, 0.5) end
      end,
    }
  end

  --- The world map markers' size: a slider, the size it's at, and to the right a marker
  --- drawn at that size, as on the map zoomed out. The map follows as the slider moves.
  local function sizeSlider(top)
    local text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 10, top - 4)
    text:SetText("Marker size")
    local slider = ns.Skin.Slider(f, 2 * BUTTON_W + 4, PIN_SIZES[1], PIN_SIZES[2], PIN_SIZES[3])
    slider:SetPoint("TOPLEFT", 10 + LABEL_W, top - 1)
    local value = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    value:SetPoint("LEFT", slider, "RIGHT", 12, 0)

    -- The preview: a marker on a dark square, big enough for the largest size.
    local box = CreateFrame("Frame", nil, f)
    local side = math.ceil(ns.MARKER_SIZE or 22) * PIN_SIZES[2] + 16
    box:SetSize(side, side)
    box:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, top + 24)
    ns.Skin.Fill(box, { 0, 0, 0, 0.45 }):SetAllPoints()
    ns.Skin.Border(box, ns.Skin.color.line)
    local marker
    if ns.MarkerArt then
      marker = CreateFrame("Frame", nil, box)
      marker:SetPoint("CENTER")
      ns.MarkerArt(marker)
    end
    local caption = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    caption:SetPoint("TOP", box, "BOTTOM", 0, -3)
    caption:SetText("Preview")

    local function show(size)
      value:SetText(("%d%%"):format(math.floor(size * 100 + 0.5)))
      if marker then
        local px = (ns.MARKER_SIZE or 22) * size
        marker:SetSize(px, px)
      end
    end
    slider:SetScript("OnValueChanged", function(_, v)
      -- To the step, as a whole number of steps over their count per 1 (0.75, not 0.7500001).
      local per = math.floor(1 / PIN_SIZES[3] + 0.5)
      v = math.floor(v * per + 0.5) / per
      show(v)
      if math.abs(v - (ns.db.pinSize or 1)) < 0.001 then return end
      ns.db.pinSize = v
      ns.Changed()
    end)
    controls[#controls + 1] = {
      Refresh = function()
        local size = ns.db.pinSize or 1
        slider:SetValue(size)
        show(size)
      end,
    }
  end

  local top = -4
  heading("Craftsman's Writs", top)
  choice("Scale", top - 28, "repScale", scales("rep"))
  -- Below: whether a writ's cost is less its Coin Pouch's average silver.
  checkbox(top - 28 - ROW, "writPouch", "Account for coin pouch silver", function()
    GameTooltip:SetText("Coin pouch gold", 1, 0.82, 0)
    GameTooltip:AddLine("Each writ turn-in gives a Coin Pouch. Account for its gold in the "
      .. "cheapest per rep calculation, at the average for the writ's tier.", 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Tier: range", "average", 1, 0.82, 0, 1, 0.82, 0)
    local starred = false
    for tier, p in ipairs(ns.WRIT_POUCH) do
      local star = p.unconfirmed and " *" or ""
      starred = starred or p.unconfirmed
      -- ns.Coins: the amounts with the game's gold, silver and copper icons.
      GameTooltip:AddDoubleLine(
        ("%s: %s - %s%s"):format(ns.WRIT_TIERS[tier], ns.Coins(p[1]), ns.Coins(p[2]), star),
        ns.Coins(p[3]), 1, 1, 1, 1, 1, 1)
    end
    if starred then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("* Only a small sample size.", 0.6, 0.6, 0.6, true)
    end
  end)
  note("Scale for the Cost per Reputation calculation. Switch at the bottom right of the Writs page.",
    top - 28 - 2 * ROW)

  top = top - 28 - 2 * ROW - 34
  heading("Waylaid Crates", top)
  choice("Scale", top - 28, "favorScale", scales("favor"))
  -- Below: whether a crate's cost is less its quest reward silver.
  checkbox(top - 28 - ROW, "crateRefund", "Account for quest reward silver", function()
    GameTooltip:SetText("Quest reward silver", 1, 0.82, 0)
    GameTooltip:AddLine("Each crate turn-in also gives half its reputation as silver in quest "
      .. "rewards. Account for this silver in the cheapest per favor calculation.", 1, 1, 1, true)
  end)
  note("Scale for the Cost per Merchant's Favor calculation. Switch at the bottom right of the "
    .. "Waylaid Crates page.", top - 28 - 2 * ROW)

  top = top - 28 - 2 * ROW - 34
  heading("Items", top)
  choice("Name color", top - 28, "itemColor", { { "tier", "Tier" }, { "rarity", "Rarity (in game)" } })
  note("Tier: writs and crates in their tier's colour. Rarity: every item as the game colours it; "
    .. "the Profession column keeps the tier's colour (by profession: the Tier column).",
    top - 28 - ROW)

  top = top - 28 - ROW - 46
  heading("World map", top)
  sizeSlider(top - 28)
  -- Below: whether the markers show at all, and whether they grow as the map zooms in.
  checkbox(top - 28 - ROW, "pins", "Show turn-in markers", function()
    GameTooltip:SetText("Turn-in markers", 1, 0.82, 0)
    GameTooltip:AddLine("A marker on the world map for each NPC that takes your writs, and one "
      .. "for your crate camp. Right-click the minimap button, or /pwc map, to show or hide "
      .. "them too.", 1, 1, 1, true)
  end)
  checkbox(top - 28 - ROW, "pinZoom", "Grow when zoomed in", function()
    GameTooltip:SetText("Grow when zoomed in", 1, 0.82, 0)
    GameTooltip:AddLine(("Markers get bigger as you zoom in on the map, up to %d%% more at the "
      .. "closest zoom. Unticked: they stay one size."):format(50), 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("With OpenMap: they grow from its whole-world view to its deepest zoom.",
      0.8, 0.8, 0.8, true)
  end, 2 * (BUTTON_W + 4))
  note("The size of the markers for writ turn-ins and the crate camp on the world map, "
    .. "zoomed out. On OpenMap's map, also times its own Icon size.", top - 28 - 2 * ROW)

  top = top - 28 - 2 * ROW - 34
  heading("Tooltips", top)
  -- Each kind: a box for all of it, then a box per line, greyed while the kind is off.
  local LINE_IN, LINE_GAP = 22, 250
  local function kind(top, label, key, lines)
    local text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 10, top - 4)
    text:SetText(label)
    toggle(top, 0, key, lines.all)
    for i, line in ipairs(lines) do
      local row, column = math.floor((i - 1) / 2), (i - 1) % 2
      toggle(top - ROW * (row + 1), LINE_IN + column * LINE_GAP, line[1], line[2], key)
    end
    return top - ROW * (math.floor((#lines + 1) / 2) + 1)
  end
  top = kind(top - 28, "Writs", "ttWrit", {
    all = "Add to writ tooltips",
    { "ttWritTier", "Tier and reputation" }, { "ttWritProfession", "Profession and skill" },
    { "ttWritMaterial", "Material and its cost" }, { "ttWritTurnIn", "Turn-in zone and NPC" },
  })
  top = kind(top - 6, "Crates", "ttCrate", {
    all = "Add to crate tooltips",
    { "ttCrateFavor", "Tier and favor" }, { "ttCrateMaterial", "Materials and their cost" },
    { "ttCrateTurnIn", "Turn-in camp" },
  })
  note("What Pugger adds to a writ's or crate's tooltip, wherever the game shows it: bags, "
    .. "auction house, mail, links in chat.", top - 2)

  top = top - 2 - 34
  heading("Characters", top)
  local names = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
  names:SetSize(24, 24)
  names:SetPoint("TOPLEFT", 6 + LABEL_W, top - 26)
  local namesLabel = names:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  namesLabel:SetPoint("LEFT", names, "RIGHT", 2, 0)
  namesLabel:SetText("Show both names")
  names:SetScript("OnClick", function(self)
    ns.db.ownerNames = self:GetChecked() and 2 or 1
  end)
  controls[#controls + 1] = { Refresh = function() names:SetChecked(ns.db.ownerNames == 2) end }
  note("The Owned columns name another character by first name, or ticked, by first name and "
    .. "surname. Also /pwc names.", top - 28 - ROW)

  top = top - 28 - ROW - 46
  heading("Window", top)
  choice("Style", top - 28, "theme", { { "modern", "Modern" }, { "classic", "Classic" } })
  -- A style is drawn when the windows are built, so a change waits for a reload.
  local reload = ns.Skin.Button(f, "Reload UI", BUTTON_W, 22)
  reload:SetPoint("TOPLEFT", 10 + LABEL_W + 2 * (BUTTON_W + 4) + 12, top - 28)
  reload:SetScript("OnClick", function() if ReloadUI then ReloadUI() end end)
  local reloadNote = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  reloadNote:SetPoint("LEFT", reload, "RIGHT", 8, 0)
  reloadNote:SetText("Reload to apply the style.")
  controls[#controls + 1] = {
    Refresh = function()
      local changed = (ns.db.theme == "classic") ~= ns.Skin.Classic()
      reload:SetShown(changed)
      reloadNote:SetShown(changed)
    end,
  }

  local columns = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  columns:SetPoint("TOPLEFT", 10, top - 28 - ROW - 4)
  columns:SetText("Columns")
  local reset = ns.Skin.Button(f, "Reset order", BUTTON_W, 22)
  reset:SetPoint("TOPLEFT", 10 + LABEL_W, top - 28 - ROW)
  reset:SetScript("OnClick", function()
    ns.db.columns = {}
    ns.Changed()
  end)
  note("On any list, drag a column's heading onto another to move the column there. "
    .. "Each page remembers its own order.", top - 28 - 2 * ROW)
  f:SetHeight(-(top - 28 - 2 * ROW) + 30)

  function panel:Refresh()
    for _, c in ipairs(controls) do c.Refresh() end
  end

  return panel
end
