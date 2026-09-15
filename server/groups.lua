--- @author DemiAutomatic
--- @file server/groups.lua
--- @description Job and gang memberships, for characters online or offline.

--- @author DemiAutomatic
--- @type {table}
--- @description The shared Result constructors.
local Result = OPX.Result

--- @author DemiAutomatic
--- @type {table<string, string>}
--- @description The one-column statement an offline group change writes, per column.
local SAVE_PRIMARY = {
	job = [[
UPDATE opx77_characters
   SET job = @value
 WHERE citizen_id = @citizen
  ]],
	gang = [[
UPDATE opx77_characters
   SET gang = @value
 WHERE citizen_id = @citizen
  ]],
}

--- @author DemiAutomatic
--- @method withCharacter
--- @description Runs a change against the live Player or a temporary offline one.
--- @param identifier {Player|Source|CitizenId}
--- @param column {string|nil} job or gang; nil touches memberships only.
--- @param apply {fun(player: Player, offline: boolean): Result}
--- @returns {Result}
local function withCharacter(identifier, column, apply)
	local player = OPX.ResolvePlayer(identifier)
	if player then return apply(player, false) end

	if type(identifier) ~= 'string' then
		return Result.err('error.notLoggedIn', tostring(identifier))
	end

	local fetched = OPX.Storage.Players.fetchOne(identifier)
	if not fetched.ok then return fetched end

	local groups = OPX.Storage.Players.fetchGroups(identifier)
	if not groups.ok then return groups end

	player = OPX.ResolvePlayer(identifier)
	if player then return apply(player, false) end

	local offline = OPX.CreatePlayer(fetched.value, true)
	offline.PlayerData.jobs = groups.value.jobs
	offline.PlayerData.gangs = groups.value.gangs

	local outcome = apply(offline, true)
	if not outcome.ok then return outcome end

	player = OPX.ResolvePlayer(identifier)
	if player then
		Open77.log.debug(('[groups] %s came online mid-change; re-applying against the live ' ..
			'player'):format(identifier))
		return apply(player, false)
	end

	if not column then return outcome end

	local saved = OPX.Storage.execute(SAVE_PRIMARY[column], {
		citizen = identifier,
		value = json.encode(offline.PlayerData[column] or {}),
	})
	if not saved.ok then return saved end
	return outcome
end

--- @author DemiAutomatic
--- @method joinGroup
--- @description Writes a membership row, then records it on PlayerData.
--- @param player {Player}
--- @param groupType {GroupType}
--- @param name {string}
--- @param grade {integer}
--- @returns {Result}
local function joinGroup(player, groupType, name, grade)
	local citizenId = player.PlayerData.citizenId
	local written = OPX.Storage.Players.upsertGroup(citizenId, groupType, name, grade)
	if not written.ok then return written end

	local bucket = groupType == 'job' and player.PlayerData.jobs or player.PlayerData.gangs
	bucket[name] = grade
	return Result.ok(true)
end

--- @author DemiAutomatic
--- @method leaveGroup
--- @description Deletes a membership row, then drops it from PlayerData.
--- @param player {Player}
--- @param groupType {GroupType}
--- @param name {string}
--- @returns {Result}
local function leaveGroup(player, groupType, name)
	local citizenId = player.PlayerData.citizenId
	local removed = OPX.Storage.Players.removeGroup(citizenId, groupType, name)
	if not removed.ok then return removed end

	local bucket = groupType == 'job' and player.PlayerData.jobs or player.PlayerData.gangs
	bucket[name] = nil
	return Result.ok(true)
end

--- @author DemiAutomatic
--- @method OPX.SetJob
--- @description Makes a job at a grade the primary one, joining it.
--- @param identifier {Player|Source|CitizenId}
--- @param name {string}
--- @param grade {integer}
--- @returns {Result}
function OPX.SetJob(identifier, name, grade)
	return withCharacter(identifier, 'job', function(player)
		local resolved = OPX.ResolveJob(name, grade)
		if not resolved.ok then return resolved end

		local joined = joinGroup(player, 'job', name, resolved.value.grade.level)
		if not joined.ok then return joined end

		player.PlayerData.job = resolved.value
		player.Functions.UpdatePlayerData()

		if not player.Offline then
			TriggerClientEvent(OPX.Events.Client.JOB_UPDATE, player.PlayerData.source, resolved.value)
		end
		TriggerEvent(OPX.Events.Internal.JOB_UPDATE, player.PlayerData.source, resolved.value)

		OPX.Logger.player(player, 'job.set', ('%s grade %d'):format(name, resolved.value.grade.level))
		return Result.ok(resolved.value)
	end)
end

--- @author DemiAutomatic
--- @method OPX.SetJobDuty
--- @description Clocks a character in or out of their primary job.
--- @param identifier {Player|Source|CitizenId}
--- @param onDuty {boolean}
--- @returns {Result}
function OPX.SetJobDuty(identifier, onDuty)
	return withCharacter(identifier, 'job', function(player)
		local job = player.PlayerData.job
		local definition = OPX.GetJob(job.name)
		if not definition then return Result.err('job.notFound', job.name) end
		if definition.defaultDuty then
			return Result.err('job.noDuty', job.name)
		end

		job.onDuty = onDuty == true
		player.Functions.UpdatePlayerData()

		if not player.Offline then
			TriggerClientEvent(OPX.Events.Client.JOB_UPDATE, player.PlayerData.source, job)
			OPX.NotifyLocale(player.PlayerData.source, job.onDuty and 'job.onDuty' or 'job.offDuty')
		end
		TriggerEvent(OPX.Events.Internal.JOB_UPDATE, player.PlayerData.source, job)
		return Result.ok(job.onDuty)
	end)
end

--- @author DemiAutomatic
--- @method OPX.AddPlayerToJob
--- @description Adds a job membership without changing the primary job.
--- @param identifier {Player|Source|CitizenId}
--- @param name {string}
--- @param grade {integer}
--- @returns {Result}
function OPX.AddPlayerToJob(identifier, name, grade)
	return withCharacter(identifier, nil, function(player)
		local resolved = OPX.ResolveJob(name, grade)
		if not resolved.ok then return resolved end
		local joined = joinGroup(player, 'job', name, resolved.value.grade.level)
		if not joined.ok then return joined end
		player.Functions.UpdatePlayerData()
		return joined
	end)
end

--- @author DemiAutomatic
--- @method OPX.RemovePlayerFromJob
--- @description Removes a job membership, falling back to the default job.
--- @param identifier {Player|Source|CitizenId}
--- @param name {string}
--- @returns {Result}
function OPX.RemovePlayerFromJob(identifier, name)
	return withCharacter(identifier, 'job', function(player)
		local left = leaveGroup(player, 'job', name)
		if not left.ok then return left end

		local announced = false
		if player.PlayerData.job.name == name then
			local fallback = OPX.ResolveJob(OPX.Config.SERVER.PLAYER.DEFAULT_JOB, 0)
			if fallback.ok then
				player.PlayerData.job = fallback.value
				player.Functions.UpdatePlayerData()
				announced = true
				if not player.Offline then
					TriggerClientEvent(OPX.Events.Client.JOB_UPDATE,
						player.PlayerData.source, fallback.value)
				end
			end
		end

		if not announced then player.Functions.UpdatePlayerData() end

		OPX.Logger.player(player, 'job.removed', name)
		return Result.ok(true)
	end)
end

--- @author DemiAutomatic
--- @method OPX.SetPlayerPrimaryJob
--- @description Makes one of a character's existing jobs the primary one.
--- @param identifier {Player|Source|CitizenId}
--- @param name {string}
--- @returns {Result}
function OPX.SetPlayerPrimaryJob(identifier, name)
	return withCharacter(identifier, 'job', function(player)
		local grade = player.PlayerData.jobs[name]
		if grade == nil then return Result.err('job.notMember', name) end
		return OPX.SetJob(player, name, grade)
	end)
end

--- @author DemiAutomatic
--- @method OPX.SetGang
--- @description Makes a gang at a grade the primary one, joining it.
--- @param identifier {Player|Source|CitizenId}
--- @param name {string}
--- @param grade {integer}
--- @returns {Result}
function OPX.SetGang(identifier, name, grade)
	return withCharacter(identifier, 'gang', function(player)
		local resolved = OPX.ResolveGang(name, grade)
		if not resolved.ok then return resolved end

		local joined = joinGroup(player, 'gang', name, resolved.value.grade.level)
		if not joined.ok then return joined end

		player.PlayerData.gang = resolved.value
		player.Functions.UpdatePlayerData()

		if not player.Offline then
			TriggerClientEvent(OPX.Events.Client.GANG_UPDATE, player.PlayerData.source, resolved.value)
		end
		TriggerEvent(OPX.Events.Internal.GANG_UPDATE, player.PlayerData.source, resolved.value)

		OPX.Logger.player(player, 'gang.set', ('%s grade %d'):format(name, resolved.value.grade.level))
		return Result.ok(resolved.value)
	end)
end

--- @author DemiAutomatic
--- @method OPX.AddPlayerToGang
--- @description Adds a gang membership without changing the primary gang.
--- @param identifier {Player|Source|CitizenId}
--- @param name {string}
--- @param grade {integer}
--- @returns {Result}
function OPX.AddPlayerToGang(identifier, name, grade)
	return withCharacter(identifier, nil, function(player)
		local resolved = OPX.ResolveGang(name, grade)
		if not resolved.ok then return resolved end
		local joined = joinGroup(player, 'gang', name, resolved.value.grade.level)
		if not joined.ok then return joined end
		player.Functions.UpdatePlayerData()
		return joined
	end)
end

--- @author DemiAutomatic
--- @method OPX.RemovePlayerFromGang
--- @description Removes a gang membership, falling back to the default gang.
--- @param identifier {Player|Source|CitizenId}
--- @param name {string}
--- @returns {Result}
function OPX.RemovePlayerFromGang(identifier, name)
	return withCharacter(identifier, 'gang', function(player)
		local left = leaveGroup(player, 'gang', name)
		if not left.ok then return left end

		local announced = false
		if player.PlayerData.gang.name == name then
			local fallback = OPX.ResolveGang(OPX.Config.SERVER.PLAYER.DEFAULT_GANG, 0)
			if fallback.ok then
				player.PlayerData.gang = fallback.value
				player.Functions.UpdatePlayerData()
				announced = true
				if not player.Offline then
					TriggerClientEvent(OPX.Events.Client.GANG_UPDATE,
						player.PlayerData.source, fallback.value)
				end
			end
		end

		if not announced then player.Functions.UpdatePlayerData() end

		OPX.Logger.player(player, 'gang.removed', name)
		return Result.ok(true)
	end)
end

--- @author DemiAutomatic
--- @method OPX.SetPlayerPrimaryGang
--- @description Makes one of a character's existing gangs the primary one.
--- @param identifier {Player|Source|CitizenId}
--- @param name {string}
--- @returns {Result}
function OPX.SetPlayerPrimaryGang(identifier, name)
	return withCharacter(identifier, 'gang', function(player)
		local grade = player.PlayerData.gangs[name]
		if grade == nil then return Result.err('gang.notMember', name) end
		return OPX.SetGang(player, name, grade)
	end)
end

--- @author DemiAutomatic
--- @method OPX.GetGroupMembers
--- @description Answers everyone in a job or gang, online or not.
--- @param groupType {GroupType}
--- @param name {string}
--- @returns {Result}
function OPX.GetGroupMembers(groupType, name)
	if groupType ~= 'job' and groupType ~= 'gang' then
		return Result.err('error.badRequest', tostring(groupType))
	end
	return OPX.Storage.Players.membersOf(groupType, name)
end

--- @author DemiAutomatic
--- @method OPX.GetPlayersByJob
--- @description Lists loaded characters whose primary job is the one named.
--- @param name {string}
--- @param onDutyOnly {boolean|nil}
--- @returns {Player[]}
function OPX.GetPlayersByJob(name, onDutyOnly)
	local out, n = {}, 0
	local players = OPX.GetPlayers()
	for i = 1, #players do
		local job = players[i].PlayerData.job
		if job.name == name and (not onDutyOnly or job.onDuty) then
			n = n + 1
			out[n] = players[i]
		end
	end
	return out
end

--- @author DemiAutomatic
--- @method OPX.GetPlayersByGang
--- @description Lists loaded characters whose primary gang is the one named.
--- @param name {string}
--- @returns {Player[]}
function OPX.GetPlayersByGang(name)
	local out, n = {}, 0
	local players = OPX.GetPlayers()
	for i = 1, #players do
		if players[i].PlayerData.gang.name == name then
			n = n + 1
			out[n] = players[i]
		end
	end
	return out
end

Open77.log.debug(('[groups] %d job(s) and %d gang(s) defined')
	:format(OPX.Table.count(OPX.Jobs), OPX.Table.count(OPX.Gangs)))
