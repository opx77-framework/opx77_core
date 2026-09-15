--- @author DemiAutomatic
--- @file server/character.lua
--- @description Multicharacter: the roster, creation, deletion, selection and placement.

--- @author DemiAutomatic
--- @type {table}
--- @description The success and failure constructors.
local Result = OPX.Result

--- @author DemiAutomatic
--- @type {table}
--- @description The configuration both runtimes read.
local Shared = OPX.Config.SHARED

--- @author DemiAutomatic
--- @type {table}
--- @description The server-only configuration of the core.
local Config = OPX.Config.SERVER

--- @author DemiAutomatic
--- @method slotsFor
--- @description Answers how many characters an account may hold.
--- @param userId {UserId}
--- @returns {integer}
local function slotsFor(userId)
	return Config.CHARACTERS.SLOTS_BY_USER[userId] or OPX.TuneNumber('CHARACTER_SLOTS', 1)
end

--- @author DemiAutomatic
--- @method toSummary
--- @description Trims a character entity to what the selection screen shows.
--- @param entity {table}
--- @returns {CharacterSummary}
local function toSummary(entity)
	return {
		citizenId = entity.citizenId,
		cid = entity.cid,
		firstName = entity.charInfo.firstName,
		lastName = entity.charInfo.lastName,
		origin = entity.charInfo.origin,
		gender = entity.charInfo.gender,
		job = entity.job and entity.job.label,
		gang = entity.gang and entity.gang.name ~= 'none' and entity.gang.label or nil,
		lastLoggedOut = entity.lastLoggedOut,
	}
end

--- @author DemiAutomatic
--- @method OPX.SendCharacters
--- @description Records the account and sends its character roster to the client.
--- @param source {Source}
--- @param pushed {boolean|nil} Already rate limited by its caller.
--- @returns {Result}
function OPX.SendCharacters(source, pushed)
	if not pushed and OPX.Cooling(source, 'roster', 2000) then
		return Result.err('error.tooFast', tostring(source))
	end
	local session = OPX.EnsureSession(source)
	if not session then return Result.err('entry.noIdentity', tostring(source)) end

	if OPX.BootError then
		OPX.Refuse(source, 'error.unavailable', OPX.Operations.ROSTER)
		return Result.err('error.unavailable', OPX.BootError)
	end

	local account = OPX.Storage.Players.upsertAccount(session.userId, session.displayName)
	if not account.ok then return account end

	local characters = OPX.Storage.Players.fetchAll(session.userId)
	if not characters.ok then return characters end

	local list = characters.value
	local summaries = {}
	for i = 1, #list do summaries[i] = toSummary(list[i]) end
	if OPX.Players[source] then return Result.ok(summaries) end

	session.charactersSent = true
	TriggerClientEvent(OPX.Events.Client.CHARACTERS, source, {
		characters = summaries,
		slots = slotsFor(session.userId),
		origins = OPX.Origins,
	})

	Open77.log.info(('[character] %s has %d character(s)'):format(session.displayName, #list))
	return Result.ok(summaries)
end

--- @author DemiAutomatic
--- @type {integer[]}
--- @description Days per month, February at its leap-year length.
local MONTH_DAYS = { 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

--- @author DemiAutomatic
--- @method realDate
--- @description Answers whether a YYYY-MM-DD date exists, from year 1900.
--- @param text {string}
--- @returns {boolean}
local function realDate(text)
	local year, month, day = text:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
	year, month, day = tonumber(year), tonumber(month), tonumber(day)
	if year == nil or year < 1900 then return false end
	if month < 1 or month > 12 then return false end
	return day >= 1 and day <= MONTH_DAYS[month]
end

--- @author DemiAutomatic
--- @method validateRegistration
--- @description Checks a character registration received from a client.
--- @param payload {any}
--- @returns {Result}
local function validateRegistration(payload)
	if type(payload) ~= 'table' then
		return Result.err('error.badRequest', 'payload is not a table')
	end

	local firstName = OPX.ValidateName(payload.firstName)
	if not firstName.ok then return Result.err('character.badName', 'firstName') end

	local lastName = OPX.ValidateName(payload.lastName)
	if not lastName.ok then return Result.err('character.badName', 'lastName') end

	local origin = OPX.Validate.oneOf(payload.origin, OPX.Origins)
	if not origin.ok then return Result.err('character.badOrigin', tostring(payload.origin)) end

	local gender = OPX.Validate.oneOf(payload.gender, { female = true, male = true })
	if not gender.ok then return Result.err('error.badRequest', 'gender') end

	local birthDate = OPX.Validate.text(payload.birthDate, {
		min = 8, max = 10, pattern = '^%d%d%d%d%-%d%d%-%d%d$',
	})
	if birthDate.ok and not realDate(birthDate.value) then
		return Result.err('character.badBirthdate', birthDate.value)
	end

	return Result.ok({
		firstName = firstName.value,
		lastName = lastName.value,
		origin = origin.value,
		gender = gender.value,
		birthDate = birthDate.ok and birthDate.value or '2050-01-01',
	})
end

--- @author DemiAutomatic
--- @method OPX.CreateCharacter
--- @description Creates a character on the caller's own account.
--- @param source {Source}
--- @param payload {table}
--- @returns {Result}
function OPX.CreateCharacter(source, payload)
	local session = OPX.EnsureSession(source)
	if not session then return Result.err('entry.noIdentity', tostring(source)) end
	if OPX.BootError then return Result.err('error.unavailable', OPX.BootError) end

	local checked = validateRegistration(payload)
	if not checked.ok then return checked end
	local registration = checked.value

	if OPX.Cooling(source, 'create', 3000) then
		return Result.err('error.tooFast', tostring(source))
	end

	local rows = OPX.Storage.Players.countRows(session.userId)
	if not rows.ok then return rows end
	local ceiling = OPX.TuneNumber('CHARACTER_ROWS', 5)
	if rows.value >= ceiling then
		Open77.log.warn(('[character] %s has %d character rows, at the ceiling of %d')
			:format(session.userId, rows.value, ceiling))
		return Result.err('character.rowLimit', tostring(ceiling))
	end

	local slots = slotsFor(session.userId)
	local cid = OPX.Storage.Players.nextCid(session.userId, slots)
	if not cid.ok then return cid end

	local job = OPX.ResolveJob(Config.PLAYER.DEFAULT_JOB, 0)
	if not job.ok then return job end
	local gang = OPX.ResolveGang(Config.PLAYER.DEFAULT_GANG, 0)
	if not gang.ok then return gang end

	local money = {}
	for moneyType, starting in pairs(Shared.MONEY.TYPES) do
		money[moneyType] = math.floor(starting)
	end

	local entity
	for attempt = 1, 5 do
		entity = {
			citizenId = OPX.CitizenId.generate(),
			userId = session.userId,
			cid = cid.value,
			name = session.displayName,
			charInfo = {
				firstName = registration.firstName,
				lastName = registration.lastName,
				origin = registration.origin,
				gender = registration.gender,
				birthDate = registration.birthDate,
				phone = OPX.String.random('111-111-1111'),
			},
			money = money,
			job = job.value,
			gang = gang.value,
			position = nil,
			metadata = OPX.Table.deepCopy(Config.PLAYER.STARTING_METADATA),
		}

		local inserted = OPX.Storage.Players.insert(entity)
		if inserted.ok then break end

		if not tostring(inserted.detail or ''):lower():find('duplicate') then
			return inserted
		end
		if attempt == 5 then
			return Result.err('error.unavailable', 'no free citizen id after 5 draws')
		end
		Open77.log.warn('[character] citizen id collision, drawing another')
	end

	local jobRow = OPX.Storage.Players.upsertGroup(entity.citizenId, 'job', entity.job.name, 0)
	local gangRow = OPX.Storage.Players.upsertGroup(entity.citizenId, 'gang', entity.gang.name, 0)
	if not jobRow.ok or not gangRow.ok then
		local failed = not jobRow.ok and jobRow or gangRow
		local undone = OPX.Storage.execute(
			'DELETE FROM opx77_characters WHERE citizen_id = @citizen',
			{ citizen = entity.citizenId })
		if not undone.ok then
			Open77.log.error(('[character] %s was inserted, its memberships failed (%s), and the ' ..
				'row could not be removed either (%s): it has to go by hand')
				:format(entity.citizenId, tostring(failed.detail), tostring(undone.detail)))
		end
		return Result.err('error.unavailable', tostring(failed.detail))
	end

	OPX.Logger.log({
		event = 'character.create',
		message = ('%s %s'):format(registration.firstName, registration.lastName),
		citizenId = entity.citizenId,
		userId = session.userId,
		source = source,
	})
	Open77.log.info(('[character] %s created %s (%s)'):format(
		session.displayName, entity.citizenId, registration.firstName))

	return Result.ok(toSummary(entity))
end

--- @author DemiAutomatic
--- @method OPX.DeleteCharacter
--- @description Soft-deletes one of the caller's own characters.
--- @param source {Source}
--- @param citizenId {CitizenId}
--- @returns {Result}
function OPX.DeleteCharacter(source, citizenId)
	if OPX.Cooling(source, 'delete', 3000) then
		return Result.err('error.tooFast', tostring(source))
	end
	local session = OPX.EnsureSession(source)
	if not session then return Result.err('entry.noIdentity', tostring(source)) end

	local parsed = OPX.CitizenId.parse(citizenId)
	if not parsed.ok then return Result.err('character.notFound', tostring(citizenId)) end
	citizenId = parsed.value

	local fetched = OPX.Storage.Players.fetchOne(citizenId)
	if not fetched.ok then return fetched end
	if fetched.value.userId ~= session.userId then
		OPX.Logger.security('character.deleteRefused',
			('player %d tried to delete %s'):format(source, citizenId),
			{ userId = session.userId, owner = fetched.value.userId }, source)
		return Result.err('character.notFound', citizenId)
	end

	local online = OPX.GetPlayerByCitizenId(citizenId)
	if online then OPX.Logout(online.PlayerData.source) end

	local deleted = OPX.Storage.Players.softDelete(citizenId)
	if not deleted.ok then return deleted end

	local cascades = Config.CHARACTERS.CASCADE_TABLES
	for i = 1, #cascades do
		local target = cascades[i]
		OPX.Storage.execute(
			('DELETE FROM %s WHERE %s = @citizen'):format(target[1], target[2]),
			{ citizen = citizenId })
	end

	OPX.Logger.log({
		event = 'character.delete',
		severity = 'warn',
		citizenId = citizenId,
		userId = session.userId,
		source = source,
	})
	TriggerEvent(OPX.Events.Internal.CHARACTER_DELETED, source, citizenId)
	return Result.ok(citizenId)
end

--- @author DemiAutomatic
--- @method isSettled
--- @description Answers whether a life state is alive or dead, not transitioning.
--- @param life {table|nil}
--- @returns {boolean}
local function isSettled(life)
	return type(life) == 'table' and (life.phase == 'alive' or life.phase == 'dead')
end

--- @author DemiAutomatic
--- @method allowSampling
--- @description Lets the position sampler write this character's position.
--- @param player {Player}
local function allowSampling(player)
	player.MaySample = true
end

--- @author DemiAutomatic
--- @method OPX.PlaceCharacter
--- @description Places a loaded character by kill then respawn, never a transform.
--- @param player {Player}
--- @returns {boolean, string|nil}
function OPX.PlaceCharacter(player)
	local data = player.PlayerData
	local source = data.source
	if not source then return false, 'offline' end

	local target = data.position
	if not target then
		local spawn = Shared.DEFAULT_SPAWN
		if not spawn.SET then
			allowSampling(player)
			return false, 'no-default-spawn'
		end
		target = { x = spawn.X, y = spawn.Y, z = spawn.Z, heading = spawn.HEADING }
	end
	local bucket = OPX.Buckets.placementOf(target.bucket)

	local life
	for _ = 1, 5 do
		life = Open77.players.getLifeState(source)
		if isSettled(life) then break end
		Wait(200)
	end
	if not isSettled(life) then
		return false, 'life-state-' .. tostring(life and life.phase or 'unknown')
	end

	OPX.Buckets.move(source, bucket, 'placement')

	local killed, killError = Open77.players.kill(source, {
		cause = 'script',
		weapon = 'opx77_core:placement',
	})
	if not killed then return false, tostring(killError) end

	local health = tonumber(data.metadata.health)
	if not OPX.Math.isFinite(health) then health = 100 end
	local respawned, respawnError = Open77.players.respawn(source, {
		position = { x = target.x, y = target.y, z = target.z },
		heading = target.heading or 0.0,
		bucket = bucket,
		health = OPX.Math.clamp(health / 100, 0.15, 1.0),
		graceMs = 5000,
	})
	if not respawned then
		local revived, reviveError = Open77.players.revive(source, {
			health = OPX.Math.clamp(health / 100, 0.15, 1.0),
			graceMs = 5000,
		})
		if not revived then
			Open77.log.error(('[character] %d was killed for placement and neither respawn (%s) ' ..
				'nor revive (%s) put them back')
				:format(source, tostring(respawnError), tostring(reviveError)))
		end
		return false, tostring(respawnError)
	end

	local armor = tonumber(data.metadata.armor)
	if OPX.Math.isFinite(armor) and armor > 0 then Open77.players.setArmor(source, armor) end

	allowSampling(player)
	return true
end

--- @author DemiAutomatic
--- @method OPX.SelectCharacter
--- @description Logs in, places, then releases the gate for a chosen character.
--- @param source {Source}
--- @param citizenId {CitizenId}
--- @returns {Result}
function OPX.SelectCharacter(source, citizenId)
	if OPX.Cooling(source, 'select', 1000) then
		return Result.err('error.tooFast', tostring(source))
	end
	local parsed = OPX.CitizenId.parse(citizenId)
	if not parsed.ok then return Result.err('character.notFound', tostring(citizenId)) end

	local current = OPX.GetPlayer(source)

	if current ~= nil and current.PlayerData.citizenId == parsed.value then
		return Result.ok(current)
	end

	if current then
		local wanted = OPX.Storage.Players.fetchOne(parsed.value)
		if not wanted.ok then return wanted end
		local session = OPX.Sessions[source]
		if not session or wanted.value.userId ~= session.userId then
			OPX.Logger.security('character.notYours',
				('player %d asked to switch to %s'):format(source, parsed.value),
				{ userId = session and session.userId, owner = wanted.value.userId }, source)
			return Result.err('character.notFound', parsed.value)
		end
		local already = OPX.GetPlayerByCitizenId(parsed.value)
		if already and already.PlayerData.source ~= source then
			return Result.err('character.inUse', parsed.value)
		end
	end

	if current then
		local saved = OPX.LogoutAndWait(source)
		if saved and saved.ok == false then
			Open77.log.error(('[character] refusing the switch: %s could not be saved (%s)')
				:format(current.PlayerData.citizenId, tostring(saved.error)))
			OPX.Buckets.isolate(source, 'switch-refused')
			return Result.err('error.unavailable', tostring(saved.error))
		end
	end

	local login = OPX.Login(source, parsed.value)
	if not login.ok then
		if current then OPX.Buckets.isolate(source, 'switch-refused') end
		return login
	end

	local placed, reason = OPX.PlaceCharacter(login.value)
	if not placed then
		Open77.log.warn(('[character] %s logged in but was not placed: %s')
			:format(parsed.value, tostring(reason)))
	end
	OPX.Buckets.release(source, placed and 'character-placed' or 'character-loaded')

	OPX.Lifecycle.release(source, placed and 'character-placed' or 'character-loaded')
	return login
end
