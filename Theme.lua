--[[
The look every window shares: flat dark panels, thin borders and one accent colour.

  ns.Skin.Window  - a panel with a title strip, the logo and a close button
  ns.Skin.Button  - a flat button
  ns.Skin.Tab     - a text tab, underlined when it is the active one
  ns.Skin.Fill    - a flat colour texture
  ns.Skin.Border  - a one-pixel border around a frame or a texture

The colours are in ns.Skin.color; change them here and every window follows.
]]

local _, ns = ...
if not CreateFrame then return end

local Skin = {}
ns.Skin = Skin

Skin.TITLE_HEIGHT = 26
Skin.BAR = "Interface/Buttons/WHITE8x8"  -- a flat status bar fill
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
  hover = { 1, 1, 1, 0.08 },
  selected = { 1, 1, 1, 0.07 },
  band = { 0, 0, 0, 0.45 },              -- group headers in a list
  dim = { 0.64, 0.64, 0.68 },            -- quiet text
}
Skin.color = C

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

--- A flat button. SetText, SetEnabled and the rest work as on any button.
function Skin.Button(parent, text, width, height)
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

--- A text tab; SetActive(true) underlines it in the accent colour.
function Skin.Tab(parent, width, height)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width, height or 22)
  local hover = Skin.Fill(b, C.hover, "HIGHLIGHT")
  hover:SetAllPoints()
  b.label = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  b.label:SetPoint("CENTER", 0, 1)
  b.line = Skin.Fill(b, C.accent, "ARTWORK")
  b.line:SetPoint("BOTTOMLEFT", 8, 0)
  b.line:SetPoint("BOTTOMRIGHT", -8, 0)
  b.line:SetHeight(2)
  function b:SetText(value) self.label:SetText(value) end
  function b:SetActive(on)
    if on then
      self.line:Show()
      self.label:SetTextColor(1, 1, 1)
    else
      self.line:Hide()
      self.label:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    end
  end
  b:SetActive(false)
  return b
end

--- A window: dark panel, title strip with the logo and `title`, and a close button that
--- hides it. The page starts below Skin.TITLE_HEIGHT.
function Skin.Window(name, parent, width, height, title)
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
  f.close = close

  return f
end
