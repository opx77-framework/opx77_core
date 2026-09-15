--- @author DemiAutomatic
--- @file server/events.lua
--- @description Every platform and net event handler the core registers.

--- @author DemiAutomatic
--- @type {table}
--- @description The event name tables published on OPX.Events.
local Events = OPX.Events

--- @author DemiAutomatic
--- @event onPlayerConnected
--- @description Starts entry for a connecting player, id read from the argument.
--- @param rawPlayerId {integer|string}
--- @param playerName {string|nil}
AddEventHandler(Events.Platform.PLAYER_CONNECTED, function(rawPlayerId, playerName)
	local source = tonumber(rawPlayerId)
	if not source or source <= 0 then
		Open77.log.error(('[events] unusable player id %q on connect'):format(tostring(rawPlayerId)))
		return
	end
	Open77.log.debug(('[events] %s connected as %d'):format(tostring(playerName), source))
	OPX.Lifecycle.beginEntry(source)
end)

--- @author DemiAutomatic
--- @event onPlayerDisconnected
--- @description Tears down everything the core holds for a departing player.
--- @param rawPlayerId {integer|string}
AddEventHandler('onPlayerDisconnected', function(rawPlayerId)
	local source = tonumber(rawPlayerId)
	if not source then return end
	local session = OPX.Sessions[source]
	if session then session.departing = true end
	OPX.Logout(source)
	OPX.ForgetSession(source)
	OPX.ForgetCooldowns(source)
	OPX.Logger.forget(source)
end)

--- @author DemiAutomatic
--- @event onPlayerReady
--- @description Logs a readiness gate opened because a hold lost liveness.
--- @param rawPlayerId {integer|string}
--- @param detail {string|nil}
AddEventHandler(Events.Platform.PLAYER_READY, function(rawPlayerId, detail)
	local source = tonumber(rawPlayerId)
	if not source then return end

	if type(detail) == 'string' and detail:sub(1, 14) == 'liveness_lost:' then
		Open77.log.warn(('[events] the readiness gate for %d opened on lost liveness (%s)')
			:format(source, detail))
		local ours = GetCurrentResourceName()
		for name in detail:sub(15):gmatch('[^,]+') do
			if name == ours then
				Open77.log.warn('[events] that hold was ours: the player may be in the world with ' ..
					'no character')
				break
			end
		end
	end
end)

--- @author DemiAutomatic
--- @event opx77:server:ready
--- @description Resends the roster, or playerLoaded, to a client announcing itself.
RegisterNetEvent(Events.Server.READY, function()
	local src = tonumber(source)
	if not src then return end
	if OPX.Cooling(src, 'ready', 2000) then return end

	local session = OPX.EnsureSession(src)
	if not session then return end

	local player = OPX.GetPlayer(src)
	if player then
		TriggerClientEvent(Events.Client.PLAYER_LOADED, src, player.PlayerData)
		return
	end

	if not OPX.Lifecycle.isReady(src) then OPX.Buckets.isolate(src, 'ready') end

	CreateThread(function() OPX.SendCharacters(src, true) end)
end)

--- @author DemiAutomatic
--- @event opx77:server:selectCharacter
--- @description Enters the world as one of the caller's characters.
--- @param payload {any}
RegisterNetEvent(Events.Server.SELECT_CHARACTER, function(payload)
	local src = tonumber(source)
	if not src then return end

	local citizenId = type(payload) == 'table' and payload.citizenId or nil
	local operation = OPX.Operations.SELECT_CHARACTER
	if type(citizenId) ~= 'string' then
		return OPX.Refuse(src, 'error.badRequest', operation)
	end
	if OPX.Cooling(src, 'select.request', 1000) then
		return OPX.Refuse(src, 'error.tooFast', operation)
	end

	CreateThread(function()
		local selected = OPX.SelectCharacter(src, citizenId)
		if not selected.ok then
			if selected.error ~= 'error.tooFast' then
				Open77.log.warn(('[events] %d could not select %s: %s')
					:format(src, OPX.Logger.safe(citizenId), tostring(selected.error)))
			end
			OPX.Refuse(src, selected.error, operation)
			OPX.NotifyLocale(src, selected.error, nil, 'error')
		end
	end)
end)

--- @author DemiAutomatic
--- @event opx77:server:createCharacter
--- @description Creates a character on the caller's account and resends the roster.
--- @param payload {any}
RegisterNetEvent(Events.Server.CREATE_CHARACTER, function(payload)
	local src = tonumber(source)
	if not src then return end

	local operation = OPX.Operations.CREATE_CHARACTER
	if OPX.Cooling(src, 'create.request', 1000) then
		return OPX.Refuse(src, 'error.tooFast', operation)
	end

	CreateThread(function()
		local created = OPX.CreateCharacter(src, payload)
		if not created.ok then
			OPX.Refuse(src, created.error, operation)
			OPX.NotifyLocale(src, created.error, { max = created.detail }, 'error')
			return
		end

		OPX.NotifyLocale(src, 'character.created',
			{ citizenId = created.value.citizenId }, 'success')

		OPX.SendCharacters(src, true)
	end)
end)

--- @author DemiAutomatic
--- @event opx77:server:deleteCharacter
--- @description Soft-deletes one of the caller's characters and resends the roster.
--- @param payload {any}
RegisterNetEvent(Events.Server.DELETE_CHARACTER, function(payload)
	local src = tonumber(source)
	if not src then return end

	local citizenId = type(payload) == 'table' and payload.citizenId or nil
	local operation = OPX.Operations.DELETE_CHARACTER
	if type(citizenId) ~= 'string' then
		return OPX.Refuse(src, 'error.badRequest', operation)
	end
	if OPX.Cooling(src, 'delete.request', 1000) then
		return OPX.Refuse(src, 'error.tooFast', operation)
	end

	CreateThread(function()
		local deleted = OPX.DeleteCharacter(src, citizenId)
		if not deleted.ok then
			OPX.Refuse(src, deleted.error, operation)
			return
		end
		OPX.NotifyLocale(src, 'character.deleted', nil, 'success')
		OPX.SendCharacters(src, true)
	end)
end)

--- @author DemiAutomatic
--- @event opx77:server:reportPosition
--- @description Keeps the client's heading hint for the next position sample.
--- @param payload {any}
RegisterNetEvent(Events.Server.REPORT_POSITION, function(payload)
	local src = tonumber(source)
	if not src then return end

	if OPX.Cooling(src, 'heading', 1000) then return end

	local player = OPX.GetPlayer(src)
	if not player then return end

	local heading = OPX.Validate.number(
		type(payload) == 'table' and payload.heading or nil, { min = -360, max = 360 })
	if heading.ok then player.PlayerData.reportedHeading = heading.value end
end)
