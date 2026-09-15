--- Reads and writes for `opx77_vehicles`. No policy here: server/vehicles.lua decides.

local Result = OPX.Result
local Storage = OPX.Storage

OPX.Storage.Vehicles = {}
local Vehicles = OPX.Storage.Vehicles

--- Where a vehicle is, as a number rather than a string: the column is a TINYINT and a
--- gamemode adds its own states without a migration.
Vehicles.STATE = { OUT = 0, STORED = 1, IMPOUNDED = 2 }

--- A nullable column's parameter. The bridge drops a nil parameter rather than binding NULL,
--- and MySqlConnector then refuses the statement, so absence travels as "" and the statement
--- turns it back into NULL with NULLIF: neither encoded JSON nor an appearance name is empty.
---@param value any
---@param encoded boolean  whether the column holds JSON
---@return string
local function nullable(value, encoded)
	if value == nil then return '' end
	return encoded and json.encode(value) or tostring(value)
end

---@param row table
---@return table
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
		-- the `body` column carries the whole damage view: body, glass, lights, tires,
		-- detachedParts
		damage = row.body and json.decode(row.body) or nil,
		paint = row.paint and json.decode(row.paint) or nil,
		metadata = row.metadata and json.decode(row.metadata) or {},
	}
end

---@param citizenId string
---@return table result  Result of a list of vehicle entities
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

---@param plate string
---@return table result  Result of one vehicle entity
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

--- Creates one. The unique key on `plate` decides a collision, not a SELECT beforehand.
---@param entity table
---@return table result
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
		appearance = nullable(entity.appearance, false),
		garage = entity.garage,
		state = entity.state,
		health = entity.health,
		body = nullable(entity.damage, true),
		paint = nullable(entity.paint, true),
		metadata = json.encode(entity.metadata or {}),
	})
end

--- Writes back what changes while a vehicle is out: condition, paint, and where it belongs.
---@param entity table
---@return table result
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
		body = nullable(entity.damage, true),
		paint = nullable(entity.paint, true),
		metadata = json.encode(entity.metadata or {}),
	})
end

--- One column, so a state change does not carry a stale copy of everything else.
---@param plate string
---@param state integer
---@param garage string|nil
---@return table result
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

---@param plate string
---@return table result
function OPX.Storage.Vehicles.delete(plate)
	return Storage.execute('DELETE FROM opx77_vehicles WHERE plate = @plate', { plate = plate })
end

--- How many one character owns, for the per-character ceiling.
---@param citizenId string
---@return table result  Result of an integer
function OPX.Storage.Vehicles.countByOwner(citizenId)
	local row = Storage.single(
		'SELECT COUNT(*) AS total FROM opx77_vehicles WHERE citizen_id = @citizen',
		{ citizen = citizenId })
	if not row.ok then return row end
	return Result.ok(tonumber(row.value and row.value.total) or 0)
end
