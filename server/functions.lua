--- @author DemiAutomatic
--- @file server/functions.lua
--- @description Non-yielding getters, answers, refusals and per-player cooldowns.

--- @author DemiAutomatic
--- @type {table}
--- @description The shared Result constructors.
local Result = OPX.Result

--- @author DemiAutomatic
--- @method OPX.GetPlayer
--- @description Answers the loaded character at a player id, or nil.
--- @param source {Source|string}
--- @returns {Player|nil}
function OPX.GetPlayer(source)
	return OPX.Players[tonumber(source) or -1]
end

--- @author DemiAutomatic
--- @method OPX.GetPlayerByCitizenId
--- @description Answers the loaded character carrying a citizen id, or nil.
--- @param citizenId {CitizenId}
--- @returns {Player|nil}
function OPX.GetPlayerByCitizenId(citizenId)
	local source = OPX.PlayerRegistry.byCitizenId[citizenId]
	return source and OPX.Players[source] or nil
end

--- @author DemiAutomatic
--- @method OPX.GetPlayerByUserId
--- @description Answers the loaded character of an account, or nil.
--- @param userId {UserId}
--- @returns {Player|nil}
function OPX.GetPlayerByUserId(userId)
	local source = OPX.PlayerRegistry.byUserId[userId]
	return source and OPX.Players[source] or nil
end

--- @author DemiAutomatic
--- @method OPX.GetPlayers
--- @description Lists every loaded character, evicting slots whose account changed.
--- @returns {Player[]}
function OPX.GetPlayers()
	local out, n = {}, 0
	local stale, staleCount = nil, 0

	for source, player in pairs(OPX.Players) do
		if OPX.UserIdOf(source) == player.PlayerData.userId then
			n = n + 1
			out[n] = player
		else
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

--- @author DemiAutomatic
--- @method OPX.GetPlayerCount
--- @description Counts the characters in the world without building a table.
--- @returns {integer}
function OPX.GetPlayerCount()
	local n = 0
	for source, player in pairs(OPX.Players) do
		if OPX.UserIdOf(source) == player.PlayerData.userId then n = n + 1 end
	end
	return n
end

--- @author DemiAutomatic
--- @method OPX.GetCharacter
--- @description Answers a character online, or its stored entity when offline.
--- @param citizenId {CitizenId}
--- @returns {Result}
function OPX.GetCharacter(citizenId)
	local online = OPX.GetPlayerByCitizenId(citizenId)
	if online then return Result.ok({ player = online, offline = false }) end

	local fetched = OPX.Storage.Players.fetchOne(citizenId)
	if not fetched.ok then return fetched end
	return Result.ok({ entity = fetched.value, offline = true })
end

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds an identical answer to one player is suppressed.
local ANSWER_DEDUPE_MS = 2000

--- @author DemiAutomatic
--- @type {table<integer, table<string, integer>>}
--- @description When each answer text last went to each player.
local lastAnswer = {}

--- @author DemiAutomatic
--- @method repeated
--- @description Answers whether this exact text just went to this player.
--- @param source {integer}
--- @param text {string}
--- @returns {boolean}
local function repeated(source, text)
	local bucket = lastAnswer[source]
	if not bucket then
		bucket = {}
		lastAnswer[source] = bucket
	end
	local now = OPX.Now()
	if bucket[text] and now - bucket[text] < ANSWER_DEDUPE_MS then return true end
	local count = 0
	for _ in pairs(bucket) do count = count + 1 end
	if count >= 32 then bucket = {}; lastAnswer[source] = bucket end
	bucket[text] = now
	return false
end

--- @author DemiAutomatic
--- @method OPX.Notify
--- @description Sends a toast through the host notifications, when one draws them.
--- @param source {Source}
--- @param message {string}
--- @param kind {string|nil} info, success, warning or error.
--- @param durationMs {integer|nil}
function OPX.Notify(source, message, kind, durationMs)
	source = tonumber(source)
	if not source or source <= 0 then return end
	if repeated(source, 'notify:' .. tostring(kind) .. ':' .. tostring(message)) then return end

	local api = Open77.notifications
	if not api or type(api.send) ~= 'function' then return end

	api.send(source, {
		type = kind or 'info',
		title = OPX.Config.SHARED.SERVER_NAME,
		message = message,
		durationMs = durationMs or 5000,
		position = OPX.Config.SHARED.NOTIFY_POSITION,
	})
end

--- @author DemiAutomatic
--- @method OPX.RefusalKey
--- @description Answers the code when the catalogue carries it, else error.unavailable.
--- @param code {any}
--- @returns {string}
function OPX.RefusalKey(code)
	if type(code) == 'string' and OPX.Locale.exists(code) then return code end
	Open77.log.warn(('[core] %q has no catalogue entry; answering error.unavailable')
		:format(tostring(code)))
	return 'error.unavailable'
end

--- @author DemiAutomatic
--- @method OPX.NotifyLocale
--- @description Sends a toast rendered from a locale key.
--- @param source {Source}
--- @param key {string}
--- @param params {table<string, string|number>|nil}
--- @param kind {string|nil}
function OPX.NotifyLocale(source, key, params, kind)
	OPX.Notify(source, locale(OPX.RefusalKey(key), params), kind)
end

--- @author DemiAutomatic
--- @method OPX.CommandResult
--- @description Answers a command report as a chat line, or prints it.
--- @param source {Source|nil} Nil or 0 prints to the console.
--- @param raw {string|nil}
--- @param accepted {boolean}
--- @param message {string}
function OPX.CommandResult(source, raw, accepted, message)
	if source and source > 0 then
		TriggerClientEvent('chat:addMessage', source, {
			type = accepted and 'info' or 'error',
			author = OPX.Config.SHARED.SERVER_NAME,
			text = message,
			color = accepted and { 120, 220, 232 } or { 255, 76, 92 },
		})
	else
		print(message)
	end
end

--- @author DemiAutomatic
--- @method OPX.CommandNotice
--- @description Answers what a command did through the client half's toast.
--- @param source {Source|nil} Nil or 0 prints to the console.
--- @param raw {string|nil}
--- @param kind {string} success, warning or error.
--- @param message {string}
--- @param toasted {boolean|nil} The action already raised this toast.
function OPX.CommandNotice(source, raw, kind, message, toasted)
	if source and source > 0 then
		TriggerClientEvent(OPX.Events.Client.ANSWER, source, raw or '', kind, message,
			toasted == true)
	else
		print(message)
	end
end

--- @author DemiAutomatic
--- @type {table<integer, table<string, integer>>}
--- @description When each player last ran each cooled operation.
local cooldowns = {}

--- @author DemiAutomatic
--- @method OPX.Cooling
--- @description Answers whether an operation is cooling, recording the attempt otherwise.
--- @param source {Source}
--- @param key {string}
--- @param everyMs {integer}
--- @returns {boolean}
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

--- @author DemiAutomatic
--- @method OPX.ForgetCooldowns
--- @description Drops a departing player's cooldowns and answer windows.
--- @param source {Source}
function OPX.ForgetCooldowns(source)
	source = tonumber(source) or -1
	cooldowns[source] = nil
	lastAnswer[source] = nil
end

--- @author DemiAutomatic
--- @method OPX.Refuse
--- @description Tells a client which request was refused, with a renderable code.
--- @param source {Source}
--- @param code {string} A locale key.
--- @param operation {string|nil} A value of OPX.Operations.
function OPX.Refuse(source, code, operation)
	source = tonumber(source)
	if not source or source <= 0 then return end
	code = OPX.RefusalKey(code)
	operation = type(operation) == 'string' and operation or 'unknown'
	if repeated(source, 'refuse:' .. operation .. ':' .. code) then return end
	TriggerClientEvent(OPX.Events.Client.NOTIFY, source,
		{ kind = 'error', code = code, operation = operation })
end
