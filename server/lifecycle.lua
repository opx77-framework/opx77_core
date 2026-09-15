--- @author DemiAutomatic
--- @file server/lifecycle.lua
--- @description The join-time readiness gate: participation, hold, release, selection watch.

--- @author DemiAutomatic
--- @type {table}
--- @description The server-only configuration the gate reads.
local Config = OPX.Config.SERVER

OPX.Lifecycle = {}
local Lifecycle = OPX.Lifecycle

--- @author DemiAutomatic
--- @method OPX.Lifecycle.participate
--- @description Declares the core's participation in the gate, once at load.
function OPX.Lifecycle.participate()
	Open77.ready.participate({
		livenessIntervalMs = Config.ENTRY.GATE_MS,
		reason = 'opx77_character_selection',
	})
	Open77.log.info(('[lifecycle] declaring a %d ms liveness interval on the readiness gate')
		:format(Config.ENTRY.GATE_MS))

	local function running(name)
		local state = GetResourceState(name)
		return state == 'running' or state == 'starting'
	end
	if not running('opx77_appearance') and not running('open77_appearance') then
		Open77.log.warn('[lifecycle] no resource here emits `open77:session:gameplayReady`, so ' ..
			"the platform's `__platform` hold never clears and `Open77.ready.isReady` stays false")
	end
end

--- @author DemiAutomatic
--- @method OPX.Lifecycle.hold
--- @description Takes the gate hold for one player and records its session.
--- @param source {Source}
--- @param reason {string|nil}
function OPX.Lifecycle.hold(source, reason)
	local session = OPX.Sessions[source]
	if not session then return end

	local gateSession = Open77.ready.hold(source, reason or 'opx77_character_selection')
	if gateSession ~= nil then
		session.gateSession = gateSession
		session.heldAt = OPX.Now()
	end
end

--- @author DemiAutomatic
--- @method OPX.Lifecycle.release
--- @description Releases a player's gate hold, idempotently, with a note.
--- @param source {Source}
--- @param note {string|nil}
function OPX.Lifecycle.release(source, note)
	local session = OPX.Sessions[source]

	local gateSession = session and session.gateSession
	if gateSession == nil then
		local status = Open77.ready.status(source)
		gateSession = status and status.session or nil
	end

	if session then
		session.gateSession = nil
		session.released = true
	end

	Open77.ready.release(source, gateSession, 'opx77_core:' .. (note or 'done'))
	Open77.log.debug(('[lifecycle] gate released for %d (%s)'):format(source, note or 'done'))
end

--- @author DemiAutomatic
--- @method OPX.Lifecycle.isReady
--- @description Answers whether the gate has opened for this player.
--- @param source {Source}
--- @returns {boolean}
function OPX.Lifecycle.isReady(source)
	local read, open = pcall(Open77.ready.isReady, source)
	return not read or open == true
end

--- @author DemiAutomatic
--- @method refuseEntry
--- @description Releases the gate and disconnects a player the core cannot admit.
--- @param source {Source}
--- @param code {string} A locale key, shown on the player's screen.
--- @param note {string}
local function refuseEntry(source, code, note)
	Lifecycle.release(source, note)
	local closed, reason = Open77.players.disconnect(source, locale(code))
	if not closed then
		Open77.log.error(('[lifecycle] could not disconnect %d (%s): %s')
			:format(source, note, tostring(reason)))
		OPX.Refuse(source, code, OPX.Operations.ENTRY)
	end
end

--- @author DemiAutomatic
--- @method OPX.Lifecycle.beginEntry
--- @description Holds, isolates and sends the roster to a connecting player.
--- @param source {Source}
function OPX.Lifecycle.beginEntry(source)
	local session = OPX.EnsureSession(source)
	if not session then
		Open77.log.error(('[lifecycle] no verified identity for %d, refusing entry'):format(source))
		refuseEntry(source, 'entry.noIdentity', 'no-identity')
		return
	end
	Open77.log.debug(('[lifecycle] %s (%s) connected as %d')
		:format(session.displayName, session.userId, source))

	Lifecycle.hold(source, 'opx77_character_selection')

	OPX.Buckets.isolate(source, 'joined')

	CreateThread(function()
		local sent = OPX.SendCharacters(source, true)
		if not sent.ok then
			Open77.log.error(('[lifecycle] could not send the character list to %d: %s')
				:format(source, tostring(sent.error)))
			OPX.Refuse(source, 'entry.failed', OPX.Operations.ENTRY)
			Lifecycle.release(source, 'roster-failed')
			return
		end
		Lifecycle.watch(source)
	end)
end

--- @author DemiAutomatic
--- @method OPX.Lifecycle.watch
--- @description Releases the gate for a player who never chooses a character.
--- @param source {Source}
function OPX.Lifecycle.watch(source)
	local session = OPX.Sessions[source]
	if not session then return end
	local userId = session.userId
	local deadline = OPX.Now() + OPX.TuneNumber('SELECTION_MS', 30000)

	CreateThread(function()
		while true do
			Wait(1000)

			local live = OPX.Sessions[source]
			if not live or live.userId ~= userId or live.released then return end
			if live.citizenId then return end

			local ok, timedOut = pcall(function()
				if OPX.Now() < deadline then return false end
				Open77.log.warn(('[lifecycle] %d spent too long choosing a character; releasing the ' ..
					'gate'):format(source))
				OPX.Refuse(source, 'entry.timedOut', OPX.Operations.ENTRY)
				Lifecycle.release(source, 'selection-timeout')
				return true
			end)
			if not ok then
				Open77.log.error(('[lifecycle] the selection watch for %d raised: %s')
					:format(source, tostring(timedOut)))
				return
			end
			if timedOut then return end
		end
	end)
end

Lifecycle.participate()
