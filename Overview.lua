--[[
The window's first page:

  - a bar, drawn like the experience bar, for the way to the next reputation standing;
  - how many writs of each tier that takes, and how many to reach Exalted;
  - how many daily turn-ins are left today, and the reputation they are worth.

ns.BuildOverview makes the frame; UI.lua places it and calls its Refresh.
]]

local _, ns = ...
if not CreateFrame then return end

local GREY = "ff808080"
local SEGMENTS = 20 -- the experience bar's
local ROW = 22
local COLUMNS = { 10, 250, 440 }

-- The reputation bar's colour for each standing, where the game does not supply them.
local BAR_COLOR = {
  { 0.8, 0.13, 0.13 }, { 0.8, 0.13, 0.13 }, { 0.75, 0.27, 0 }, { 0.9, 0.7, 0 },
  { 0, 0.6, 0.1 }, { 0, 0.6, 0.1 }, { 0, 0.6, 0.1 }, { 0, 0.6, 0.1 },
}

local function number(n)
  if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
  return tostring(n)
end

local function turnIns(reputation, each)
  return number(math.ceil(reputation / each))
end

--- A table of text cells: rows of three, the first row its column titles.
local function makeGrid(parent, top, rows)
  local grid = {}
  for r = 1, rows do
    grid[r] = {}
    if r > 1 and r % 2 == 0 then
      local stripe = parent:CreateTexture(nil, "BACKGROUND")
      stripe:SetColorTexture(1, 1, 1, 0.04)
      stripe:SetPoint("TOPLEFT", 4, top - (r - 1) * ROW)
      stripe:SetPoint("RIGHT", -4, 0)
      stripe:SetHeight(ROW)
    end
    for c = 1, #COLUMNS do
      local cell = parent:CreateFontString(nil, "ARTWORK", r == 1 and "GameFontDisableSmall" or "GameFontHighlight")
      cell:SetPoint("LEFT", parent, "TOPLEFT", COLUMNS[c], top - (r - 1) * ROW - ROW / 2)
      cell:SetJustifyH("LEFT")
      grid[r][c] = cell
    end
  end
  function grid:Row(r, a, b, c)
    self[r][1]:SetText(a or "")
    self[r][2]:SetText(b or "")
    self[r][3]:SetText(c or "")
  end
  return grid
end

local function tierLabel(tier)
  return ns.Color(ns.WRIT_COLOR[tier], ns.WRIT_TIERS[tier]) .. ns.Color(GREY, ("  +%d rep"):format(ns.WRIT_REP[tier]))
end

function ns.BuildOverview(parent, width)
  local f = CreateFrame("Frame", nil, parent)
  local barWidth = width - 20

  f.faction = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  f.faction:SetPoint("TOPLEFT", 10, -4)
  ns.Skin.Plain(f.faction)
  f.standing = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  f.standing:SetPoint("TOPRIGHT", f, "TOPLEFT", 10 + barWidth, -7)

  local classic = ns.Skin.Classic()
  local bar = CreateFrame("StatusBar", nil, f)
  bar:SetStatusBarTexture(ns.Skin.Bar())
  bar:SetMinMaxValues(0, 1)
  if classic then
    -- A dark trough, the fill, and the experience bar's dividers over it.
    local trough = f:CreateTexture(nil, "BACKGROUND")
    trough:SetColorTexture(0, 0, 0, 0.7)
    trough:SetPoint("TOPLEFT", 8, -28)
    trough:SetSize(barWidth + 4, 22)
    bar:SetPoint("TOPLEFT", 10, -30)
    bar:SetSize(barWidth, 18)
    for i = 1, SEGMENTS - 1 do
      local tick = bar:CreateTexture(nil, "OVERLAY")
      tick:SetColorTexture(0, 0, 0, 0.45)
      tick:SetSize(1, 18)
      tick:SetPoint("LEFT", bar, "LEFT", math.floor(barWidth * i / SEGMENTS + 0.5), 0)
    end
  else
    -- A low, flat bar with rounded ends: the trough and the fill share one shape.
    local HEIGHT = 14
    bar:SetPoint("TOPLEFT", 10, -32)
    bar:SetSize(barWidth, HEIGHT)
    local trough = bar:CreateTexture(nil, "BACKGROUND")
    trough:SetAllPoints()
    trough:SetColorTexture(0, 0, 0, 0.6)
    ns.Skin.Round(bar, bar, HEIGHT / 2)
  end
  bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.text:SetPoint("CENTER")
  f.bar = bar

  f.toNext = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.toNext:SetPoint("TOPLEFT", 10, -54)
  f.toExalted = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  f.toExalted:SetPoint("TOPRIGHT", f, "TOPLEFT", 10 + barWidth, -54)

  local function heading(text, top)
    local h = f:CreateFontString(nil, "ARTWORK", classic and "GameFontNormal" or "GameFontHighlight")
    h:SetPoint("TOPLEFT", 10, top)
    h:SetText(text)
    return h
  end
  --- A card behind a block of the page, from `top` down to `bottom` (modern style).
  local function card(top, bottom)
    if classic then return end
    local back = ns.Skin.Fill(f, ns.Skin.color.card, "BACKGROUND", -1)
    back:SetPoint("TOPLEFT", 0, top)
    back:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, bottom)
    ns.Skin.Border(f, ns.Skin.color.line, "BORDER", back)
  end

  card(-80, -106 - (1 + #ns.WRIT_TIERS) * ROW - 24)
  heading("Turn-ins needed", -88)
  f.needed = makeGrid(f, -106, 1 + #ns.WRIT_TIERS)
  f.neededNote = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  f.neededNote:SetPoint("TOPLEFT", 10, -106 - (1 + #ns.WRIT_TIERS) * ROW - 4)
  f.neededNote:SetText("If all of one tier.")

  local todayTop = -106 - (1 + #ns.WRIT_TIERS) * ROW - 44
  card(todayTop + 8, todayTop - 44 - (2 + #ns.WRIT_TIERS) * ROW - 6)
  heading("Today", todayTop)
  f.todayLine = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  f.todayLine:SetPoint("TOPLEFT", 10, todayTop - 20)
  f.today = makeGrid(f, todayTop - 44, 2 + #ns.WRIT_TIERS)

  function f:Refresh()
    local rep = ns.Reputation()
    local today = ns.Today()
    local tiers = #ns.WRIT_TIERS

    if not rep then
      self.faction:SetText(ns.TITLE)
      self.standing:SetText("")
      self.bar:SetValue(0)
      self.bar.text:SetText("")
      self.toNext:SetText(ns.Color(GREY, "Faction unknown."))
      self.toExalted:SetText("")
    else
      local standing = ns.StandingName(rep.standing)
      local nextName = ns.StandingName(math.min(rep.standing + 1, 8))
      local color = (FACTION_BAR_COLORS and FACTION_BAR_COLORS[rep.standing])
      local r, g, b
      if color then r, g, b = color.r, color.g, color.b else r, g, b = unpack(BAR_COLOR[rep.standing] or BAR_COLOR[4]) end
      self.faction:SetText(rep.name)
      self.standing:SetText(standing)
      self.bar:SetStatusBarColor(r, g, b)
      if rep.exalted then
        self.bar:SetValue(1)
        self.bar.text:SetText("Exalted")
        self.toNext:SetText("Exalted.")
        self.toExalted:SetText("")
      else
        local span = math.max(1, rep.high - rep.low)
        local into = math.max(0, rep.value - rep.low)
        self.bar:SetValue(into / span)
        self.bar.text:SetText(("%s / %s"):format(number(into), number(span)))
        self.toNext:SetText(("%s rep to %s"):format(number(rep.toNext), nextName))
        self.toExalted:SetText(("%s rep to Exalted"):format(number(rep.toExalted)))
        if rep.unknown then
          self.toNext:SetText(("No standing yet. %s rep to %s"):format(number(rep.toNext), nextName))
        end
      end

      local nextIsExalted = rep.standing + 1 >= 8
      self.needed:Row(1, "Tier", rep.exalted and "" or ("To " .. nextName), (rep.exalted or nextIsExalted) and "" or "To Exalted")
      for tier = 1, tiers do
        if rep.exalted then
          self.needed:Row(1 + tier, tierLabel(tier), ns.Color(GREY, "none"), "")
        else
          self.needed:Row(1 + tier, tierLabel(tier),
            turnIns(rep.toNext, ns.WRIT_REP[tier]) .. " turn-ins",
            not nextIsExalted and (turnIns(rep.toExalted, ns.WRIT_REP[tier]) .. " turn-ins") or "")
        end
      end
    end
    if not rep then
      self.needed:Row(1, "Tier", "", "")
      for tier = 1, tiers do self.needed:Row(1 + tier, tierLabel(tier), "", "") end
    end

    if today.open == 0 then
      self.todayLine:SetText("All done today.")
    else
      self.todayLine:SetText(("Open today: %s turn-in%s, %s rep."):format(
        ns.Color("ff40d040", number(today.open)), today.open == 1 and "" or "s",
        ns.Color("ff40d040", number(today.rep))))
    end
    self.today:Row(1, "Tier", "Open", "Rep left")
    for tier = 1, tiers do
      local t = today[tier]
      self.today:Row(1 + tier, tierLabel(tier), ("%d of %d"):format(t.open, t.total), number(t.rep))
    end
    self.today:Row(2 + tiers, "All", ("%d of %d"):format(today.open, today.total), number(today.rep))
  end

  return f
end
