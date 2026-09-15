---@meta

--- Success or failure as a value, so `nil` never means both "failed" and "found nothing".
OPX.Result = {}

--- Wraps a success. The value may be nil: an empty answer is a success.
---@param value any
---@return Result
function OPX.Result.ok(value) end

--- Wraps a failure.
---@param code string stable, meant to be branched on; doubles as a locale key
---@param detail? string for logs and staff only: it can carry a raw database exception
---@return Result
function OPX.Result.err(code, detail) end
