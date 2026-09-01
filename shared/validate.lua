--- Checks for values crossing a trust boundary: net events, command arguments, WebUI
--- payloads. The platform authenticates who sent a message, never what is inside it.

local Result = OPX.Result

local Validate = {}

--- Trims, then enforces length and an optional pattern. Length is in characters, not bytes,
--- and malformed UTF-8 is refused outright rather than measured.
---@param value any
---@param opts? { min?: integer, max?: integer, pattern?: string }
---@return Result
function Validate.text(value, opts)
  opts = opts or {}
  if type(value) ~= "string" then
    return Result.err("type", "expected string, got " .. type(value))
  end

  -- Bounded in BYTES before the trim, which is the only work here that scales
  -- with the input. `max` is in characters and cannot serve: a UTF-8 character
  -- is up to four bytes, so four times it is the honest ceiling, and 1024 keeps
  -- a caller that passes no `max` from handing the trim a whole envelope.
  local ceiling = math.min(((opts.max or 255) * 4) + 16, 1024)
  if #value > ceiling then return Result.err("too-long") end

  local trimmed = OPX.String.trim(value)
  local length = OPX.String.length(trimmed)
  if not length then return Result.err("not-utf8") end
  if length < (opts.min or 1) then return Result.err("too-short") end
  if length > (opts.max or 255) then return Result.err("too-long") end
  if opts.pattern and not trimmed:match(opts.pattern) then
    return Result.err("format")
  end
  return Result.ok(trimmed)
end

---@param value any
---@param opts? { integer?: boolean, min?: number, max?: number }
---@return Result
function Validate.number(value, opts)
  opts = opts or {}
  local n = tonumber(value)
  if n == nil then
    return Result.err("type", "expected number, got " .. type(value))
  end
  if not OPX.Math.isFinite(n) then return Result.err("not-finite") end
  if opts.integer and n % 1 ~= 0 then return Result.err("not-integer") end
  if opts.min and n < opts.min then return Result.err("too-small") end
  if opts.max and n > opts.max then return Result.err("too-large") end
  return Result.ok(n)
end

---@param value any
---@param allowed table<any, boolean> a set, so the check is one hash read
---@return Result
function Validate.oneOf(value, allowed)
  if allowed[value] then return Result.ok(value) end
  return Result.err("not-allowed", tostring(value))
end

OPX.Validate = Validate
