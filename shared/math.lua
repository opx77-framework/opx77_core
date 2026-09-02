--- Numeric helpers.

local Math = {}

---@param value number
---@param low number
---@param high number
---@return number
function Math.clamp(value, low, high)
  if value < low then return low end
  if value > high then return high end
  return value
end

--- True only for a real, finite number. NaN arrives through JSON from a client, passes every
--- comparison, and poisons any sum it lands in.
---@param value any
---@return boolean
function Math.isFinite(value)
  return type(value) == "number"
    and value == value
    and value ~= math.huge
    and value ~= -math.huge
end

--- Use this for every "is it within N" test: same question, no square root.
---@param a Vector3Like
---@param b Vector3Like
---@return number
function Math.distanceSquared(a, b)
  local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
  return dx * dx + dy * dy + dz * dz
end

--- Thousands separator, for money shown to a player.
---@param value number
---@param separator? string defaults to a space
---@return string
function Math.groupDigits(value, separator)
  separator = separator or " "
  local whole = tostring(math.floor(math.abs(value)))
  local grouped = whole:reverse():gsub("(%d%d%d)", "%1" .. separator):reverse()
  grouped = grouped:gsub("^" .. separator:gsub("%p", "%%%0"), "")
  return (value < 0 and "-" or "") .. grouped
end

OPX.Math = Math
