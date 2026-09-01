--- The two table helpers with callers. Fourteen more lived here -- map, filter, reduce and
--- the rest -- and none was ever reached for in ten thousand lines; a helper comes back the
--- day a file needs it.

local Table = {}

--- Deep copy, cycle-safe.
---@param source any
---@param seen? table already-copied table -> its copy, so a self-referencing graph terminates
---@return any
function Table.deepCopy(source, seen)
  if type(source) ~= "table" then return source end
  seen = seen or {}
  if seen[source] then return seen[source] end

  local out = {}
  seen[source] = out
  for key, value in pairs(source) do
    out[Table.deepCopy(key, seen)] = Table.deepCopy(value, seen)
  end
  return out
end

--- Number of keys, array part included. `#` only answers for arrays.
---@param source table
---@return integer
function Table.count(source)
  local n = 0
  for _ in pairs(source) do n = n + 1 end
  return n
end

OPX.Table = Table
