---@meta

--- The live proxy `Open77.tunables.declare` answers for the core's tunables. Read
--- `OPX.Tune.KEY` at the point of use, never into a file-scope local.
---@type table<string, any>
OPX.Tune = {}

--- Re-reads a tunable as a finite number with a floor; `floor` is also the answer for a value
--- that is not a finite number.
---@param key string
---@param floor number
---@return number
function OPX.TuneNumber(key, floor) end
