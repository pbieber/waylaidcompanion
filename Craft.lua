--[[
Filling crates, from the crates page: clicking a material under a crate opens a small
window with a Fill button. In the game a crate is filled by using it and then picking the
material with the cursor, which starts a cast; the button does both, for one crate a
click (the game lets an addon use an item only from a click, through a secure button).

For a crafted material (a bar, a bolt, a cured hide, an engineering part) the window also
has the queue of recipes that make enough of it for the crates in the bags, what it is
made of first.

The game only lets an addon craft from a click, and one click crafts one recipe as often
as asked, so the queue is worked through with one click on Craft per recipe.

The queue is worked out anew from the bags each time they change: a recipe drops off the
queue once the bags hold what it was to make. Recipes and what they take are read from the
profession window while it is open, and kept for the session, so a queue can span two
professions (bars smelted for engineering parts); crafting a recipe needs its profession
open.

Only the modern profession window (C_TradeSkillUI, which WoW Forever has).
]]

local ADDON, ns = ...

-- How deep a material's own materials are followed.
local MAX_DEPTH = 6

--- The recipes to craft, in order, to hold `want` of `item`.
---   known   [item] = { id, name, makes (items per craft), reagents = { { item, count } } }
---   count   function(item): how many the bags hold
--- Returns the steps, { { item, recipe, crafts }, ... } with what a recipe takes before the
--- recipe itself, and what is short and can't be crafted, { { item, count }, ... }.
function ns.CraftPlan(item, want, known, count)
  local stock, crafts, short, path = {}, {}, {}, {}

  local function need(id, quantity, depth)
    if stock[id] == nil then stock[id] = count(id) or 0 end
    local use = math.min(stock[id], quantity)
    stock[id] = stock[id] - use
    local lack = quantity - use
    if lack <= 0 then return end
    local recipe = known[id]
    -- path: a recipe that takes what it makes, straight or roundabout (transmutes).
    if not recipe or path[id] or depth > MAX_DEPTH then
      short[id] = (short[id] or 0) + lack
      return
    end
    local n = math.ceil(lack / recipe.makes)
    path[id] = true
    for _, r in ipairs(recipe.reagents) do need(r.item, r.count * n, depth + 1) end
    path[id] = nil
    crafts[id] = (crafts[id] or 0) + n
    -- What a craft makes beyond the need is there for the next one to ask.
    stock[id] = stock[id] + n * recipe.makes - lack
  end
  need(item, want, 1)

  local steps, seen = {}, {}
  local function visit(id)
    if seen[id] or not crafts[id] then return end
    seen[id] = true
    for _, r in ipairs(known[id].reagents) do visit(r.item) end
    steps[#steps + 1] = { item = id, recipe = known[id], crafts = crafts[id] }
  end
  visit(item)

  local missing = {}
  for id, n in pairs(short) do missing[#missing + 1] = { item = id, count = n } end
  table.sort(missing, function(a, b) return a.item < b.item end)
  return steps, missing
end

--- The crates in the bags that the bags can fill, and with what: { { crate, bundle,
--- fills }, ... } in the crates' own order, or from the `start`th crate down and then
--- round from the top. A crate takes one material; when one runs short for every crate
--- of a kind, the next fills the rest.
function ns.FillPlan(count, start)
  local plan, all = {}, ns.crates
  start = (start and start >= 1 and start <= #all) and start or 1
  for i = 0, #all - 1 do
    local crate = all[(start - 1 + i) % #all + 1]
    local left = count(crate.item) or 0
    for _, bundle in ipairs(crate.bundles) do
      if left <= 0 then break end
      local fills = math.min(left, math.floor((count(bundle.item) or 0) / bundle.count))
      if fills > 0 then
        plan[#plan + 1] = { crate = crate, bundle = bundle, fills = fills }
        left = left - fills
      end
    end
  end
  return plan
end

if not CreateFrame then return end

local TS = C_TradeSkillUI
local CAN = TS ~= nil and TS.GetAllRecipeIDs ~= nil and TS.GetRecipeInfo ~= nil
  and TS.GetRecipeSchematic ~= nil and TS.CraftRecipe ~= nil
local RED, GREY, GOLD, GREEN, ORANGE = "ffff4040", "ff808080", "ffffd100", "ff40d040", "ffff8040"

local known = {}      -- [item made] = the learned recipe that makes it
local unlearned = {}  -- [item made] = the name of a recipe seen but not learned
local open = {}       -- [recipe id] = true for the recipes of the profession now open
local shown = false   -- a profession window is open
local stale = false   -- the open profession changed since its recipes were read
local indexed         -- the profession last read
local blocked = false -- the game refused the addon's craft
local job             -- { crate, bundle, crates }: what the window is queueing
local current         -- { recipe, crafts }: what the Craft button does
local dialog

local function inCombat()
  return InCombatLockdown ~= nil and InCombatLockdown()
end

--- Whether this client lets the addon queue crafting.
function ns.CanCraft()
  return CAN
end

-- ---------------------------------------------------------------------------
-- Reading the open profession
-- ---------------------------------------------------------------------------

--- Whether the open profession is the player's own, not one linked or an NPC's.
local function own()
  if TS.IsTradeSkillLinked and TS.IsTradeSkillLinked() then return false end
  if TS.IsTradeSkillGuild and TS.IsTradeSkillGuild() then return false end
  if TS.IsNPCCrafting and TS.IsNPCCrafting() then return false end
  return true
end

--- The open profession's name ("Mining").
local function professionName()
  local info = TS.GetBaseProfessionInfo and TS.GetBaseProfessionInfo()
  return info and info.professionName or nil
end

--- One recipe of the open profession: the item it makes and, when learned, the recipe.
local function read(id, profession)
  local info = TS.GetRecipeInfo(id)
  if not info then return end
  local schematic = TS.GetRecipeSchematic(id, false)
  if not schematic then return end
  local item = schematic.outputItemID
  if not item and TS.GetRecipeItemLink then
    local link = TS.GetRecipeItemLink(id)
    item = link and tonumber(link:match("item:(%d+)"))
  end
  if not item then return end
  if not info.learned then return item, nil, info.name end
  local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
  local reagents = {}
  for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
    local reagent = slot.reagents and slot.reagents[1]
    if reagent and reagent.itemID and (slot.reagentType == nil or slot.reagentType == basic)
      and (slot.quantityRequired or 0) > 0 then
      reagents[#reagents + 1] = { item = reagent.itemID, count = slot.quantityRequired }
    end
  end
  return item, { id = id, name = info.name, makes = math.max(1, schematic.quantityMin or 1),
    reagents = reagents, profession = profession }
end

--- Read the open profession's recipes.
local function index()
  stale, open = false, {}
  if not shown or not own() then return end
  if TS.IsTradeSkillReady and not TS.IsTradeSkillReady() then
    stale = true  -- the list is still coming: TRADE_SKILL_LIST_UPDATE follows
    return
  end
  local profession = professionName() or "its profession"
  local fresh = {}
  for _, id in ipairs(TS.GetAllRecipeIDs() or {}) do
    -- A recipe the game can't describe is left out, not an error.
    local ok, item, recipe, name = pcall(read, id, profession)
    if ok and item then
      if recipe then
        open[id] = true
        if not fresh[item] then
          fresh[item], known[item], unlearned[item] = true, recipe, nil
        end
      elseif not known[item] then
        unlearned[item] = name or true
      end
    end
  end
  indexed = profession
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

--- How often a recipe can be crafted from what the bags hold now.
local function canMake(recipe)
  local n
  for _, r in ipairs(recipe.reagents) do
    local m = math.floor(ns.Count(r.item) / r.count)
    n = n and math.min(n, m) or m
  end
  return n or 9999
end

local function refresh()
  if not dialog or not dialog:IsShown() or not job then return end
  if stale then index() end
  -- A run over every crate: whatever is next to fill, until nothing is.
  local left
  if job.run then
    local plan = ns.FillPlan(ns.Count, job.start)
    left = 0
    for _, p in ipairs(plan) do left = left + p.fills end
    if plan[1] then job.crate, job.bundle = plan[1].crate, plan[1].bundle end
  end
  local bundle, crate = job.bundle, job.crate
  local name, icon = ns.Item(bundle.item, bundle.name)
  local want = job.crates * bundle.count
  local have = ns.Count(bundle.item)

  dialog.heading:SetText(crate.name)
  dialog.item.id = bundle.item
  dialog.item.icon:SetTexture(icon)
  dialog.name:SetText(("%d x %s"):format(want, name))
  dialog.held:SetText(ns.Color(have >= want and GREEN or GREY, ("In bags: %d"):format(have)))

  -- Filling: one crate a click, while the bags hold a crate and enough to fill it.
  local crates = ns.Count(crate.item)
  local fills = math.min(crates, math.floor(have / bundle.count))
  local lines = {}
  if left == 0 then
    fills = 0
    lines[1] = ns.Color(GREEN, "Done: the bags can fill no more crates.")
  elseif left then
    lines[1] = ns.Color(GREEN, ("%d crate%s to fill in all, %d with this."):format(
      left, left == 1 and "" or "s", fills))
    lines[2] = ns.Color(GREY, "One click fills one crate. Click again after the cast.")
    lines[3] = ns.Color(GREY, "The next kind of crate follows by itself.")
  elseif crates == 0 then
    lines[1] = ns.Color(RED, "No unfilled crate in the bags.")
  elseif fills == 0 then
    lines[1] = ns.Color(RED, ("%d crate%s in the bags, each takes %d."):format(
      crates, crates == 1 and "" or "s", bundle.count))
  else
    lines[1] = ns.Color(GREEN, ("%d crate%s in the bags, enough to fill %d."):format(
      crates, crates == 1 and "" or "s", fills))
    lines[2] = ns.Color(GREY, "One click fills one crate. Click again after the cast.")
  end
  -- A secure button can't be changed in combat; it is set again when the fight ends.
  if not inCombat() then
    local fill = dialog.fill
    if fills > 0 then
      fill:SetAttribute("type", "item")
      fill:SetAttribute("item", "item:" .. crate.item)
      fill:SetAttribute("target-item", "item:" .. bundle.item)
      fill:SetText(("Fill a crate (%d left)"):format(left or fills))
      fill:Enable()
    else
      fill:SetAttribute("type", nil)
      fill:SetText("Fill a crate")
      fill:Disable()
    end
  end

  current = nil
  local crafted = not job.run and CAN and ns.CRATE_CRAFTED[crate.kind]
  dialog.crates:SetShown(crafted and true or false)
  dialog.cratesLabel:SetShown(crafted and true or false)
  dialog.craft:SetShown(crafted and true or false)
  if not crafted then
    dialog.notes:SetText(table.concat(lines, "\n"))
    return
  end
  lines[#lines + 1] = " "
  local steps, missing = ns.CraftPlan(bundle.item, want, known, ns.Count)
  if have >= want then
    lines[#lines + 1] = ns.Color(GREEN, ("Nothing to craft for %d crate%s."):format(
      job.crates, job.crates == 1 and "" or "s"))
  elseif #steps == 0 then
    if type(unlearned[bundle.item]) == "string" then
      lines[#lines + 1] = ns.Color(RED, ("Recipe not learned: %s."):format(unlearned[bundle.item]))
    elseif unlearned[bundle.item] then
      lines[#lines + 1] = ns.Color(RED, "Recipe not learned.")
    else
      lines[#lines + 1] = ns.Color(ORANGE, ("To craft it: open %s."):format(ns.CRATE_SKILL[crate.kind]))
    end
  else
    local queued = {}
    for _, step in ipairs(steps) do queued[step.item] = true end
    for i, step in ipairs(steps) do
      local recipe = step.recipe
      local can = math.min(step.crafts, canMake(recipe))
      -- A recipe that takes what an earlier one makes is only waiting its turn.
      local waiting = false
      for _, r in ipairs(recipe.reagents) do waiting = waiting or queued[r.item] end
      local note
      if not open[recipe.id] then
        note = ns.Color(ORANGE, "open " .. recipe.profession)
      elseif can == 0 then
        note = not waiting and ns.Color(RED, "material missing") or nil
      elseif not current then
        current = { recipe = recipe, crafts = can, item = step.item }
        note = can < step.crafts and ns.Color(GREY, ("material for %d"):format(can * recipe.makes)) or nil
      end
      local text = ("%d. %d x %s"):format(i, step.crafts * recipe.makes, (ns.Item(step.item, recipe.name)))
      if current and current.recipe == recipe then text = ns.Color(GOLD, text) end
      lines[#lines + 1] = text .. (note and ("  " .. note) or "")
    end
    for _, m in ipairs(missing) do
      lines[#lines + 1] = ns.Color(RED, ("Missing: %d x %s%s"):format(m.count, (ns.Item(m.item)),
        unlearned[m.item] and " (recipe not learned)" or ""))
    end
  end
  if blocked then
    current = nil
    lines[#lines + 1] = ns.Color(RED, "Blocked by the game. Craft it in the profession window.")
  end
  dialog.notes:SetText(table.concat(lines, "\n"))

  if current then
    dialog.craft:SetText(("Craft %d x %s"):format(current.crafts * current.recipe.makes,
      (ns.Item(current.item, current.recipe.name))))
    dialog.craft:Enable()
  else
    dialog.craft:SetText("Craft")
    dialog.craft:Disable()
  end
end

--- The Craft button: the next recipe of the queue, as often as the bags allow.
local function onCraft()
  if not current then return end
  -- The craft first, the window after: nothing runs between the click and the protected
  -- call (Buy.lua: WoW Forever blocked a purchase when the window was updated first).
  TS.CraftRecipe(current.recipe.id, current.crafts)
end

local function makeDialog()
  dialog = ns.Skin.Window("PuggerWaylaidCompanionCraft", UIParent, 400, 330, "Fill crates")
  dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
  dialog:SetToplevel(true)
  dialog:SetFrameStrata("DIALOG")
  dialog:SetMovable(true)
  dialog:EnableMouse(true)
  dialog:SetClampedToScreen(true)
  dialog:RegisterForDrag("LeftButton")
  dialog:SetScript("OnDragStart", dialog.StartMoving)
  dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
  dialog:Hide()

  dialog.heading = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  dialog.heading:SetPoint("TOPLEFT", 16, -36)
  dialog.heading:SetJustifyH("LEFT")
  dialog.heading:SetTextColor(unpack(ns.Skin.color.accent))

  -- How many crates to fill.
  dialog.crates = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
  dialog.crates:SetSize(36, 20)
  dialog.crates:SetPoint("TOPRIGHT", -16, -32)
  dialog.crates:SetAutoFocus(false)
  dialog.crates:SetNumeric(true)
  dialog.crates:SetMaxLetters(3)
  dialog.crates:SetJustifyH("CENTER")
  dialog.crates:SetScript("OnTextChanged", function(self, userInput)
    if not userInput or not job then return end
    job.crates = math.max(1, math.floor(tonumber(self:GetText()) or 1))
    refresh()
  end)
  dialog.crates:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  dialog.crates:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  local label = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("RIGHT", dialog.crates, "LEFT", -10, 0)
  label:SetText("Craft for crates")
  dialog.cratesLabel = label

  local ROW = -78
  dialog.item = CreateFrame("Button", nil, dialog)
  dialog.item:SetSize(32, 32)
  dialog.item:SetPoint("LEFT", dialog, "TOPLEFT", 16, ROW)
  dialog.item.icon = dialog.item:CreateTexture(nil, "ARTWORK")
  dialog.item.icon:SetAllPoints()
  dialog.item.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  ns.Skin.Border(dialog.item, ns.Skin.color.edge, "OVERLAY")
  dialog.item:SetScript("OnEnter", function(self)
    if not self.id then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.id)
    GameTooltip:Show()
  end)
  dialog.item:SetScript("OnLeave", function() GameTooltip:Hide() end)

  dialog.held = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  dialog.held:SetPoint("RIGHT", dialog, "TOPRIGHT", -16, ROW)
  dialog.held:SetJustifyH("RIGHT")

  dialog.name = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  dialog.name:SetPoint("LEFT", dialog.item, "RIGHT", 8, 0)
  dialog.name:SetPoint("RIGHT", dialog.held, "LEFT", -8, 0)
  dialog.name:SetJustifyH("LEFT")
  dialog.name:SetWordWrap(false)

  dialog.notes = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  dialog.notes:SetPoint("TOPLEFT", 16, -106)
  dialog.notes:SetPoint("TOPRIGHT", -16, -106)
  dialog.notes:SetJustifyH("LEFT")
  dialog.notes:SetJustifyV("TOP")
  dialog.notes:SetSpacing(3)

  -- The Fill button uses the crate and picks the material, which only a secure button
  -- may do: its attributes say what a click does, and the game does it.
  local classic = ns.Skin.Classic()
  local fill = CreateFrame("Button", "PuggerWaylaidCompanionFill", dialog,
    classic and "SecureActionButtonTemplate,UIPanelButtonTemplate" or "SecureActionButtonTemplate")
  fill:SetSize(250, 26)
  fill:SetPoint("BOTTOMLEFT", 16, 44)
  -- The game acts on the press or the release, as its own setting has it.
  fill:RegisterForClicks("AnyUp", "AnyDown")
  if not classic then
    local accent = ns.Skin.color.accent
    local back = ns.Skin.Fill(fill, { accent[1], accent[2], accent[3], 0.22 }, "BACKGROUND")
    back:SetAllPoints()
    ns.Skin.Border(fill, { accent[1], accent[2], accent[3], 0.6 }, "BORDER")
    local hover = ns.Skin.Fill(fill, ns.Skin.color.hover, "HIGHLIGHT")
    hover:SetAllPoints()
    fill:SetNormalFontObject("GameFontHighlight")
    fill:SetHighlightFontObject("GameFontHighlight")
    fill:SetDisabledFontObject("GameFontDisable")
    fill:SetScript("OnDisable", function() back:SetColorTexture(1, 1, 1, 0.03) end)
    fill:SetScript("OnEnable", function() back:SetColorTexture(accent[1], accent[2], accent[3], 0.22) end)
  end
  fill:SetText("Fill a crate")
  dialog.fill = fill

  dialog.craft = ns.Skin.Button(dialog, "Craft", 250, 22)
  dialog.craft:SetPoint("BOTTOMLEFT", 16, 14)
  dialog.craft:SetScript("OnClick", onCraft)

  dialog.close = ns.Skin.Button(dialog, "Close", 90, 22)
  dialog.close:SetPoint("BOTTOMRIGHT", -16, 14)
  dialog.close:SetScript("OnClick", function() dialog:Hide() end)

  -- Escape closes it.
  if UISpecialFrames then table.insert(UISpecialFrames, "PuggerWaylaidCompanionCraft") end
end

--- Open the window for a crate and one of its materials: filling the crates in the bags
--- with it and, for a crafted material, crafting enough for them (one at the least).
function ns.Craft(crate, bundle)
  -- A window with a secure button can't be shown or changed in combat.
  if inCombat() then
    print(ns.TITLE .. ": not in combat.")
    return
  end
  if not dialog then makeDialog() end
  job = { crate = crate, bundle = bundle, crates = math.max(1, ns.Count(crate.item)) }
  blocked = false
  dialog.crates:SetText(tostring(job.crates))
  dialog:Show()
  refresh()
end

--- Open the window on a run over every crate in the bags that the bags can fill: one
--- kind after the other, a click a crate. With `from` (a crate), from that one down the
--- list, then round from the top for those above it.
function ns.FillAll(from)
  if inCombat() then
    print(ns.TITLE .. ": not in combat.")
    return
  end
  local start
  for i, crate in ipairs(ns.crates) do
    if crate == from then start = i end
  end
  local first = ns.FillPlan(ns.Count, start)[1]
  if not first then
    print(ns.TITLE .. ": no crate in the bags that the bags can fill.")
    return
  end
  if not dialog then makeDialog() end
  job = { run = true, start = start, crate = first.crate, bundle = first.bundle, crates = 1 }
  blocked = false
  dialog:Show()
  refresh()
end

local BLOCKED = { ADDON_ACTION_BLOCKED = true, ADDON_ACTION_FORBIDDEN = true }

local events = CreateFrame("Frame")
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE",
  "TRADE_SKILL_DATA_SOURCE_CHANGED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
  "PLAYER_REGEN_ENABLED" }) do
  pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, addon, fn)
  if event == "PLAYER_REGEN_ENABLED" then return refresh() end
  if not CAN then return end
  if BLOCKED[event] then
    if addon == ADDON and type(fn) == "string" and fn:find("CraftRecipe") then
      blocked = true
      refresh()
    end
    return
  end
  if event == "TRADE_SKILL_CLOSE" then
    shown, stale, open = false, false, {}
    return refresh()
  end
  shown, stale = true, true
  -- Read now when the queue is on screen or the profession is a new one; else when the
  -- queue next opens: the list updates with every craft.
  local watching = dialog and dialog:IsShown()
  if watching or professionName() ~= indexed then
    C_Timer.After(0.3, function()
      if stale then index() end
      refresh()
    end)
  end
end)

ns.OnChange(refresh)
