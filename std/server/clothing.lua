---@meta

OPX.Clothing = {}

--- The schema version written into every stored record.
---@type integer
OPX.Clothing.VERSION = 1

--- The name of the optional migration that creates `opx77_character_clothing`.
---@type string
OPX.Clothing.MIGRATION = '0007_character_clothing'

--- A clothing record in canonical form (all nine slots stated, outfit keys "0" to "6", empty
--- outfits dropped), or nil and a code naming what was wrong with it.
---@param value any
---@return ClothingRecord|nil canonical
---@return string|nil error
function OPX.Clothing.canonical(value) end

--- Whether two canonical records are the same clothing, for skipping a write that changes
--- nothing.
---@param left ClothingRecord|false|nil
---@param right ClothingRecord|false|nil
---@return boolean
function OPX.Clothing.same(left, right) end

--- Whether the clothing table exists as far as this run knows: its migration was not skipped.
---@return boolean
function OPX.Clothing.available() end

--- What `PlayerData.clothing` starts as at login: the record, false when none is stored, or nil
--- when it could not be read. Never refuses a login. Coroutine only.
---@param citizenId CitizenId
---@return ClothingRecord|false|nil
function OPX.Clothing.load(citizenId) end

--- Validates a record, writes it to `opx77_character_clothing`, puts it on
--- `PlayerData.clothing` and publishes it. Refused while the stored row could not be read.
--- Coroutine only.
---@param identifier Player|Source|CitizenId
---@param clothing any straight off the wire
---@return Result ok value is the canonical record
function OPX.SaveClothing(identifier, clothing) end

--- The stored clothing for a character, online or not. Coroutine only when offline.
--- The ok value is a record, false for none stored, or nil when it could not be read.
--- The client half defines its own `OPX.GetClothing`; this field describes the server one.
---@type fun(identifier: Player|Source|CitizenId): Result
OPX.GetClothing = OPX.GetClothing
