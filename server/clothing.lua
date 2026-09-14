--- What a character wears: validation, the write, and the answer. `opx77_appearance` reads the
--- puppet's equipment and wardrobe and sends them here; nothing else may write them.
---
--- One record per character in `opx77_character_clothing`, carried in `PlayerData.clothing`:
--- the record, `false` when none is stored, or nil when the core cannot say -- the table is
--- missing, or the read failed -- which the client reads as "dress nothing, save nothing". The
--- record has the platform's own shape, the one its presentation service stores: nine slots,
--- seven outfits overriding the seven visible ones, and the active outfit.

local Result = OPX.Result

local Clothing = {}
OPX.Clothing = Clothing

--- The schema version written into every stored record.
Clothing.VERSION = 1

--- The migration that creates the table. It is optional: see `Clothing.available`.
Clothing.MIGRATION = "0007_character_clothing"

--- The nine equipment slots, as the platform names them. Underwear is worn, never overridden.
local SLOTS = { "Head", "Face", "InnerChest", "OuterChest", "Legs", "Feet", "Outfit",
                "UnderwearTop", "UnderwearBottom" }
local IS_SLOT = {}
for index = 1, #SLOTS do IS_SLOT[SLOTS[index]] = true end
local IS_OUTFIT_SLOT = { Head = true, Face = true, InnerChest = true, OuterChest = true,
                         Legs = true, Feet = true, Outfit = true }

--- Outfits are indexed 0 to 6, as `Open77.wardrobe` indexes them.
local OUTFITS = 7

--- A record name, as `Open77.equipment.info` bounds one.
local MAX_RECORD_BYTES = 160

--- Nine slots and 49 overrides of 160 bytes stay under 10 KiB encoded; this only catches a
--- shape the checks below have let through by mistake.
local MAX_JSON_BYTES = 16384

--- The same cooldown as a face: one save per player per window, on its own key.
local COOLDOWN_MS = 2000

---@param value any
---@return boolean
local function isInteger(value)
  return type(value) == "number" and OPX.Math.isFinite(value) and value % 1 == 0
end

--- A worn record name, or false for an empty slot; nil for anything else. No catalogue: the
--- server has none, so this is the shape the look distribution accepts too.
---@param value any
---@return string|false|nil
local function recordOf(value)
  if value == false then return false end
  if type(value) ~= "string" or #value < 1 or #value > MAX_RECORD_BYTES then return nil end
  if value:match("^[%w_%.%-]+$") == nil then return nil end
  return value
end

--- An outfit index from a key that arrived as a number or, after JSON, as a string.
---@param key any
---@return integer|nil
local function outfitIndex(key)
  local number
  if type(key) == "number" then
    number = key
  elseif type(key) == "string" and key:match("^%d$") then
    number = tonumber(key)
  end
  if not isInteger(number) or number < 0 or number >= OUTFITS then return nil end
  return math.floor(number)
end

--- A record in canonical form -- all nine slots stated, outfit keys "0" to "6", empty outfits
--- dropped -- or nil and the code saying what was wrong with it.
---@param value any
---@return ClothingRecord|nil canonical, string|nil error
function Clothing.canonical(value)
  if type(value) ~= "table" then return nil, "invalid_record" end
  for key in pairs(value) do
    if key ~= "schemaVersion" and key ~= "equipment" and key ~= "wardrobe" then
      return nil, "unknown_field"
    end
  end
  if value.schemaVersion ~= Clothing.VERSION then return nil, "unsupported_schema" end

  local equipment = value.equipment
  if type(equipment) ~= "table" then return nil, "invalid_equipment" end
  local canonical = {
    schemaVersion = Clothing.VERSION, equipment = {}, wardrobe = { outfits = {} },
  }
  for slot, item in pairs(equipment) do
    if not IS_SLOT[slot] then return nil, "invalid_slot" end
    if recordOf(item) == nil then return nil, "invalid_item" end
  end
  for index = 1, #SLOTS do
    local slot = SLOTS[index]
    canonical.equipment[slot] = recordOf(equipment[slot]) or false
  end

  local wardrobe = value.wardrobe
  if type(wardrobe) ~= "table" then return nil, "invalid_wardrobe" end
  for key in pairs(wardrobe) do
    if key ~= "active" and key ~= "outfits" then return nil, "unknown_wardrobe_field" end
  end
  if wardrobe.active ~= nil then
    local active = outfitIndex(wardrobe.active)
    if active == nil or type(wardrobe.active) ~= "number" then return nil, "invalid_active" end
    canonical.wardrobe.active = active
  end

  local outfits = wardrobe.outfits
  if outfits ~= nil and type(outfits) ~= "table" then return nil, "invalid_outfits" end
  local seen, count = {}, 0
  for key, overrides in pairs(outfits or {}) do
    count = count + 1
    local index = outfitIndex(key)
    -- "0" and 0 are one outfit: two of them is a client that means two different things
    if count > OUTFITS or index == nil or seen[index] then return nil, "invalid_outfit" end
    seen[index] = true
    if type(overrides) ~= "table" then return nil, "invalid_outfit" end
    local clean, any = {}, false
    for slot, item in pairs(overrides) do
      if not IS_OUTFIT_SLOT[slot] then return nil, "invalid_outfit_slot" end
      local record = recordOf(item)
      if record == nil then return nil, "invalid_item" end
      clean[slot], any = record, true
    end
    if any then canonical.wardrobe.outfits[tostring(index)] = clean end
  end

  return canonical
end

--- Whether two canonical records are the same clothing, for skipping a write that would change
--- nothing.
---@param left ClothingRecord|false|nil
---@param right ClothingRecord|false|nil
---@return boolean
function Clothing.same(left, right)
  if type(left) ~= "table" or type(right) ~= "table" then return false end
  for index = 1, #SLOTS do
    local slot = SLOTS[index]
    if left.equipment[slot] ~= right.equipment[slot] then return false end
  end
  if left.wardrobe.active ~= right.wardrobe.active then return false end
  for index = 0, OUTFITS - 1 do
    local a, b = left.wardrobe.outfits[tostring(index)], right.wardrobe.outfits[tostring(index)]
    if (a == nil) ~= (b == nil) then return false end
    if a ~= nil then
      for slot in pairs(IS_OUTFIT_SLOT) do
        if a[slot] ~= b[slot] then return false end
      end
    end
  end
  return true
end

--- Whether the table exists as far as this run knows: its migration was not skipped.
---@return boolean
function Clothing.available()
  return OPX.Storage.skipped[Clothing.MIGRATION] ~= true
end

--- The stored record for a character, validated. Coroutine only.
---@param citizenId CitizenId
---@return Result  ok value is the record, or false when none is stored
local function fetch(citizenId)
  if not Clothing.available() then return Result.err("error.unavailable", "clothing_table") end
  local fetched = OPX.Storage.Players.fetchClothing(citizenId)
  if not fetched.ok then return fetched end
  if fetched.value == nil then return Result.ok(false) end
  local canonical, reason = Clothing.canonical(fetched.value)
  if not canonical then return Result.err("clothing-unreadable", reason) end
  return Result.ok(canonical)
end

--- What `PlayerData.clothing` starts as at login. Never refuses a login: a failure is nil, which
--- keeps the stored row away from a client that could not be shown it. Coroutine only.
---@param citizenId CitizenId
---@return ClothingRecord|false|nil
function Clothing.load(citizenId)
  local fetched = fetch(citizenId)
  if fetched.ok then return fetched.value end
  if Clothing.available() then
    Open77.log.warn(("[clothing] %s: the stored clothing could not be read (%s: %s); it is " ..
      "neither restored nor overwritten this session"):format(citizenId,
        tostring(fetched.error), tostring(fetched.detail)))
  end
  return nil
end

--- Validates a record, writes it to `opx77_character_clothing` and puts it on
--- `PlayerData.clothing`. Coroutine only.
---@param identifier Player|Source|CitizenId
---@param clothing any straight off the wire
---@return Result  ok value is the canonical record
function OPX.SaveClothing(identifier, clothing)
  local player = OPX.ResolvePlayer(identifier)
  if not player then return Result.err("error.notLoggedIn", tostring(identifier)) end

  local canonical, reason = Clothing.canonical(clothing)
  if not canonical then return Result.err("clothing.invalid", reason) end

  local data = player.PlayerData
  -- nil is a login that could not read the row: a write now would replace what nobody has seen
  if data.clothing == nil or not Clothing.available() then
    return Result.err("error.unavailable", "clothing_unavailable")
  end
  if Clothing.same(data.clothing, canonical) then return Result.ok(data.clothing) end

  local encoded = json.encode(canonical)
  if #encoded > MAX_JSON_BYTES then
    return Result.err("clothing.tooLarge", tostring(#encoded))
  end

  local written = OPX.Storage.Players.saveClothing(data.citizenId, encoded)
  if not written.ok then return written end
  data.clothing = canonical

  -- the write yielded: a player who switched character meanwhile is not sent this one's
  if not player.Offline and OPX.Players[data.source] == player then
    player.Functions.UpdatePlayerData()
    TriggerClientEvent(OPX.Events.Client.CLOTHING_UPDATE, data.source, canonical)
  end
  TriggerEvent(OPX.Events.Internal.CLOTHING_CHANGE, data.source, data.citizenId, canonical)

  OPX.Logger.player(player, "clothing.saved", nil, { bytes = #encoded })
  return Result.ok(canonical)
end

--- The stored clothing for a character, online or not. Coroutine only when offline.
---@param identifier Player|Source|CitizenId
---@return Result  ok value is a record, false for none stored, or nil when it could not be read
function OPX.GetClothing(identifier)
  local player = OPX.ResolvePlayer(identifier)
  if player then return Result.ok(player.PlayerData.clothing) end
  if type(identifier) ~= "string" then
    return Result.err("error.notLoggedIn", tostring(identifier))
  end
  return fetch(identifier)
end

--- What `opx77_appearance` sends when what the player wears has changed. The row written is the
--- connection's character; the citizen id in the payload only refuses a save that was captured
--- for the character before it.
RegisterNetEvent(OPX.Events.Server.SAVE_CLOTHING, function(payload)
  local src = tonumber(source)
  if not src then return end
  local operation = OPX.Operations.SAVE_CLOTHING
  if type(payload) ~= "table" then
    return OPX.Refuse(src, "error.badRequest", operation)
  end
  if OPX.Cooling(src, "clothing.request", COOLDOWN_MS) then
    return OPX.Refuse(src, "error.tooFast", operation)
  end

  local player = OPX.GetPlayer(src)
  if not player then return OPX.Refuse(src, "error.notLoggedIn", operation) end
  if payload.citizenId ~= player.PlayerData.citizenId then
    return OPX.Refuse(src, "clothing.stale", operation)
  end

  CreateThread(function()
    local saved = OPX.SaveClothing(player, payload.clothing)
    if not saved.ok then
      Open77.log.warn(("[clothing] %d: clothing not saved: %s (%s)")
        :format(src, tostring(saved.error), tostring(saved.detail)))
      OPX.Refuse(src, saved.error, operation)
    end
  end)
end)
