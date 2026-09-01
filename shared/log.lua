--- Levelled logging over `Open77.log`, falling back to `print` when the namespace is missing.

local Log = {}

local LEVELS = { debug = 1, info = 2, warn = 3, error = 4, silent = 99 }
local threshold = LEVELS.info

local sinks = {}

local function sink(level)
  local cached = sinks[level]
  if cached then return cached end

  local open77 = rawget(_G, "Open77")
  local fn = open77 and open77.log and open77.log[level]
  -- a miss is not cached: caching `print` during boot would strand every later line
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

---@param level "debug" | "info" | "warn" | "error" | "silent"
function Log.setLevel(level)
  threshold = LEVELS[level] or LEVELS.info
end

---@return string
function Log.level()
  for name, value in pairs(LEVELS) do
    if value == threshold then return name end
  end
  return "info"
end

--- A named logger, so a line is attributable without every call site repeating its prefix.
---@param scope string
---@return LogScope
function Log.scope(scope)
  return {
    debug = function(...) write("debug", scope, ...) end,
    info = function(...) write("info", scope, ...) end,
    warn = function(...) write("warn", scope, ...) end,
    error = function(...) write("error", scope, ...) end,
  }
end

--- Unscoped shorthands, for one-off lines that do not belong to a subsystem.
function Log.debug(...) write("debug", "opx77", ...) end
function Log.info(...) write("info", "opx77", ...) end
function Log.warn(...) write("warn", "opx77", ...) end
function Log.error(...) write("error", "opx77", ...) end

OPX.Log = Log
