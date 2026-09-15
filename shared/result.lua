--- @author DemiAutomatic
--- @file shared/result.lua
--- @description Success or failure as a value, never an ambiguous nil.

OPX.Result = {}

--- @author DemiAutomatic
--- @method OPX.Result.ok
--- @description Wraps a success; its value may be nil.
--- @param value {any}
--- @returns {Result}
function OPX.Result.ok(value)
	return { ok = true, value = value }
end

--- @author DemiAutomatic
--- @method OPX.Result.err
--- @description Wraps a failure with a stable code and a log-only detail.
--- @param code {string}
--- @param detail {string|nil}
--- @returns {Result}
function OPX.Result.err(code, detail)
	return { ok = false, error = code, detail = detail }
end
