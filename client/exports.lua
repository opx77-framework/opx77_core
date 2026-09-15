--- @author DemiAutomatic
--- @file client/exports.lua
--- @description The client exports satellite resources call, each answering ok.

--- @author DemiAutomatic
--- @export GetPlayerData
--- @description Answers the whole loaded character, refused before login.
--- @returns {table}
exports('GetPlayerData', function()
	if not OPX.IsLoggedIn then return { ok = false, error = 'error.notLoggedIn' } end
	return { ok = true, data = OPX.PlayerData }
end)

--- @author DemiAutomatic
--- @export IsLoggedIn
--- @description Answers whether a character is loaded.
--- @returns {table}
exports('IsLoggedIn', function()
	return { ok = true, loggedIn = OPX.IsLoggedIn }
end)

--- @author DemiAutomatic
--- @export HasJob
--- @description Answers job membership with optional duty and minimum grade.
--- @param name {string}
--- @param onDutyOnly {boolean|nil}
--- @param minGrade {integer|nil}
--- @returns {table}
exports('HasJob', function(name, onDutyOnly, minGrade)
	return { ok = true, result = OPX.HasJob(name, onDutyOnly == true, tonumber(minGrade)) }
end)

--- @author DemiAutomatic
--- @export HasGang
--- @description Answers gang membership with an optional minimum grade.
--- @param name {string}
--- @param minGrade {integer|nil}
--- @returns {table}
exports('HasGang', function(name, minGrade)
	return { ok = true, result = OPX.HasGang(name, tonumber(minGrade)) }
end)

--- @author DemiAutomatic
--- @export GetAppearance
--- @description Answers the live character's stored face, refused before login.
--- @returns {table}
exports('GetAppearance', function()
	if not OPX.IsLoggedIn then return { ok = false, error = 'error.notLoggedIn' } end
	return { ok = true, appearance = OPX.GetAppearance() }
end)

--- @author DemiAutomatic
--- @export GetClothing
--- @description Answers the live character's stored clothing, refused before login.
--- @returns {table}
exports('GetClothing', function()
	if not OPX.IsLoggedIn then return { ok = false, error = 'error.notLoggedIn' } end
	return { ok = true, clothing = OPX.GetClothing() }
end)

--- @author DemiAutomatic
--- @export GetCharacters
--- @description Answers the roster last sent to this client.
--- @returns {table}
exports('GetCharacters', function()
	return {
		ok = true,
		characters = OPX.Characters.list,
		slots = OPX.Characters.slots,
		origins = OPX.Characters.origins,
	}
end)

--- @author DemiAutomatic
--- @export RequestCharacters
--- @description Asks the server to send the roster again.
--- @returns {table}
exports('RequestCharacters', function()
	OPX.RequestCharacters()
	return { ok = true }
end)

--- @author DemiAutomatic
--- @export SelectCharacter
--- @description Sends a selection request and answers whether it was sent.
--- @param citizenId {string}
--- @returns {table}
exports('SelectCharacter', function(citizenId)
	local sent, reason = OPX.SelectCharacter(citizenId)
	return { ok = sent, error = reason }
end)

--- @author DemiAutomatic
--- @export CreateCharacter
--- @description Sends a creation request and answers whether it was sent.
--- @param registration {table}
--- @returns {table}
exports('CreateCharacter', function(registration)
	local sent, reason = OPX.CreateCharacter(registration)
	return { ok = sent, error = reason }
end)

--- @author DemiAutomatic
--- @export DeleteCharacter
--- @description Sends a deletion request and answers whether it was sent.
--- @param citizenId {string}
--- @returns {table}
exports('DeleteCharacter', function(citizenId)
	local sent, reason = OPX.DeleteCharacter(citizenId)
	return { ok = sent, error = reason }
end)

if not OPX.IsNotifyPosition(OPX.Config.SHARED.NOTIFY_POSITION) then
	Open77.log.warn(('[exports] NOTIFY_POSITION %q is not one of the documented ' ..
		'open77_notifications positions'):format(tostring(OPX.Config.SHARED.NOTIFY_POSITION)))
end

--- @author DemiAutomatic
--- @export GetSharedConfig
--- @description Answers the shared configuration values a UI needs.
--- @returns {table}
exports('GetSharedConfig', function()
	local shared = OPX.Config.SHARED
	return {
		ok = true,
		config = {
			serverName = shared.SERVER_NAME,
			locale = OPX.Locale.current(),
			moneyTypes = shared.MONEY.TYPES,
			defaultMoneyType = shared.MONEY.DEFAULT,
			nameBounds = shared.CHARACTERS.NAME,
			notifyPosition = shared.NOTIFY_POSITION,
		},
	}
end)

--- @author DemiAutomatic
--- @export Locale
--- @description Answers one catalogue line rendered in the locale in force.
--- @param key {string}
--- @param params {table<string, string|number>|nil}
--- @returns {table}
exports('Locale', function(key, params)
	if type(key) ~= 'string' then return { ok = false, error = 'error.badRequest' } end
	return { ok = true, text = locale(key, params) }
end)

--- @author DemiAutomatic
--- @export GetJobs
--- @description Answers the job definitions with 1-based grade arrays.
--- @returns {table}
exports('GetJobs', function()
	local out = {}
	for name, job in pairs(OPX.Jobs) do
		local grades, n = {}, 0
		for level = 0, OPX.TopGrade(job.grades) do
			local rank = job.grades[level]
			if rank then
				n = n + 1
				grades[n] = { level = level, name = rank.name, payment = rank.payment,
					isBoss = rank.isBoss == true, bankAuth = rank.bankAuth == true }
			end
		end
		out[name] = { label = job.label, type = job.type, defaultDuty = job.defaultDuty == true,
			offDutyPay = job.offDutyPay == true, grades = grades }
	end
	return { ok = true, jobs = out }
end)

--- @author DemiAutomatic
--- @export GetGangs
--- @description Answers the gang definitions with 1-based grade arrays.
--- @returns {table}
exports('GetGangs', function()
	local out = {}
	for name, gang in pairs(OPX.Gangs) do
		local grades, n = {}, 0
		for level = 0, OPX.TopGrade(gang.grades) do
			local rank = gang.grades[level]
			if rank then
				n = n + 1
				grades[n] = { level = level, name = rank.name,
					isBoss = rank.isBoss == true, bankAuth = rank.bankAuth == true }
			end
		end
		out[name] = { label = gang.label, grades = grades }
	end
	return { ok = true, gangs = out }
end)

--- @author DemiAutomatic
--- @export GetOrigins
--- @description Answers the lifepaths offered at character creation.
--- @returns {table}
exports('GetOrigins', function()
	return { ok = true, origins = OPX.Origins }
end)

--- @author DemiAutomatic
--- @export GetVersion
--- @description Answers the core's version for a compatibility check.
--- @returns {table}
exports('GetVersion', function()
	return { ok = true, version = OPX.VERSION }
end)
