--[[
Lines added to a writ's or a crate's own tooltip, wherever the game shows it (bags, auction
house, mail, a link in chat). Each line can be turned off, and each kind entirely, on the
Options page (Tooltips).

A writ:
  Expert writ                              +125 reputation    (tier and reputation)
  Made with Alchemy 205                                       (profession and skill)
  Needs: 5 x Mithril Bar                            1g 20s    (material and its cost)
  Turn in: Tanaris                  Vizzklick (51.0, 27.4)    (zone, then NPC and where)

A crate:
  Expert crate                    +15 Merchant's Favor        (tier and favor)
  Filled with one of:                                         (what fills it, each at its
    20 x Peacebloom                            12s 40c         cost; the cheapest green)
  Turn in: The Barrens               Dokimi (50.0, 29.2)      (the player's side's camp)

A writ the data doesn't list (a "Craftsman's Writ: " the game names) says its tier is
unknown. Costs are what the writs and crates pages use: the AH scan's or Auctionator's.
]]

local _, ns = ...
if not CreateFrame then return end

local GOLD = { 1, 0.82, 0 }
local GREY = { 0.6, 0.6, 0.6 }
local GREEN = { 0.25, 1, 0.25 }

--- Whether a tooltip line (or kind of line) is on: Options, Tooltips. On until turned off.
local function on(key)
  return not ns.db or ns.db[key] ~= false
end

local function rgb(hex)
  return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
end

--- "Turn in: <zone>" on the left, "<NPC> (x, y)" on the right.
local function turnInLine(tooltip, place)
  tooltip:AddDoubleLine("Turn in: " .. ns.Color("ffffffff", place.zone),
    ("%s (%.1f, %.1f)"):format(place.name, place.x, place.y),
    GOLD[1], GOLD[2], GOLD[3], GREY[1], GREY[2], GREY[3])
end

--- A cost on the right of a line: the coins, or "No price" in grey.
local function costLine(tooltip, left, copper, r, g, b)
  if copper then
    tooltip:AddDoubleLine(left, ns.Coins(copper), r, g, b, 1, 1, 1)
  else
    tooltip:AddDoubleLine(left, "No price", r, g, b, GREY[1], GREY[2], GREY[3])
  end
end

-- ---------------------------------------------------------------------------
-- Writs
-- ---------------------------------------------------------------------------

local writsOf  -- [writ item] = the writs the data lists for it (both sides at times)

--- The writ an item is, the one for this character's side first; nil if no writ.
local function writFor(id)
  if not writsOf then
    writsOf = {}
    for _, writ in ipairs(ns.writs) do
      local list = writsOf[writ.writItem] or {}
      list[#list + 1] = writ
      writsOf[writ.writItem] = list
    end
  end
  local list = writsOf[id]
  if not list then return nil end
  for _, writ in ipairs(list) do
    if ns.ForPlayer(writ) then return writ end
  end
  return list[1]
end

-- The tiers' colours, as the WritTier addon has them (the item quality colours).
local TIER_RGB = { { 0.12, 1.00, 0.00 }, { 0.00, 0.44, 0.87 }, { 0.64, 0.21, 0.93 } }
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local function addWrit(tooltip, writ)
  if on("ttWritTier") then
    local r, g, b = unpack(TIER_RGB[writ.tier])
    tooltip:AddDoubleLine(ns.WRIT_TIERS[writ.tier] .. " writ", ("+%d reputation"):format(ns.WRIT_REP[writ.tier]),
      r, g, b, GOLD[1], GOLD[2], GOLD[3])
  end
  if on("ttWritProfession") then
    tooltip:AddLine(("Made with %s %d"):format(writ.profession, writ.skill), 0.8, 0.8, 0.8)
  end
  if on("ttWritMaterial") then
    local name = ns.Item(writ.item, writ.name)
    if writ.count > 1 then name = writ.count .. " x " .. name end
    costLine(tooltip, "Needs: " .. ns.Color("ffffffff", name), ns.WritCost(writ).material,
      GOLD[1], GOLD[2], GOLD[3])
  end
  if on("ttWritTurnIn") then
    local npc = ns.WritNpc(writ)
    if npc then
      turnInLine(tooltip, npc)
    else
      tooltip:AddLine("Turn in: unknown. Saved when you accept the quest.", GREY[1], GREY[2], GREY[3], true)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Crates
-- ---------------------------------------------------------------------------

local crateOf  -- [crate item] = the crate

local function addCrate(tooltip, crate)
  if on("ttCrateFavor") then
    local favor = ns.CrateFavor(crate)
    local r, g, b = rgb(ns.CRATE_COLOR[crate.tier] or "ffffffff")
    tooltip:AddDoubleLine(ns.CRATE_TIERS[crate.tier] .. " crate",
      favor and ("+%d Merchant's Favor"):format(favor) or "", r, g, b, GOLD[1], GOLD[2], GOLD[3])
  end
  if on("ttCrateMaterial") then
    local cost = ns.CrateCost(crate)
    local several = #crate.bundles > 1
    tooltip:AddLine(several and "Filled with one of:" or "Filled with:", GOLD[1], GOLD[2], GOLD[3])
    for _, bundle in ipairs(crate.bundles) do
      local cheapest = several and bundle == cost.cheapest
      local color = cheapest and GREEN or { 1, 1, 1 }
      costLine(tooltip, ("  %d x %s"):format(bundle.count, ns.Item(bundle.item, bundle.name)),
        cost.bundles[bundle].material, color[1], color[2], color[3])
    end
  end
  if on("ttCrateTurnIn") then
    local camp = ns.Camp()
    if camp then turnInLine(tooltip, camp) end
  end
end

-- ---------------------------------------------------------------------------
-- Adding the lines
-- ---------------------------------------------------------------------------

--- Add a writ's or crate's lines to an item tooltip, those that are on. True when `id`
--- is a writ or crate whose lines are on, whether or not any line is.
local function addLines(tooltip, id)
  if not id then return false end
  if not crateOf then
    crateOf = {}
    for _, crate in ipairs(ns.crates) do crateOf[crate.item] = crate end
  end
  local crate = crateOf[id]
  if crate then
    if not on("ttCrate") then return false end
    addCrate(tooltip, crate)
    return true
  end
  if not on("ttWrit") then return false end
  local writ = writFor(id)
  if writ then
    addWrit(tooltip, writ)
    return true
  end
  local name = GetItemInfo and GetItemInfo(id)
  if type(name) ~= "string" or not name:find("^Craftsman's Writ: ") then return false end
  if on("ttWritTier") then tooltip:AddLine("Writ tier: unknown", GREY[1], GREY[2], GREY[3]) end
  return true
end

local function itemID(link)
  return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if tooltip and tooltip.AddLine and data then pcall(addLines, tooltip, data.id) end
  end)
else
  -- Older clients: when the tooltip is set to an item. That can come twice for one item,
  -- so a tooltip takes the lines once until it is cleared.
  local added = setmetatable({}, { __mode = "k" })
  for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
    if tooltip and tooltip.HookScript and tooltip:HasScript("OnTooltipSetItem") then
      -- Without word of the tooltip clearing, every time: twice beats never again.
      local clears = tooltip:HasScript("OnTooltipCleared")
      tooltip:HookScript("OnTooltipSetItem", function(self)
        local _, link = self:GetItem()
        local id = itemID(link)
        if not id or (clears and added[self] == id) then return end
        local ok, ours = pcall(addLines, self, id)
        if ok and ours then
          added[self] = id
          self:Show()  -- room for the lines
        end
      end)
      if clears then
        tooltip:HookScript("OnTooltipCleared", function(self) added[self] = nil end)
      end
    end
  end
end
