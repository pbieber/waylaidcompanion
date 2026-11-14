--[[
The Options page: how the writs and crates pages show cost, and how characters are named.

  - Craftsman's Writs: cost per reputation or in all; per 1, 10, 100 or 1000 rep;
    whether the coin pouch's average silver comes off the cost.
  - Waylaid Crates: cost per Merchant's Favor or in all; per 1, 10, 100 or 1000 favor;
    whether the quest reward silver comes off the cost.
  - Items: names coloured by writ or crate tier, or by the item's rarity as in game.
  - Characters: "Show both names" (first name and surname) in the Owned columns.
  - Window: the modern or the classic style (after a reload), and the columns' order.

ns.BuildOptions makes the frame; UI.lua places it and calls its Refresh.
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

function ns.BuildOptions(parent, width)
  local f = CreateFrame("Frame", nil, parent)
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
        f:Refresh()
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

  --- A box beside a section's Cost boxes for a setting that is on unless set to false,
  --- with a "(?)" after its label: hover it for `fill`, which writes the tooltip.
  local function checkbox(top, key, label, fill)
    local box = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    box:SetSize(24, 24)
    box:SetPoint("TOPLEFT", 10 + LABEL_W + 2 * (BUTTON_W + 4) + 12, top - 27)
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
    end)
    controls[#controls + 1] = { Refresh = function() box:SetChecked(ns.db[key] ~= false) end }
  end

  local top = -4
  heading("Craftsman's Writs", top)
  choice("Cost", top - 28, "writCost", {
    { "per", function() return "Per " .. ns.ScaleLabel(ns.db.repScale, "rep") end },
    { "total", "Absolute" },
  })
  choice("Scale", top - 28 - ROW, "repScale", scales("rep"))
  -- Beside the Cost boxes: whether a writ's cost is less its Coin Pouch's average silver.
  checkbox(top, "writPouch", "Account for coin pouch silver", function()
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
      GameTooltip:AddLine("* Not confirmed yet: from one pouch so far.", 0.6, 0.6, 0.6, true)
    end
  end)
  note("Per rep: the writ and its material for that much reputation. Absolute: what one writ costs. "
    .. "Ticked: less the coin pouch's average silver.", top - 28 - 2 * ROW)

  top = top - 28 - 2 * ROW - 34
  heading("Waylaid Crates", top)
  choice("Cost", top - 28, "crateCost", {
    { "per", function() return "Per " .. ns.ScaleLabel(ns.db.favorScale, "favor") end },
    { "total", "Absolute" },
  })
  choice("Scale", top - 28 - ROW, "favorScale", scales("favor"))
  -- Beside the Cost boxes: whether a crate's cost is less its quest reward silver.
  checkbox(top, "crateRefund", "Account for quest reward silver", function()
    GameTooltip:SetText("Quest reward silver", 1, 0.82, 0)
    GameTooltip:AddLine("Each crate turn-in also gives half its reputation as silver in quest "
      .. "rewards. Account for this silver in the cheapest per favor calculation.", 1, 1, 1, true)
  end)
  note("Per favor: the crate and a material for that much of the Merchant's Favor it pays. "
    .. "Absolute: what one filled crate costs. Ticked: less the quest reward silver.",
    top - 28 - 2 * ROW)

  top = top - 28 - 2 * ROW - 34
  heading("Items", top)
  choice("Name color", top - 28, "itemColor", { { "tier", "Tier" }, { "rarity", "Rarity (in game)" } })
  note("Tier: writs and crates in their tier's colour. Rarity: every item as the game colours it; "
    .. "the Profession column keeps the tier's colour (by profession: the Tier column).",
    top - 28 - ROW)

  top = top - 28 - ROW - 46
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

  function f:Refresh()
    for _, c in ipairs(controls) do c.Refresh() end
  end

  return f
end
