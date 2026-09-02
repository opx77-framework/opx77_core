--- Vehicles a character owns: what exists, who owns it, and where it is.
---
--- The runtime id is not the identity. `Open77.vehicles.create` issues a 64-bit id, and the
--- documented policy is that stopping or reloading a resource removes every vehicle it owns
--- -- so the id is gone every reload while the car is not. The PLATE is the durable name, it
--- is what the row is keyed on, and every export takes one.
---
--- Ownership is proved here and nowhere else. A client names a plate; this file compares the
--- row's `citizen_id` against the character the connection has loaded, which is the row this
--- VM read. There is no client claim in that comparison.

local Config = OPX_VEHICLES
local Store = OPX.Storage.Vehicles
local Result = OPX.Result
local log = OPX.Log.scope("vehicles")

local Vehicles = {}
OPX.Vehicles = Vehicles

--- plate -> { id, citizenId, bucket }. What is spawned right now. Rebuilt from nothing on a
--- reload, because the host removed every vehicle this resource owned when it stopped.
local live = {}

---@return integer
local function nowMs()
  return math.floor(Open77.time.monotonic() * 1000)
end

--- The same predicate as `finite` elsewhere in this framework, coercing first and answering
--- with the number: anything `tonumber` accepts, so long as it is neither NaN nor either
--- infinity. It carries no range of its own -- a caller that needs one applies it to the
--- answer -- so that "finite" means exactly one thing everywhere and a bound stays visible
--- where it bites.
---@param value any
---@return number|nil
local function finiteNumber(value)
  value = tonumber(value)
  -- `value ~= value` is the NaN check, not a typo: NaN is the one value unequal to itself
  if value == nil or value ~= value or value == math.huge or value == -math.huge then
    return nil
  end
  return value
end

--- A plate in the configured shape. Uppercase ASCII only: the column is `ascii_bin`, and a
--- plate is compared for equality far more often than it is read.
---@return string
local function plate()
  local out = {}
  for index = 1, #Config.PLATE_FORMAT do
    local slot = Config.PLATE_FORMAT:sub(index, index)
    if slot == "1" then
      out[index] = tostring(math.random(0, 9))
    elseif slot == "A" then
      out[index] = string.char(math.random(65, 90))
    else
      out[index] = slot
    end
  end
  return table.concat(out)
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
      log.info(("%s given %s (%s)"):format(citizenId, entity.plate, record))
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

--- Put a character's vehicle in the world beside them.
---
--- Ownership is checked against the loaded character, never against anything the caller sent.
--- Coroutine only.
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

  -- Given BACK. Without this the row's damage is write-only and a store-then-spawn cycle is a
  -- free repair of glass, lights, tyres, dents and the destroyed flag -- the one thing the
  -- platform deliberately refuses a client.
  if type(vehicle.damage) == "table" then
    Open77.vehicles.setDamage(id, vehicle.damage)
  end
  local flags = tonumber(vehicle.metadata and vehicle.metadata.flags)
  if flags ~= nil then Open77.vehicles.update(id, { flags = flags }) end

  -- re-read the connection: `Store.fetchOne` above yielded, and the player may have switched
  -- character or left in that window. Writing `live` for a character that is gone strands a
  -- vehicle nothing will ever store, because the departure sweep has already run.
  local still = character(source)
  if not still or still.citizenId ~= data.citizenId then
    Open77.vehicles.remove(id)
    return Result.err("error.notLoggedIn", tostring(source))
  end

  live[plateId] = { id = id, citizenId = data.citizenId, bucket = position.bucket,
                    atMs = nowMs() }
  Store.setState(plateId, Store.STATE.OUT)
  OPX.Logger.player(OPX.GetPlayer(source), "vehicle.spawn", plateId, { id = tostring(id) })
  return Result.ok({ plate = plateId, id = id })
end

--- Take it back off the world and write what happened to it.
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
    if fetched.ok then
      local vehicle = fetched.value
      vehicle.health = finiteNumber(snapshot.health) or vehicle.health
      vehicle.damage = Open77.vehicles.getDamage(record.id)
      vehicle.metadata = vehicle.metadata or {}
      vehicle.metadata.flags = tonumber(snapshot.flags) or nil
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
---@param citizenId string
---@return integer stored
function Vehicles.StoreAll(citizenId)
  -- The plates are collected BEFORE anything yields. `Vehicles.Store` awaits the database
  -- twice, and a spawn landing during either one inserts a key into the table being walked --
  -- which is Lua's undefined case for `next`: the rehash silently skips entries, and a car
  -- that is skipped here is left in the street with nobody connected.
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

--- A character leaving takes its cars with it. Without this they sit in the street with an
--- owner who is not connected, and the host removes them on the next reload anyway -- with
--- whatever damage they took since the last save unwritten.
AddEventHandler(OPX.Events.Internal.PLAYER_UNLOADED, function(_, playerData)
  if type(playerData) ~= "table" then return end
  local stored = Vehicles.StoreAll(playerData.citizenId)
  if stored > 0 then
    log.debug(("%s left with %d vehicle(s) out"):format(playerData.citizenId, stored))
  end
end)

--- The host removed one: it was destroyed, or another resource took it. Forget the id rather
--- than trying to write through it.
AddEventHandler("onVehicleRemoved", function(id, reason)
  id = tonumber(id)
  for plateId, record in pairs(live) do
    if record.id == id then
      live[plateId] = nil
      Store.setState(plateId, Store.STATE.STORED)
      log.info(("%s removed: %s"):format(plateId, tostring(reason)))
      return
    end
  end
end)

--- Condition, written while the vehicle is still out. Damage a player took thirty minutes ago
--- is lost otherwise: the row is only written when the car is put away, and a crash, a reload
--- or a disconnect at the wrong moment never gets there.
CreateThread(function()
  while true do
    Wait(Config.SAVE_SECONDS * 1000)
    -- snapshot the keys first, for the reason StoreAll does; and wrapped, because this is a
    -- bare `while true` with no restart -- one raise ends condition persistence for the whole
    -- process, silently, and the only writes left would be put-away and logout
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
        vehicle.metadata.flags = tonumber(snapshot.flags) or nil
        Store.save(vehicle)
      end)
      if not ok then log.error(("saving %s: %s"):format(plateId, tostring(err))) end
    end
  end
end)

--- A resource stop removes every vehicle it owns, so the rows are written first.
AddEventHandler("onResourceStop", function(name)
  if name ~= GetCurrentResourceName() then return end
  -- Not dispatched to a thread: a stop does not resume one. Every database call here yields,
  -- so whether the rows land depends on how far the host lets this handler run -- which is
  -- why the periodic save above exists and is the guarantee, not this.
  local stored = Vehicles.StoreAll(nil)
  if stored > 0 then log.info(("stored %d vehicle(s) on stop"):format(stored)) end
end)

-- ---------------------------------------------------------------------------
-- Client to server
-- ---------------------------------------------------------------------------

--- A player asking for one of their own cars. Everything is re-derived: the character comes
--- from the connection, the ownership from the row.
RegisterNetEvent(OPX.Events.Server.SPAWN_VEHICLE, function(payload)
  local src = tonumber(source)
  if not src then return end
  local plateId = type(payload) == "table" and payload.plate or nil
  if type(plateId) ~= "string" then return OPX.Refuse(src, "error.badRequest") end
  if OPX.Cooling(src, "vehicle.spawn", 3000) then
    return OPX.Refuse(src, "error.tooFast")
  end

  CreateThread(function()
    local spawned = Vehicles.Spawn(src, plateId)
    if not spawned.ok then
      OPX.Refuse(src, spawned.error)
      OPX.NotifyLocale(src, spawned.error, nil, "error")
      return
    end
    OPX.NotifyLocale(src, "vehicle.spawned", { plate = plateId }, "success")
  end)
end)

RegisterNetEvent(OPX.Events.Server.STORE_VEHICLE, function(payload)
  local src = tonumber(source)
  if not src then return end
  local plateId = type(payload) == "table" and payload.plate or nil
  if type(plateId) ~= "string" then return OPX.Refuse(src, "error.badRequest") end
  if OPX.Cooling(src, "vehicle.store", 3000) then
    return OPX.Refuse(src, "error.tooFast")
  end

  CreateThread(function()
    -- ownership, before anything is taken off the world: `live` is keyed by plate and a
    -- player could otherwise store somebody else's car by naming its plate
    local data = character(src)
    local record = live[plateId]
    if not data or record == nil or record.citizenId ~= data.citizenId then
      return OPX.Refuse(src, "vehicle.notFound")
    end
    local put = Vehicles.Store(plateId)
    if not put.ok then return OPX.Refuse(src, put.error) end
    OPX.NotifyLocale(src, "vehicle.stored", { plate = plateId }, "success")
  end)
end)
