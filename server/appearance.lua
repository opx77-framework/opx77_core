--- @author DemiAutomatic
--- @file server/appearance.lua
--- @description The character's face: validation, the stored write and the broadcast.

--- @author DemiAutomatic
--- @type {table}
--- @description The success and failure constructors.
local Result = OPX.Result

--- @author DemiAutomatic
--- @type {table}
--- @description The shared appearance configuration: accepted builds and size ceiling.
local Config = OPX.Config.SHARED.APPEARANCE

OPX.Appearance = {}
local Appearance = OPX.Appearance

--- @author DemiAutomatic
--- @type {integer}
--- @description The schema version written into every stored snapshot.
Appearance.VERSION = 1

--- @author DemiAutomatic
--- @type {table<string, boolean>}
--- @description The three parts the engine's catalogue is divided into.
local PARTS = { head = true, body = true, arms = true }

--- @author DemiAutomatic
--- @type {integer}
--- @description The ceiling on an option index and its choice count.
local MAX_CHOICES = 512

--- @author DemiAutomatic
--- @type {integer}
--- @description The most options one snapshot may carry.
local MAX_OPTIONS = 256

--- @author DemiAutomatic
--- @method isInteger
--- @description Answers whether a value is a finite whole number.
--- @param value {any}
--- @returns {boolean}
local function isInteger(value)
	return type(value) == 'number' and OPX.Math.isFinite(value) and value % 1 == 0
end

--- @author DemiAutomatic
--- @method isHash
--- @description Answers whether a value is a rendered 64-bit engine hash.
--- @param value {any}
--- @param allowZero {boolean} True for the body family hash.
--- @returns {boolean}
local function isHash(value, allowZero)
	if type(value) ~= 'string' or #value ~= 18 then return false end
	if value:sub(1, 2) ~= '0x' or value:sub(3):match('^%x+$') == nil then return false end
	return allowZero or value ~= '0x0000000000000000'
end

--- @author DemiAutomatic
--- @method digest
--- @description Lower-cases a SHA-256 catalogue fingerprint, or answers nil.
--- @param value {any}
--- @returns {string|nil}
local function digest(value)
	if type(value) ~= 'string' then return nil end
	local lowered = value:lower()
	if #lowered ~= 64 or lowered:match('^%x+$') == nil then return nil end
	return lowered
end

--- @author DemiAutomatic
--- @method OPX.Appearance.buildAccepted
--- @description Answers whether a stored face may be read into this build.
--- @param value {any}
--- @returns {boolean}
function OPX.Appearance.buildAccepted(value)
	return type(value) == 'string' and Config.GAME_BUILDS[value] == true
end

--- @author DemiAutomatic
--- @method OPX.Appearance.canonical
--- @description Answers a snapshot in canonical form, or nil and a code.
--- @param value {any}
--- @returns {AppearanceSnapshot|nil, string|nil}
function OPX.Appearance.canonical(value)
	if type(value) ~= 'table' then return nil, 'invalid_snapshot' end
	if value.schemaVersion ~= Appearance.VERSION then return nil, 'unsupported_schema' end
	if not Appearance.buildAccepted(value.gameBuild) then
		return nil, 'unsupported_game_build'
	end

	local catalog = digest(value.catalogDigest)
	if catalog == nil then return nil, 'invalid_catalog_digest' end

	if not isHash(value.gender, true) then return nil, 'invalid_gender' end

	if type(value.options) ~= 'table' then return nil, 'invalid_options' end
	local count = #value.options
	if count < 1 or count > MAX_OPTIONS then return nil, 'invalid_option_count' end

	local canonical = {
		schemaVersion = Appearance.VERSION,
		gameBuild = value.gameBuild,
		catalogDigest = catalog,
		gender = value.gender,
		options = {},
	}

	local seen = {}
	for index = 1, count do
		local option = value.options[index]
		if type(option) ~= 'table' then return nil, 'invalid_option' end
		if not PARTS[option.part] then return nil, 'invalid_option_part' end
		if not isHash(option.name, false) then return nil, 'invalid_option_name' end
		if not isInteger(option.value) or option.value < 0 or option.value >= MAX_CHOICES then
			return nil, 'invalid_option_value'
		end
		if not isInteger(option.choices) or option.choices < 0 or option.choices > MAX_CHOICES then
			return nil, 'invalid_option_choices'
		end
		if option.choices > 0 and option.value >= option.choices then
			return nil, 'option_out_of_range'
		end
		local key = option.part .. ':' .. option.name:lower()
		if seen[key] then return nil, 'duplicate_option' end
		seen[key] = true
		canonical.options[index] = {
			part = option.part,
			name = option.name:lower(),
			value = option.value,
			choices = option.choices,
		}
	end

	for key in pairs(value.options) do
		if type(key) == 'number' and (not isInteger(key) or key < 1 or key > count) then
			return nil, 'sparse_options'
		end
	end

	return canonical
end

--- @author DemiAutomatic
--- @method OPX.Appearance.same
--- @description Answers whether two canonical snapshots are the same face.
--- @param left {AppearanceSnapshot|nil}
--- @param right {AppearanceSnapshot|nil}
--- @returns {boolean}
function OPX.Appearance.same(left, right)
	if type(left) ~= 'table' or type(right) ~= 'table' then return false end
	if left.gameBuild ~= right.gameBuild or left.catalogDigest ~= right.catalogDigest then
		return false
	end
	if left.gender ~= right.gender then return false end
	local count = #left.options
	if count ~= #right.options then return false end
	for index = 1, count do
		local a, b = left.options[index], right.options[index]
		if a.part ~= b.part or a.name ~= b.name or a.value ~= b.value then return false end
	end
	return true
end

--- @author DemiAutomatic
--- @method OPX.SaveAppearance
--- @description Validates, stores and publishes a character's captured face.
--- @param identifier {Player|Source|CitizenId}
--- @param snapshot {any}
--- @returns {Result}
function OPX.SaveAppearance(identifier, snapshot)
	local player = OPX.ResolvePlayer(identifier)
	if not player then return Result.err('error.notLoggedIn', tostring(identifier)) end

	local canonical, reason = Appearance.canonical(snapshot)
	if not canonical then return Result.err('appearance.invalid', reason) end

	local data = player.PlayerData
	if Appearance.same(data.appearance, canonical) then return Result.ok(data.appearance) end

	local encoded = json.encode(canonical)
	if #encoded > Config.MAX_JSON_BYTES then
		return Result.err('appearance.tooLarge', tostring(#encoded))
	end

	local previous = data.appearance
	data.appearance = canonical
	local written = OPX.Storage.Players.saveAppearance(data.citizenId, canonical)
	if not written.ok then
		if data.appearance == canonical then data.appearance = previous end
		return written
	end

	if not player.Offline and OPX.Players[data.source] == player then
		player.Functions.UpdatePlayerData()
		TriggerClientEvent(OPX.Events.Client.APPEARANCE_UPDATE, data.source, canonical)
	end
	TriggerEvent(OPX.Events.Internal.APPEARANCE_CHANGE, data.source, data.citizenId, canonical)

	OPX.Logger.player(player, 'appearance.saved', canonical.gameBuild,
		{ options = #canonical.options })
	return Result.ok(canonical)
end

--- @author DemiAutomatic
--- @method OPX.GetAppearance
--- @description Answers the stored face for a character, online or not.
--- @param identifier {Player|Source|CitizenId}
--- @returns {Result}
function OPX.GetAppearance(identifier)
	local player = OPX.ResolvePlayer(identifier)
	if player then return Result.ok(player.PlayerData.appearance) end
	if type(identifier) ~= 'string' then
		return Result.err('error.notLoggedIn', tostring(identifier))
	end

	local fetched = OPX.Storage.Players.fetchOne(identifier)
	if not fetched.ok then return fetched end
	return Result.ok(fetched.value.appearance)
end

--- @author DemiAutomatic
--- @event opx77:server:saveAppearance
--- @description Stores the face captured for the connection's character, refusing a stale save.
--- @param payload {any}
RegisterNetEvent(OPX.Events.Server.SAVE_APPEARANCE, function(payload)
	local src = tonumber(source)
	if not src then return end
	local operation = OPX.Operations.SAVE_APPEARANCE
	if type(payload) ~= 'table' then
		return OPX.Refuse(src, 'error.badRequest', operation)
	end
	if OPX.Cooling(src, 'appearance.request', 2000) then
		return OPX.Refuse(src, 'error.tooFast', operation)
	end

	local player = OPX.GetPlayer(src)
	if not player then return OPX.Refuse(src, 'error.notLoggedIn', operation) end
	if payload.citizenId ~= nil and payload.citizenId ~= player.PlayerData.citizenId then
		return OPX.Refuse(src, 'appearance.stale', operation)
	end

	local snapshot = payload.snapshot or payload
	CreateThread(function()
		local saved = OPX.SaveAppearance(player, snapshot)
		if not saved.ok then
			Open77.log.warn(('[appearance] %d sent an unusable face: %s (%s)')
				:format(src, tostring(saved.error), tostring(saved.detail)))
			OPX.Refuse(src, saved.error, operation)
		end
	end)
end)
