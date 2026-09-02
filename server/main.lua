--- The roster, and boot. A session is a connected machine; a Player is a loaded character.

local log = OPX.Log.scope("core")

--- playerId -> session. Everyone connected, character or not.
---@type table<Source, Session>
OPX.Sessions = {}

--- playerId -> Player. Only those with a character loaded.
---@type table<Source, Player>
OPX.Players = {}

--- Reverse lookups, so the getters in server/functions.lua resolve in O(1). Maintained by
--- RegisterPlayer / UnregisterPlayer only.
OPX.PlayerRegistry = {
  ---@type table<CitizenId, Source>
  byCitizenId = {},
  ---@type table<UserId, Source>
  byUserId = {},
}

-- resolved once and kept, and only on a hit: during boot the global may not be installed
-- yet, and a cached nil would make every later call answer "nobody is there"
local identifierOf

local function userIdOf(playerId)
  if identifierOf then return identifierOf(playerId) end
  local fn = rawget(_G, "GetPlayerIdentifier")
  if not fn then return nil end
  identifierOf = fn
  return fn(playerId)
end

---@type fun(playerId: Source): UserId|nil
OPX.UserIdOf = userIdOf

local function displayNameOf(playerId)
  local fn = rawget(_G, "GetPlayerName")
  return fn and fn(playerId) or nil
end

--- The session for `playerId`, created if this VM has not seen them and dropped if the slot
--- now belongs to somebody else. Everything that wants a session goes through here, which is
--- what makes the recycling check unskippable.
---@param playerId Source|string
---@return Session|nil
function OPX.EnsureSession(playerId)
  playerId = tonumber(playerId)
  if not playerId or playerId <= 0 then return nil end

  local userId = userIdOf(playerId)
  if userId == nil or userId == "" then
    -- no verified identity: nothing may be attributed to them
    OPX.ForgetSession(playerId)
    return nil
  end

  local session = OPX.Sessions[playerId]
  if session then
    if session.userId == userId then return session end
    log.warn(("slot %d now belongs to a different account, evicting"):format(playerId))
    OPX.ForgetSession(playerId)
  end

  session = {
    source = playerId,
    userId = userId,
    displayName = displayNameOf(playerId) or "",
    connectedAt = OPX.Now(),
    gateSession = nil, -- set by server/lifecycle.lua while the readiness gate is held
    charactersSent = false, -- set by server/character.lua, so a second request is cheap
  }
  OPX.Sessions[playerId] = session
  return session
end

--- Drops a session and, with it, any player still attached to the slot. The character is
--- logged out rather than dropped: this is the net for a departure nobody reported, and
--- what is in the roster has not been written since the last autosave.
---@param playerId Source
function OPX.ForgetSession(playerId)
  local player = OPX.Players[playerId]
  if player then
    -- the slot may already belong to somebody else, and the save samples by source:
    -- sampling now would write their position onto this character's row
    player.MaySample = false
    OPX.Logout(playerId)
  end
  OPX.Sessions[playerId] = nil
end

--- Puts a loaded character into the roster and both reverse indexes.
---@param player Player
function OPX.RegisterPlayer(player)
  local data = player.PlayerData
  -- a slot already holding somebody else means a second login raced this one: take the old
  -- entry out of both indexes first, or byCitizenId keeps a row pointing at a character
  -- nobody holds
  local occupant = OPX.Players[data.source]
  if occupant and occupant ~= player then OPX.UnregisterPlayer(occupant) end
  OPX.Players[data.source] = player
  OPX.PlayerRegistry.byCitizenId[data.citizenId] = data.source
  OPX.PlayerRegistry.byUserId[data.userId] = data.source
end

--- Takes it back out. Each index entry is removed only if it still points at this player: a
--- reconnecting account has both sessions in the roster for a moment.
---@param player Player
function OPX.UnregisterPlayer(player)
  local data = player.PlayerData
  OPX.Players[data.source] = nil
  if OPX.PlayerRegistry.byCitizenId[data.citizenId] == data.source then
    OPX.PlayerRegistry.byCitizenId[data.citizenId] = nil
  end
  if OPX.PlayerRegistry.byUserId[data.userId] == data.source then
    OPX.PlayerRegistry.byUserId[data.userId] = nil
  end
end

--- Warns once per conflicting resource that is actually running. `GetResourceState` is the
--- only way to ask: server resources cannot call each other.
local function warnAboutPlacementConflicts()
  local names = OPX.Config.SERVER.CONFLICTING_PLACERS
  local mine = GetCurrentResourceName()
  for i = 1, #names do
    local name = names[i]
    -- "starting" counts: a resource coming up will be placing players a moment from now
    local state = GetResourceState(name)
    if name ~= mine and (state == "running" or state == "starting") then
      log.warn(("%s is running and also places players"):format(name))
      log.warn("  two resources moving the same player means the last one wins, with no")
      log.warn("  rule saying which. See CONFLICTING_PLACERS in config/server.lua.")
    end
  end
end

--- Everything that has to happen before the first player may log in. On its own thread:
--- migrations block on database round trips and the main chunk has to return promptly.
CreateThread(function()
  OPX.Log.setLevel(OPX.Config.SHARED.LOG_LEVEL)
  log.info(("opx77_core %s starting"):format(OPX.VERSION))

  local ready = OPX.Storage.ready()
  if ready then
    local migrated = OPX.Storage.migrate(OPX.Schema)
    if not migrated.ok then
      OPX.BootError = "migration failed: " .. tostring(migrated.error)
      log.error("refusing to accept logins against an unknown schema")
    end
  else
    OPX.BootError = "no database"
  end

  warnAboutPlacementConflicts()

  if not OPX.Config.SHARED.DEFAULT_SPAWN.SET then
    log.warn("DEFAULT_SPAWN.SET is false in config/shared.lua")
    log.warn("  characters with no stored position will be left where the game put them.")
    log.warn("  run `opx77.here` in game to print a coordinate in the right shape.")
  end

  if OPX.BootError then
    log.error(("opx77_core %s is up but cannot load characters: %s")
      :format(OPX.VERSION, OPX.BootError))
  else
    log.info(("opx77_core %s ready"):format(OPX.VERSION))
  end
end)
