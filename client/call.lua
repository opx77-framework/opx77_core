--- Calling another client resource's exports.
---
--- The call fails in two places and it is easy to check only the first:
--- `nil, reason` when the call cannot be dispatched (resource stopped, export
--- missing, stale generation), then `value, callError` when it was dispatched
--- but failed. Missing the second turns a remote error into a silent nil.
---
--- `await` yields, so every call site must be inside a CreateThread.

local Result = require("shared.result")
local Log = require("shared.log")

local Call = {}

function Call.request(resource, name, ...)
  local ns = rawget(_G, "Open77")
  if not (ns and ns.exports and ns.exports.call) then
    return Result.err("no-exports", "Open77.exports is unavailable")
  end

  local promise, reason = ns.exports.call(resource, name, ...)
  if not promise then
    return Result.err("unreachable", ("%s:%s -- %s"):format(resource, name, tostring(reason)))
  end

  local ok, value, callError = pcall(promise.await, promise)
  if not ok then
    return Result.err("await-raised", tostring(value))
  end
  if callError then
    return Result.err("remote-error", ("%s:%s -- %s"):format(resource, name, tostring(callError)))
  end
  return Result.ok(value)
end

--- Fire-and-forget, so a slow neighbour cannot stall the caller. Failures
--- still reach the log.
function Call.send(resource, name, ...)
  local args = table.pack(...)
  CreateThread(function()
    local result = Call.request(resource, name, table.unpack(args, 1, args.n))
    if not result.ok then
      Log.scope("call").warn(("%s:%s failed: %s")
        :format(resource, name, tostring(result.detail or result.error)))
    end
  end)
end

return Call
