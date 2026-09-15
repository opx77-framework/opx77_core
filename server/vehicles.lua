--- @author DemiAutomatic
--- @file server/vehicles.lua
--- @description Owned vehicles: giving, spawning, storing and keeping their condition.

--- @author DemiAutomatic
--- @type {table}
--- @description The server-only vehicle configuration.
local Config = OPX.Config.VEHICLES

--- @author DemiAutomatic
--- @type {table}
--- @description The statements for the vehicles table.
local Store = OPX.Storage.Vehicles

--- @author DemiAutomatic
--- @type {table}
--- @description The success and failure constructors.
local Result = OPX.Result

OPX.Vehicles = {}
local Vehicles = OPX.Vehicles

--- @author DemiAutomatic
--- @type {table<string, table>}
--- @description Spawned vehicles by plate, with runtime id and owner.
local live = {}

--- @author DemiAutomatic
--- @method finiteNumber
--- @description Answers a value as a finite number, or nil.
--- @param value {any}
--- @returns {number|nil}
local function finiteNumber(value)
	value = tonumber(value)
	if not OPX.Math.isFinite(value) then return nil end
	return value
end

--- @author DemiAutomatic
--- @method plate
--- @description Draws a plate in the configured PLATE_FORMAT shape.
--- @returns {string}
local function plate()
	return OPX.String.random(Config.PLATE_FORMAT)
end

--- @author DemiAutomatic
--- @method character
--- @description Answers the PlayerData this connection has loaded, or nil.
--- @param source {Source}
--- @returns {table|nil}
local function character(source)
	local player = OPX.GetPlayer(source)
	return player and player.PlayerData or nil
end

--- @author DemiAutomatic
--- @method OPX.Vehicles.Give
--- @description Stores a new vehicle for a character under a fresh plate.
--- @param citizenId {string}
--- @param record {string} A TweakDB vehicle record.
--- @param options {table|nil}
--- @returns {Result}
function OPX.Vehicles.Give(citizenId, record, options)
	options = options or {}
	if type(citizenId) ~= 'string' or type(record) ~= 'string' or record == '' then
		return Result.err('error.badRequest', 'citizenId and record are required')
	end
	if #record > 256 then return Result.err('vehicle.badRecord', 'record is too long') end

	if Config.PER_CHARACTER > 0 then
		local owned = Store.countByOwner(citizenId)
		if not owned.ok then return owned end
		if owned.value >= Config.PER_CHARACTER then
			return Result.err('vehicle.limit', tostring(Config.PER_CHARACTER))
		end
	end

	local entity
	for _ = 1, 5 do
		entity = {
			plate = plate(),
			citizenId = citizenId,
			record = record,
			appearance = options.appearance,
			garage = options.garage or Config.DEFAULT_GARAGE,
			state = Store.STATE.STORED,
			health = 1.0,
			paint = options.paint,
			metadata = options.metadata or {},
		}
		local inserted = Store.insert(entity)
		if inserted.ok then
			Open77.log.info(('[vehicles] %s given %s (%s)')
				:format(citizenId, entity.plate, record))
			return Result.ok(entity)
		end
		if not tostring(inserted.detail or ''):find('Duplicate', 1, true) then return inserted end
	end
	return Result.err('vehicle.plateExhausted', entity and entity.plate or '?')
end

--- @author DemiAutomatic
--- @method OPX.Vehicles.List
--- @description Answers every vehicle a character owns.
--- @param citizenId {string}
--- @returns {Result}
function OPX.Vehicles.List(citizenId)
	return Store.fetchByOwner(citizenId)
end

--- @author DemiAutomatic
--- @method OPX.Vehicles.PlateOf
--- @description Answers the plate and owner of a vehicle the core spawned.
--- @param vehicleId {integer}
--- @returns {string|nil, string|nil}
function OPX.Vehicles.PlateOf(vehicleId)
	for plateId, record in pairs(live) do
		if record.id == vehicleId then return plateId, record.citizenId end
	end
	return nil, nil
end

--- @author DemiAutomatic
--- @method OPX.Vehicles.Get
--- @description Answers the stored row and whether it is spawned now.
--- @param plateId {string}
--- @returns {Result}
function OPX.Vehicles.Get(plateId)
	local fetched = Store.fetchOne(plateId)
	if not fetched.ok then return fetched end
	local record = live[plateId]
	fetched.value.id = record and record.id or nil
	fetched.value.spawned = record ~= nil
	return fetched
end

--- @author DemiAutomatic
--- @method OPX.Vehicles.Spawn
--- @description Spawns a loaded character's own vehicle beside them.
--- @param source {Source}
--- @param plateId {string}
--- @returns {Result}
function OPX.Vehicles.Spawn(source, plateId)
	local data = character(source)
	if not data then return Result.err('error.notLoggedIn', tostring(source)) end
	if type(plateId) ~= 'string' then return Result.err('error.badRequest', 'plate') end

	local fetched = Store.fetchOne(plateId)
	if not fetched.ok then return fetched end
	local vehicle = fetched.value
	if vehicle.citizenId ~= data.citizenId then
		OPX.Logger.security('vehicle.notYours',
			('%s asked for %s'):format(data.citizenId, plateId),
			{ owner = vehicle.citizenId }, source)
		return Result.err('vehicle.notFound', plateId)
	end
	if live[plateId] then return Result.ok({ plate = plateId, id = live[plateId].id }) end

	local position = Open77.players.position(source)
	if position == nil then return Result.err('vehicle.noPosition', tostring(source)) end

	local id, reason = Open77.vehicles.create({
		record = vehicle.record,
		appearance = vehicle.appearance,
		position = { x = position.x + Config.SPAWN_OFFSET, y = position.y, z = position.z + 0.25 },
		bucket = position.bucket,
		health = vehicle.health,
		primaryColor = vehicle.paint and vehicle.paint.primary or nil,
		secondaryColor = vehicle.paint and vehicle.paint.secondary or nil,
	})
	if id == nil then return Result.err('vehicle.spawnRefused', tostring(reason)) end

	if type(vehicle.damage) == 'table' then
		Open77.vehicles.setDamage(id, vehicle.damage)
	end
	local flags = finiteNumber(vehicle.metadata and vehicle.metadata.flags)
	if flags ~= nil then Open77.vehicles.update(id, { flags = flags }) end

	local still = character(source)
	if not still or still.citizenId ~= data.citizenId then
		Open77.vehicles.remove(id)
		return Result.err('error.notLoggedIn', tostring(source))
	end

	live[plateId] = { id = id, citizenId = data.citizenId }
	Store.setState(plateId, Store.STATE.OUT)
	OPX.Logger.player(OPX.GetPlayer(source), 'vehicle.spawn', plateId, { id = tostring(id) })
	return Result.ok({ plate = plateId, id = id })
end

--- @author DemiAutomatic
--- @method OPX.Vehicles.Store
--- @description Removes a spawned vehicle and writes its condition back.
--- @param plateId {string}
--- @param garage {string|nil} Omitted keeps the current garage.
--- @returns {Result}
function OPX.Vehicles.Store(plateId, garage)
	local record = live[plateId]
	if record == nil then return Result.err('vehicle.notSpawned', tostring(plateId)) end

	local snapshot = Open77.vehicles.get(record.id)
	if snapshot ~= nil then
		local fetched = Store.fetchOne(plateId)
		if not fetched.ok then
			Open77.log.error(('[vehicles] %s is being removed but its row could not be read (%s); ' ..
				'its condition is not written'):format(plateId, tostring(fetched.detail)))
		else
			local vehicle = fetched.value
			vehicle.health = finiteNumber(snapshot.health) or vehicle.health
			vehicle.damage = Open77.vehicles.getDamage(record.id)
			vehicle.metadata = vehicle.metadata or {}
			vehicle.metadata.flags = finiteNumber(snapshot.flags)
			vehicle.state = Store.STATE.STORED
			if garage ~= nil then vehicle.garage = garage end
			Store.save(vehicle)
		end
	else
		Store.setState(plateId, Store.STATE.STORED, garage)
	end

	Open77.vehicles.remove(record.id)
	live[plateId] = nil
	return Result.ok({ plate = plateId })
end

--- @author DemiAutomatic
--- @method OPX.Vehicles.StoreAll
--- @description Stores every spawned vehicle of one character, or of everyone.
--- @param citizenId {string|nil}
--- @returns {integer}
function OPX.Vehicles.StoreAll(citizenId)
	local plates = {}
	for plateId, record in pairs(live) do
		if citizenId == nil or record.citizenId == citizenId then plates[#plates + 1] = plateId end
	end

	local stored = 0
	for index = 1, #plates do
		local plateId = plates[index]
		if live[plateId] ~= nil and Vehicles.Store(plateId).ok then stored = stored + 1 end
	end
	return stored
end

--- @author DemiAutomatic
--- @event opx77:player:unloaded
--- @description Stores the vehicles a departing character left out.
--- @param _ {Source}
--- @param playerData {PlayerData}
AddEventHandler(OPX.Events.Internal.PLAYER_UNLOADED, function(_, playerData)
	if type(playerData) ~= 'table' then return end
	local stored = Vehicles.StoreAll(playerData.citizenId)
	if stored > 0 then
		Open77.log.debug(('[vehicles] %s left with %d vehicle(s) out')
			:format(playerData.citizenId, stored))
	end
end)

--- @author DemiAutomatic
--- @event onVehicleRemoved
--- @description Forgets a spawned vehicle the host removed and marks it stored.
--- @param id {integer|string}
--- @param reason {string}
AddEventHandler('onVehicleRemoved', function(id, reason)
	id = tonumber(id)
	for plateId, record in pairs(live) do
		if record.id == id then
			live[plateId] = nil
			Store.setState(plateId, Store.STATE.STORED)
			Open77.log.info(('[vehicles] %s removed: %s'):format(plateId, tostring(reason)))
			return
		end
	end
end)

CreateThread(function()
	while true do
		Wait(Config.SAVE_SECONDS * 1000)
		local plates = {}
		for plateId in pairs(live) do plates[#plates + 1] = plateId end

		for index = 1, #plates do
			local plateId = plates[index]
			local ok, err = pcall(function()
				local record = live[plateId]
				if record == nil then return end
				local snapshot = Open77.vehicles.get(record.id)
				if snapshot == nil then return end
				local fetched = Store.fetchOne(plateId)
				if not fetched.ok then return end
				local vehicle = fetched.value
				vehicle.health = finiteNumber(snapshot.health) or vehicle.health
				vehicle.damage = Open77.vehicles.getDamage(record.id)
				vehicle.metadata = vehicle.metadata or {}
				vehicle.metadata.flags = finiteNumber(snapshot.flags)
				Store.save(vehicle)
			end)
			if not ok then
				Open77.log.error(('[vehicles] saving %s: %s'):format(plateId, tostring(err)))
			end
		end
	end
end)

--- @author DemiAutomatic
--- @event onResourceStop
--- @description Stores every spawned vehicle before the core stops.
--- @param name {string}
AddEventHandler('onResourceStop', function(name)
	if name ~= GetCurrentResourceName() then return end
	local stored = Vehicles.StoreAll(nil)
	if stored > 0 then
		Open77.log.info(('[vehicles] stored %d vehicle(s) on stop'):format(stored))
	end
end)

--- @author DemiAutomatic
--- @event opx77:server:spawnVehicle
--- @description Spawns one of the connection's own vehicles by plate.
--- @param payload {any}
RegisterNetEvent(OPX.Events.Server.SPAWN_VEHICLE, function(payload)
	local src = tonumber(source)
	if not src then return end
	local operation = OPX.Operations.SPAWN_VEHICLE
	local plateId = type(payload) == 'table' and payload.plate or nil
	if type(plateId) ~= 'string' then
		return OPX.Refuse(src, 'error.badRequest', operation)
	end
	if OPX.Cooling(src, 'vehicle.spawn', 3000) then
		return OPX.Refuse(src, 'error.tooFast', operation)
	end

	CreateThread(function()
		local spawned = Vehicles.Spawn(src, plateId)
		if not spawned.ok then
			OPX.Refuse(src, spawned.error, operation)
			OPX.NotifyLocale(src, spawned.error, nil, 'error')
			return
		end
		OPX.NotifyLocale(src, 'vehicle.spawned', { plate = plateId }, 'success')
	end)
end)

--- @author DemiAutomatic
--- @event opx77:server:storeVehicle
--- @description Stores one of the connection's own spawned vehicles by plate.
--- @param payload {any}
RegisterNetEvent(OPX.Events.Server.STORE_VEHICLE, function(payload)
	local src = tonumber(source)
	if not src then return end
	local operation = OPX.Operations.STORE_VEHICLE
	local plateId = type(payload) == 'table' and payload.plate or nil
	if type(plateId) ~= 'string' then
		return OPX.Refuse(src, 'error.badRequest', operation)
	end
	if OPX.Cooling(src, 'vehicle.store', 3000) then
		return OPX.Refuse(src, 'error.tooFast', operation)
	end

	CreateThread(function()
		local data = character(src)
		local record = live[plateId]
		if not data or record == nil or record.citizenId ~= data.citizenId then
			return OPX.Refuse(src, 'vehicle.notFound', operation)
		end
		local put = Vehicles.Store(plateId)
		if not put.ok then return OPX.Refuse(src, put.error, operation) end
		OPX.NotifyLocale(src, 'vehicle.stored', { plate = plateId }, 'success')
	end)
end)
