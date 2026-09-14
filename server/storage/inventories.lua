--- Reads and writes for `opx77_inventories` and `opx77_inventory_items`. No policy here:
--- server/exports.lua validates, and opx77_inventory decides what goes in a container.
--- Everything returns a Result and yields: coroutine only.

local Result = OPX.Result
local Storage = OPX.Storage

local Inventories = {}
OPX.Storage.Inventories = Inventories

--- Rows one INSERT carries inside a save. A container's rows go in several statements of the
--- same transaction past it, which keeps each statement's parameter list short.
local ROWS_PER_INSERT = 50

--- Accepts a string or an already-decoded table, because a bridge build may do either. A
--- metadata cell that fails to decode is absent rather than fatal: the stack still loads.
---@param value any
---@return table|nil
local function decode(value)
  if type(value) == "table" then return value end
  if type(value) ~= "string" or value == "" then return nil end
  local ok, decoded = pcall(json.decode, value)
  if not ok or type(decoded) ~= "table" then return nil end
  return decoded
end

---@param row table|nil
---@return table|nil
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

--- Whether a living character carries this citizen id. A soft-deleted one does not: its bag
--- stays in the table, and nobody opens it.
---@param citizenId CitizenId
---@return Result  ok value is a boolean
function Inventories.characterExists(citizenId)
  local row = Storage.single([[
SELECT 1 AS found FROM opx77_characters
 WHERE citizen_id = @citizen AND deleted_at IS NULL
 LIMIT 1
  ]], { citizen = citizenId })
  if not row.ok then return row end
  return Result.ok(row.value ~= nil)
end

---@param plate string
---@return Result  ok value is a boolean
function Inventories.vehicleExists(plate)
  local row = Storage.single(
    "SELECT 1 AS found FROM opx77_vehicles WHERE plate = @plate LIMIT 1", { plate = plate })
  if not row.ok then return row end
  return Result.ok(row.value ~= nil)
end

--- Finds or creates one container. The unique key on (kind, owner) decides a race between two
--- creators, not a SELECT beforehand, and the size given is only used by the one that creates.
---@param entity InventoryEntity
---@return Result  ok value is { header, created }
function Inventories.ensure(entity)
  local inserted = Storage.update([[
INSERT IGNORE INTO opx77_inventories (kind, owner, citizen_id, plate, slots, max_weight)
VALUES (@kind, @owner, NULLIF(@citizen, ''), NULLIF(@plate, ''), @slots, @maxWeight)
  ]], {
    kind = entity.kind,
    owner = entity.owner,
    citizen = entity.citizenId or "",
    plate = entity.plate or "",
    slots = entity.slots,
    maxWeight = entity.maxWeight,
  })
  if not inserted.ok then return inserted end

  local affected = inserted.value
  if type(affected) == "table" then affected = affected.affectedRows end

  local row = Storage.single([[
SELECT id, kind, owner, slots, max_weight FROM opx77_inventories
 WHERE kind = @kind AND owner = @owner
 LIMIT 1
  ]], { kind = entity.kind, owner = entity.owner })
  if not row.ok then return row end
  if not row.value then return Result.err("inventory.noOwner", entity.owner) end
  return Result.ok({ header = toHeader(row.value), created = tonumber(affected) == 1 })
end

---@param id integer
---@return Result  ok value is a header, or nil
function Inventories.header(id)
  local row = Storage.single([[
SELECT id, kind, owner, slots, max_weight FROM opx77_inventories
 WHERE id = @id
 LIMIT 1
  ]], { id = id })
  if not row.ok then return row end
  return Result.ok(toHeader(row.value))
end

--- One page of a container's stacks, in slot order, after `after`. Paged by slot rather than
--- by offset, so a save landing between two pages cannot shift a stack out of both.
---@param id integer
---@param after integer
---@param limit integer  a constant of the caller's, formatted into the statement
---@return Result  ok value is a list of { slot, name, count, metadata }
function Inventories.contents(id, after, limit)
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
      metadata = decode(row.metadata),
    }
  end
  return Result.ok(out)
end

--- Rewrites every listed container's rows as one unit: a delete, the inserts, and the stamp.
--- Positional parameters, unlike the rest of this file: a transaction statement is bound the
--- way the platform's own resources bind one, and the count of `?` is checked against the
--- values before anything is sent.
---@param containers { id: integer, rows: InventoryStack[] }[]
---@return Result
function Inventories.save(containers)
  local statements = {}
  for c = 1, #containers do
    local container = containers[c]
    statements[#statements + 1] = {
      query = "DELETE FROM opx77_inventory_items WHERE inventory_id = ?",
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
        -- absence travels as "" and NULLIF turns it back into NULL: encoded JSON is never empty
        values[#values + 1] = row.metadata ~= nil and json.encode(row.metadata) or ""
      end
      statements[#statements + 1] = {
        query = "INSERT INTO opx77_inventory_items (inventory_id, slot, name, quantity, " ..
          "metadata) VALUES " .. table.concat(placeholders, ", "),
        values = values,
      }
    end

    statements[#statements + 1] = {
      query = "UPDATE opx77_inventories SET updated_at = CURRENT_TIMESTAMP WHERE id = ?",
      values = { container.id },
    }
  end
  return Storage.transaction(statements)
end

---@param id integer
---@param slots integer
---@param maxWeight integer
---@return Result
function Inventories.resize(id, slots, maxWeight)
  return Storage.execute(
    "UPDATE opx77_inventories SET slots = @slots, max_weight = @maxWeight WHERE id = @id",
    { id = id, slots = slots, maxWeight = maxWeight })
end

--- Deletes a container; its stacks go with it by cascade.
---@param id integer
---@return Result
function Inventories.delete(id)
  return Storage.execute("DELETE FROM opx77_inventories WHERE id = @id", { id = id })
end

--- Every container holding an item, the largest stacks first.
---@param name string
---@param limit integer  a constant of the caller's, formatted into the statement
---@return Result  ok value is a list of { id, kind, owner, slot, count }
function Inventories.holders(name, limit)
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
