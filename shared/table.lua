--- @author DemiAutomatic
--- @file shared/table.lua
--- @description Table helpers: a cycle-safe deep copy and a key count.

OPX.Table = {}
local Table = OPX.Table

--- @author DemiAutomatic
--- @method OPX.Table.deepCopy
--- @description Copies a value deeply, terminating on self-referencing tables.
--- @param source {any}
--- @param seen {table|nil} Already-copied table to its copy.
--- @returns {any}
function OPX.Table.deepCopy(source, seen)
	if type(source) ~= 'table' then return source end
	seen = seen or {}
	if seen[source] then return seen[source] end

	local out = {}
	seen[source] = out
	for key, value in pairs(source) do
		out[Table.deepCopy(key, seen)] = Table.deepCopy(value, seen)
	end
	return out
end

--- @author DemiAutomatic
--- @method OPX.Table.count
--- @description Counts every key of a table, array part included.
--- @param source {table}
--- @returns {integer}
function OPX.Table.count(source)
	local n = 0
	for _ in pairs(source) do n = n + 1 end
	return n
end
