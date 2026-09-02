--- The getters and the server-side helpers everything uses. None of them yield, so they are
--- callable from an event handler without a thread. `OPX.*` is the server API: the runtime
--- installs no `exports`, so a second server resource could not call this one anyway.

local Result = OPX.Result

--- The loaded character at `source`, or nil. Nil includes somebody still choosing one: it is
--- not an error, and a caller that treats it as one refuses legitimate joins.
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
--- evicts any slot whose userId no longer matches, through `OPX.ForgetSession`, which logs
--- the character out, which saves.
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
    -- ForgetSession clears MaySample before logging out, so the eviction save cannot write
    -- the new occupant of a recycled slot into the departed character's row
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

--- A character online or not, so a caller does not have to ask "are they here" first. The
--- offline shape is a bare entity with no `Functions`. Yields when offline: coroutine only.
---@param citizenId CitizenId
---@return Result  ok value is { player, offline = false } or { entity, offline = true }
function OPX.GetCharacter(citizenId)
  local online = OPX.GetPlayerByCitizenId(citizenId)
  if online then return Result.ok({ player = online, offline = false }) end

  local fetched = OPX.Storage.Players.fetchOne(citizenId)
  if not fetched.ok then return fetched end
  return Result.ok({ entity = fetched.value, offline = true })
end

-- How long an identical answer to the same source is suppressed. The cooldowns below guard
-- the write; this guards the reply, which is the cheaper branch for an attacker: a malformed
-- payload is refused before reaching any cooled operation. Identical (source, text) only --
-- two different refusals are two things the player has to be told.
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

--- Routed through `open77_notifications`, degrading to nothing when that resource is absent:
--- the core declares no dependency on it, because a dependency is hard here.
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

--- The same message, from a locale key.
---@param source Source
---@param key string
---@param params? table<string, string|number>
---@param kind? "info"|"success"|"warning"|"error"
function OPX.NotifyLocale(source, key, params, kind)
  OPX.Notify(source, locale(key, params), kind)
end

--- Answers a command the way the shipped resources do, so console and in-game output land
--- where a player already expects.
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

-- Per-source cooldowns. They belong to the OPERATION, not to a doorway onto it: anything
-- that can be driven in a loop is guarded where it is done, or the next entry point added
-- forgets. Not a security boundary -- the ownership checks in server/character.lua are.
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

--- Tells a client a request was refused, with a stable code and nothing else. The reason is
--- not sent: a refusal that explains itself tells an attacker which half of the guess was
--- right.
---@param source Source
---@param code string a locale key
function OPX.Refuse(source, code)
  source = tonumber(source)
  if not source or source <= 0 then return end
  if repeated(source, "refuse:" .. tostring(code)) then return end
  TriggerClientEvent(OPX.Events.Client.NOTIFY, source, { kind = "error", code = code })
end
