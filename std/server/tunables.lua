---@meta

--- The live values declared to `Open77.tunables`, or the config/server.lua values on a host
--- without tunables. Read `OPX.Tune.KEY` at the point of use, never into a file-scope local.
---@type table<string, any>
OPX.Tune = {}

--- Re-reads a tunable as a finite number with a floor. A non-finite value falls back to the
--- declared default, then to `floor`, which is also the answer for an undeclared key.
---@param key string
---@param floor number
---@return number
function OPX.TuneNumber(key, floor) end
