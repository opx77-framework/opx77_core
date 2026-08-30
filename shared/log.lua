--- Scoped logging over `Open77.log`, which already prefixes the resource name.
--- Falls back to `print` when the namespace is missing: a logger that throws
--- during boot hides the error you are trying to read.

local Log = {}

local LEVELS = { debug = 1, info = 2, warn = 3, error = 4, silent = 99 }
local threshold = LEVELS.info

--- Resolved once per level, then reused: every line otherwise paid a global
--- read and three indexations. A miss is deliberately *not* cached -- during
--- boot `Open77` may not exist yet, and caching `print` then would keep every
--- later line out of the platform log.
local sinks = {}

local function sink(level)
  local cached = sinks[level]
  if cached then return cached end

  local ns = rawget(_G, "Open77")
  local fn = ns and ns.log and ns.log[level]
  if not fn then return print end

  sinks[level] = fn
  return fn
end

local function write(level, scope, ...)
  if LEVELS[level] < threshold then return end
  local parts = table.pack(...)
  for i = 1, parts.n do parts[i] = tostring(parts[i]) end
  sink(level)(("[%s] %s"):format(scope, table.concat(parts, " ", 1, parts.n)))
end

function Log.setLevel(level)
  threshold = LEVELS[level] or LEVELS.info
end

--- Modules take one of these instead of the global, so output is attributable
--- without every call site repeating a prefix.
function Log.scope(scope)
  return {
    debug = function(...) write("debug", scope, ...) end,
    info = function(...) write("info", scope, ...) end,
    warn = function(...) write("warn", scope, ...) end,
    error = function(...) write("error", scope, ...) end,
  }
end

return Log
