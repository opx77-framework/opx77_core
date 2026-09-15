---@meta

OPX.Vehicles = {}

--- Gives a character a vehicle, stored in its garage under a fresh plate drawn from
--- `PLATE_FORMAT`, within `PER_CHARACTER`. Coroutine only.
---@param citizenId string
---@param record string a TweakDB record, e.g. "Vehicle.v_standard2_archer_hella_player"
---@param options? { garage?: string, appearance?: string, paint?: table, metadata?: table }
---@return Result ok value is the stored vehicle
function OPX.Vehicles.Give(citizenId, record, options) end

--- Every vehicle a character owns. Coroutine only.
---@param citizenId string
---@return Result ok value is a list of vehicle entities
function OPX.Vehicles.List(citizenId) end

--- Which owned vehicle a runtime id is, when the core spawned it. A vehicle another resource
--- created answers nil.
---@param vehicleId integer
---@return string|nil plate
---@return string|nil citizenId
function OPX.Vehicles.PlateOf(vehicleId) end

--- The stored row of a vehicle, plus `id` and `spawned` when it is out now. Coroutine only.
---@param plateId string
---@return Result
function OPX.Vehicles.Get(plateId) end

--- Spawns a loaded character's own vehicle beside them, ownership checked against the
--- connection's character. Coroutine only.
---@param source Source
---@param plateId string
---@return Result ok value is { plate, id }
function OPX.Vehicles.Spawn(source, plateId) end

--- Takes a spawned vehicle off the world and writes its condition. Coroutine only.
---@param plateId string
---@param garage? string where it belongs now; omitted keeps the one it had
---@return Result ok value is { plate }
function OPX.Vehicles.Store(plateId, garage) end

--- Stores every spawned vehicle of one character, or every one when nil. Coroutine only.
---@param citizenId string|nil
---@return integer stored
function OPX.Vehicles.StoreAll(citizenId) end
