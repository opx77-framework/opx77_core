--- @author DemiAutomatic
--- @file shared/validate.lua
--- @description Checks for values that cross a trust boundary.

--- @author DemiAutomatic
--- @type {table}
--- @description The Result constructors, read through a local.
local Result = OPX.Result

OPX.Validate = {}
local Validate = OPX.Validate

--- @author DemiAutomatic
--- @method OPX.Validate.text
--- @description Trims text and checks its length in characters and its pattern.
--- @param value {any}
--- @param opts {table|nil} min, max and pattern.
--- @returns {Result}
function OPX.Validate.text(value, opts)
	opts = opts or {}
	if type(value) ~= 'string' then
		return Result.err('type', 'expected string, got ' .. type(value))
	end

	local ceiling = math.min(((opts.max or 255) * 4) + 16, 1024)
	if #value > ceiling then return Result.err('too-long') end

	local trimmed = OPX.String.trim(value)
	local length = OPX.String.length(trimmed)
	if not length then return Result.err('not-utf8') end
	if length < (opts.min or 1) then return Result.err('too-short') end
	if length > (opts.max or 255) then return Result.err('too-long') end
	if opts.pattern and not trimmed:match(opts.pattern) then
		return Result.err('format')
	end
	return Result.ok(trimmed)
end

--- @author DemiAutomatic
--- @method OPX.Validate.number
--- @description Reads a finite number and checks integrality and bounds.
--- @param value {any}
--- @param opts {table|nil} integer, min and max.
--- @returns {Result}
function OPX.Validate.number(value, opts)
	opts = opts or {}
	local n = tonumber(value)
	if n == nil then
		return Result.err('type', 'expected number, got ' .. type(value))
	end
	if not OPX.Math.isFinite(n) then return Result.err('not-finite') end
	if opts.integer and n % 1 ~= 0 then return Result.err('not-integer') end
	if opts.min and n < opts.min then return Result.err('too-small') end
	if opts.max and n > opts.max then return Result.err('too-large') end
	return Result.ok(n)
end

--- @author DemiAutomatic
--- @method OPX.Validate.oneOf
--- @description Accepts a value only when the allowed set holds it.
--- @param value {any}
--- @param allowed {table<any, boolean>}
--- @returns {Result}
function OPX.Validate.oneOf(value, allowed)
	if allowed[value] then return Result.ok(value) end
	return Result.err('not-allowed', tostring(value))
end
