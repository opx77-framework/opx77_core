--- The roster, and boot. A session is a connected machine; a Player is a loaded character.

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

--- Everything the host will vouch for about an admitted player, in one call, or nil when it
--- vouches for nothing. No permission is needed.
---
--- Prefer this at the entry points -- session creation, commands, audit -- and keep
--- `OPX.UserIdOf` for the sweeps in server/functions.lua, which run per player per tick and
--- want a string rather than a fresh table.
---@param playerId Source
---@return PlayerIdentity|nil
local function identityOf(playerId)
  local players = Open77.players
  if type(players) ~= "table" or type(players.identity) ~= "function" then return nil end
  local ok, identity = pcall(players.identity, playerId)
  if not ok or type(identity) ~= "table" then return nil end
  return identity
end

---@type fun(playerId: Source): PlayerIdentity|nil
OPX.IdentityOf = identityOf

--- The session for `playerId`, created if this VM has not seen them and dropped if the slot
--- now belongs to somebody else. Everything that wants a session goes through here.
---@param playerId Source|string
---@return Session|nil
function OPX.EnsureSession(playerId)
  playerId = tonumber(playerId)
  if not playerId or playerId <= 0 then return nil end

  -- one host call for the account id, the name, and the join instant. The older pair of
  -- globals is the fallback for a host that predates Open77.players.identity.
  local identity = identityOf(playerId)
  local userId = identity and identity.userId or userIdOf(playerId)
  if type(userId) ~= "string" or userId == "" then
    -- no verified identity: nothing may be attributed to them
    OPX.ForgetSession(playerId)
    return nil
  end

  local session = OPX.Sessions[playerId]
  if session then
    if session.userId == userId then return session end
    Open77.log.warn(("[core] slot %d now belongs to a different account, evicting")
      :format(playerId))
    OPX.ForgetSession(playerId)
  end

  session = {
    source = playerId,
    userId = userId,
    -- the display name is authenticated but the player chooses it, so it is a label and
    -- never a key. It is sanitised HERE, once, because every log line and every command
    -- that prints a player takes it from the session: a newline in a chosen name would
    -- otherwise forge a whole audit line.
    displayName = OPX.Logger.safe(identity and identity.name or displayNameOf(playerId), 64),
    fingerprint = identity and identity.fingerprint or nil,
    joinedAt = identity and identity.joinedAt or nil,
    connectedAt = OPX.Now(),
    gateSession = nil, -- set by server/lifecycle.lua while the readiness gate is held
    charactersSent = false, -- set by server/character.lua, so a second request is cheap
  }
  OPX.Sessions[playerId] = session
  return session
end

--- Drops a session and, with it, any player still attached to the slot. The character is
--- logged out rather than dropped: this is the net for a departure nobody reported.
---@param playerId Source
function OPX.ForgetSession(playerId)
  local player = OPX.Players[playerId]
  if player then
    -- the slot may already belong to somebody else, and the save samples by source
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
  -- entry out of both indexes first
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
      Open77.log.warn(("[core] %s is running and also places players; see " ..
        "CONFLICTING_PLACERS in config/server.lua"):format(name))
    end
  end
end

--- Everything that has to happen before the first player may log in. On its own thread:
--- migrations block on database round trips and the main chunk has to return promptly.
CreateThread(function()
  Open77.log.info(("[core] opx77_core %s starting"):format(OPX.VERSION))

  local ready = OPX.Storage.ready()
  if ready then
    local migrated = OPX.Storage.migrate(OPX.Schema)
    if not migrated.ok then
      OPX.BootError = "migration failed: " .. tostring(migrated.error)
      Open77.log.error("[core] refusing to accept logins against an unknown schema")
    end
  else
    OPX.BootError = "no database"
  end

  local warned, warnError = pcall(warnAboutPlacementConflicts)
  if not warned then
    Open77.log.error("[core] the placement-conflict check raised: " .. tostring(warnError))
  end

  if not OPX.Config.SHARED.DEFAULT_SPAWN.SET then
    Open77.log.warn("[core] DEFAULT_SPAWN.SET is false in config/shared.lua: characters " ..
      "with no stored position are left where the game put them. Run `opx77.here` in game " ..
      "to print a coordinate in the right shape.")
  end

  if OPX.BootError then
    Open77.log.error(("[core] opx77_core %s is up but cannot load characters: %s")
      :format(OPX.VERSION, OPX.BootError))
  else
    Open77.log.info(("[core] opx77_core %s ready"):format(OPX.VERSION))
  end
end)
