--- The character's face: validation, the write, and the broadcast. `opx77_appearance` is a
--- client resource that captures a snapshot and sends it here; nothing else may write it.

local Result = OPX.Result

local Config = OPX.Config.SHARED.APPEARANCE

local Appearance = {}
OPX.Appearance = Appearance

--- The schema version written into every stored snapshot.
Appearance.VERSION = 1

--- The three parts the engine's catalogue is divided into.
local PARTS = { head = true, body = true, arms = true }

--- An option index, and the ceiling on the number of options in one snapshot.
local MAX_CHOICES = 512
local MAX_OPTIONS = 256

--- A whole number, never `tonumber("3")`: an option index arriving as a string is a client
--- that has stopped speaking this file's language.
---@param value any
---@return boolean
local function isInteger(value)
  return type(value) == "number" and OPX.Math.isFinite(value) and value % 1 == 0
end

--- A 64-bit engine identifier as the platform renders one: "0x" and sixteen hex digits,
--- compared lower-cased and never through `tonumber`, which a 64-bit hash does not survive.
---@param value any
---@param allowZero boolean the body family hash may be zero; an option name may not
---@return boolean
local function isHash(value, allowZero)
  if type(value) ~= "string" or #value ~= 18 then return false end
  if value:sub(1, 2) ~= "0x" or value:sub(3):match("^%x+$") == nil then return false end
  return allowZero or value ~= "0x0000000000000000"
end

--- The catalogue fingerprint: a SHA-256 digest, lower-cased, or nil.
---@param value any
---@return string|nil
local function digest(value)
  if type(value) ~= "string" then return nil end
  local lowered = value:lower()
  if #lowered ~= 64 or lowered:match("^%x+$") == nil then return nil end
  return lowered
end

--- Whether a game build is one the core will read a stored face back into.
---@param value any
---@return boolean
function Appearance.buildAccepted(value)
  return type(value) == "string" and Config.GAME_BUILDS[value] == true
end

--- A snapshot in canonical form -- dense options, lower-cased names, every field the type
--- the column expects -- or nil and the code saying what was wrong with it.
---@param value any
---@return AppearanceSnapshot|nil canonical, string|nil error
function Appearance.canonical(value)
  if type(value) ~= "table" then return nil, "invalid_snapshot" end
  if value.schemaVersion ~= Appearance.VERSION then return nil, "unsupported_schema" end
  if not Appearance.buildAccepted(value.gameBuild) then
    return nil, "unsupported_game_build"
  end

  local catalog = digest(value.catalogDigest)
  if catalog == nil then return nil, "invalid_catalog_digest" end

  -- the engine's own body-family hash, opaque and allowed to be zero: not the
  -- "female"/"male" string, which is `charInfo.gender` and lives on the character row
  if not isHash(value.gender, true) then return nil, "invalid_gender" end

  if type(value.options) ~= "table" then return nil, "invalid_options" end
  local count = #value.options
  if count < 1 or count > MAX_OPTIONS then return nil, "invalid_option_count" end

  local canonical = {
    schemaVersion = Appearance.VERSION,
    gameBuild = value.gameBuild,
    catalogDigest = catalog,
    gender = value.gender,
    options = {},
  }

  local seen = {}
  for index = 1, count do
    local option = value.options[index]
    if type(option) ~= "table" then return nil, "invalid_option" end
    if not PARTS[option.part] then return nil, "invalid_option_part" end
    if not isHash(option.name, false) then return nil, "invalid_option_name" end
    if not isInteger(option.value) or option.value < 0 or option.value >= MAX_CHOICES then
      return nil, "invalid_option_value"
    end
    if not isInteger(option.choices) or option.choices < 0 or option.choices > MAX_CHOICES then
      return nil, "invalid_option_choices"
    end
    -- `choices = 0` is a catalogue entry with nothing to choose from, which the engine does
    -- report; it is the one case where the index cannot be bounded by it
    if option.choices > 0 and option.value >= option.choices then
      return nil, "option_out_of_range"
    end
    local key = option.part .. ":" .. option.name:lower()
    if seen[key] then return nil, "duplicate_option" end
    seen[key] = true
    canonical.options[index] = {
      part = option.part,
      name = option.name:lower(),
      value = option.value,
      choices = option.choices,
    }
  end

  -- `#value.options` stops at the first hole, so everything above has only proved the PREFIX
  -- is well formed
  for key in pairs(value.options) do
    if type(key) == "number" and (not isInteger(key) or key < 1 or key > count) then
      return nil, "sparse_options"
    end
  end

  return canonical
end

--- Whether two canonical snapshots are the same face, for skipping a write that would change
--- nothing.
---@param left AppearanceSnapshot|nil
---@param right AppearanceSnapshot|nil
---@return boolean
function Appearance.same(left, right)
  if type(left) ~= "table" or type(right) ~= "table" then return false end
  if left.gameBuild ~= right.gameBuild or left.catalogDigest ~= right.catalogDigest then
    return false
  end
  if left.gender ~= right.gender then return false end
  local count = #left.options
  if count ~= #right.options then return false end
  for index = 1, count do
    local a, b = left.options[index], right.options[index]
    if a.part ~= b.part or a.name ~= b.name or a.value ~= b.value then return false end
  end
  return true
end

--- Validates a captured snapshot, writes it to `opx77_characters.appearance` and puts it on
--- `PlayerData.appearance`. Coroutine only.
---@param identifier Player|Source|CitizenId
---@param snapshot any straight off the wire
---@return Result  ok value is the canonical snapshot
function OPX.SaveAppearance(identifier, snapshot)
  local player = OPX.ResolvePlayer(identifier)
  if not player then return Result.err("error.notLoggedIn", tostring(identifier)) end

  local canonical, reason = Appearance.canonical(snapshot)
  if not canonical then return Result.err("appearance.invalid", reason) end

  local encoded = json.encode(canonical)
  if #encoded > Config.MAX_JSON_BYTES then
    return Result.err("appearance.tooLarge", tostring(#encoded))
  end

  local data = player.PlayerData
  if Appearance.same(data.appearance, canonical) then return Result.ok(data.appearance) end

  local written = OPX.Storage.Players.saveAppearance(data.citizenId, canonical)
  if not written.ok then return written end

  data.appearance = canonical
  player.Functions.UpdatePlayerData()

  if not player.Offline then
    TriggerClientEvent(OPX.Events.Client.APPEARANCE_UPDATE, data.source, canonical)
  end
  TriggerEvent(OPX.Events.Internal.APPEARANCE_CHANGE, data.source, data.citizenId, canonical)

  OPX.Logger.player(player, "appearance.saved", canonical.gameBuild,
    { options = #canonical.options })
  return Result.ok(canonical)
end

--- The stored face for a character, online or not. Coroutine only when offline.
---@param identifier Player|Source|CitizenId
---@return Result  ok value is an AppearanceSnapshot, or nil for a character with no face
function OPX.GetAppearance(identifier)
  local player = OPX.ResolvePlayer(identifier)
  if player then return Result.ok(player.PlayerData.appearance) end
  if type(identifier) ~= "string" then
    return Result.err("error.notLoggedIn", tostring(identifier))
  end

  local fetched = OPX.Storage.Players.fetchOne(identifier)
  if not fetched.ok then return fetched end
  return Result.ok(fetched.value.appearance)
end

--- What `opx77_appearance` sends after the player commits a face. The character comes from
--- the connection and never from the payload.
RegisterNetEvent(OPX.Events.Server.SAVE_APPEARANCE, function(payload)
  local src = tonumber(source)
  if not src then return end
  local operation = OPX.Operations.SAVE_APPEARANCE
  if type(payload) ~= "table" then
    return OPX.Refuse(src, "error.badRequest", operation)
  end
  if OPX.Cooling(src, "appearance.request", 2000) then
    return OPX.Refuse(src, "error.tooFast", operation)
  end

  local snapshot = payload.snapshot or payload
  CreateThread(function()
    local saved = OPX.SaveAppearance(src, snapshot)
    if not saved.ok then
      Open77.log.warn(("[appearance] %d sent an unusable face: %s (%s)")
        :format(src, tostring(saved.error), tostring(saved.detail)))
      OPX.Refuse(src, saved.error, operation)
    end
  end)
end)
