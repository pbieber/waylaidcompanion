--[[
The Options page: how the writs and crates pages show cost, and how characters are named.

  - Craftsman's Writs: cost per reputation or in all; per 1, 10, 100 or 1000 rep.
  - Waylaid Crates: cost per Merchant's Favor or in all; per 1, 10, 100 or 1000 favor.
  - Items: names coloured by writ or crate tier, or by the item's rarity as in game.
  - Characters: "Show both names" (first name and surname) in the Owned columns.

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
  end
  local function note(text, top)
    local n = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    n:SetPoint("TOPLEFT", 10 + LABEL_W, top)
    n:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    n:SetJustifyH("LEFT")
    n:SetText(text)
  end

  --- A row of buttons, one per choice, for a saved setting; the chosen one is pressed in
  --- (disabled), the way the sort buttons show theirs. `choices` are { value, text },
  --- text a string or a function giving one.
  local function choice(label, top, key, choices)
    local text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOPLEFT", 10, top - 4)
    text:SetText(label)
    local buttons = {}
    for i, c in ipairs(choices) do
      local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
      b:SetSize(BUTTON_W, 22)
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
          b:SetEnabled(ns.db[key] ~= c[1])
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

  local top = -4
  heading("Craftsman's Writs", top)
  choice("Cost", top - 28, "writCost", {
    { "per", function() return "Per " .. ns.ScaleLabel(ns.db.repScale, "rep") end },
    { "total", "Absolute" },
  })
  choice("Scale", top - 28 - ROW, "repScale", scales("rep"))
  note("Per rep: the writ and its material for that much reputation. Absolute: what one writ costs.",
    top - 28 - 2 * ROW)

  top = top - 28 - 2 * ROW - 34
  heading("Waylaid Crates", top)
  choice("Cost", top - 28, "crateCost", {
    { "per", function() return "Per " .. ns.ScaleLabel(ns.db.favorScale, "favor") end },
    { "total", "Absolute" },
  })
  choice("Scale", top - 28 - ROW, "favorScale", scales("favor"))
  note("Per favor: the crate and a material for that much Merchant's Favor, at the least a crate "
    .. "pays. Absolute: what one filled crate costs.", top - 28 - 2 * ROW)

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

  function f:Refresh()
    for _, c in ipairs(controls) do c.Refresh() end
  end

  return f
end
