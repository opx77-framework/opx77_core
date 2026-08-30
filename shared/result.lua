--- Success or failure as a value, matching the platform convention
--- (`value` on success, `nil, reason` on failure).

local Result = {}

function Result.ok(value)
  return { ok = true, value = value }
end

--- `code` is stable and machine-readable; `detail` is for logs only and is
--- never shown to a player.
function Result.err(code, detail)
  return { ok = false, error = code, detail = detail }
end

--- Used at trust boundaries, where a returned table may be anything.
function Result.is(value)
  return type(value) == "table" and type(value.ok) == "boolean"
end

--- Returns the value, or raises. The only function here that throws: it marks
--- a place the author claims cannot fail.
function Result.unwrap(result, context)
  if result.ok then return result.value end
  error(("%s: %s%s"):format(
    context or "unwrap",
    tostring(result.error),
    result.detail and (" (" .. tostring(result.detail) .. ")") or ""
  ), 2)
end

function Result.valueOr(result, fallback)
  if result.ok then return result.value end
  return fallback
end

--- Applies `fn` to a success value; errors pass through untouched.
function Result.map(result, fn)
  if not result.ok then return result end
  return Result.ok(fn(result.value))
end

--- Adapts a platform call's `value, reason` pair. Wrap at the call site so the
--- rest of the code only ever handles one convention.
--- `false` is a value, not an absence, so only `nil` counts as failure.
function Result.fromCall(value, reason)
  if value == nil then
    return Result.err("platform", reason and tostring(reason) or "no reason given")
  end
  return Result.ok(value)
end

return Result
