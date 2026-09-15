--- @author DemiAutomatic
--- @file server/clothing.lua
--- @description What a character wears: validation, the stored write and the answer.

--- @author DemiAutomatic
--- @type {table}
--- @description The success and failure constructors.
local Result = OPX.Result

OPX.Clothing = {}
local Clothing = OPX.Clothing

--- @author DemiAutomatic
--- @type {integer}
--- @description The schema version written into every stored record.
Clothing.VERSION = 1

--- @author DemiAutomatic
--- @type {string[]}
--- @description The nine equipment slots, as the platform names them.
local SLOTS = { 'Head', 'Face', 'InnerChest', 'OuterChest', 'Legs', 'Feet', 'Outfit',
	'UnderwearTop', 'UnderwearBottom' }

--- @author DemiAutomatic
--- @type {table<string, boolean>}
--- @description The nine equipment slots as a set.
local IS_SLOT = {}
for index = 1, #SLOTS do IS_SLOT[SLOTS[index]] = true end

--- @author DemiAutomatic
--- @type {table<string, boolean>}
--- @description The seven visible slots an outfit may override.
local IS_OUTFIT_SLOT = { Head = true, Face = true, InnerChest = true, OuterChest = true,
	Legs = true, Feet = true, Outfit = true }

--- @author DemiAutomatic
--- @type {integer}
--- @description How many wardrobe outfits exist, indexed 0 to 6.
local OUTFITS = 7

--- @author DemiAutomatic
--- @type {integer}
--- @description The longest record name, as the equipment service bounds one.
local MAX_RECORD_BYTES = 160

--- @author DemiAutomatic
--- @type {integer}
--- @description The largest encoded clothing document the core stores.
local MAX_JSON_BYTES = 16384

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds between two clothing saves from one player.
local COOLDOWN_MS = 2000

--- @author DemiAutomatic
--- @method isInteger
--- @description Answers whether a value is a finite whole number.
--- @param value {any}
--- @returns {boolean}
local function isInteger(value)
	return type(value) == 'number' and OPX.Math.isFinite(value) and value % 1 == 0
end

--- @author DemiAutomatic
--- @method recordOf
--- @description Answers a worn record name, false for empty, nil otherwise.
--- @param value {any}
--- @returns {string|false|nil}
local function recordOf(value)
	if value == false then return false end
	if type(value) ~= 'string' or #value < 1 or #value > MAX_RECORD_BYTES then return nil end
	if value:match('^[%w_%.%-]+$') == nil then return nil end
	return value
end

--- @author DemiAutomatic
--- @method outfitIndex
--- @description Reads an outfit index from a number or digit string key.
--- @param key {any}
--- @returns {integer|nil}
local function outfitIndex(key)
	local number
	if type(key) == 'number' then
		number = key
	elseif type(key) == 'string' and key:match('^%d$') then
		number = tonumber(key)
	end
	if not isInteger(number) or number < 0 or number >= OUTFITS then return nil end
	return math.floor(number)
end

--- @author DemiAutomatic
--- @method OPX.Clothing.canonical
--- @description Answers a clothing record in canonical form, or nil and a code.
--- @param value {any}
--- @returns {ClothingRecord|nil, string|nil}
function OPX.Clothing.canonical(value)
	if type(value) ~= 'table' then return nil, 'invalid_record' end
	for key in pairs(value) do
		if key ~= 'schemaVersion' and key ~= 'equipment' and key ~= 'wardrobe' then
			return nil, 'unknown_field'
		end
	end
	if value.schemaVersion ~= Clothing.VERSION then return nil, 'unsupported_schema' end

	local equipment = value.equipment
	if type(equipment) ~= 'table' then return nil, 'invalid_equipment' end
	local canonical = {
		schemaVersion = Clothing.VERSION, equipment = {}, wardrobe = { outfits = {} },
	}
	for slot, item in pairs(equipment) do
		if not IS_SLOT[slot] then return nil, 'invalid_slot' end
		if recordOf(item) == nil then return nil, 'invalid_item' end
	end
	for index = 1, #SLOTS do
		local slot = SLOTS[index]
		canonical.equipment[slot] = recordOf(equipment[slot]) or false
	end

	local wardrobe = value.wardrobe
	if type(wardrobe) ~= 'table' then return nil, 'invalid_wardrobe' end
	for key in pairs(wardrobe) do
		if key ~= 'active' and key ~= 'outfits' then return nil, 'unknown_wardrobe_field' end
	end
	if wardrobe.active ~= nil then
		local active = outfitIndex(wardrobe.active)
		if active == nil or type(wardrobe.active) ~= 'number' then return nil, 'invalid_active' end
		canonical.wardrobe.active = active
	end

	local outfits = wardrobe.outfits
	if outfits ~= nil and type(outfits) ~= 'table' then return nil, 'invalid_outfits' end
	local seen, count = {}, 0
	for key, overrides in pairs(outfits or {}) do
		count = count + 1
		local index = outfitIndex(key)
		if count > OUTFITS or index == nil or seen[index] then return nil, 'invalid_outfit' end
		seen[index] = true
		if type(overrides) ~= 'table' then return nil, 'invalid_outfit' end
		local clean, any = {}, false
		for slot, item in pairs(overrides) do
			if not IS_OUTFIT_SLOT[slot] then return nil, 'invalid_outfit_slot' end
			local record = recordOf(item)
			if record == nil then return nil, 'invalid_item' end
			clean[slot], any = record, true
		end
		if any then canonical.wardrobe.outfits[tostring(index)] = clean end
	end

	return canonical
end

--- @author DemiAutomatic
--- @method OPX.Clothing.same
--- @description Answers whether two canonical records are the same clothing.
--- @param left {ClothingRecord|false|nil}
--- @param right {ClothingRecord|false|nil}
--- @returns {boolean}
function OPX.Clothing.same(left, right)
	if type(left) ~= 'table' or type(right) ~= 'table' then return false end
	for index = 1, #SLOTS do
		local slot = SLOTS[index]
		if left.equipment[slot] ~= right.equipment[slot] then return false end
	end
	if left.wardrobe.active ~= right.wardrobe.active then return false end
	for index = 0, OUTFITS - 1 do
		local a, b = left.wardrobe.outfits[tostring(index)], right.wardrobe.outfits[tostring(index)]
		if (a == nil) ~= (b == nil) then return false end
		if a ~= nil then
			for slot in pairs(IS_OUTFIT_SLOT) do
				if a[slot] ~= b[slot] then return false end
			end
		end
	end
	return true
end

--- @author DemiAutomatic
--- @method fetch
--- @description Reads and validates a character's stored clothing record.
--- @param citizenId {CitizenId}
--- @returns {Result}
local function fetch(citizenId)
	local fetched = OPX.Storage.Players.fetchClothing(citizenId)
	if not fetched.ok then return fetched end
	if fetched.value == nil then return Result.ok(false) end
	local canonical, reason = Clothing.canonical(fetched.value)
	if not canonical then return Result.err('clothing-unreadable', reason) end
	return Result.ok(canonical)
end

--- @author DemiAutomatic
--- @method OPX.Clothing.load
--- @description Answers what PlayerData.clothing starts as at login.
--- @param citizenId {CitizenId}
--- @returns {ClothingRecord|false|nil}
function OPX.Clothing.load(citizenId)
	local fetched = fetch(citizenId)
	if fetched.ok then return fetched.value end
	Open77.log.warn(('[clothing] %s: the stored clothing could not be read (%s: %s); it is ' ..
		'neither restored nor overwritten this session'):format(citizenId,
			tostring(fetched.error), tostring(fetched.detail)))
	return nil
end

--- @author DemiAutomatic
--- @method OPX.SaveClothing
--- @description Validates, stores and publishes what a character wears.
--- @param identifier {Player|Source|CitizenId}
--- @param clothing {any}
--- @returns {Result}
function OPX.SaveClothing(identifier, clothing)
	local player = OPX.ResolvePlayer(identifier)
	if not player then return Result.err('error.notLoggedIn', tostring(identifier)) end

	local canonical, reason = Clothing.canonical(clothing)
	if not canonical then return Result.err('clothing.invalid', reason) end

	local data = player.PlayerData
	if data.clothing == nil then
		return Result.err('error.unavailable', 'clothing_unavailable')
	end
	if Clothing.same(data.clothing, canonical) then return Result.ok(data.clothing) end

	local encoded = json.encode(canonical)
	if #encoded > MAX_JSON_BYTES then
		return Result.err('clothing.tooLarge', tostring(#encoded))
	end

	local written = OPX.Storage.Players.saveClothing(data.citizenId, encoded)
	if not written.ok then return written end
	data.clothing = canonical

	if not player.Offline and OPX.Players[data.source] == player then
		player.Functions.UpdatePlayerData()
		TriggerClientEvent(OPX.Events.Client.CLOTHING_UPDATE, data.source, canonical)
	end
	TriggerEvent(OPX.Events.Internal.CLOTHING_CHANGE, data.source, data.citizenId, canonical)

	OPX.Logger.player(player, 'clothing.saved', nil, { bytes = #encoded })
	return Result.ok(canonical)
end

--- @author DemiAutomatic
--- @method OPX.GetClothing
--- @description Answers the stored clothing for a character, online or not.
--- @param identifier {Player|Source|CitizenId}
--- @returns {Result}
function OPX.GetClothing(identifier)
	local player = OPX.ResolvePlayer(identifier)
	if player then return Result.ok(player.PlayerData.clothing) end
	if type(identifier) ~= 'string' then
		return Result.err('error.notLoggedIn', tostring(identifier))
	end
	return fetch(identifier)
end

--- @author DemiAutomatic
--- @event opx77:server:saveClothing
--- @description Stores what the connection's character wears, refusing a stale save.
--- @param payload {any}
RegisterNetEvent(OPX.Events.Server.SAVE_CLOTHING, function(payload)
	local src = tonumber(source)
	if not src then return end
	local operation = OPX.Operations.SAVE_CLOTHING
	if type(payload) ~= 'table' then
		return OPX.Refuse(src, 'error.badRequest', operation)
	end
	if OPX.Cooling(src, 'clothing.request', COOLDOWN_MS) then
		return OPX.Refuse(src, 'error.tooFast', operation)
	end

	local player = OPX.GetPlayer(src)
	if not player then return OPX.Refuse(src, 'error.notLoggedIn', operation) end
	if payload.citizenId ~= player.PlayerData.citizenId then
		return OPX.Refuse(src, 'clothing.stale', operation)
	end

	CreateThread(function()
		local saved = OPX.SaveClothing(player, payload.clothing)
		if not saved.ok then
			Open77.log.warn(('[clothing] %d: clothing not saved: %s (%s)')
				:format(src, tostring(saved.error), tostring(saved.detail)))
			OPX.Refuse(src, saved.error, operation)
		end
	end)
end)
