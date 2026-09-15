---@meta

--- Checks for values crossing a trust boundary.
OPX.Validate = {}

--- Trims, then enforces length (in characters) and an optional pattern. Malformed UTF-8 is
--- refused rather than measured.
---@param value any
---@param opts? { min?: integer, max?: integer, pattern?: string }
---@return Result
function OPX.Validate.text(value, opts) end

--- A finite number, optionally whole and bounded.
---@param value any
---@param opts? { integer?: boolean, min?: number, max?: number }
---@return Result
function OPX.Validate.number(value, opts) end

--- A value the allowed set holds.
---@param value any
---@param allowed table<any, boolean>
---@return Result
function OPX.Validate.oneOf(value, allowed) end
