--- @author DemiAutomatic
--- @file server/loops.lua
--- @description Background position sampling, autosave, paychecks and the stop save.

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds between two passes of the background loop.
local SAMPLE_MS = 1000

--- @author DemiAutomatic
--- @type {number}
--- @description Metres a character must move before its row is dirty.
local MOVED_METRES = 1.0

--- @author DemiAutomatic
--- @type {table<string, table>}
--- @description Position and revision at each character's last successful write.
local lastWritten = {}

--- @author DemiAutomatic
--- @method needsWriting
--- @description Answers whether a character's row would come out different.
--- @param player {Player}
--- @returns {boolean}
local function needsWriting(player)
	local mark = lastWritten[player.PlayerData.citizenId]
	if not mark then return true end
	if player.Revision ~= mark.revision then return true end

	local current = player.PlayerData.position
	if not current then return false end
	if not mark.position then return true end
	return OPX.Math.distanceSquared(current, mark.position) >= MOVED_METRES * MOVED_METRES
end

--- @author DemiAutomatic
--- @method remember
--- @description Records the revision and position a successful write stored.
--- @param player {Player}
--- @param revision {integer} Revision read before the write started.
local function remember(player, revision)
	local position = player.PlayerData.position
	lastWritten[player.PlayerData.citizenId] = {
		revision = revision,
		position = position and { x = position.x, y = position.y, z = position.z } or nil,
	}
end

--- @author DemiAutomatic
--- @method autosave
--- @description Writes every loaded character whose row would come out different.
local function autosave()
	local players = OPX.GetPlayers()
	local written = 0

	for i = 1, #players do
		local player = players[i]
		if needsWriting(player) then
			local revision = player.Revision
			local saved = OPX.Save(player, false)
			if saved.ok then
				remember(player, revision)
				written = written + 1
			end
		end
	end

	if written > 0 then
		Open77.log.debug(('[loops] autosave wrote %d of %d character(s)')
			:format(written, #players))
	end
end

--- @author DemiAutomatic
--- @type {string}
--- @description The money type a salary lands in, resolved once at load.
local PAYCHECK_TYPE = OPX.Config.SERVER.MONEY.PAYCHECK_TYPE
if not OPX.IsMoneyType(PAYCHECK_TYPE) then
	Open77.log.warn(('[loops] MONEY.PAYCHECK_TYPE %s is not a money type; paying into %s')
		:format(tostring(PAYCHECK_TYPE), OPX.Config.SHARED.MONEY.DEFAULT))
	PAYCHECK_TYPE = OPX.Config.SHARED.MONEY.DEFAULT
end

--- @author DemiAutomatic
--- @method paycheck
--- @description Pays every eligible character their grade payment.
local function paycheck()
	local players = OPX.GetPlayers()
	local requireDuty = OPX.Tune.PAYCHECK_REQUIRES_DUTY

	for i = 1, #players do
		local player = players[i]
		local job = player.PlayerData.job
		local definition = OPX.GetJob(job.name)
		local payment = math.floor(job.payment or 0)

		local eligible = payment > 0
			and (not requireDuty or job.onDuty or (definition and definition.offDutyPay))

		if eligible then
			if OPX.Hooks.trigger('paycheck:before', { player = player, amount = payment }) then
				if OPX.AddMoney(player, PAYCHECK_TYPE, payment, 'paycheck:' .. job.name) then
					OPX.NotifyLocale(player.PlayerData.source, 'money.paycheck',
						{ amount = payment, type = PAYCHECK_TYPE, job = job.label }, 'success')
					TriggerEvent(OPX.Events.Internal.PAYCHECK,
						player.PlayerData.source, payment, job.name)
				end
			end
		end
	end
end

--- @author DemiAutomatic
--- @method prune
--- @description Forgets the write tracking of characters nobody is playing.
local function prune()
	for citizenId in pairs(lastWritten) do
		if not OPX.PlayerRegistry.byCitizenId[citizenId] then
			lastWritten[citizenId] = nil
		end
	end
end

--- @author DemiAutomatic
--- @type {integer|nil}
--- @description When the next autosave, paycheck and prune are due.
local nextSaveAt, nextPaycheckAt, nextPruneAt

--- @author DemiAutomatic
--- @method tick
--- @description Runs one pass: sampling, autosave, paychecks and pruning.
local function tick()
	local sampled, sampleError = pcall(function()
		for _, player in pairs(OPX.Players) do
			OPX.SamplePosition(player)
		end
	end)
	if not sampled then
		Open77.log.error('[loops] position sampling raised: ' .. tostring(sampleError))
	end

	local now = OPX.Now()

	if now >= nextSaveAt then
		nextSaveAt = now + OPX.TuneNumber('AUTOSAVE_SECONDS', 30) * 1000
		local ok, err = pcall(autosave)
		if not ok then Open77.log.error('[loops] autosave raised: ' .. tostring(err)) end
	end

	local paycheckMinutes = OPX.TuneNumber('PAYCHECK_MINUTES', 0)
	if paycheckMinutes > 0 and now >= nextPaycheckAt then
		nextPaycheckAt = now + paycheckMinutes * 60000
		local ok, err = pcall(paycheck)
		if not ok then Open77.log.error('[loops] paycheck raised: ' .. tostring(err)) end
	end

	if now >= nextPruneAt then
		nextPruneAt = now + 300000
		prune()
	end
end

CreateThread(function()
	nextSaveAt = OPX.Now() + OPX.TuneNumber('AUTOSAVE_SECONDS', 30) * 1000
	nextPaycheckAt = OPX.Now() + math.max(OPX.TuneNumber('PAYCHECK_MINUTES', 0), 1) * 60000
	nextPruneAt = OPX.Now() + 300000

	while true do
		Wait(SAMPLE_MS)

		if not OPX.BootError then
			local ok, err = pcall(tick)
			if not ok then Open77.log.error('[loops] the background pass raised: ' .. tostring(err)) end
		end
	end
end)

--- @author DemiAutomatic
--- @event onResourceStop
--- @description Dispatches a best-effort save of every character when the core stops.
--- @param name {string}
AddEventHandler('onResourceStop', function(name)
	if name ~= GetCurrentResourceName() then return end
	local players = OPX.GetPlayers()

	for i = 1, #players do
		local player = players[i]
		CreateThread(function() OPX.Save(player, false) end)
	end

	Open77.log.info(('[loops] stopping: dispatched a save for %d character(s), best effort')
		:format(#players))
end)
