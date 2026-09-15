--- @author DemiAutomatic
--- @file server/storage/vehicles.lua
--- @description Reads and writes for the owned vehicles table.

--- @author DemiAutomatic
--- @type {table}
--- @description The Result constructors every statement answers with.
local Result = OPX.Result

--- @author DemiAutomatic
--- @type {table}
--- @description The database access every statement runs through.
local Storage = OPX.Storage

OPX.Storage.Vehicles = {}
local Vehicles = OPX.Storage.Vehicles

--- @author DemiAutomatic
--- @type {table<string, integer>}
--- @description Where a vehicle is, as stored in the state column.
Vehicles.STATE = { OUT = 0, STORED = 1, IMPOUNDED = 2 }

--- @author DemiAutomatic
--- @method toEntity
--- @description Turns a vehicle row into the entity server/vehicles.lua uses.
--- @param row {table}
--- @returns {table}
local function toEntity(row)
	local state = tonumber(row.state)
	local health = tonumber(row.health)
	return {
		plate = row.plate,
		citizenId = row.citizen_id,
		record = row.record,
		appearance = row.appearance,
		garage = row.garage,
		state = OPX.Math.isFinite(state) and state or Vehicles.STATE.STORED,
		health = OPX.Math.isFinite(health) and health or 1.0,
		damage = row.body and json.decode(row.body) or nil,
		paint = row.paint and json.decode(row.paint) or nil,
		metadata = row.metadata and json.decode(row.metadata) or {},
	}
end

--- @author DemiAutomatic
--- @method OPX.Storage.Vehicles.fetchByOwner
--- @description Lists every vehicle a character owns, oldest first.
--- @param citizenId {string}
--- @returns {Result}
function OPX.Storage.Vehicles.fetchByOwner(citizenId)
	local rows = Storage.query([[
SELECT plate, citizen_id, record, appearance, garage, state, health, body, paint, metadata
  FROM opx77_vehicles
 WHERE citizen_id = @citizen
 ORDER BY created_at
  ]], { citizen = citizenId })
	if not rows.ok then return rows end
	local fetched = rows.value
	local list = {}
	for index = 1, type(fetched) == 'table' and #fetched or 0 do
		list[index] = toEntity(fetched[index])
	end
	return Result.ok(list)
end

--- @author DemiAutomatic
--- @method OPX.Storage.Vehicles.fetchOne
--- @description Reads one vehicle by its plate.
--- @param plate {string}
--- @returns {Result}
function OPX.Storage.Vehicles.fetchOne(plate)
	local row = Storage.single([[
SELECT plate, citizen_id, record, appearance, garage, state, health, body, paint, metadata
  FROM opx77_vehicles
 WHERE plate = @plate
 LIMIT 1
  ]], { plate = plate })
	if not row.ok then return row end
	if not row.value then return Result.err('vehicle.notFound', plate) end
	return Result.ok(toEntity(row.value))
end

--- @author DemiAutomatic
--- @method OPX.Storage.Vehicles.insert
--- @description Inserts a vehicle row, the plate key deciding a collision.
--- @param entity {table}
--- @returns {Result}
function OPX.Storage.Vehicles.insert(entity)
	return Storage.execute([[
INSERT INTO opx77_vehicles (plate, citizen_id, record, appearance, garage, state, health,
                            body, paint, metadata)
VALUES (@plate, @citizen, @record, NULLIF(@appearance, ''), @garage, @state, @health,
        NULLIF(@body, ''), NULLIF(@paint, ''), @metadata)
  ]], {
		plate = entity.plate,
		citizen = entity.citizenId,
		record = entity.record,
		appearance = entity.appearance ~= nil and tostring(entity.appearance) or '',
		garage = entity.garage,
		state = entity.state,
		health = entity.health,
		body = Storage.Nullable(entity.damage),
		paint = Storage.Nullable(entity.paint),
		metadata = json.encode(entity.metadata or {}),
	})
end

--- @author DemiAutomatic
--- @method OPX.Storage.Vehicles.save
--- @description Writes back a vehicle's condition, paint, state and garage.
--- @param entity {table}
--- @returns {Result}
function OPX.Storage.Vehicles.save(entity)
	return Storage.execute([[
UPDATE opx77_vehicles
   SET garage = @garage, state = @state, health = @health, body = NULLIF(@body, ''),
       paint = NULLIF(@paint, ''), metadata = @metadata
 WHERE plate = @plate
  ]], {
		plate = entity.plate,
		garage = entity.garage,
		state = entity.state,
		health = entity.health,
		body = Storage.Nullable(entity.damage),
		paint = Storage.Nullable(entity.paint),
		metadata = json.encode(entity.metadata or {}),
	})
end

--- @author DemiAutomatic
--- @method OPX.Storage.Vehicles.setState
--- @description Writes only a vehicle's state, and its garage when given.
--- @param plate {string}
--- @param state {integer}
--- @param garage {string|nil}
--- @returns {Result}
function OPX.Storage.Vehicles.setState(plate, state, garage)
	if garage == nil then
		return Storage.execute(
			'UPDATE opx77_vehicles SET state = @state WHERE plate = @plate',
			{ plate = plate, state = state })
	end
	return Storage.execute(
		'UPDATE opx77_vehicles SET state = @state, garage = @garage WHERE plate = @plate',
		{ plate = plate, state = state, garage = garage })
end

--- @author DemiAutomatic
--- @method OPX.Storage.Vehicles.delete
--- @description Deletes a vehicle row by its plate.
--- @param plate {string}
--- @returns {Result}
function OPX.Storage.Vehicles.delete(plate)
	return Storage.execute('DELETE FROM opx77_vehicles WHERE plate = @plate', { plate = plate })
end

--- @author DemiAutomatic
--- @method OPX.Storage.Vehicles.countByOwner
--- @description Counts the vehicles one character owns.
--- @param citizenId {string}
--- @returns {Result}
function OPX.Storage.Vehicles.countByOwner(citizenId)
	local row = Storage.single(
		'SELECT COUNT(*) AS total FROM opx77_vehicles WHERE citizen_id = @citizen',
		{ citizen = citizenId })
	if not row.ok then return row end
	return Result.ok(tonumber(row.value and row.value.total) or 0)
end
