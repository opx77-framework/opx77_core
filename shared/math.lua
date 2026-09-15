--- @author DemiAutomatic
--- @file shared/math.lua
--- @description Numeric helpers: clamp, finiteness, distance and digit grouping.

OPX.Math = {}

--- @author DemiAutomatic
--- @method OPX.Math.clamp
--- @description Holds a number between a low and a high bound.
--- @param value {number}
--- @param low {number}
--- @param high {number}
--- @returns {number}
function OPX.Math.clamp(value, low, high)
	if value < low then return low end
	if value > high then return high end
	return value
end

--- @author DemiAutomatic
--- @method OPX.Math.isFinite
--- @description True only for a real number that is neither NaN nor infinite.
--- @param value {any}
--- @returns {boolean}
function OPX.Math.isFinite(value)
	return type(value) == 'number'
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
end

--- @author DemiAutomatic
--- @method OPX.Math.distanceSquared
--- @description Squared distance between two points, for within-range tests.
--- @param a {Vector3Like}
--- @param b {Vector3Like}
--- @returns {number}
function OPX.Math.distanceSquared(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
	return dx * dx + dy * dy + dz * dz
end

--- @author DemiAutomatic
--- @method OPX.Math.groupDigits
--- @description Groups a whole amount's digits by thousands for display.
--- @param value {number}
--- @param separator {string|nil} A space when omitted.
--- @returns {string}
function OPX.Math.groupDigits(value, separator)
	separator = separator or ' '
	local whole = tostring(math.floor(math.abs(value)))
	local grouped = whole:reverse():gsub('(%d%d%d)', '%1' .. separator):reverse()
	grouped = grouped:gsub('^' .. separator:gsub('%p', '%%%0'), '')
	return (value < 0 and '-' or '') .. grouped
end
