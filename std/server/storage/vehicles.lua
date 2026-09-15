---@meta

--- Reads and writes for `opx77_vehicles`. No policy: server/vehicles.lua decides.
OPX.Storage.Vehicles = {}

--- Where a vehicle is: `OUT` 0, `STORED` 1, `IMPOUNDED` 2.
---@type table<string, integer>
OPX.Storage.Vehicles.STATE = {}

--- Every vehicle a character owns, oldest first.
---@param citizenId string
---@return Result
function OPX.Storage.Vehicles.fetchByOwner(citizenId) end

--- One vehicle by plate; err `vehicle.notFound`.
---@param plate string
---@return Result
function OPX.Storage.Vehicles.fetchOne(plate) end

--- Inserts a vehicle row; a plate collision fails on the unique key.
---@param entity table
---@return Result
function OPX.Storage.Vehicles.insert(entity) end

--- Writes back condition, paint, state and garage.
---@param entity table
---@return Result
function OPX.Storage.Vehicles.save(entity) end

--- Writes only the state, and the garage when one is given.
---@param plate string
---@param state integer
---@param garage string|nil
---@return Result
function OPX.Storage.Vehicles.setState(plate, state, garage) end

--- Deletes a vehicle row.
---@param plate string
---@return Result
function OPX.Storage.Vehicles.delete(plate) end

--- How many vehicles one character owns.
---@param citizenId string
---@return Result
function OPX.Storage.Vehicles.countByOwner(citizenId) end
