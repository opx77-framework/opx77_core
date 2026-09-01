--- Structured logging for what an operator will be asked about later -- "who took 40 000
--- eddies out of the Valentinos account on Tuesday" -- as opposed to `OPX.Log`, which is for
--- what the code is doing. Console only: the runtime exposes no HTTP client and the sandbox
--- removes `io` and `os`, so the platform log is the sink.

local Logger = {}

local SEVERITIES = { debug = true, info = true, warn = true, error = true }

---@class LogEntry
---@field event string      stable and greppable: "money.remove", "character.delete"
---@field severity string|nil
---@field message string|nil
---@field source integer|nil
---@field citizenId string|nil
---@field userId string|nil
---@field data table|nil

--- What one entry may carry, in characters. Everything here can come from a client.
local MAX_MESSAGE = 200

--- Window in which repeated identical entries are collapsed, so a client looping a refusal
--- costs one line and a number instead of a screenful.
local DEDUPE_MS = 10000
local recent = {}

---@param value any
---@param maximum integer
---@return string
local function bounded(value, maximum)
  local text = tostring(value or "")
  text = text:gsub("[%c]", " ")
  if #text > maximum then text = text:sub(1, maximum) .. "..." end
  return text
end

--- Truncate and strip control characters. Published because anything a client chose reaches
--- the platform log through a format string, and a newline in it forges a whole log line
--- attributed to whatever resource the attacker names.
---@param value any
---@param maximum? integer
---@return string
function Logger.safe(value, maximum)
  return bounded(value, maximum or 64)
end

--- One line, same shape every time, so a grep over the platform log finds them.
---@param entry LogEntry
---@return string
local function toLine(entry)
  local parts = {
    ("event=%s"):format(entry.event),
    ("severity=%s"):format(entry.severity),
  }
  if entry.citizenId then parts[#parts + 1] = ("citizen=%s"):format(entry.citizenId) end
  if entry.userId then parts[#parts + 1] = ("user=%s"):format(entry.userId) end
  if entry.source then parts[#parts + 1] = ("player=%d"):format(entry.source) end
  if entry.message and entry.message ~= "" then
    parts[#parts + 1] = ("message=%q"):format(entry.message)
  end
  if entry.data then
    parts[#parts + 1] = ("data=%s"):format(bounded(json.encode(entry.data), MAX_MESSAGE))
  end
  return table.concat(parts, " ")
end

--- True when this exact entry was written within DEDUPE_MS. Counts it either way, so the
--- first entry after the window reports how many it stands for.
---@param key string
---@return boolean repeated, integer carried
local function repeated(key)
  local now = OPX.Now()
  local seen = recent[key]
  if seen and now - seen.at < DEDUPE_MS then
    seen.count = seen.count + 1
    return true, seen.count
  end
  local carried = seen and seen.count or 0
  recent[key] = { at = now, count = 0 }
  return false, carried
end

--- Dropped on departure, so a source that never returns does not hold a key forever.
---@param source Source
function Logger.forget(source)
  local suffix = "\1" .. tostring(source)
  for key in pairs(recent) do
    if key:sub(-#suffix) == suffix then recent[key] = nil end
  end
end

---@param entry LogEntry
function Logger.log(entry)
  if type(entry) ~= "table" or type(entry.event) ~= "string" then return end
  entry.severity = SEVERITIES[entry.severity] and entry.severity or "info"
  entry.message = entry.message ~= nil and bounded(entry.message, MAX_MESSAGE) or nil

  local key = entry.event .. "\1" .. tostring(entry.source or entry.citizenId or "-")
  local again, carried = repeated(key)
  if again then return end
  if carried > 0 then
    entry.message = ("%s [+%d suppressed]"):format(entry.message or "", carried)
  end

  OPX.Log[entry.severity](("[log] %s"):format(toLine(entry)))
end

--- The two shapes that come up constantly, so call sites do not rebuild them.
---@param player Player|nil
---@param event string
---@param message? string
---@param data? table
function Logger.player(player, event, message, data)
  local playerData = player and player.PlayerData
  Logger.log({
    event = event,
    message = message,
    data = data,
    source = playerData and playerData.source,
    citizenId = playerData and playerData.citizenId,
    userId = playerData and playerData.userId,
  })
end

---@param event string
---@param message? string
---@param data? table
---@param source? Source  who caused it: without one the dedupe key is global per event, and
---                        one player looping a refusal swallows every other player's
function Logger.security(event, message, data, source)
  Logger.log({ event = event, severity = "warn", message = message, data = data,
               source = source })
end

OPX.Logger = Logger
