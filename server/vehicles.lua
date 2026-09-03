--- Vehicles a character owns. The plate is the identity, not the runtime id, and ownership is
--- proved against the character the connection has loaded rather than any client claim.

local Config = OPX.Config.VEHICLES
local Store = OPX.Storage.Vehicles
local Result = OPX.Result

local Vehicles = {}
OPX.Vehicles = Vehicles

--- plate -> { id, citizenId }. What is spawned right now, rebuilt from nothing on a reload.
local live = {}

--- The number `value` is, or nil when it is not a real finite one.
---@param value any
---@return number|nil
local function finiteNumber(value)
  value = tonumber(value)
  if not OPX.Math.isFinite(value) then return nil end
  return value
end

--- A plate in the configured shape. Uppercase ASCII only: the column is `ascii_bin`.
---@return string
local function plate()
  return OPX.String.random(Config.PLATE_FORMAT)
end

--- The character this connection has loaded, or nil.
---@param source Source
---@return table|nil
local function character(source)
  local player = OPX.GetPlayer(source)
  return player and player.PlayerData or nil
end

-- ---------------------------------------------------------------------------
-- Owning
-- ---------------------------------------------------------------------------

--- Give a character a vehicle. Coroutine only: it writes.
---@param citizenId string
---@param record string  a TweakDB record, e.g. "Vehicle.v_standard2_archer_hella_player"
---@param options? { garage?: string, appearance?: string, paint?: table, metadata?: table }
---@return table result  Result of the stored vehicle
function Vehicles.Give(citizenId, record, options)
  options = options or {}
  if type(citizenId) ~= "string" or type(record) ~= "string" or record == "" then
    return Result.err("error.badRequest", "citizenId and record are required")
  end
  -- the host caps the record at 256; refusing here keeps the reason readable
  if #record > 256 then return Result.err("vehicle.badRecord", "record is too long") end

  if Config.PER_CHARACTER > 0 then
    local owned = Store.countByOwner(citizenId)
    if not owned.ok then return owned end
    if owned.value >= Config.PER_CHARACTER then
      return Result.err("vehicle.limit", tostring(Config.PER_CHARACTER))
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
      Open77.log.info(("[vehicles] %s given %s (%s)")
        :format(citizenId, entity.plate, record))
      return Result.ok(entity)
    end
    -- a duplicate plate is the only failure worth retrying; anything else is the database
    if not tostring(inserted.detail or ""):find("Duplicate", 1, true) then return inserted end
  end
  return Result.err("vehicle.plateExhausted", entity and entity.plate or "?")
end

--- Every vehicle a character owns.
---@param citizenId string
---@return table result
function Vehicles.List(citizenId)
  return Store.fetchByOwner(citizenId)
end

--- The stored row, plus whether it is spawned right now.
---@param plateId string
---@return table result
function Vehicles.Get(plateId)
  local fetched = Store.fetchOne(plateId)
  if not fetched.ok then return fetched end
  local record = live[plateId]
  fetched.value.id = record and record.id or nil
  fetched.value.spawned = record ~= nil
  return fetched
end

-- ---------------------------------------------------------------------------
-- Spawning
-- ---------------------------------------------------------------------------

--- Puts a character's vehicle in the world beside them. Ownership is checked against the
--- loaded character, never against anything the caller sent. Coroutine only.
---@param source Source
---@param plateId string
---@return table result  Result of { plate, id }
function Vehicles.Spawn(source, plateId)
  local data = character(source)
  if not data then return Result.err("error.notLoggedIn", tostring(source)) end
  if type(plateId) ~= "string" then return Result.err("error.badRequest", "plate") end

  local fetched = Store.fetchOne(plateId)
  if not fetched.ok then return fetched end
  local vehicle = fetched.value
  if vehicle.citizenId ~= data.citizenId then
    OPX.Logger.security("vehicle.notYours",
      ("%s asked for %s"):format(data.citizenId, plateId),
      { owner = vehicle.citizenId }, source)
    -- the same code a missing plate gets: "somebody else's" is an existence oracle
    return Result.err("vehicle.notFound", plateId)
  end
  if live[plateId] then return Result.ok({ plate = plateId, id = live[plateId].id }) end

  local position = Open77.players.position(source)
  if position == nil then return Result.err("vehicle.noPosition", tostring(source)) end

  local id, reason = Open77.vehicles.create({
    record = vehicle.record,
    appearance = vehicle.appearance,
    position = { x = position.x + Config.SPAWN_OFFSET, y = position.y, z = position.z + 0.25 },
    bucket = position.bucket,
    health = vehicle.health,
    primaryColor = vehicle.paint and vehicle.paint.primary or nil,
    secondaryColor = vehicle.paint and vehicle.paint.secondary or nil,
  })
  if id == nil then return Result.err("vehicle.spawnRefused", tostring(reason)) end

  -- given back, or a store-then-spawn cycle is a free repair of glass, lights, tyres, dents
  -- and the destroyed flag
  if type(vehicle.damage) == "table" then
    Open77.vehicles.setDamage(id, vehicle.damage)
  end
  local flags = finiteNumber(vehicle.metadata and vehicle.metadata.flags)
  if flags ~= nil then Open77.vehicles.update(id, { flags = flags }) end

  -- re-read the connection: the fetch above yielded, and writing `live` for a character who
  -- has since left strands a vehicle nothing will ever store
  local still = character(source)
  if not still or still.citizenId ~= data.citizenId then
    Open77.vehicles.remove(id)
    return Result.err("error.notLoggedIn", tostring(source))
  end

  live[plateId] = { id = id, citizenId = data.citizenId }
  Store.setState(plateId, Store.STATE.OUT)
  OPX.Logger.player(OPX.GetPlayer(source), "vehicle.spawn", plateId, { id = tostring(id) })
  return Result.ok({ plate = plateId, id = id })
end

--- Takes it back off the world and writes what happened to it. Coroutine only.
---@param plateId string
---@param garage? string  where it belongs now; omitted keeps the one it had
---@return table result
function Vehicles.Store(plateId, garage)
  local record = live[plateId]
  if record == nil then return Result.err("vehicle.notSpawned", tostring(plateId)) end

  -- read before the remove: the snapshot is gone the moment the vehicle is
  local snapshot = Open77.vehicles.get(record.id)
  if snapshot ~= nil then
    local fetched = Store.fetchOne(plateId)
    if not fetched.ok then
      -- the removal below still happens, so say so: the condition is lost, not deferred
      Open77.log.error(("[vehicles] %s is being removed but its row could not be read (%s); " ..
        "its condition is not written"):format(plateId, tostring(fetched.detail)))
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

--- Everything this character has out, stored. Called on logout and on a resource stop.
---@param citizenId string|nil nil stores every live vehicle
---@return integer stored
function Vehicles.StoreAll(citizenId)
  -- plates collected BEFORE anything yields: a spawn landing mid-walk inserts a key into the
  -- table being iterated, which is Lua's undefined case for `next`
  local plates = {}
  for plateId, record in pairs(live) do
    if citizenId == nil or record.citizenId == citizenId then plates[#plates + 1] = plateId end
  end

  local stored = 0
  for index = 1, #plates do
    local plateId = plates[index]
    -- re-read: it may have been stored or removed while we were awaiting an earlier one
    if live[plateId] ~= nil and Vehicles.Store(plateId).ok then stored = stored + 1 end
  end
  return stored
end

-- ---------------------------------------------------------------------------
-- Keeping the world and the rows in step
-- ---------------------------------------------------------------------------

--- A character leaving takes its cars with it, so their condition is written rather than
--- lost to the host's next reload.
AddEventHandler(OPX.Events.Internal.PLAYER_UNLOADED, function(_, playerData)
  if type(playerData) ~= "table" then return end
  local stored = Vehicles.StoreAll(playerData.citizenId)
  if stored > 0 then
    Open77.log.debug(("[vehicles] %s left with %d vehicle(s) out")
      :format(playerData.citizenId, stored))
  end
end)

--- The host removed one: it was destroyed, or another resource took it.
AddEventHandler("onVehicleRemoved", function(id, reason)
  id = tonumber(id)
  for plateId, record in pairs(live) do
    if record.id == id then
      live[plateId] = nil
      Store.setState(plateId, Store.STATE.STORED)
      Open77.log.info(("[vehicles] %s removed: %s"):format(plateId, tostring(reason)))
      return
    end
  end
end)

--- Condition, written while the vehicle is still out. This loop is the guarantee that damage
--- is kept, not the stop handler below.
CreateThread(function()
  while true do
    Wait(Config.SAVE_SECONDS * 1000)
    -- keys snapshotted and each save wrapped: one raise would end condition persistence for
    -- the whole process, silently
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
        Open77.log.error(("[vehicles] saving %s: %s"):format(plateId, tostring(err)))
      end
    end
  end
end)

--- A resource stop removes every vehicle it owns, so the rows are written first. Not
--- dispatched to a thread: a stop does not resume one.
AddEventHandler("onResourceStop", function(name)
  if name ~= GetCurrentResourceName() then return end
  local stored = Vehicles.StoreAll(nil)
  if stored > 0 then
    Open77.log.info(("[vehicles] stored %d vehicle(s) on stop"):format(stored))
  end
end)

-- ---------------------------------------------------------------------------
-- Client to server
-- ---------------------------------------------------------------------------

--- A player asking for one of their own cars. Everything is re-derived: the character from
--- the connection, the ownership from the row.
RegisterNetEvent(OPX.Events.Server.SPAWN_VEHICLE, function(payload)
  local src = tonumber(source)
  if not src then return end
  local operation = OPX.Operations.SPAWN_VEHICLE
  local plateId = type(payload) == "table" and payload.plate or nil
  if type(plateId) ~= "string" then
    return OPX.Refuse(src, "error.badRequest", operation)
  end
  if OPX.Cooling(src, "vehicle.spawn", 3000) then
    return OPX.Refuse(src, "error.tooFast", operation)
  end

  CreateThread(function()
    local spawned = Vehicles.Spawn(src, plateId)
    if not spawned.ok then
      OPX.Refuse(src, spawned.error, operation)
      OPX.NotifyLocale(src, spawned.error, nil, "error")
      return
    end
    OPX.NotifyLocale(src, "vehicle.spawned", { plate = plateId }, "success")
  end)
end)

RegisterNetEvent(OPX.Events.Server.STORE_VEHICLE, function(payload)
  local src = tonumber(source)
  if not src then return end
  local operation = OPX.Operations.STORE_VEHICLE
  local plateId = type(payload) == "table" and payload.plate or nil
  if type(plateId) ~= "string" then
    return OPX.Refuse(src, "error.badRequest", operation)
  end
  if OPX.Cooling(src, "vehicle.store", 3000) then
    return OPX.Refuse(src, "error.tooFast", operation)
  end

  CreateThread(function()
    -- ownership before anything is taken off the world: `live` is keyed by plate, so a
    -- player could otherwise store somebody else's car by naming it
    local data = character(src)
    local record = live[plateId]
    if not data or record == nil or record.citizenId ~= data.citizenId then
      return OPX.Refuse(src, "vehicle.notFound", operation)
    end
    local put = Vehicles.Store(plateId)
    if not put.ok then return OPX.Refuse(src, put.error, operation) end
    OPX.NotifyLocale(src, "vehicle.stored", { plate = plateId }, "success")
  end)
end)
