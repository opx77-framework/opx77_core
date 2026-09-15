--- @author DemiAutomatic
--- @file client/events.lua
--- @description Server-to-client handlers that mirror state, then fire local events.

--- @author DemiAutomatic
--- @type {table}
--- @description The event name tables published on OPX.Events.
local Events = OPX.Events

--- @author DemiAutomatic
--- @type {table<string, string>}
--- @description The local event names fired after the mirror is updated.
local Local = Events.Local

--- @author DemiAutomatic
--- @event opx77:client:characters
--- @description Stores the roster the server sent and fires charactersReady.
--- @param payload {any}
RegisterNetEvent(Events.Client.CHARACTERS, function(payload)
	if type(payload) ~= 'table' then return end

	local list = type(payload.characters) == 'table' and payload.characters or {}
	local slots = tonumber(payload.slots)
	slots = OPX.Math.isFinite(slots) and math.floor(slots) or 0
	if slots < 0 then slots = 0 end

	OPX.Characters.list = list
	OPX.Characters.slots = slots
	OPX.Characters.origins = type(payload.origins) == 'table' and payload.origins or {}

	Open77.log.info(('[events] %d character(s) available, %d slot(s)'):format(#list, slots))
	TriggerEvent(Local.CHARACTERS_READY, OPX.Characters)
end)

--- @author DemiAutomatic
--- @event opx77:client:playerLoaded
--- @description Mirrors the loaded character and fires onPlayerLoaded.
--- @param playerData {any}
RegisterNetEvent(Events.Client.PLAYER_LOADED, function(playerData)
	if type(playerData) ~= 'table' then return end
	OPX.PlayerData = playerData
	OPX.IsLoggedIn = true

	Open77.log.info(('[events] loaded %s (%s %s)'):format(
		tostring(playerData.citizenId),
		tostring(playerData.charInfo and playerData.charInfo.firstName),
		tostring(playerData.charInfo and playerData.charInfo.lastName)))
	TriggerEvent(Local.PLAYER_LOADED, playerData)
end)

--- @author DemiAutomatic
--- @event opx77:client:playerUnloaded
--- @description Empties the mirror and fires onPlayerUnloaded.
RegisterNetEvent(Events.Client.PLAYER_UNLOADED, function()
	OPX.PlayerData = {}
	OPX.IsLoggedIn = false
	TriggerEvent(Local.PLAYER_UNLOADED)
end)

--- @author DemiAutomatic
--- @event opx77:client:setPlayerData
--- @description Replaces the mirrored PlayerData whole and fires playerDataChanged.
--- @param playerData {any}
RegisterNetEvent(Events.Client.SET_PLAYER_DATA, function(playerData)
	if type(playerData) ~= 'table' then return end
	OPX.PlayerData = playerData
	TriggerEvent(Local.PLAYER_DATA_CHANGED, playerData)
end)

--- @author DemiAutomatic
--- @event opx77:client:onMoneyChange
--- @description Mirrors a new balance and fires moneyChanged.
--- @param moneyType {string}
--- @param amount {integer}
--- @param action {string}
--- @param balance {integer}
RegisterNetEvent(Events.Client.MONEY_CHANGE, function(moneyType, amount, action, balance)
	if OPX.PlayerData.money then OPX.PlayerData.money[moneyType] = balance end
	TriggerEvent(Local.MONEY_CHANGED, moneyType, amount, action, balance)
end)

--- @author DemiAutomatic
--- @event opx77:client:onJobUpdate
--- @description Mirrors the primary job and fires jobChanged.
--- @param job {PlayerJob}
RegisterNetEvent(Events.Client.JOB_UPDATE, function(job)
	OPX.PlayerData.job = job
	TriggerEvent(Local.JOB_CHANGED, job)
end)

--- @author DemiAutomatic
--- @event opx77:client:onGangUpdate
--- @description Mirrors the primary gang and fires gangChanged.
--- @param gang {PlayerGang}
RegisterNetEvent(Events.Client.GANG_UPDATE, function(gang)
	OPX.PlayerData.gang = gang
	TriggerEvent(Local.GANG_CHANGED, gang)
end)

--- @author DemiAutomatic
--- @event opx77:client:onAppearanceUpdate
--- @description Mirrors a newly stored face and fires appearanceSaved.
--- @param snapshot {any}
RegisterNetEvent(Events.Client.APPEARANCE_UPDATE, function(snapshot)
	if type(snapshot) ~= 'table' then return end
	OPX.PlayerData.appearance = snapshot
	TriggerEvent(Local.APPEARANCE_SAVED, snapshot)
end)

--- @author DemiAutomatic
--- @event opx77:client:onClothingUpdate
--- @description Mirrors newly stored clothing and fires clothingSaved.
--- @param record {any}
RegisterNetEvent(Events.Client.CLOTHING_UPDATE, function(record)
	if type(record) ~= 'table' then return end
	OPX.PlayerData.clothing = record
	TriggerEvent(Local.CLOTHING_SAVED, record)
end)

--- @author DemiAutomatic
--- @event opx77:client:notify
--- @description Logs a server refusal and fires refused with code and operation.
--- @param payload {any}
RegisterNetEvent(Events.Client.NOTIFY, function(payload)
	if type(payload) ~= 'table' then return end
	Open77.log.warn(('[events] server refused %s: %s')
		:format(tostring(payload.operation), tostring(payload.code)))
	TriggerEvent(Local.REFUSED, payload.code, payload.kind, payload.operation)
end)

--- @author DemiAutomatic
--- @type {string}
--- @description The toast resource command answers are raised through.
local NOTIFY = 'opx77_notify'

--- @author DemiAutomatic
--- @type {boolean}
--- @description Whether a failed toast has already been logged once.
local toastReported = false

--- @author DemiAutomatic
--- @method answerLine
--- @description Writes a command answer as a chat line.
--- @param kind {string}
--- @param message {string}
local function answerLine(kind, message)
	local accepted = kind == 'success'
	TriggerEvent('chat:addMessage', {
		type = accepted and 'info' or 'error',
		author = OPX.Config.SHARED.SERVER_NAME,
		text = message,
		color = accepted and { 120, 220, 232 } or { 255, 76, 92 },
	})
end

--- @author DemiAutomatic
--- @method toast
--- @description Raises a toast through opx77_notify, answering the failure reason or nil.
--- @param definition {table}
--- @returns {string|nil}
local function toast(definition)
	if GetResourceState(NOTIFY) ~= 'running' then return 'not_running' end
	local dispatched, promise, reason = pcall(Open77.exports.call, NOTIFY, 'show', definition)
	if not dispatched then return tostring(promise) end
	if not promise then return tostring(reason or 'not_dispatched') end
	local result, callError = promise:await()
	if callError then return tostring(callError) end
	if type(result) ~= 'table' then return 'malformed_answer' end
	if result.ok == false then return tostring(result.error or 'refused') end
	return nil
end

--- @author DemiAutomatic
--- @event opx77:client:commandAnswer
--- @description Shows a command answer as a toast, or as a chat line.
--- @param raw {string}
--- @param kind {string}
--- @param message {string}
--- @param toasted {boolean|nil}
RegisterNetEvent(Events.Client.ANSWER, function(raw, kind, message, toasted)
	if type(raw) ~= 'string' or type(message) ~= 'string' or message == '' then return end
	if kind ~= 'success' and kind ~= 'warning' and kind ~= 'error' then kind = 'error' end
	CreateThread(function()
		if toasted == true then
			if GetResourceState(NOTIFY) ~= 'running' then answerLine(kind, message) end
			return
		end
		local failure = toast({
			id = 'opx77_core.command',
			replace = true,
			type = kind,
			title = OPX.Config.SHARED.SERVER_NAME,
			message = message,
			durationMs = 5000,
			position = OPX.Config.SHARED.NOTIFY_POSITION,
		})
		if failure == nil then return end
		if not toastReported then
			toastReported = true
			Open77.log.warn(('[events] no toast (%s): command answers go to the chat box instead')
				:format(failure))
		end
		answerLine(kind, message)
	end)
end)
