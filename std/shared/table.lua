---@meta

--- Table helpers.
OPX.Table = {}

--- Deep copy, cycle-safe.
---@param source any
---@param seen? table already-copied table -> its copy, so a self-referencing graph terminates
---@return any
function OPX.Table.deepCopy(source, seen) end

--- Number of keys, array part included. `#` only answers for arrays.
---@param source table
---@return integer
function OPX.Table.count(source) end
