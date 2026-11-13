--[[
The look every window shares, in one of two styles (Options, "Style"):

  modern   - flat dark panels, thin borders and one accent colour
  classic  - the game's own window frame, red buttons and yellow headings

  ns.Skin.Window  - a panel with a title and a close button
  ns.Skin.Button  - a button
  ns.Skin.Tab     - a boxed tab, brighter and underlined when it is the active one
  ns.Skin.Choice  - one of a row of choices, filled in the accent when it is the chosen one
  ns.Skin.Fill    - a flat colour texture
  ns.Skin.Border  - a one-pixel border around a frame or a texture
  ns.Skin.Round   - rounded corners for a bar

The modern colours are in ns.Skin.color; change them here and every window follows.
The style is read once, when the first window is built: a change needs a reload.
]]

local _, ns = ...
if not CreateFrame then return end

local Skin = {}
ns.Skin = Skin

Skin.TITLE_HEIGHT = 26
Skin.ACCENT_HEX = "ffffc94a"

local C = {
  window = { 0.075, 0.075, 0.085, 0.97 },
  strip = { 0.035, 0.035, 0.045, 1 },    -- the title strip
  side = { 0, 0, 0, 0.32 },              -- the menu's column
  edge = { 0, 0, 0, 1 },                 -- the window's border
  line = { 1, 1, 1, 0.08 },              -- thin dividers and card borders
  card = { 1, 1, 1, 0.03 },
  accent = { 1, 0.79, 0.29, 1 },
  button = { 1, 1, 1, 0.08 },
  buttonOff = { 1, 1, 1, 0.03 },
  buttonEdge = { 1, 1, 1, 0.14 },
  tabOn = { 1, 1, 1, 0.2 },              -- the active sort tab
  choice = { 1, 1, 1, 0.05 },            -- a choice that is not the chosen one
  choiceEdge = { 1, 1, 1, 0.22 },
  onAccent = { 0.1, 0.08, 0.04 },        -- text on the accent colour
  hover = { 1, 1, 1, 0.08 },
  selected = { 1, 1, 1, 0.07 },
  band = { 0, 0, 0, 0.45 },              -- group headers in a list
  dim = { 0.64, 0.64, 0.68 },            -- quiet text
}
Skin.color = C

local classic

--- Whether the windows are drawn in the classic style. Settled at the first call once
--- the saved settings are in, so every window of a session looks the same.
function Skin.Classic()
  if classic == nil then
    if not ns.db then return false end
    classic = ns.db.theme == "classic"
  end
  return classic
end

--- The texture a status bar is filled with.
function Skin.Bar()
  return Skin.Classic() and "Interface/TargetingFrame/UI-StatusBar" or "Interface/Buttons/WHITE8x8"
end

--- White for a heading in the modern style; the classic one keeps the game's yellow.
function Skin.Plain(text)
  if not Skin.Classic() then text:SetTextColor(1, 1, 1) end
end

--- The red, green and blue of an "aarrggbb" colour, each 0 to 1.
function Skin.RGB(hex)
  return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
end

--- A flat colour texture on `parent`; the caller places it.
function Skin.Fill(parent, color, layer, sub)
  local t
  if sub then
    t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
  else
    t = parent:CreateTexture(nil, layer or "BACKGROUND")
  end
  t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
  return t
end

--- A one-pixel border around `target` (a frame or texture; `parent` itself by default).
function Skin.Border(parent, color, layer, target)
  target = target or parent
  local function edge(from, to, upright)
    local t = Skin.Fill(parent, color, layer or "BORDER")
    t:SetPoint(from, target, from)
    t:SetPoint(to, target, to)
    if upright then t:SetWidth(1) else t:SetHeight(1) end
  end
  edge("TOPLEFT", "TOPRIGHT")
  edge("BOTTOMLEFT", "BOTTOMRIGHT")
  edge("TOPLEFT", "BOTTOMLEFT", true)
  edge("TOPRIGHT", "BOTTOMRIGHT", true)
end

local CORNER = "Interface/AddOns/PuggerWaylaidCompanion/Media/corner"

--- Round the corners of `target` (a frame or texture on `parent`) by `radius`: each
--- corner is painted over in the window's colour, outside a quarter circle.
function Skin.Round(parent, target, radius)
  local function corner(point, left, right, top, bottom)
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetTexture(CORNER)
    t:SetTexCoord(left, right, top, bottom)
    t:SetVertexColor(C.window[1], C.window[2], C.window[3])
    t:SetSize(radius, radius)
    t:SetPoint(point, target, point)
  end
  corner("TOPLEFT", 0, 1, 0, 1)
  corner("TOPRIGHT", 1, 0, 0, 1)
  corner("BOTTOMLEFT", 0, 1, 1, 0)
  corner("BOTTOMRIGHT", 1, 0, 1, 0)
end

--- The game's own red button; with `toggle`, SetActive(true) presses it in.
local function classicButton(parent, text, width, height, toggle)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, height or 22)
  b:SetText(text or "")
  if toggle then
    function b:SetActive(on) self:SetEnabled(not on) end
  end
  return b
end

--- A button. SetText, SetEnabled and the rest work as on any button.
function Skin.Button(parent, text, width, height)
  if Skin.Classic() then return classicButton(parent, text, width, height) end
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, height or 22)
  local fill = Skin.Fill(b, C.button, "BACKGROUND")
  fill:SetAllPoints()
  Skin.Border(b, C.buttonEdge, "BORDER")
  local hover = Skin.Fill(b, C.hover, "HIGHLIGHT")
  hover:SetAllPoints()
  b:SetNormalFontObject("GameFontHighlightSmall")
  b:SetHighlightFontObject("GameFontHighlightSmall")
  b:SetDisabledFontObject("GameFontDisableSmall")
  b:SetText(text or "")
  b:SetScript("OnDisable", function()
    fill:SetColorTexture(unpack(C.buttonOff))
    hover:SetColorTexture(1, 1, 1, 0)
  end)
  b:SetScript("OnEnable", function()
    fill:SetColorTexture(unpack(C.button))
    hover:SetColorTexture(unpack(C.hover))
  end)
  return b
end

--- A boxed tab; SetActive(true) brightens it and underlines it in the accent colour.
function Skin.Tab(parent, width, height)
  if Skin.Classic() then return classicButton(parent, "", width, 22, true) end
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, height or 22)
  -- Boxed like a button; the active one is brighter, with the accent along its foot.
  b.fill = Skin.Fill(b, C.button, "BACKGROUND")
  b.fill:SetAllPoints()
  Skin.Border(b, C.buttonEdge, "BORDER")
  local hover = Skin.Fill(b, C.hover, "HIGHLIGHT")
  hover:SetAllPoints()
  b.label = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  b.label:SetPoint("CENTER", 0, 1)
  b.line = Skin.Fill(b, C.accent, "ARTWORK")
  b.line:SetPoint("BOTTOMLEFT", 1, 1)
  b.line:SetPoint("BOTTOMRIGHT", -1, 1)
  b.line:SetHeight(2)
  function b:SetText(value) self.label:SetText(value) end
  function b:SetActive(on)
    if on then
      self.line:Show()
      self.fill:SetColorTexture(unpack(C.tabOn))
      self.label:SetTextColor(1, 1, 1)
    else
      self.line:Hide()
      self.fill:SetColorTexture(unpack(C.button))
      self.label:SetTextColor(0.82, 0.82, 0.85)
    end
  end
  b:SetActive(false)
  return b
end

--- One of a row of choices: an outlined box, filled in the accent colour with dark text
--- by SetActive(true) when it is the chosen one.
function Skin.Choice(parent, width, height)
  if Skin.Classic() then return classicButton(parent, "", width, height, true) end
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, height or 22)
  b.fill = Skin.Fill(b, C.choice, "BACKGROUND")
  b.fill:SetAllPoints()
  Skin.Border(b, C.choiceEdge, "BORDER")
  local hover = Skin.Fill(b, C.hover, "HIGHLIGHT")
  hover:SetAllPoints()
  b.label = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  b.label:SetPoint("CENTER")
  function b:SetText(value) self.label:SetText(value) end
  function b:SetActive(on)
    if on then
      self.fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.95)
      self.label:SetTextColor(C.onAccent[1], C.onAccent[2], C.onAccent[3])
      self.label:SetShadowColor(0, 0, 0, 0)
    else
      self.fill:SetColorTexture(unpack(C.choice))
      self.label:SetTextColor(0.9, 0.9, 0.9)
      self.label:SetShadowColor(0, 0, 0, 1)
    end
  end
  b:SetActive(false)
  return b
end

--- A window with `title` and a close button that hides it. Modern: a dark panel whose
--- title strip has the logo. Classic: the game's own frame. The page starts 28 down.
function Skin.Window(name, parent, width, height, title)
  if Skin.Classic() then
    local f = CreateFrame("Frame", name, parent, "BasicFrameTemplateWithInset")
    f:SetSize(width, height)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOP", 0, -5)
    f.title:SetText(title or "")
    return f
  end

  local f = CreateFrame("Frame", name, parent)
  f:SetSize(width, height)

  local back = Skin.Fill(f, C.window, "BACKGROUND", -8)
  back:SetAllPoints()
  local strip = Skin.Fill(f, C.strip, "BACKGROUND", -7)
  strip:SetPoint("TOPLEFT", 1, -1)
  strip:SetPoint("TOPRIGHT", -1, -1)
  strip:SetHeight(Skin.TITLE_HEIGHT)
  local under = Skin.Fill(f, C.line, "BORDER")
  under:SetPoint("TOPLEFT", strip, "BOTTOMLEFT")
  under:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT")
  under:SetHeight(1)
  Skin.Border(f, C.edge, "OVERLAY")

  local logo = f:CreateTexture(nil, "ARTWORK")
  logo:SetTexture(ns.ICON)
  logo:SetSize(18, 18)
  logo:SetPoint("LEFT", strip, "LEFT", 8, 0)
  f.title = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  f.title:SetPoint("LEFT", logo, "RIGHT", 7, 0)
  f.title:SetText(title or "")

  local close = CreateFrame("Button", nil, f)
  close:SetSize(Skin.TITLE_HEIGHT, Skin.TITLE_HEIGHT)
  close:SetPoint("TOPRIGHT", -1, -1)
  local hover = Skin.Fill(close, { 0.8, 0.2, 0.2, 0.55 }, "HIGHLIGHT")
  hover:SetAllPoints()
  local cross = close:CreateTexture(nil, "ARTWORK")
  cross:SetTexture("Interface/Buttons/UI-StopButton")
  cross:SetSize(12, 12)
  cross:SetPoint("CENTER")
  cross:SetVertexColor(0.85, 0.85, 0.85)
  close:SetScript("OnClick", function() f:Hide() end)

  return f
end
