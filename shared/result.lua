--- Success or failure as a value, so `nil` never has to mean both "failed" and "found
--- nothing". A failure still never unwinds the stack.

local Result = {}

---@param value any
---@return Result
function Result.ok(value)
  return { ok = true, value = value }
end

---@param code string stable, meant to be branched on
---@param detail? string for logs and staff only: it can carry a raw database exception
---@return Result
function Result.err(code, detail)
  return { ok = false, error = code, detail = detail }
end

OPX.Result = Result
