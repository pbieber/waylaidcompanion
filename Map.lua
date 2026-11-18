--[[
Markers on the world map: one for each NPC that takes Craftsman's Writs, and one for the
player's crate camp. Hovering a marker lists the writs handed in there and whether each
is still available today: Done, Ready with a tick (writ and material in bags), Writ with a
tick and Material with a cross (or the other way round) for half of it in bags, or Open.
When what the bags lack (the writ, or for a writ in bags its material) is elsewhere on the
account (bank, mail, another character), the writ's and the material's counts follow
underneath, by character, as on the writs page.

A writ's or crate's own tooltip: Tooltips.lua.

The markers are plain frames on the map's canvas, placed by hand, so nothing here goes
through the map's own pin pools (which want XML templates and are easy to taint). On a
zone's own map a marker sits at its zone coordinates; on a continent map those are
converted through world coordinates. Options: the markers' size, whether they grow as the
map zooms in, and whether they show at all (also the minimap button's right-click).

With OpenMap (an addon: one seamless map of the world) showing its stitched map, markers are
placed through its API (OpenMapAPI) all over it, not only on the zone underneath; they grow
with its zoom, and follow its own Icon size (OpenMapDB.worldmap.iconScale: read, never set).
]]

local _, ns = ...
if not CreateFrame or not WorldMapFrame then return end

local SIZE = 22 * 0.65 -- a marker at the normal size (Options: Marker size 100%)
local ZOOM_GROW = 0.5 -- how much bigger markers get at the map's closest zoom (Options: grow)
local CONTINENT = 2 -- Enum.UIMapType.Continent

local pins = {}

local TICK = "|TInterface/RaidFrame/ReadyCheck-Ready:12:12|t"
local CROSS = "|TInterface/RaidFrame/ReadyCheck-NotReady:12:12|t"

--- A writ's tag on the map: its text and colour.
local function writTag(writ)
  local state = ns.WritState(writ)
  if state == "done" then return "Done", 0.5, 0.5, 0.5 end
  if state == "ready" then return "Ready " .. TICK, 0.25, 1, 0.25 end
  local enough = ns.Count(writ.item) >= writ.count
  if state == "holding" then return "Writ " .. TICK .. "  Material " .. CROSS, 1, 0.82, 0 end
  if enough then return "Writ " .. CROSS .. "  Material " .. TICK, 1, 0.82, 0 end
  return "Open", 0.25, 0.82, 0.25
end

local function canvas()
  if WorldMapFrame.GetCanvas then return WorldMapFrame:GetCanvas() end
  return WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end

--- Where a zone position (0-100) falls on the shown map, as 0-1; nil if it does not.
local function place(map, x, y, shown)
  x, y = x / 100, y / 100
  if map == shown then return x, y end
  if not (C_Map and C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
  local info = C_Map.GetMapInfo(shown)
  if not info or info.mapType ~= CONTINENT then return nil end
  local ok, continent, world = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
  if not ok or not world then return nil end
  local ok2, _, pos = pcall(C_Map.GetMapPosFromWorldPos, continent, world, shown)
  if not ok2 or not pos then return nil end
  local px, py = pos:GetXY()
  if not px or px < 0 or px > 1 or py < 0 or py > 1 then return nil end
  return px, py
end

-- ---------------------------------------------------------------------------
-- OpenMap
-- ---------------------------------------------------------------------------

local OPENMAP_ZOOM = 48 -- OpenMap's deepest zoom (x the whole world) when its setting can't be read

--- OpenMap's API while its stitched map is up; nil otherwise.
local function openMap()
  local api = OpenMapAPI
  if type(api) ~= "table" or type(api.IsStitched) ~= "function" then return nil end
  local ok, stitched = pcall(api.IsStitched)
  return ok and stitched and api or nil
end

--- One of OpenMap's world map settings, if it's a number.
local function openMapSetting(key)
  local db = type(OpenMapDB) == "table" and OpenMapDB.worldmap
  return type(db) == "table" and tonumber(db[key]) or nil
end

--- Where a zone position (0-100) falls on the stitched map's canvas: 0-1 over the map
--- underneath (`shown`), and past it where the view reaches beyond it.
local function placeStitched(api, map, x, y, shown)
  local ok, u, v = pcall(api.WorldFromMap, map, x / 100, y / 100)
  if not ok or not u then return nil end
  local ok2, cx, cy = pcall(api.MapFromWorld, shown, u, v)
  if not ok2 or not cx then return nil end
  return cx, cy
end

--- How much bigger than their set size the markers are at this zoom: 1 zoomed out, up to
--- 1 + ZOOM_GROW zoomed all the way in (Options: grow). On OpenMap's map by its zoom, from
--- the whole world to its deepest; on Blizzard's, by the map's own zoom.
local function zoomGrowth(api)
  if ns.db.pinZoom == false then return 1 end
  local percent
  if api then
    local ok, _, _, zoom = pcall(api.GetView)
    local most = openMapSetting("maxZoom") or OPENMAP_ZOOM
    if ok and type(zoom) == "number" and zoom > 1 and most > 1 then
      percent = math.log(zoom) / math.log(most)
    end
  elseif WorldMapFrame.GetCanvasZoomPercent then
    local ok, p = pcall(WorldMapFrame.GetCanvasZoomPercent, WorldMapFrame)
    if ok and type(p) == "number" then percent = p end
  end
  return 1 + ZOOM_GROW * math.max(0, math.min(1, percent or 0))
end

local function showTooltip(pin)
  local stop = pin.stop
  GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
  GameTooltip:AddLine(stop.npc.name, 1, 0.82, 0)
  GameTooltip:AddLine(("%s  %.1f, %.1f"):format(stop.npc.zone, stop.npc.x, stop.npc.y), 0.7, 0.7, 0.7)

  if stop.camp then
    GameTooltip:AddLine(stop.npc.faction, 1, 1, 1)
    GameTooltip:AddLine("Turn in filled crates here.", 0.8, 0.8, 0.8)
    local held = 0
    for _, crate in ipairs(ns.crates) do held = held + ns.Count(crate.item) end
    if held > 0 then
      GameTooltip:AddLine(("%d unfilled crate%s in bags"):format(held, held == 1 and "" or "s"), 1, 0.82, 0)
    end
  else
    if stop.open > 0 then
      GameTooltip:AddLine(("Daily turn-ins available: %d of %d"):format(stop.open, #stop.writs), 0.25, 0.82, 0.25)
    else
      GameTooltip:AddLine("All turn-ins here are done for today", 0.5, 0.5, 0.5)
    end
    GameTooltip:AddLine(" ")
    for _, writ in ipairs(stop.writs) do
      local right, r, g, b = writTag(writ)
      local itemName = ns.Item(writ.item, writ.name)
      local name = writ.count > 1 and (writ.count .. " x " .. itemName) or itemName
      GameTooltip:AddDoubleLine(
        ns.Color(ns.WRIT_COLOR[writ.tier], name) .. ns.Color("ff808080", "  " .. ns.WRIT_TIERS[writ.tier]),
        right, 1, 1, 1, r, g, b)
      -- What the bags lack (the writ, or with the writ in bags its material) is somewhere
      -- else on the account: who has the writ and its material.
      local state = ns.WritState(writ)
      local lacking = (state == "open" and writ.writItem) or (state == "holding" and writ.item)
      if ns.HoldingLines and lacking and ns.AccountHoldings(lacking).total > ns.Count(lacking) then
        local lines = {}
        ns.HoldingLines(lines, "Writ", writ.writItem, nil, "    ")
        ns.HoldingLines(lines, itemName, writ.item, writ.count, "    ")
        for _, line in ipairs(lines) do
          if line[2] then
            GameTooltip:AddDoubleLine(line[1], line[2], 1, 1, 1, 1, 1, 1)
          else
            GameTooltip:AddLine(line[1], 1, 1, 1)
          end
        end
      end
    end
  end
  GameTooltip:Show()
end

ns.MARKER_SIZE = SIZE
ns.MARKER_ICON = "Interface/Icons/INV_Misc_Note_01"

--- A marker's look on `frame` (frame.disc, frame.icon): an icon on a dark disc, the icon
--- filling the frame. Also the Options page's preview.
function ns.MarkerArt(frame)
  frame.disc = frame:CreateTexture(nil, "BACKGROUND")
  frame.disc:SetTexture("Interface/Minimap/UI-Minimap-Background")
  frame.disc:SetPoint("TOPLEFT", -2, 2)
  frame.disc:SetPoint("BOTTOMRIGHT", 2, -2)
  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetAllPoints()
  frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  frame.icon:SetTexture(ns.MARKER_ICON)
end

local function makePin(parent)
  local pin = CreateFrame("Frame", nil, parent)
  pin:SetSize(SIZE, SIZE)
  pin:EnableMouse(true)
  ns.MarkerArt(pin)
  -- A ring that lights up when the player is carrying a writ for this place.
  pin.glow = pin:CreateTexture(nil, "OVERLAY")
  pin.glow:SetTexture("Interface/Buttons/UI-ActionButton-Border")
  pin.glow:SetBlendMode("ADD")
  pin.glow:SetPoint("CENTER")
  pin.glow:SetSize(SIZE * 2, SIZE * 2)
  pin.glow:SetVertexColor(0.3, 1, 0.3)
  pin:SetScript("OnEnter", showTooltip)
  pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return pin
end

local function refresh()
  local parent = canvas()
  if not parent or not WorldMapFrame:IsShown() then return end
  local used = 0
  local shown = ns.db and ns.db.pins and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()

  if shown then
    local stops = ns.Stops()
    local camp = ns.Camp()
    if camp then
      stops[#stops + 1] = { npc = camp, camp = true, writs = {}, open = 1, held = 0 }
    end
    local api = openMap()
    -- The canvas grows as the map zooms in; shrink the markers back to the size the
    -- options ask for (times OpenMap's Icon size on its map), grown for the zoom.
    local zoom = parent:GetScale()
    if not zoom or zoom <= 0 then zoom = 1 end
    local size = (ns.db.pinSize or 1) * zoomGrowth(api)
    if api then size = size * (openMapSetting("iconScale") or 1) end
    local scale = size / zoom
    local width, height = parent:GetWidth(), parent:GetHeight()
    -- Above the map's own pins, and on OpenMap's map above its art, in whatever strata
    -- the map is in.
    local level = parent:GetFrameLevel() + 3000
    if api and api.ArtTopLevel then
      local ok, top = pcall(api.ArtTopLevel)
      if ok and type(top) == "number" then level = math.max(level, top + 10) end
    end
    level = math.min(9000, level)

    for _, stop in ipairs(stops) do
      local x, y
      if api then x, y = placeStitched(api, stop.npc.map, stop.npc.x, stop.npc.y, shown) end
      if not x then x, y = place(stop.npc.map, stop.npc.x, stop.npc.y, shown) end
      if x then
        used = used + 1
        local pin = pins[used]
        if not pin then
          pin = makePin(parent)
          pins[used] = pin
        end
        pin.stop = stop
        pin:SetFrameLevel(level)
        -- Offsets count in the marker's own scale.
        pin:SetScale(scale)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", parent, "TOPLEFT", x * width / scale, -y * height / scale)
        pin.icon:SetTexture(stop.camp and "Interface/Icons/INV_Crate_01" or ns.MARKER_ICON)
        local done = stop.open == 0
        if pin.icon.SetDesaturated then pin.icon:SetDesaturated(done) end
        pin.icon:SetAlpha(done and 0.6 or 1)
        pin.glow:SetShown(stop.held > 0)
        pin:Show()
      end
    end
  end
  for i = used + 1, #pins do pins[i]:Hide() end
end

WorldMapFrame:HookScript("OnShow", refresh)
if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", refresh) end
if WorldMapFrame.OnCanvasScaleChanged then hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", refresh) end
ns.OnChange(refresh)
-- OpenMap: its view moving (a pan can bring other zones in), and its map switching on or off.
if type(OpenMapAPI) == "table" and type(OpenMapAPI.RegisterCallback) == "function" then
  pcall(OpenMapAPI.RegisterCallback, "PuggerWaylaidCompanion", "OpenMap_ViewChanged", refresh)
  pcall(OpenMapAPI.RegisterCallback, "PuggerWaylaidCompanion", "OpenMap_StitchedChanged", refresh)
end
