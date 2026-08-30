--- Live sessions: which account and character a connected player is.
---
--- No disconnect event is documented, so nothing here depends on one.
--- `playerId` is session-scoped and recycled while `userId` is durable and
--- Master-signed, so the first is only a lookup key: every read re-checks the
--- userId behind the slot and drops the row if it changed. A missed disconnect
--- becomes a non-event instead of a security hole.

local Result = require("shared.result")
local Log = require("shared.log")

local Session = {}
Session.__index = Session

local log = Log.scope("session")

--- nil means the player is gone, which is how a departure is detected.
---
--- The lookup itself is resolved once and kept: `get` runs on every net event
--- and once per row in `all`, so the global read was on the hottest path here.
--- Only a hit is cached; the globals may not be installed yet at first call.
local identifierOf

local function userIdOf(playerId)
  if identifierOf then return identifierOf(playerId) end

  local ns = rawget(_G, "Open77")
  local fn = ns and ns.players and ns.players.identifier
    or rawget(_G, "GetPlayerIdentifier")
  if not fn then return nil end

  identifierOf = fn
  return fn(playerId)
end

function Session.new()
  return setmetatable({
    byPlayer = {},
    playerOfCharacter = {},  -- characterId -> playerId, so lookups are not a scan
  }, Session)
end

--- Drops a row and its character index entry.
function Session:forget(playerId)
  local session = self.byPlayer[playerId]
  if not session then return nil end
  if session.characterId then
    self.playerOfCharacter[session.characterId] = nil
  end
  self.byPlayer[playerId] = nil
  return session
end

--- Opens a session for a freshly connected player, before any character is
--- chosen. Overwrites rather than refuses: an existing row means the previous
--- holder of the slot left without us hearing about it.
function Session:open(playerId, userId, displayName)
  if type(userId) ~= "string" or userId == "" then
    return Result.err("no-identity", "player " .. tostring(playerId))
  end
  if self.byPlayer[playerId] then
    log.debug(("slot %d reused, dropping stale session"):format(playerId))
    self:forget(playerId)
  end

  local session = {
    playerId = playerId,
    userId = userId,
    displayName = displayName,
    characterId = nil,
    openedAt = self:now(),
  }
  self.byPlayer[playerId] = session
  return Result.ok(session)
end

--- The only accessor, so the recycling check cannot be skipped elsewhere.
function Session:get(playerId)
  local session = self.byPlayer[playerId]
  if not session then return Result.err("no-session") end

  local current = userIdOf(playerId)
  if current == nil then
    self:forget(playerId)
    return Result.err("no-session", "player is gone")
  end
  if current ~= session.userId then
    log.warn(("slot %d now belongs to a different user, evicting"):format(playerId))
    self:forget(playerId)
    return Result.err("no-session", "slot recycled")
  end

  return Result.ok(session)
end

function Session:attachCharacter(playerId, characterId)
  local found = self:get(playerId)
  if not found.ok then return found end

  local session = found.value
  if session.characterId then
    self.playerOfCharacter[session.characterId] = nil
  end
  session.characterId = characterId
  self.playerOfCharacter[characterId] = playerId
  return Result.ok(session)
end

function Session:close(playerId)
  return self:forget(playerId)
end

--- Direct lookup through the index, then one validity check.
function Session:findByCharacter(characterId)
  local playerId = self.playerOfCharacter[characterId]
  if not playerId then return Result.err("not-online") end

  local found = self:get(playerId)
  if not found.ok then
    self.playerOfCharacter[characterId] = nil
    return Result.err("not-online")
  end
  return found
end

--- Every session still backed by a connected player. Iterating also prunes the
--- dead rows, which is how the store stays honest without a disconnect event.
function Session:all()
  local live = {}
  for playerId in pairs(self.byPlayer) do
    local found = self:get(playerId)
    if found.ok then live[#live + 1] = found.value end
  end
  return live
end

--- `os` is removed by the sandbox, so this is the only clock available.
--- Resolved once, like the identifier lookup above.
local gameTimer

function Session:now()
  if gameTimer then return gameTimer() end

  local timer = rawget(_G, "GetGameTimer")
  if not timer then return 0 end

  gameTimer = timer
  return timer()
end

return Session
