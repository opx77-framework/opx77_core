---@meta

--- Reads and writes for `opx77_inventories` and `opx77_inventory_items`. No policy:
--- server/exports.lua validates and opx77_inventory decides. Everything yields.
OPX.Storage.Inventories = {}

--- Whether a living character carries this citizen id.
---@param citizenId CitizenId
---@return Result
function OPX.Storage.Inventories.characterExists(citizenId) end

--- Whether an owned vehicle carries this plate.
---@param plate string
---@return Result
function OPX.Storage.Inventories.vehicleExists(plate) end

--- Finds or creates a container keyed on (kind, owner); the ok value is `{ header, created }`.
--- The size is used only by the call that creates it.
---@param entity InventoryEntity
---@return Result
function OPX.Storage.Inventories.ensure(entity) end

--- One container's header by id, or nil.
---@param id integer
---@return Result
function OPX.Storage.Inventories.header(id) end

--- One page of stacks after slot `after`, in slot order, as `{ slot, name, count, metadata }`.
---@param id integer
---@param after integer
---@param limit integer a caller constant formatted into the statement
---@return Result
function OPX.Storage.Inventories.contents(id, after, limit) end

--- Rewrites every listed container's stacks in one transaction.
---@param containers { id: integer, rows: InventoryStack[] }[]
---@return Result
function OPX.Storage.Inventories.save(containers) end

--- Writes a container's slot count and weight limit.
---@param id integer
---@param slots integer
---@param maxWeight integer
---@return Result
function OPX.Storage.Inventories.resize(id, slots, maxWeight) end

--- Deletes a container; its stacks go by cascade.
---@param id integer
---@return Result
function OPX.Storage.Inventories.delete(id) end

--- The containers holding an item as `{ id, kind, owner, slot, count }`, largest stacks first.
---@param name string
---@param limit integer a caller constant formatted into the statement
---@return Result
function OPX.Storage.Inventories.holders(name, limit) end
