--- @author DemiAutomatic
--- @file server/commands.lua
--- @description The core's commands and their chat autocomplete suggestions.

--- @author DemiAutomatic
--- @type {table[]}
--- @description Every registered command in order, with its ACL gate.
local registered = {}

--- @author DemiAutomatic
--- @method register
--- @description Registers a command and remembers its name and gate.
--- @param name {string}
--- @param handler {fun(source: integer, args: table, raw: string)}
--- @param restricted {boolean}
local function register(name, handler, restricted)
	RegisterCommand(name, handler, restricted)
	registered[#registered + 1] = { name = name, restricted = restricted }
end

--- @author DemiAutomatic
--- @method requirePlayer
--- @description Answers the caller's loaded Player, or tells them they have none.
--- @param source {integer}
--- @param raw {string}
--- @returns {Player|nil}
local function requirePlayer(source, raw)
	local player = OPX.GetPlayer(source)
	if not player then
		OPX.CommandNotice(source, raw, 'error', locale('error.notLoggedIn'))
		return nil
	end
	return player
end

--- @author DemiAutomatic
--- @method targetOf
--- @description Resolves a player id or citizen id argument to a loaded Player.
--- @param argument {string|nil} Nil falls back to the caller.
--- @param fallbackSource {integer}
--- @returns {Player|nil}
local function targetOf(argument, fallbackSource)
	if argument == nil then return OPX.GetPlayer(fallbackSource) end
	local asId = tonumber(argument)
	if asId then return OPX.GetPlayer(asId) end
	local parsed = OPX.CitizenId.parse(argument)
	if not parsed.ok then return nil end
	return OPX.GetPlayerByCitizenId(parsed.value)
end

--- @author DemiAutomatic
--- @method tooFast
--- @description Refuses and answers a caller still inside a command's cooldown.
--- @param source {integer}
--- @param raw {string}
--- @param key {string} The wire doorway's request key.
--- @param everyMs {integer}
--- @returns {boolean}
local function tooFast(source, raw, key, everyMs)
	if not OPX.Cooling(source, key, everyMs) then return false end
	OPX.CommandNotice(source, raw, 'warning', locale('error.tooFast'))
	return true
end

--- @author DemiAutomatic
--- @method failureText
--- @description Renders a failed Result as catalogue text, logging a hidden cause.
--- @param failed {Result}
--- @param withDetail {boolean} Appends the detail of a catalogue code.
--- @returns {string}
local function failureText(failed, withDetail)
	local key = OPX.RefusalKey(failed.error)
	if key ~= failed.error then
		Open77.log.warn(('[commands] %s: %s'):format(tostring(failed.error), tostring(failed.detail)))
		return locale(key)
	end
	if withDetail and failed.detail ~= nil then
		return ('%s (%s)'):format(locale(key), tostring(failed.detail))
	end
	return locale(key)
end

--- @author DemiAutomatic
--- @command /opx77
--- @description Lists who is in the world and the boot state.
register('opx77', function(source, _, raw)
	local players = OPX.GetPlayers()
	table.sort(players, function(a, b) return a.PlayerData.source < b.PlayerData.source end)
	local lines = {
		('opx77_core %s -- %d character(s) in the world, %d session(s) connected')
			:format(OPX.VERSION, #players, OPX.Table.count(OPX.Sessions)),
	}
	if OPX.BootError then
		lines[#lines + 1] = ('  DEGRADED: %s'):format(OPX.BootError)
	end
	for i = 1, #players do
		local data = players[i].PlayerData
		lines[#lines + 1] = ('  %-4d %-10s %s %s  %s')
			:format(data.source, data.citizenId,
				data.charInfo.firstName or '?', data.charInfo.lastName or '?',
				data.job.label or '?')
	end
	OPX.CommandResult(source, raw, true, table.concat(lines, '\n'))
end, true)

--- @author DemiAutomatic
--- @command /opx77.where
--- @description Reports everything the server holds on one player.
register('opx77.where', function(source, args, raw)
	local target = tonumber(args[1]) or source
	local session = OPX.Sessions[target]
	if not session then
		return OPX.CommandNotice(source, raw, 'warning', locale('command.noSession', { id = target }))
	end

	local player = OPX.GetPlayer(target)
	local position = Open77.players.position(target)
	local life = Open77.players.getLifeState(target)

	local lines = {
		('player %d  user=%s  name=%s'):format(target, tostring(session.userId), session.displayName),
		('  character : %s'):format(player and player.PlayerData.citizenId or 'none loaded'),
		('  gate      : %s'):format(session.gateSession and 'held' or 'released'),
		('  life      : %s'):format(life and life.phase or 'unreadable'),
		('  position  : %s'):format(position
			and ('%.1f %.1f %.1f  bucket=%d'):format(position.x, position.y, position.z,
				position.bucket or 0)
			or 'unreadable'),
	}
	if player then
		local data = player.PlayerData
		lines[#lines + 1] = ('  job       : %s %s')
			:format(data.job.name, data.job.onDuty and '(on duty)' or '')
		lines[#lines + 1] = ('  gang      : %s'):format(data.gang.name)
		local moneyTypes = {}
		for moneyType in pairs(data.money) do moneyTypes[#moneyTypes + 1] = moneyType end
		table.sort(moneyTypes)
		for i = 1, #moneyTypes do
			lines[#lines + 1] = ('  %-10s: %d'):format(moneyTypes[i], data.money[moneyTypes[i]])
		end
	end
	OPX.CommandResult(source, raw, true, table.concat(lines, '\n'))
end, true)

--- @author DemiAutomatic
--- @command /opx77.here
--- @description Prints the caller's position as a DEFAULT_SPAWN block.
register('opx77.here', function(source, _, raw)
	if source <= 0 then
		return OPX.CommandResult(source, raw, false, 'opx77.here must be run in game')
	end
	local position = Open77.players.position(source)
	if not position then
		return OPX.CommandNotice(source, raw, 'error', locale('command.positionUnreadable'))
	end

	local player = OPX.GetPlayer(source)
	local heading = player and player.PlayerData.reportedHeading or 0.0
	OPX.CommandResult(source, raw, true, ([[
DEFAULT_SPAWN = {
  SET = true,
  X = %.2f,
  Y = %.2f,
  Z = %.2f,
  HEADING = %.2f,
},]]):format(position.x, position.y, position.z, heading))
end, true)

--- @author DemiAutomatic
--- @command /opx77.whois
--- @description Reports a player's account id and display name.
register('opx77.whois', function(source, args, raw)
	local target = tonumber(args[1]) or source
	local session = OPX.Sessions[target]
	if not session then
		return OPX.CommandNotice(source, raw, 'warning', locale('command.noSession', { id = target }))
	end
	OPX.CommandResult(source, raw, true,
		('player %d  user=%s  name=%s'):format(target, session.userId, session.displayName))
end, true)

--- @author DemiAutomatic
--- @command /opx77.characters
--- @description Lists the caller's characters and resends their roster.
register('opx77.characters', function(source, _, raw)
	if source <= 0 then
		return OPX.CommandNotice(source, raw, 'error', locale('command.inGameOnly'))
	end
	if tooFast(source, raw, 'ready', 2000) then return end
	CreateThread(function()
		local sent = OPX.SendCharacters(source)
		if not sent.ok then
			return OPX.CommandNotice(source, raw, 'error', locale(OPX.RefusalKey(sent.error)))
		end
		local lines = { locale('command.characterCount', { count = #sent.value }) }
		for i = 1, #sent.value do
			local character = sent.value[i]
			lines[#lines + 1] = ('  %-10s %s %s')
				:format(character.citizenId, character.firstName, character.lastName)
		end
		OPX.CommandResult(source, raw, true, table.concat(lines, '\n'))
	end)
end, false)

--- @author DemiAutomatic
--- @command /opx77.select
--- @description Enters the world as one of the caller's characters.
register('opx77.select', function(source, args, raw)
	if source <= 0 or not args[1] then
		return OPX.CommandNotice(source, raw, 'warning', locale('command.usage.select'))
	end
	if tooFast(source, raw, 'select.request', 1000) then return end
	CreateThread(function()
		local selected = OPX.SelectCharacter(source, args[1])
		OPX.CommandNotice(source, raw, selected.ok and 'success' or 'error',
			selected.ok and locale('command.entered',
				{ citizenId = selected.value.PlayerData.citizenId })
				or locale(OPX.RefusalKey(selected.error)))
	end)
end, false)

--- @author DemiAutomatic
--- @command /opx77.create
--- @description Creates a character on the caller's account.
register('opx77.create', function(source, args, raw)
	if source <= 0 or not (args[1] and args[2]) then
		return OPX.CommandNotice(source, raw, 'warning', locale('command.usage.create'))
	end
	if tooFast(source, raw, 'create.request', 1000) then return end
	CreateThread(function()
		local created = OPX.CreateCharacter(source, {
			firstName = args[1],
			lastName = args[2],
			origin = args[3] or 'streetkid',
			gender = args[4] or 'female',
			birthDate = args[5],
		})
		OPX.CommandNotice(source, raw, created.ok and 'success' or 'error',
			created.ok and locale('character.created', { citizenId = created.value.citizenId })
				or locale(OPX.RefusalKey(created.error), { max = created.detail }))
	end)
end, false)

--- @author DemiAutomatic
--- @command /opx77.delete
--- @description Soft-deletes one of the caller's characters.
register('opx77.delete', function(source, args, raw)
	if source <= 0 or not args[1] then
		return OPX.CommandNotice(source, raw, 'warning', locale('command.usage.delete'))
	end
	if tooFast(source, raw, 'delete.request', 1000) then return end
	CreateThread(function()
		local deleted = OPX.DeleteCharacter(source, args[1])
		OPX.CommandNotice(source, raw, deleted.ok and 'success' or 'error',
			deleted.ok and locale('character.deleted') or locale(OPX.RefusalKey(deleted.error)))
	end)
end, false)

--- @author DemiAutomatic
--- @command /opx77.duty
--- @description Clocks the caller in or out of their primary job.
register('opx77.duty', function(source, _, raw)
	local src = tonumber(source) or 0
	if src > 0 and OPX.Cooling(src, 'duty', 2000) then
		return OPX.CommandNotice(src, raw, 'warning', locale('error.tooFast'))
	end
	local player = requirePlayer(source, raw)
	if not player then return end
	CreateThread(function()
		local toggled = OPX.SetJobDuty(player, not player.PlayerData.job.onDuty)
		OPX.CommandNotice(source, raw, toggled.ok and 'success' or 'error',
			toggled.ok and (toggled.value and locale('job.onDuty') or locale('job.offDuty'))
				or locale(OPX.RefusalKey(toggled.error)), toggled.ok)
	end)
end, false)

--- @author DemiAutomatic
--- @command /opx77.money
--- @description Gives a loaded character money, or takes it, audited.
register('opx77.money', function(source, args, raw)
	local target = targetOf(args[1], source)
	local moneyType = args[2] and args[2]:upper()
	local amount = tonumber(args[3])
	if not target or not moneyType or not amount then
		return OPX.CommandNotice(source, raw, 'warning', locale('command.usage.money'))
	end

	local reason = ('staff command by %s'):format(tostring(source))

	local ok, why
	if amount >= 0 then
		ok, why = OPX.AddMoney(target, moneyType, amount, reason)
	else
		ok, why = OPX.RemoveMoney(target, moneyType, -amount, reason)
	end

	OPX.CommandNotice(source, raw, ok and 'success' or 'error', ok
		and locale('command.moneySet', { citizenId = target.PlayerData.citizenId,
			amount = OPX.FormatMoney(target.PlayerData.money[moneyType] or 0, moneyType) })
		or locale(why or 'error.badRequest', { type = moneyType }))
end, true)

--- @author DemiAutomatic
--- @command /opx77.job
--- @description Sets a character's primary job and grade.
register('opx77.job', function(source, args, raw)
	local target = targetOf(args[1], source)
	if not target or not args[2] then
		return OPX.CommandNotice(source, raw, 'warning', locale('command.usage.job'))
	end
	CreateThread(function()
		local set = OPX.SetJob(target, args[2], tonumber(args[3]) or 0)
		OPX.CommandNotice(source, raw, set.ok and 'success' or 'error',
			set.ok and locale('command.jobSet', { citizenId = target.PlayerData.citizenId,
				grade = set.value.grade.name, job = set.value.label })
				or failureText(set, true))
	end)
end, true)

--- @author DemiAutomatic
--- @command /opx77.gang
--- @description Sets a character's primary gang and grade.
register('opx77.gang', function(source, args, raw)
	local target = targetOf(args[1], source)
	if not target or not args[2] then
		return OPX.CommandNotice(source, raw, 'warning', locale('command.usage.gang'))
	end
	CreateThread(function()
		local set = OPX.SetGang(target, args[2], tonumber(args[3]) or 0)
		OPX.CommandNotice(source, raw, set.ok and 'success' or 'error',
			set.ok and locale('command.gangSet', { citizenId = target.PlayerData.citizenId,
				grade = set.value.grade.name, gang = set.value.label })
				or failureText(set, true))
	end)
end, true)

--- @author DemiAutomatic
--- @command /opx77.group
--- @description Lists the members of a job or a gang.
register('opx77.group', function(source, args, raw)
	local groupType, name = args[1], args[2]
	if groupType ~= 'job' and groupType ~= 'gang' or not name then
		return OPX.CommandNotice(source, raw, 'warning', locale('command.usage.group'))
	end
	CreateThread(function()
		local members = OPX.GetGroupMembers(groupType, name)
		if not members.ok then
			return OPX.CommandNotice(source, raw, 'error', failureText(members, false))
		end
		local lines = { ('%s %s -- %d member(s)'):format(groupType, name, #members.value) }
		for i = 1, #members.value do
			local member = members.value[i]
			lines[#lines + 1] = ('  %-10s grade %d  %s')
				:format(member.citizenId, member.grade, member.name)
		end
		OPX.CommandResult(source, raw, true, table.concat(lines, '\n'))
	end)
end, true)

--- @author DemiAutomatic
--- @command /opx77.save
--- @description Writes every loaded character back to the database now.
register('opx77.save', function(source, _, raw)
	CreateThread(function()
		local players = OPX.GetPlayers()
		local saved = 0
		for i = 1, #players do
			if OPX.Save(players[i]).ok then saved = saved + 1 end
		end
		OPX.CommandNotice(source, raw, 'success',
			locale('command.saved', { saved = saved, total = #players }))
	end)
end, true)

--- @author DemiAutomatic
--- @type {table}
--- @description Suggestion parameter for a player id or citizen id.
local TARGET = { name = 'playerId|citizenId', help = 'command.param.target' }
--- @author DemiAutomatic
--- @type {table}
--- @description Optional suggestion parameter for a player id, defaulting to self.
local PLAYER_OR_SELF = { name = 'playerId', help = 'command.param.playerSelf', optional = true }
--- @author DemiAutomatic
--- @type {table}
--- @description Suggestion parameter for one of the caller's citizen ids.
local OWN_CITIZEN = { name = 'citizenId', help = 'command.param.ownCitizenId' }
--- @author DemiAutomatic
--- @type {table}
--- @description Optional suggestion parameter for a grade level.
local GRADE = { name = 'grade', help = 'command.param.grade', optional = true }

--- @author DemiAutomatic
--- @type {table<string, table>}
--- @description Help and parameter catalogue keys shown while typing, per command.
local HELP = {
	['opx77'] = { text = 'command.help.opx77' },
	['opx77.where'] = { text = 'command.help.where', params = { PLAYER_OR_SELF } },
	['opx77.here'] = { text = 'command.help.here' },
	['opx77.whois'] = { text = 'command.help.whois', params = { PLAYER_OR_SELF } },
	['opx77.characters'] = { text = 'command.help.characters' },
	['opx77.select'] = { text = 'command.help.select', params = { OWN_CITIZEN } },
	['opx77.create'] = { text = 'command.help.create', params = {
		{ name = 'firstName', help = 'command.param.name' },
		{ name = 'lastName', help = 'command.param.name' },
		{ name = 'nomad|streetkid|corpo', help = 'command.param.origin', optional = true },
		{ name = 'female|male', help = 'command.param.gender', optional = true },
		{ name = 'YYYY-MM-DD', help = 'command.param.birthDate', optional = true },
	} },
	['opx77.delete'] = { text = 'command.help.delete', params = { OWN_CITIZEN } },
	['opx77.duty'] = { text = 'command.help.duty' },
	['opx77.money'] = { text = 'command.help.money', params = {
		TARGET,
		{ name = 'TYPE', help = 'command.param.moneyType' },
		{ name = 'amount', help = 'command.param.amount' },
	} },
	['opx77.job'] = { text = 'command.help.job', params = {
		TARGET, { name = 'job', help = 'command.param.job' }, GRADE,
	} },
	['opx77.gang'] = { text = 'command.help.gang', params = {
		TARGET, { name = 'gang', help = 'command.param.gang' }, GRADE,
	} },
	['opx77.group'] = { text = 'command.help.group', params = {
		{ name = 'job|gang', help = 'command.param.groupType' },
		{ name = 'name', help = 'command.param.groupName' },
	} },
	['opx77.save'] = { text = 'command.help.save' },
}

--- @author DemiAutomatic
--- @method permitted
--- @description Answers whether the host ACL grants a player a command.
--- @param player {integer}
--- @param name {string}
--- @returns {boolean}
local function permitted(player, name)
	local read, allowed = pcall(Open77.acl.isAllowed, player, 'command.' .. name)
	return read and allowed == true
end

--- @author DemiAutomatic
--- @method helpValues
--- @description Builds the placeholder values the parameter help lines fill in.
--- @returns {table<string, string|number>}
local function helpValues()
	local shared = OPX.Config.SHARED
	local types = {}
	for moneyType in pairs(shared.MONEY.TYPES) do types[#types + 1] = tostring(moneyType) end
	table.sort(types)
	local bounds = shared.CHARACTERS.NAME
	return { types = table.concat(types, ', '), min = bounds.MIN, max = bounds.MAX }
end

--- @author DemiAutomatic
--- @event chat:ready
--- @description Sends the chat the commands this player may run.
RegisterNetEvent('chat:ready', function()
	local src = tonumber(source)
	if not src or src <= 0 then return end
	if OPX.Cooling(src, 'chat_suggestions', 10000) then return end

	local values = helpValues()
	local suggestions = {}
	for i = 1, #registered do
		local command = registered[i]
		if not command.restricted or permitted(src, command.name) then
			local help = HELP[command.name] or {}
			local params = help.params or {}
			local parameters = {}
			for position = 1, #params do
				local parameter = params[position]
				parameters[position] = {
					name = parameter.name,
					help = parameter.help and locale(parameter.help, values) or nil,
					optional = parameter.optional == true or nil,
				}
			end
			suggestions[#suggestions + 1] = {
				command = '/' .. command.name,
				help = help.text and locale(help.text) or '',
				parameters = parameters,
			}
		end
	end
	TriggerClientEvent('chat:addSuggestions', src, suggestions)
end)
