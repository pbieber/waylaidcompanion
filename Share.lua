--[[
Sharing what the addon has learned, as text a player copies out and another pastes in.

/pwc export shows a string holding this account's turn-in places, the writs it has had on
the side the data says can't get them, the Merchant's Favor crates paid and the
quartermasters' rewards; nothing about its characters. /pwc import
takes such a string and adds what this account does not know yet. scripts/bake_waylaid.py
reads the same strings (it loads this file) to bake them into Data/Recorded.lua.

The string is "PWC1:<adler-32 of the data, hex>:<the data in base64>." The closing dot
marks its end, as line breaks inside it are allowed (pasting adds them). The data is a
small serialization of one table:

  value = "T" { value value } "E"     a table, as key and value pairs
        | "A" { value } "E"           a list (a table keyed 1 to n)
        | "S" <length> ":" <bytes>    a string
        | "N" <number> ";"            a number
        | "Y" | "F"                   true, false

  { v = 1, npcs = { [place] = { name, uiMapID, x, y, zone } }, writs = { [quest] = place },
    anySide = { [quest] = true }, favor = { [crate key] = { [amount] = times seen } },
    rewards = { [faction] = { [npc] = { npc, time, items = { { id, standing (0 for none),
    price, quantity, cost value, cost name, cost value, cost name, ... } } } } } }

with the shapes the saved settings use (Learn.lua, Rewards.lua), except that a reward is
a short list, without its name or icons: the game has those. A string from
someone else is never run as code: it is parsed, and only the shapes above are kept.
]]

local _, ns = ...

local PREFIX = "PWC1"

-- ---------------------------------------------------------------------------
-- Base64 and checksum, in plain Lua 5.1 arithmetic
-- ---------------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_VALUE = {}
for i = 1, 64 do B64_VALUE[B64:byte(i)] = i - 1 end

local function toBase64(s)
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local d1, d2 = math.floor(n / 262144) % 64, math.floor(n / 4096) % 64
    local d3, d4 = math.floor(n / 64) % 64, n % 64
    out[#out + 1] = B64:sub(d1 + 1, d1 + 1) .. B64:sub(d2 + 1, d2 + 1)
      .. (b and B64:sub(d3 + 1, d3 + 1) or "=") .. (c and B64:sub(d4 + 1, d4 + 1) or "=")
  end
  return table.concat(out)
end

--- The bytes of a base64 text, or nil when it is not base64. Line breaks and spaces, which
--- pasting adds, are skipped.
local function fromBase64(text)
  text = text:gsub("%s", "")
  if #text % 4 ~= 0 then return nil end
  local out = {}
  for i = 1, #text, 4 do
    local n, pad = 0, 0
    for j = i, i + 3 do
      local byte = text:byte(j)
      local v = B64_VALUE[byte]
      if byte == 61 and j > #text - 2 then -- "=" padding, only at the very end
        v, pad = 0, pad + 1
      elseif not v or pad > 0 then
        return nil
      end
      n = n * 64 + v
    end
    local a, b, c = math.floor(n / 65536), math.floor(n / 256) % 256, n % 256
    out[#out + 1] = pad == 2 and string.char(a) or pad == 1 and string.char(a, b) or string.char(a, b, c)
  end
  return table.concat(out)
end

local function adler32(s)
  local a, b = 1, 0
  for i = 1, #s do
    a = (a + s:byte(i)) % 65521
    b = (b + a) % 65521
  end
  return ("%08x"):format(b * 65536 + a)
end

-- ---------------------------------------------------------------------------
-- Serialization
-- ---------------------------------------------------------------------------

--- Whether a table is a list: keyed 1 to n and nothing else.
local function isList(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n > 0 and n == #t
end

local function write(value, out)
  local kind = type(value)
  if kind == "table" and isList(value) then
    out[#out + 1] = "A"
    for _, v in ipairs(value) do write(v, out) end
    out[#out + 1] = "E"
  elseif kind == "table" then
    out[#out + 1] = "T"
    -- In key order, so the same data always gives the same string.
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(x, y)
      if type(x) ~= type(y) then return type(x) == "number" end
      return x < y
    end)
    for _, k in ipairs(keys) do
      write(k, out)
      write(value[k], out)
    end
    out[#out + 1] = "E"
  elseif kind == "string" then
    out[#out + 1] = "S" .. #value .. ":" .. value
  elseif kind == "number" then
    out[#out + 1] = "N" .. ("%.14g"):format(value) .. ";"
  elseif kind == "boolean" then
    out[#out + 1] = value and "Y" or "F"
  end
end

local MAX_DEPTH, MAX_VALUES = 10, 200000

--- The value serialized in s, or nil and why not.
local function read(s)
  local pos, count = 1, 0
  local function value(depth)
    count = count + 1
    if depth > MAX_DEPTH or count > MAX_VALUES then error("too deep or too long", 0) end
    local tag = s:sub(pos, pos)
    pos = pos + 1
    if tag == "T" then
      local t = {}
      while s:sub(pos, pos) ~= "E" do
        if pos > #s then error("cut short", 0) end
        local k = value(depth + 1)
        local v = value(depth + 1)
        if k == nil or k ~= k then error("bad key", 0) end
        t[k] = v
      end
      pos = pos + 1
      return t
    elseif tag == "A" then
      local t = {}
      while s:sub(pos, pos) ~= "E" do
        if pos > #s then error("cut short", 0) end
        t[#t + 1] = value(depth + 1)
      end
      pos = pos + 1
      return t
    elseif tag == "S" then
      local digits = s:match("^%d+:", pos)
      if not digits then error("bad text", 0) end
      local len = tonumber(digits:sub(1, -2))
      local start = pos + #digits
      if start + len - 1 > #s then error("cut short", 0) end
      pos = start + len
      return s:sub(start, start + len - 1)
    elseif tag == "N" then
      local text = s:match("^[^;]*;", pos)
      local n = text and tonumber(text:sub(1, -2))
      if not n or n ~= n or n == math.huge or n == -math.huge then error("bad number", 0) end
      pos = pos + #text
      return n
    elseif tag == "Y" then
      return true
    elseif tag == "F" then
      return false
    end
    error("unknown data", 0)
  end
  local ok, result = pcall(value, 1)
  if not ok then return nil, result end
  if pos <= #s then return nil, "extra data" end
  return result
end

-- ---------------------------------------------------------------------------
-- Keeping only the expected shapes
-- ---------------------------------------------------------------------------

--- A short text, without control characters or the game's "|" escape codes (links,
--- textures, colors).
local function text(v, max)
  if type(v) == "string" and #v > 0 and #v <= (max or 100) and not v:find("[%c|]") then return v end
end

local function int(v, low, high)
  if type(v) == "number" and v == math.floor(v) and v >= (low or 0) and v <= (high or 2 ^ 31) then
    return v
  end
end

local function coord(v)
  if type(v) == "number" and v >= 0 and v <= 100 then return v end
end

--- A place's key: an NPC id, or "at:map:x:y" for a spot nobody has named yet.
local function placeKey(k)
  if int(k, 1) then return k end
  if type(k) == "string" and k:match("^at:%d+:%d+:%d+$") then return k end
end

--- { name, uiMapID, x, y, zone }, or nil.
local function place(p)
  if type(p) ~= "table" then return nil end
  local name, map, x, y, zone = text(p[1]), int(p[2], 1), coord(p[3]), coord(p[4]), text(p[5])
  if name and map and x and y and zone then return { name, map, x, y, zone } end
end

--- A reward from its shared list { id, standing, price, quantity, value, name, ... }, in
--- the shape Rewards.lua keeps.
local function rewardItem(item)
  if type(item) ~= "table" or not int(item[1], 1) then return nil end
  local costs = {}
  for i = 5, math.min(#item, 14), 2 do
    local value, name = int(item[i], 1), text(item[i + 1])
    if value and name then costs[#costs + 1] = { value = value, name = name } end
  end
  return {
    id = item[1], standing = int(item[2], 1, 8), price = int(item[3]) or 0,
    quantity = int(item[4], 1, 1000) or 1, costs = costs,
  }
end

--- A reward as its shared list.
local function rewardList(item)
  local out = { item.id, item.standing or 0, item.price or 0, item.quantity or 1 }
  for _, c in ipairs(item.costs or {}) do
    out[#out + 1] = c.value
    out[#out + 1] = c.name
  end
  return out
end

local function shop(s)
  if type(s) ~= "table" or type(s.items) ~= "table" then return nil end
  local items = {}
  for _, item in ipairs(s.items) do
    items[#items + 1] = rewardItem(item)
    if #items >= 500 then break end
  end
  if #items == 0 then return nil end
  return { npc = text(s.npc), time = int(s.time) or 0, items = items }
end

--- The shared data in a decoded table, in the shapes above; anything else is dropped.
local function clean(data)
  local out = { npcs = {}, writs = {}, anySide = {}, favor = {}, rewards = {} }
  if type(data) ~= "table" or data.v ~= 1 then return nil end
  for k, p in pairs(type(data.npcs) == "table" and data.npcs or {}) do
    if placeKey(k) then out.npcs[k] = place(p) end
  end
  for quest, at in pairs(type(data.writs) == "table" and data.writs or {}) do
    if int(quest, 1) and placeKey(at) then out.writs[quest] = at end
  end
  for quest, yes in pairs(type(data.anySide) == "table" and data.anySide or {}) do
    if int(quest, 1) and yes == true then out.anySide[quest] = true end
  end
  for key, paid in pairs(type(data.favor) == "table" and data.favor or {}) do
    if (int(key, 1) or (type(key) == "string" and key:match("^q%d+$"))) and type(paid) == "table" then
      local amounts = {}
      for amount, times in pairs(paid) do
        if int(amount, 1, 100000) and int(times, 1) then amounts[amount] = times end
      end
      if next(amounts) then out.favor[key] = amounts end
    end
  end
  for faction, shops in pairs(type(data.rewards) == "table" and data.rewards or {}) do
    if text(faction) and type(shops) == "table" then
      local kept = {}
      for npc, s in pairs(shops) do
        if int(npc, 1) or text(npc) then kept[npc] = shop(s) end
      end
      if next(kept) then out.rewards[faction] = kept end
    end
  end
  return out
end

--- The data in a shared string: { npcs, writs, anySide, favor, rewards }, or nil and why
--- not.
function ns.ShareDecode(str)
  if type(str) ~= "string" then return nil, "no text" end
  if not str:find(PREFIX .. ":", 1, true) then return nil, "not a " .. ns.TITLE .. " string" end
  local sum, body = str:match(PREFIX .. ":(%x%x%x%x%x%x%x%x):([%w%+/=%s]+)%.")
  if not sum then return nil, "the text is incomplete" end
  local bytes = fromBase64(body)
  if not bytes then return nil, "the text is damaged" end
  if adler32(bytes) ~= sum:lower() then return nil, "the text is incomplete or changed" end
  local data, why = read(bytes)
  if not data then return nil, "the data is damaged (" .. why .. ")" end
  local out = clean(data)
  if not out then return nil, "made by a newer version of the addon" end
  return out
end

--- A shared string of what this account has learned.
function ns.ShareEncode()
  local db = ns.db or {}
  local rewards = {}
  for faction, shops in pairs(db.rewards or {}) do
    -- Before 0.5.1 a faction held a single shop.
    if shops.items then shops = { [shops.npc or "?"] = shops } end
    rewards[faction] = {}
    for npc, s in pairs(shops) do
      if type(s) == "table" and s.items then
        local items = {}
        for i, item in ipairs(s.items) do items[i] = rewardList(item) end
        rewards[faction][npc] = { npc = s.npc, time = s.time, items = items }
      end
    end
  end
  local out = {}
  write({ v = 1, npcs = db.npcs, writs = db.writNpc, anySide = db.anySide, favor = db.favor,
    rewards = rewards }, out)
  local bytes = table.concat(out)
  return PREFIX .. ":" .. adler32(bytes) .. ":" .. toBase64(bytes) .. "."
end

-- ---------------------------------------------------------------------------
-- Adding shared data to this account's
-- ---------------------------------------------------------------------------

--- Add what a shared string knows and this account does not. Returns counts:
--- { turnIns, sides, favor, shops }.
function ns.ShareMerge(data)
  local db = ns.db
  local added = { turnIns = 0, sides = 0, favor = 0, shops = 0 }
  for quest, at in pairs(data.writs) do
    local writ = ns.writByQuest[quest]
    local old = db.writNpc[quest]
    -- A turn-in this account or the shipped data names stays. A named NPC replaces a spot.
    local wanted = writ and type(writ.npc) ~= "number" and type(old) ~= "number"
      and (old == nil or type(at) == "number") and old ~= at
    local spot = data.npcs[at] or db.npcs[at] or ns.WRIT_NPCS[at]
    if wanted and spot then
      if not db.npcs[at] and not ns.WRIT_NPCS[at] then db.npcs[at] = spot end
      db.writNpc[quest] = at
      added.turnIns = added.turnIns + 1
    end
  end
  for quest in pairs(data.anySide) do
    local writ = ns.writByQuest[quest]
    if writ and writ.side and not ns.AnySide(quest) then
      db.anySide[quest] = true
      added.sides = added.sides + 1
    end
  end
  for key, paid in pairs(data.favor) do
    local kept = db.favor[key] or {}
    db.favor[key] = kept
    for amount, times in pairs(paid) do
      -- The larger count, not the sum: importing the same string twice changes nothing.
      if times > (kept[amount] or 0) then
        if not kept[amount] then added.favor = added.favor + 1 end
        kept[amount] = times
      end
    end
  end
  db.rewards = db.rewards or {}
  for faction, shops in pairs(data.rewards) do
    local list = db.rewards[faction] or {}
    db.rewards[faction] = list
    for npc, s in pairs(shops) do
      local old = list[npc]
      if not (old and old.items and (old.time or 0) >= s.time) then
        list[npc] = s
        added.shops = added.shops + 1
      end
    end
  end
  return added
end

if not CreateFrame then return end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

local window

local function makeWindow()
  window = CreateFrame("Frame", "PuggerWaylaidCompanionShare", UIParent, "BasicFrameTemplateWithInset")
  window:SetSize(460, 320)
  window:SetPoint("CENTER", 0, 60)
  window:SetFrameStrata("DIALOG")
  window:SetToplevel(true)
  window:SetMovable(true)
  window:EnableMouse(true)
  window:SetClampedToScreen(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", window.StopMovingOrSizing)
  window:Hide()
  tinsert(UISpecialFrames, "PuggerWaylaidCompanionShare")

  window.title = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  window.title:SetPoint("TOP", 0, -5)

  window.help = window:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  window.help:SetPoint("TOPLEFT", 16, -32)
  window.help:SetPoint("TOPRIGHT", -16, -32)
  window.help:SetJustifyH("LEFT")

  local scroll = CreateFrame("ScrollFrame", "PuggerWaylaidCompanionShareScroll", window, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 16, -70)
  scroll:SetPoint("BOTTOMRIGHT", -34, 48)
  window.box = CreateFrame("EditBox", nil, scroll)
  window.box:SetMultiLine(true)
  window.box:SetMaxLetters(0)
  window.box:SetAutoFocus(false)
  window.box:SetFontObject(ChatFontNormal)
  window.box:SetWidth(400)
  window.box:SetScript("OnEscapePressed", function() window:Hide() end)
  scroll:SetScrollChild(window.box)
  scroll:EnableMouse(true)
  scroll:SetScript("OnMouseDown", function() window.box:SetFocus() end)

  window.go = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
  window.go:SetSize(110, 22)
  window.go:SetPoint("BOTTOMLEFT", 16, 14)
  window.go:SetText("Import")
  window.go:SetScript("OnClick", function()
    local data, why = ns.ShareDecode(window.box:GetText())
    if not data then
      print(ns.TITLE .. ": could not import: " .. why .. ".")
      return
    end
    local added = ns.ShareMerge(data)
    local function n(count, word) return ("%d %s%s"):format(count, word, count == 1 and "" or "s") end
    print(("%s: imported %s, %s, %s, %s."):format(ns.TITLE, n(added.turnIns, "turn-in"),
      n(added.sides, "writ") .. " for both sides",
      n(added.favor, "Merchant's Favor amount"), n(added.shops, "quartermaster")))
    ns.Changed()
    window:Hide()
  end)

  window.close = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
  window.close:SetSize(90, 22)
  window.close:SetPoint("BOTTOMRIGHT", -16, 14)
  window.close:SetText("Close")
  window.close:SetScript("OnClick", function() window:Hide() end)
end

--- Show the export string, selected for copying.
function ns.ShowExport()
  if not window then makeWindow() end
  window.title:SetText("Share what you've learned")
  window.help:SetText("Press Ctrl+C to copy, then post it for the addon's author or other players.")
  window.go:Hide()
  window.box:SetText(ns.ShareEncode())
  window:Show()
  window.box:SetFocus()
  window.box:HighlightText()
end

--- Show an empty box to paste a shared string into.
function ns.ShowImport()
  if not window then makeWindow() end
  window.title:SetText("Add shared data")
  window.help:SetText("Paste a shared string with Ctrl+V, then press Import.")
  window.go:Show()
  window.box:SetText("")
  window:Show()
  window.box:SetFocus()
end
