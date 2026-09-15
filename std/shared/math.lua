---@meta

--- Numeric helpers.
OPX.Math = {}

--- Holds `value` between `low` and `high`.
---@param value number
---@param low number
---@param high number
---@return number
function OPX.Math.clamp(value, low, high) end

--- True only for a real, finite number. NaN arrives through JSON from a client and passes every
--- comparison.
---@param value any
---@return boolean
function OPX.Math.isFinite(value) end

--- Squared distance, for every "is it within N" test.
---@param a Vector3Like
---@param b Vector3Like
---@return number
function OPX.Math.distanceSquared(a, b) end

--- Thousands separator, for money shown to a player.
---@param value number
---@param separator? string defaults to a space
---@return string
function OPX.Math.groupDigits(value, separator) end
