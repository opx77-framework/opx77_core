--- Success or failure as a value, so `nil` never means both "failed" and "found nothing".

OPX.Result = {}
local Result = OPX.Result

---@param value any
---@return Result
function OPX.Result.ok(value)
	return { ok = true, value = value }
end

---@param code string stable, meant to be branched on
---@param detail? string for logs and staff only: it can carry a raw database exception
---@return Result
function OPX.Result.err(code, detail)
	return { ok = false, error = code, detail = detail }
end
