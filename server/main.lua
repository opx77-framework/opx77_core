--- @author DemiAutomatic
--- @file server/main.lua
--- @description The session and player rosters, and the boot sequence.

--- @author DemiAutomatic
--- @type {table<Source, Session>}
--- @description Every connected machine by player id, character or not.
OPX.Sessions = {}

--- @author DemiAutomatic
--- @type {table<Source, Player>}
--- @description Every loaded character by player id.
OPX.Players = {}

--- @author DemiAutomatic
--- @type {table}
--- @description Player ids by citizen id and by user id.
OPX.PlayerRegistry = {
	byCitizenId = {},
	byUserId = {},
}

--- @author DemiAutomatic
--- @type {fun(playerId: Source): UserId|nil}
--- @description The host identifier reader, kept once it has been found.
local identifierOf

--- @author DemiAutomatic
--- @method userIdOf
--- @description Reads the durable user id the host vouches for.
--- @param playerId {Source}
--- @returns {UserId|nil}
local function userIdOf(playerId)
	if identifierOf then return identifierOf(playerId) end
	local fn = rawget(_G, 'GetPlayerIdentifier')
	if not fn then return nil end
	identifierOf = fn
	return fn(playerId)
end

--- @author DemiAutomatic
--- @type {fun(playerId: Source): UserId|nil}
--- @description Reads the durable user id the host vouches for.
OPX.UserIdOf = userIdOf

--- @author DemiAutomatic
--- @method displayNameOf
--- @description Reads a player's display name from the host, or nil.
--- @param playerId {Source}
--- @returns {string|nil}
local function displayNameOf(playerId)
	local fn = rawget(_G, 'GetPlayerName')
	return fn and fn(playerId) or nil
end

--- @author DemiAutomatic
--- @method OPX.EnsureSession
--- @description Answers a player's session, creating or evicting it by user id.
--- @param playerId {Source|string}
--- @returns {Session|nil}
function OPX.EnsureSession(playerId)
	playerId = tonumber(playerId)
	if not playerId or playerId <= 0 then return nil end

	local userId = userIdOf(playerId)
	if userId == nil or userId == '' then
		OPX.ForgetSession(playerId)
		return nil
	end

	local session = OPX.Sessions[playerId]
	if session then
		if session.userId == userId then return session end
		Open77.log.warn(('[core] slot %d now belongs to a different account, evicting')
			:format(playerId))
		OPX.ForgetSession(playerId)
	end

	session = {
		source = playerId,
		userId = userId,
		displayName = displayNameOf(playerId) or '',
		connectedAt = OPX.Now(),
		gateSession = nil,
		charactersSent = false,
	}
	OPX.Sessions[playerId] = session
	return session
end

--- @author DemiAutomatic
--- @method OPX.ForgetSession
--- @description Drops a session, logging out any character still on the slot.
--- @param playerId {Source}
function OPX.ForgetSession(playerId)
	local player = OPX.Players[playerId]
	local session = OPX.Sessions[playerId]
	if session then session.departing = true end
	if player then
		player.MaySample = false
		OPX.Logout(playerId)
	end
	OPX.Sessions[playerId] = nil
end

--- @author DemiAutomatic
--- @method OPX.RegisterPlayer
--- @description Puts a loaded character into the roster and both indexes.
--- @param player {Player}
function OPX.RegisterPlayer(player)
	local data = player.PlayerData
	local occupant = OPX.Players[data.source]
	if occupant and occupant ~= player then OPX.UnregisterPlayer(occupant) end
	OPX.Players[data.source] = player
	OPX.PlayerRegistry.byCitizenId[data.citizenId] = data.source
	OPX.PlayerRegistry.byUserId[data.userId] = data.source
end

--- @author DemiAutomatic
--- @method OPX.UnregisterPlayer
--- @description Takes a character out of the roster and its own index entries.
--- @param player {Player}
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

--- @author DemiAutomatic
--- @method warnAboutPlacementConflicts
--- @description Warns once for each running resource that also places players.
local function warnAboutPlacementConflicts()
	local names = OPX.Config.SERVER.CONFLICTING_PLACERS
	local mine = GetCurrentResourceName()
	for i = 1, #names do
		local name = names[i]
		local state = GetResourceState(name)
		if name ~= mine and (state == 'running' or state == 'starting') then
			Open77.log.warn(('[core] %s is running and also places players; see ' ..
				'CONFLICTING_PLACERS in config/server.lua'):format(name))
		end
	end
end

CreateThread(function()
	Open77.log.info(('[core] opx77_core %s starting'):format(OPX.VERSION))

	local ready = OPX.Storage.ready()
	if ready then
		local migrated = OPX.Storage.migrate(OPX.Schema)
		if not migrated.ok then
			OPX.BootError = 'migration failed: ' .. tostring(migrated.error)
			Open77.log.error('[core] refusing to accept logins against an unknown schema')
		end
	else
		OPX.BootError = 'no database'
	end

	local warned, warnError = pcall(warnAboutPlacementConflicts)
	if not warned then
		Open77.log.error('[core] the placement-conflict check raised: ' .. tostring(warnError))
	end

	if not OPX.Config.SHARED.DEFAULT_SPAWN.SET then
		Open77.log.warn('[core] DEFAULT_SPAWN.SET is false in config/shared.lua: characters ' ..
			'with no stored position are left where the game put them. Run `opx77.here` in game ' ..
			'to print a coordinate in the right shape.')
	end

	OPX.Booted = true

	if OPX.BootError then
		Open77.log.error(('[core] opx77_core %s is up but cannot load characters: %s')
			:format(OPX.VERSION, OPX.BootError))
	else
		Open77.log.info(('[core] opx77_core %s ready'):format(OPX.VERSION))
	end
end)
