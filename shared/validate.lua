--- Checks for values crossing a trust boundary: net events, command arguments,
--- WebUI payloads. The platform authenticates who sent a message, never what
--- is inside it.

local Result = require("shared.result")

local Validate = {}

--- `utf8` is not among the libraries the sandbox strips, but a byte count is a
--- safe degradation if a build disagrees: it never rejects more than it should.
local lengthOf = rawget(_G, "utf8") and utf8.len or function(s) return #s end

--- Trims, then enforces length and an optional pattern.
---
--- Length is counted in characters, not bytes. `#"Éloïse"` is 8 for 6 letters,
--- so a byte budget quietly shortens every name carrying an accent -- and this
--- is a French-speaking server.
---
--- Malformed UTF-8 is refused outright rather than measured. A client can put
--- arbitrary bytes on the wire, and `utf8.len` returning nil is what separates
--- them from text; every byte-oriented pattern downstream assumes valid input.
function Validate.text(value, opts)
  opts = opts or {}
  if type(value) ~= "string" then
    return Result.err("type", "expected string, got " .. type(value))
  end

  local trimmed = value:match("^%s*(.-)%s*$")
  local length = lengthOf(trimmed)
  if not length then return Result.err("not-utf8") end
  if length < (opts.min or 1) then return Result.err("too-short") end
  if length > (opts.max or 255) then return Result.err("too-long") end
  if opts.pattern and not trimmed:match(opts.pattern) then
    return Result.err("format")
  end
  return Result.ok(trimmed)
end

--- `n ~= n` is true only for NaN, which a client can send through JSON and
--- which passes every comparison silently otherwise.
function Validate.number(value, opts)
  opts = opts or {}
  local n = tonumber(value)
  if n == nil then
    return Result.err("type", "expected number, got " .. type(value))
  end
  if n ~= n or n == math.huge or n == -math.huge then
    return Result.err("not-finite")
  end
  if opts.integer and n % 1 ~= 0 then return Result.err("not-integer") end
  if opts.min and n < opts.min then return Result.err("too-small") end
  if opts.max and n > opts.max then return Result.err("too-large") end
  return Result.ok(n)
end

--- Player ids arrive from net events as strings.
function Validate.playerId(value)
  local checked = Validate.number(value, { integer = true, min = 0 })
  if not checked.ok then return Result.err("bad-player-id", checked.error) end
  return checked
end

--- `allowed` is a set (`{ male = true }`) so the check is a lookup, not a scan.
function Validate.oneOf(value, allowed)
  if allowed[value] then return Result.ok(value) end
  return Result.err("not-allowed", tostring(value))
end

--- Validates a table field by field. Unknown keys are dropped rather than
--- copied: an unexpected field must never reach storage.
function Validate.shape(value, schema)
  if type(value) ~= "table" then
    return Result.err("type", "expected table, got " .. type(value))
  end

  local out = {}
  for key, check in pairs(schema) do
    local checked = check(value[key])
    if not checked.ok then
      return Result.err("field", ("%s: %s"):format(key, tostring(checked.error)))
    end
    out[key] = checked.value
  end
  return Result.ok(out)
end

return Validate
