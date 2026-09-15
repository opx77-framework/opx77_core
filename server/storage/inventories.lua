--- @author DemiAutomatic
--- @file server/storage/inventories.lua
--- @description Reads and writes for the container and item stack tables.

--- @author DemiAutomatic
--- @type {table}
--- @description The Result constructors every statement answers with.
local Result = OPX.Result

--- @author DemiAutomatic
--- @type {table}
--- @description The database access every statement runs through.
local Storage = OPX.Storage

OPX.Storage.Inventories = {}

--- @author DemiAutomatic
--- @type {integer}
--- @description Item rows one insert statement carries inside a save.
local ROWS_PER_INSERT = 50

--- @author DemiAutomatic
--- @method toHeader
--- @description Turns a container row into its header shape.
--- @param row {table|nil}
--- @returns {InventoryHeader|nil}
local function toHeader(row)
	if not row then return nil end
	return {
		id = tonumber(row.id),
		kind = row.kind,
		owner = row.owner,
		slots = tonumber(row.slots),
		maxWeight = tonumber(row.max_weight),
	}
end

--- @author DemiAutomatic
--- @method OPX.Storage.Inventories.characterExists
--- @description Answers whether a living character carries this citizen id.
--- @param citizenId {CitizenId}
--- @returns {Result}
function OPX.Storage.Inventories.characterExists(citizenId)
	local row = Storage.single([[
SELECT 1 AS found FROM opx77_characters
 WHERE citizen_id = @citizen AND deleted_at IS NULL
 LIMIT 1
  ]], { citizen = citizenId })
	if not row.ok then return row end
	return Result.ok(row.value ~= nil)
end

--- @author DemiAutomatic
--- @method OPX.Storage.Inventories.vehicleExists
--- @description Answers whether an owned vehicle carries this plate.
--- @param plate {string}
--- @returns {Result}
function OPX.Storage.Inventories.vehicleExists(plate)
	local row = Storage.single(
		'SELECT 1 AS found FROM opx77_vehicles WHERE plate = @plate LIMIT 1', { plate = plate })
	if not row.ok then return row end
	return Result.ok(row.value ~= nil)
end

--- @author DemiAutomatic
--- @method OPX.Storage.Inventories.ensure
--- @description Finds or creates one container keyed on kind and owner.
--- @param entity {InventoryEntity}
--- @returns {Result}
function OPX.Storage.Inventories.ensure(entity)
	local inserted = Storage.update([[
INSERT IGNORE INTO opx77_inventories (kind, owner, citizen_id, plate, slots, max_weight)
VALUES (@kind, @owner, NULLIF(@citizen, ''), NULLIF(@plate, ''), @slots, @maxWeight)
  ]], {
		kind = entity.kind,
		owner = entity.owner,
		citizen = entity.citizenId or '',
		plate = entity.plate or '',
		slots = entity.slots,
		maxWeight = entity.maxWeight,
	})
	if not inserted.ok then return inserted end

	local affected = inserted.value
	if type(affected) == 'table' then affected = affected.affectedRows end

	local row = Storage.single([[
SELECT id, kind, owner, slots, max_weight FROM opx77_inventories
 WHERE kind = @kind AND owner = @owner
 LIMIT 1
  ]], { kind = entity.kind, owner = entity.owner })
	if not row.ok then return row end
	if not row.value then return Result.err('inventory.noOwner', entity.owner) end
	return Result.ok({ header = toHeader(row.value), created = tonumber(affected) == 1 })
end

--- @author DemiAutomatic
--- @method OPX.Storage.Inventories.header
--- @description Reads one container's header by id, or nil.
--- @param id {integer}
--- @returns {Result}
function OPX.Storage.Inventories.header(id)
	local row = Storage.single([[
SELECT id, kind, owner, slots, max_weight FROM opx77_inventories
 WHERE id = @id
 LIMIT 1
  ]], { id = id })
	if not row.ok then return row end
	return Result.ok(toHeader(row.value))
end

--- @author DemiAutomatic
--- @method OPX.Storage.Inventories.contents
--- @description Reads one page of a container's stacks after a slot.
--- @param id {integer}
--- @param after {integer}
--- @param limit {integer} A caller constant formatted into the statement.
--- @returns {Result}
function OPX.Storage.Inventories.contents(id, after, limit)
	local rows = Storage.query(([[
SELECT slot, name, quantity, metadata FROM opx77_inventory_items
 WHERE inventory_id = @id AND slot > @after
 ORDER BY slot
 LIMIT %d
  ]]):format(math.floor(limit)), { id = id, after = after })
	if not rows.ok then return rows end

	local list = rows.value or {}
	local out = {}
	for i = 1, #list do
		local row = list[i]
		out[i] = {
			slot = tonumber(row.slot),
			name = row.name,
			count = tonumber(row.quantity),
			metadata = Storage.Decode(row.metadata),
		}
	end
	return Result.ok(out)
end

--- @author DemiAutomatic
--- @method OPX.Storage.Inventories.save
--- @description Rewrites every listed container's stacks in one transaction.
--- @param containers {table[]}
--- @returns {Result}
function OPX.Storage.Inventories.save(containers)
	local statements = {}
	for c = 1, #containers do
		local container = containers[c]
		statements[#statements + 1] = {
			query = 'DELETE FROM opx77_inventory_items WHERE inventory_id = ?',
			values = { container.id },
		}

		local rows = container.rows
		for first = 1, #rows, ROWS_PER_INSERT do
			local placeholders, values = {}, {}
			for r = first, math.min(first + ROWS_PER_INSERT - 1, #rows) do
				local row = rows[r]
				placeholders[#placeholders + 1] = "(?, ?, ?, ?, NULLIF(?, ''))"
				values[#values + 1] = container.id
				values[#values + 1] = row.slot
				values[#values + 1] = row.name
				values[#values + 1] = row.count
					values[#values + 1] = Storage.Nullable(row.metadata)
			end
			statements[#statements + 1] = {
				query = 'INSERT INTO opx77_inventory_items (inventory_id, slot, name, quantity, ' ..
					'metadata) VALUES ' .. table.concat(placeholders, ', '),
				values = values,
			}
		end

		statements[#statements + 1] = {
			query = 'UPDATE opx77_inventories SET updated_at = CURRENT_TIMESTAMP WHERE id = ?',
			values = { container.id },
		}
	end
	return Storage.transaction(statements)
end

--- @author DemiAutomatic
--- @method OPX.Storage.Inventories.resize
--- @description Writes a container's slot count and weight limit.
--- @param id {integer}
--- @param slots {integer}
--- @param maxWeight {integer}
--- @returns {Result}
function OPX.Storage.Inventories.resize(id, slots, maxWeight)
	return Storage.execute(
		'UPDATE opx77_inventories SET slots = @slots, max_weight = @maxWeight WHERE id = @id',
		{ id = id, slots = slots, maxWeight = maxWeight })
end

--- @author DemiAutomatic
--- @method OPX.Storage.Inventories.delete
--- @description Deletes a container, its stacks going by cascade.
--- @param id {integer}
--- @returns {Result}
function OPX.Storage.Inventories.delete(id)
	return Storage.execute('DELETE FROM opx77_inventories WHERE id = @id', { id = id })
end

--- @author DemiAutomatic
--- @method OPX.Storage.Inventories.holders
--- @description Lists the containers holding an item, largest stacks first.
--- @param name {string}
--- @param limit {integer} A caller constant formatted into the statement.
--- @returns {Result}
function OPX.Storage.Inventories.holders(name, limit)
	local rows = Storage.query(([[
SELECT i.id, i.kind, i.owner, it.slot, it.quantity
  FROM opx77_inventory_items it
  JOIN opx77_inventories i ON i.id = it.inventory_id
 WHERE it.name = @name
 ORDER BY it.quantity DESC
 LIMIT %d
  ]]):format(math.floor(limit)), { name = name })
	if not rows.ok then return rows end

	local list = rows.value or {}
	local out = {}
	for i = 1, #list do
		local row = list[i]
		out[i] = {
			id = tonumber(row.id),
			kind = row.kind,
			owner = row.owner,
			slot = tonumber(row.slot),
			count = tonumber(row.quantity),
		}
	end
	return Result.ok(out)
end
