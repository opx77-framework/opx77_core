--- @author DemiAutomatic
--- @file server/player.lua
--- @description The Player object, money, metadata, login, save and logout.

--- @author DemiAutomatic
--- @type {table}
--- @description The shared Result constructors.
local Result = OPX.Result

--- @author DemiAutomatic
--- @type {table}
--- @description The configuration only the server half reads.
local Config = OPX.Config.SERVER

--- @author DemiAutomatic
--- @type {table}
--- @description The configuration both halves read.
local Shared = OPX.Config.SHARED

--- @author DemiAutomatic
--- @method normalise
--- @description Fills in whatever a stored entity is missing, in place.
--- @param entity {table}
--- @returns {table}
local function normalise(entity)
	entity.charInfo = entity.charInfo or {}
	entity.metadata = entity.metadata or {}
	entity.money = entity.money or {}

	for moneyType in pairs(Shared.MONEY.TYPES) do
		entity.money[moneyType] = math.floor(tonumber(entity.money[moneyType]) or 0)
	end

	for key, value in pairs(Config.PLAYER.STARTING_METADATA) do
		if entity.metadata[key] == nil then
			entity.metadata[key] = OPX.Table.deepCopy(value)
		end
	end

	if type(entity.appearance) ~= 'table' then entity.appearance = nil end

	local job = OPX.ResolveJob(entity.job and entity.job.name, entity.job and entity.job.grade
		and entity.job.grade.level)
	if not job.ok then
		job = OPX.ResolveJob(Config.PLAYER.DEFAULT_JOB, 0)
	end
	entity.job = job.value

	local gang = OPX.ResolveGang(entity.gang and entity.gang.name, entity.gang and entity.gang.grade
		and entity.gang.grade.level)
	if not gang.ok then
		gang = OPX.ResolveGang(Config.PLAYER.DEFAULT_GANG, 0)
	end
	entity.gang = gang.value

	return entity
end

--- @author DemiAutomatic
--- @type {fun(entity: table): table}
--- @description Publishes the entity normaliser to the other server files.
OPX.NormaliseEntity = normalise

--- @author DemiAutomatic
--- @method OPX.CreatePlayer
--- @description Builds a Player, with its Functions, around a stored entity.
--- @param entity {table}
--- @param offline {boolean|nil} An offline Player sends and places nothing.
--- @returns {Player}
function OPX.CreatePlayer(entity, offline)
	local self = { Offline = offline == true }

	self.Revision = 0

	self.MaySample = false

	self.PlayerData = normalise(entity)

	if self.Offline then
		self.PlayerData.source = nil
	else
		self.PlayerData.source = entity.source
	end

	local Functions = {}
	self.Functions = Functions

	function Functions.UpdatePlayerData()
		self.Revision = self.Revision + 1
		if self.Offline then return end
		TriggerClientEvent(OPX.Events.Client.SET_PLAYER_DATA, self.PlayerData.source, self.PlayerData)
	end

	function Functions.SetPlayerData(key, value)
		if key == 'citizenId' or key == 'userId' or key == 'source' then
			error(('PlayerData.%s is identity and cannot be set'):format(key), 2)
		end
		self.PlayerData[key] = value
		Functions.UpdatePlayerData()
	end

	function Functions.SetMetaData(key, value)
		self.PlayerData.metadata[key] = value
		Functions.UpdatePlayerData()
	end

	function Functions.GetMetaData(key)
		if key == nil then return self.PlayerData.metadata end
		return self.PlayerData.metadata[key]
	end

	function Functions.SetCharInfo(key, value)
		self.PlayerData.charInfo[key] = value
		Functions.UpdatePlayerData()
	end

	function Functions.AddMoney(moneyType, amount, reason)
		return OPX.AddMoney(self, moneyType, amount, reason)
	end

	function Functions.RemoveMoney(moneyType, amount, reason)
		return OPX.RemoveMoney(self, moneyType, amount, reason)
	end

	function Functions.SetMoney(moneyType, amount, reason)
		return OPX.SetMoney(self, moneyType, amount, reason)
	end

	function Functions.GetMoney(moneyType)
		return OPX.GetMoney(self, moneyType)
	end

	function Functions.SetJob(name, grade)
		return OPX.SetJob(self, name, grade)
	end

	function Functions.SetGang(name, grade)
		return OPX.SetGang(self, name, grade)
	end

	function Functions.SetJobDuty(onDuty)
		return OPX.SetJobDuty(self, onDuty)
	end

	function Functions.Save()
		return OPX.Save(self)
	end

	function Functions.Logout()
		return OPX.Logout(self.PlayerData.source)
	end

	return self
end

--- @author DemiAutomatic
--- @method resolve
--- @description Resolves a Player, player id or citizen id to a Player.
--- @param identifier {Player|Source|CitizenId}
--- @returns {Player|nil}
local function resolve(identifier)
	if type(identifier) == 'table' and identifier.PlayerData then return identifier end
	if type(identifier) == 'number' then return OPX.GetPlayer(identifier) end
	if type(identifier) == 'string' then return OPX.GetPlayerByCitizenId(identifier) end
	return nil
end

--- @author DemiAutomatic
--- @type {fun(identifier: Player|Source|CitizenId): Player|nil}
--- @description Publishes the identifier resolver to the other server files.
OPX.ResolvePlayer = resolve

--- @author DemiAutomatic
--- @method amountOf
--- @description Answers a positive, finite, rounded amount, or nil.
--- @param value {any}
--- @returns {integer|nil}
local function amountOf(value)
	local n = tonumber(value)
	if not OPX.Math.isFinite(n) then return nil end
	n = math.floor(n + 0.5)
	if n <= 0 then return nil end
	return n
end

--- @author DemiAutomatic
--- @method announceMoney
--- @description Announces a balance change to the client, core files and audit.
--- @param player {Player}
--- @param moneyType {MoneyType}
--- @param amount {integer}
--- @param action {string} add, remove or set.
--- @param reason {string|nil}
local function announceMoney(player, moneyType, amount, action, reason)
	local data = player.PlayerData
	player.Functions.UpdatePlayerData()

	TriggerClientEvent(OPX.Events.Client.MONEY_CHANGE, data.source,
		moneyType, amount, action, data.money[moneyType])

	TriggerEvent(OPX.Events.Internal.MONEY_CHANGE,
		data.source, data.citizenId, moneyType, amount, action, reason,
		data.money[moneyType])

	OPX.Logger.player(player, 'money.' .. action, reason, {
		moneyType = moneyType,
		amount = amount,
		balance = data.money[moneyType],
	})
end

--- @author DemiAutomatic
--- @method OPX.AddMoney
--- @description Adds money to a loaded character, hooked and audited.
--- @param identifier {Player|Source|CitizenId}
--- @param moneyType {MoneyType}
--- @param amount {number}
--- @param reason {string|nil}
--- @returns {boolean, string|nil}
function OPX.AddMoney(identifier, moneyType, amount, reason)
	local player = resolve(identifier)
	if not player then return false, 'error.notLoggedIn' end
	if player.Offline then return false, 'money.offline' end
	if not OPX.IsMoneyType(moneyType) then
		Open77.log.error(('[player] AddMoney: %q is not a money type on this server')
			:format(tostring(moneyType)))
		return false, 'money.badType'
	end

	local value = amountOf(amount)
	if not value then
		OPX.Logger.security('money.badAmount',
			('AddMoney refused %s'):format(tostring(amount)),
			{ citizenId = player.PlayerData.citizenId, moneyType = moneyType },
			player.PlayerData.source)
		return false, 'money.badAmount'
	end

	if not OPX.Hooks.trigger('money:beforeAdd', {
		player = player, moneyType = moneyType, amount = value, reason = reason,
	}) then
		return false, 'money.vetoed'
	end

	local money = player.PlayerData.money
	money[moneyType] = money[moneyType] + value
	announceMoney(player, moneyType, value, 'add', reason)
	return true
end

--- @author DemiAutomatic
--- @method OPX.RemoveMoney
--- @description Removes money, refusing rather than truncating when short.
--- @param identifier {Player|Source|CitizenId}
--- @param moneyType {MoneyType}
--- @param amount {number}
--- @param reason {string|nil}
--- @returns {boolean, string|nil}
function OPX.RemoveMoney(identifier, moneyType, amount, reason)
	local player = resolve(identifier)
	if not player then return false, 'error.notLoggedIn' end
	if player.Offline then return false, 'money.offline' end
	if not OPX.IsMoneyType(moneyType) then
		Open77.log.error(('[player] RemoveMoney: %q is not a money type on this server')
			:format(tostring(moneyType)))
		return false, 'money.badType'
	end

	local value = amountOf(amount)
	if not value then
		OPX.Logger.security('money.badAmount',
			('RemoveMoney refused %s'):format(tostring(amount)),
			{ citizenId = player.PlayerData.citizenId, moneyType = moneyType },
			player.PlayerData.source)
		return false, 'money.badAmount'
	end

	local money = player.PlayerData.money
	if money[moneyType] - value < 0 and not Config.MONEY.ALLOW_NEGATIVE[moneyType] then
		return false, 'money.insufficient'
	end

	if not OPX.Hooks.trigger('money:beforeRemove', {
		player = player, moneyType = moneyType, amount = value, reason = reason,
	}) then
		return false, 'money.vetoed'
	end

	money[moneyType] = money[moneyType] - value
	announceMoney(player, moneyType, value, 'remove', reason)
	return true
end

--- @author DemiAutomatic
--- @method OPX.SetMoney
--- @description Sets a balance outright, zero included.
--- @param identifier {Player|Source|CitizenId}
--- @param moneyType {MoneyType}
--- @param amount {number}
--- @param reason {string|nil}
--- @returns {boolean, string|nil}
function OPX.SetMoney(identifier, moneyType, amount, reason)
	local player = resolve(identifier)
	if not player then return false, 'error.notLoggedIn' end
	if player.Offline then return false, 'money.offline' end
	if not OPX.IsMoneyType(moneyType) then return false, 'money.badType' end

	local n = tonumber(amount)
	if not OPX.Math.isFinite(n) then return false, 'money.badAmount' end
	n = math.floor(n + 0.5)
	if n < 0 and not Config.MONEY.ALLOW_NEGATIVE[moneyType] then
		return false, 'money.negative'
	end

	if not OPX.Hooks.trigger('money:beforeSet', {
		player = player, moneyType = moneyType, amount = n, reason = reason,
	}) then
		return false, 'money.vetoed'
	end

	player.PlayerData.money[moneyType] = n
	announceMoney(player, moneyType, n, 'set', reason)
	return true
end

--- @author DemiAutomatic
--- @method OPX.GetMoney
--- @description Answers one balance, or the whole money table.
--- @param identifier {Player|Source|CitizenId}
--- @param moneyType {MoneyType|nil}
--- @returns {integer|table|nil}
function OPX.GetMoney(identifier, moneyType)
	local player = resolve(identifier)
	if not player then return nil end
	if moneyType == nil then return player.PlayerData.money end
	return player.PlayerData.money[moneyType]
end

--- @author DemiAutomatic
--- @method OPX.SetMetadata
--- @description Sets one key of a loaded character's free-form metadata.
--- @param identifier {Player|Source|CitizenId}
--- @param key {string}
--- @param value {any}
--- @returns {boolean}
function OPX.SetMetadata(identifier, key, value)
	local player = resolve(identifier)
	if not player then return false end
	player.Functions.SetMetaData(key, value)
	return true
end

--- @author DemiAutomatic
--- @method OPX.GetMetadata
--- @description Answers one metadata key, or the whole metadata table.
--- @param identifier {Player|Source|CitizenId}
--- @param key {string|nil}
--- @returns {any}
function OPX.GetMetadata(identifier, key)
	local player = resolve(identifier)
	if not player then return nil end
	return player.Functions.GetMetaData(key)
end

--- @author DemiAutomatic
--- @method OPX.SamplePosition
--- @description Re-reads a character's position from the host, with the reported heading.
--- @param player {Player}
--- @returns {boolean}
function OPX.SamplePosition(player)
	local data = player.PlayerData
	if not data.source then return false end
	if not player.MaySample then return false end
	if OPX.UserIdOf(data.source) ~= data.userId then return false end

	local snapshot = Open77.players.position(data.source)
	if type(snapshot) ~= 'table' or snapshot.x == nil then return false end

	local previous = data.position
	data.position = {
		x = snapshot.x,
		y = snapshot.y,
		z = snapshot.z,
		heading = data.reportedHeading or (previous and previous.heading) or 0.0,
		bucket = snapshot.bucket or 0,
	}
	return true
end

--- @author DemiAutomatic
--- @method OPX.Login
--- @description Loads a character the session owns into the roster.
--- @param source {Source}
--- @param citizenId {CitizenId}
--- @returns {Result}
function OPX.Login(source, citizenId)
	local session = OPX.EnsureSession(source)
	if not session then return Result.err('entry.noIdentity', tostring(source)) end

	if OPX.BootError then
		return Result.err('error.unavailable', OPX.BootError)
	end

	local fetched = OPX.Storage.Players.fetchOne(citizenId)
	if not fetched.ok then return fetched end

	local entity = fetched.value
	if entity.userId ~= session.userId then
		OPX.Logger.security('character.notYours',
			('player %d asked for %s'):format(source, citizenId),
			{ userId = session.userId, owner = entity.userId }, source)
		return Result.err('character.notFound', citizenId)
	end

	local already = OPX.GetPlayerByCitizenId(citizenId)
	if already and already.PlayerData.source ~= source then
		return Result.err('character.inUse', citizenId)
	end

	local groups = OPX.Storage.Players.fetchGroups(citizenId)
	if not groups.ok then return groups end

	local clothing = OPX.Clothing.load(citizenId)

	entity.source = source
	local player = OPX.CreatePlayer(entity, false)
	player.PlayerData.jobs = groups.value.jobs
	player.PlayerData.gangs = groups.value.gangs
	player.PlayerData.clothing = clothing

	OPX.RegisterPlayer(player)
	session.citizenId = citizenId

	TriggerClientEvent(OPX.Events.Client.PLAYER_LOADED, source, player.PlayerData)
	TriggerEvent(OPX.Events.Internal.PLAYER_LOADED, source, player.PlayerData)

	OPX.Logger.player(player, 'character.login', 'logged in')
	Open77.log.info(('[player] %s (%s) logged in as %s %s'):format(
		session.displayName, citizenId,
		player.PlayerData.charInfo.firstName or '?',
		player.PlayerData.charInfo.lastName or '?'))

	return Result.ok(player)
end

--- @author DemiAutomatic
--- @method OPX.Save
--- @description Writes a character back, sampling its position first.
--- @param identifier {Player|Source|CitizenId}
--- @param loggedOut {boolean|nil} Stamps last_logged_out.
--- @returns {Result}
function OPX.Save(identifier, loggedOut)
	local player = resolve(identifier)
	if not player then return Result.err('error.notLoggedIn') end

	if not player.Offline then OPX.SamplePosition(player) end

	local saved = OPX.Storage.Players.save(player.PlayerData, loggedOut)
	if not saved.ok then
		Open77.log.error(('[player] save failed for %s: %s')
			:format(player.PlayerData.citizenId, tostring(saved.detail)))
	end
	return saved
end

--- @author DemiAutomatic
--- @method OPX.Logout
--- @description Unloads a character and dispatches its save, idempotently.
--- @param source {Source}
function OPX.Logout(source)
	source = tonumber(source)
	local player = source and OPX.Players[source]
	if not player then return end

	OPX.UnregisterPlayer(player)

	local session = OPX.Sessions[source]
	if session then session.citizenId = nil end

	TriggerClientEvent(OPX.Events.Client.PLAYER_UNLOADED, source)
	TriggerEvent(OPX.Events.Internal.PLAYER_UNLOADED, source, player.PlayerData)

	OPX.SamplePosition(player)
	player.MaySample = false
	OPX.Buckets.isolate(source, 'unloaded')

	CreateThread(function()
		OPX.Save(player, true)
		OPX.Logger.player(player, 'character.logout', 'logged out')
	end)
end

--- @author DemiAutomatic
--- @method OPX.LogoutAndWait
--- @description Unloads a character and waits for its row to be written.
--- @param source {Source}
--- @returns {Result}
function OPX.LogoutAndWait(source)
	source = tonumber(source)
	local player = source and OPX.Players[source]
	if not player then return Result.ok(false) end

	OPX.UnregisterPlayer(player)

	local session = OPX.Sessions[source]
	if session then session.citizenId = nil end

	TriggerClientEvent(OPX.Events.Client.PLAYER_UNLOADED, source)
	TriggerEvent(OPX.Events.Internal.PLAYER_UNLOADED, source, player.PlayerData)

	local saved = OPX.Save(player, true)
	OPX.Logger.player(player, 'character.logout', 'logged out')
	return saved
end
