--- The getters and the server-side helpers everything uses. None of them yield, so they are
--- callable from an event handler without a thread.

local Result = OPX.Result

--- The loaded character at `source`, or nil. Nil includes somebody still choosing one, which
--- is not an error.
---@param source Source|string
---@return Player|nil
function OPX.GetPlayer(source)
  return OPX.Players[tonumber(source) or -1]
end

---@param citizenId CitizenId
---@return Player|nil
function OPX.GetPlayerByCitizenId(citizenId)
  local source = OPX.PlayerRegistry.byCitizenId[citizenId]
  return source and OPX.Players[source] or nil
end

---@param userId UserId
---@return Player|nil
function OPX.GetPlayerByUserId(userId)
  local source = OPX.PlayerRegistry.byUserId[userId]
  return source and OPX.Players[source] or nil
end

--- Every loaded character. Iterate this rather than `pairs(OPX.Players)`: the walk also
--- evicts any slot whose userId no longer matches, which logs that character out and saves.
---@return Player[]
function OPX.GetPlayers()
  local out, n = {}, 0
  local stale, staleCount = nil, 0

  for source, player in pairs(OPX.Players) do
    if OPX.UserIdOf(source) == player.PlayerData.userId then
      n = n + 1
      out[n] = player
    else
      -- evicted after the walk: Logout's handlers would mutate the table being iterated
      staleCount = staleCount + 1
      stale = stale or {}
      stale[staleCount] = source
    end
  end

  for i = 1, staleCount do
    OPX.ForgetSession(stale[i])
  end
  return out
end

--- How many characters are in the world, building no table.
---@return integer
function OPX.GetPlayerCount()
  local n = 0
  for source, player in pairs(OPX.Players) do
    if OPX.UserIdOf(source) == player.PlayerData.userId then n = n + 1 end
  end
  return n
end

--- A character online or not. The offline shape is a bare entity with no `Functions`.
--- Yields when offline: coroutine only.
---@param citizenId CitizenId
---@return Result  ok value is { player, offline = false } or { entity, offline = true }
function OPX.GetCharacter(citizenId)
  local online = OPX.GetPlayerByCitizenId(citizenId)
  if online then return Result.ok({ player = online, offline = false }) end

  local fetched = OPX.Storage.Players.fetchOne(citizenId)
  if not fetched.ok then return fetched end
  return Result.ok({ entity = fetched.value, offline = true })
end

-- How long an identical (source, text) answer is suppressed. Two different refusals are two
-- things the player has to be told, so only an exact repeat is swallowed.
local ANSWER_DEDUPE_MS = 2000

--- source -> answer text -> when it last went out. Emptied by `OPX.ForgetCooldowns`.
local lastAnswer = {}

--- True when this exact answer has just gone to this source.
---@param source integer
---@param text string
---@return boolean
local function repeated(source, text)
  local bucket = lastAnswer[source]
  if not bucket then
    bucket = {}
    lastAnswer[source] = bucket
  end
  local now = OPX.Now()
  if bucket[text] and now - bucket[text] < ANSWER_DEDUPE_MS then return true end
  -- bounded: a client naming a fresh code every message would grow this for the session
  local count = 0
  for _ in pairs(bucket) do count = count + 1 end
  if count >= 32 then bucket = {}; lastAnswer[source] = bucket end
  bucket[text] = now
  return false
end

--- A toast, through `Open77.notifications`. Degrades to nothing when no resource draws
--- `open77:notifications:show`; the core declares no dependency on one.
---@param source Source
---@param message string
---@param kind? "info"|"success"|"warning"|"error"
---@param durationMs? integer
function OPX.Notify(source, message, kind, durationMs)
  source = tonumber(source)
  if not source or source <= 0 then return end
  if repeated(source, "notify:" .. tostring(kind) .. ":" .. tostring(message)) then return end

  local api = Open77.notifications
  if not api or type(api.send) ~= "function" then return end

  api.send(source, {
    type = kind or "info",
    title = OPX.Config.SHARED.SERVER_NAME,
    message = message,
    durationMs = durationMs or 5000,
    position = OPX.Config.SHARED.NOTIFY_POSITION,
  })
end

--- A code the catalogue can actually render. A storage layer answers `query-failed` and
--- `no-database`, and a validator answers `too-short`: those are for a log, not a player.
---@param code any
---@return string
function OPX.RefusalKey(code)
  if type(code) == "string" and OPX.Locale.exists(code) then return code end
  Open77.log.warn(("[core] %q has no catalogue entry; answering error.unavailable")
    :format(tostring(code)))
  return "error.unavailable"
end

--- The same message, from a locale key. A key with no entry is replaced rather than shown.
---@param source Source
---@param key string
---@param params? table<string, string|number>
---@param kind? "info"|"success"|"warning"|"error"
function OPX.NotifyLocale(source, key, params, kind)
  OPX.Notify(source, locale(OPX.RefusalKey(key), params), kind)
end

--- Answers a command the way the shipped resources do.
---@param source Source|nil  nil or 0 prints to the console
---@param raw string|nil
---@param accepted boolean
---@param message string
function OPX.CommandResult(source, raw, accepted, message)
  if source and source > 0 then
    TriggerClientEvent("open77:command:result", source, raw or "", accepted == true, message)
  else
    print(message)
  end
end

-- Per-source cooldowns, keyed by operation rather than by doorway. Not a security boundary:
-- the ownership checks in server/character.lua are.
local cooldowns = {}

--- True when this source ran `key` less than `everyMs` ago. Records the attempt when not.
---@param source Source
---@param key string
---@param everyMs integer
---@return boolean
function OPX.Cooling(source, key, everyMs)
  source = tonumber(source)
  if not source or source <= 0 then return false end
  local now = OPX.Now()
  local bucket = cooldowns[source]
  if not bucket then
    bucket = {}
    cooldowns[source] = bucket
  end
  if bucket[key] and now - bucket[key] < everyMs then return true end
  bucket[key] = now
  return false
end

--- Dropped on departure: a source is recycled, and a window left behind would refuse the
--- next player to hold that id.
---@param source Source
function OPX.ForgetCooldowns(source)
  source = tonumber(source) or -1
  cooldowns[source] = nil
  -- the answer window too, or the next player's first refusal on this id is swallowed
  lastAnswer[source] = nil
end

--- Tells a client a request was refused: which request, and a code, and nothing else. A
--- refusal that explains itself tells an attacker which half of the guess was right.
---@param source Source
---@param code string a locale key; one the catalogue does not carry becomes
---        `error.unavailable`, so this channel never sends a client a code it cannot render
---@param operation? string a value of `OPX.Operations`. Without it a client waiting on one of
---        several requests cannot tell which `error.tooFast` is its own
function OPX.Refuse(source, code, operation)
  source = tonumber(source)
  if not source or source <= 0 then return end
  code = OPX.RefusalKey(code)
  operation = type(operation) == "string" and operation or "unknown"
  -- the operation is in the dedupe key: two requests refused for the same reason are two
  -- answers, and collapsing them strands whichever client was not told
  if repeated(source, "refuse:" .. operation .. ":" .. code) then return end
  TriggerClientEvent(OPX.Events.Client.NOTIFY, source,
    { kind = "error", code = code, operation = operation })
end
