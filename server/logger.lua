--- The player audit log: what an operator will be asked to account for later, as opposed to
--- `Open77.log`, which is for what the code is doing. The platform log is the only sink.

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

--- How long a closed window is kept, so the next entry of its kind can say how many it
--- stands for.
local RETAIN_MS = DEDUPE_MS * 6

--- key -> { at, count, owner }. `owner` is kept beside the key rather than parsed back out of
--- it, because a key ends in the source OR the citizen id.
local recent = {}

--- Event prefixes that are never collapsed: six purchases in eight seconds are six answers.
--- Refusals under the same prefixes still are, through `severity`.
local LEDGER_PREFIXES = { "money.", "character." }

---@param value any
---@param maximum integer
---@return string
local function bounded(value, maximum)
  local text = tostring(value or "")
  text = text:gsub("[%c]", " ")
  if #text > maximum then text = text:sub(1, maximum) .. "..." end
  return text
end

--- Truncates and strips control characters. Published because a newline in client-chosen
--- text forges a whole log line attributed to whatever resource the attacker names.
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

--- True for an entry that has to be written out in full every time it happens.
---@param entry LogEntry
---@return boolean
local function isLedger(entry)
  -- `Logger.security` is the only producer of `warn`, and a refusal is not a ledger line
  if entry.severity ~= "info" and entry.severity ~= "debug" then return false end
  for i = 1, #LEDGER_PREFIXES do
    local prefix = LEDGER_PREFIXES[i]
    if entry.event:sub(1, #prefix) == prefix then return true end
  end
  return false
end

--- When it was last worth walking `recent`: sweeping per entry is a full table scan per log
--- line.
local nextSweepAt = 0

--- Drops entries nobody will read again. This, not `Logger.forget`, is what bounds the table.
---@param now integer
local function sweep(now)
  if now < nextSweepAt then return end
  nextSweepAt = now + DEDUPE_MS
  -- assigning nil to a key `pairs` has already handed out is defined; adding one is not
  for key, seen in pairs(recent) do
    if now - seen.at >= RETAIN_MS then recent[key] = nil end
  end
end

--- True when this exact entry was written within DEDUPE_MS. Counts it either way, so the
--- first entry after the window reports how many it stands for.
---@param key string
---@param owner string
---@return boolean repeated, integer carried
local function repeated(key, owner)
  local now = OPX.Now()
  sweep(now)
  local seen = recent[key]
  if seen and now - seen.at < DEDUPE_MS then
    seen.count = seen.count + 1
    return true, seen.count
  end
  local carried = seen and seen.count or 0
  recent[key] = { at = now, count = 0, owner = owner }
  return false, carried
end

--- Dropped on departure, so a source that never returns does not hold a key forever.
---@param source Source
---@param citizenId? CitizenId pass it when the caller has one: an entry logged without a
---        source is keyed by citizen id, which a departing source does not name
function Logger.forget(source, citizenId)
  local bySource = tostring(source)
  local byCitizen = citizenId ~= nil and tostring(citizenId) or nil
  for key, seen in pairs(recent) do
    if seen.owner == bySource or (byCitizen and seen.owner == byCitizen) then
      recent[key] = nil
    end
  end
end

---@param entry LogEntry
function Logger.log(entry)
  if type(entry) ~= "table" or type(entry.event) ~= "string" then return end
  entry.severity = SEVERITIES[entry.severity] and entry.severity or "info"
  entry.message = entry.message ~= nil and bounded(entry.message, MAX_MESSAGE) or nil

  -- a ledger event skips the window entirely: collapsing it destroys the record
  if not isLedger(entry) then
    local owner = tostring(entry.source or entry.citizenId or "-")
    local again, carried = repeated(entry.event .. "\1" .. owner, owner)
    if again then return end
    if carried > 0 then
      entry.message = ("%s [+%d suppressed]"):format(entry.message or "", carried)
    end
  end

  Open77.log[entry.severity](("[audit] %s"):format(toLine(entry)))
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
---@param source? Source who caused it: without one the dedupe key is global per event, and
---        one player looping a refusal swallows every other player's
function Logger.security(event, message, data, source)
  Logger.log({ event = event, severity = "warn", message = message, data = data,
               source = source })
end

OPX.Logger = Logger
