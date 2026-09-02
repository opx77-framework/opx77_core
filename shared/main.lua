--- The OPX namespace: one global, and everything hangs off it.

OPX = OPX or {}

OPX.VERSION = "0.2.0"

--- Read off a global only one runtime has -- both are installed by the bootstrap before any
--- script runs. Not Open77.database: that is only installed with `database.access`.
OPX.IsServer = rawget(_G, "TriggerClientEvent") ~= nil
OPX.IsClient = rawget(_G, "TriggerServerEvent") ~= nil

--- Filled in by config/shared.lua, config/server.lua and config/client.lua. SERVER is nil on
--- a client and CLIENT is nil on the server, so a wrong-side read fails loudly.
OPX.Config = OPX.Config or {}

--- Event names, `opx77:<side>:<subject>`. No name appears in two tables: a `TriggerEvent`
--- also reaches `RegisterNetEvent` handlers of the same name.
OPX.Events = {
  --- Owned by Open2077, not by us; listed so there is one place to update if they move.
  Platform = {
    PLAYER_CONNECTED = "onPlayerConnected",
    PLAYER_READY = "onPlayerReady",
    RESOURCE_START = "onClientResourceStart",
    RESOURCE_STOP = "onClientResourceStop",
    WORLD_READY = "open77:worldReady",
  },

  --- server -> client. A listener holds `network.events` and uses `RegisterNetEvent`.
  Client = {
    CHARACTERS = "opx77:client:characters",
    PLAYER_LOADED = "opx77:client:playerLoaded",
    PLAYER_UNLOADED = "opx77:client:playerUnloaded",
    SET_PLAYER_DATA = "opx77:client:setPlayerData",
    MONEY_CHANGE = "opx77:client:onMoneyChange",
    JOB_UPDATE = "opx77:client:onJobUpdate",
    GANG_UPDATE = "opx77:client:onGangUpdate",
    APPEARANCE_UPDATE = "opx77:client:onAppearanceUpdate",
    NOTIFY = "opx77:client:notify",
  },

  --- client -> server. Every payload is attacker-controlled; only `source` cannot be forged.
  Server = {
    READY = "opx77:server:ready",
    SELECT_CHARACTER = "opx77:server:selectCharacter",
    CREATE_CHARACTER = "opx77:server:createCharacter",
    DELETE_CHARACTER = "opx77:server:deleteCharacter",
    REPORT_POSITION = "opx77:server:reportPosition",
    SAVE_APPEARANCE = "opx77:server:saveAppearance",
    SPAWN_VEHICLE = "opx77:server:spawnVehicle",
    STORE_VEHICLE = "opx77:server:storeVehicle",
  },

  --- Fired by the core's client half after its mirror is updated, so a handler can read
  --- `OPX.GetPlayerData()` and see the change. Plain `AddEventHandler`, no permission.
  Local = {
    CHARACTERS_READY = "opx77:client:charactersReady",
    PLAYER_LOADED = "opx77:client:onPlayerLoaded",
    PLAYER_UNLOADED = "opx77:client:onPlayerUnloaded",
    PLAYER_DATA_CHANGED = "opx77:client:playerDataChanged",
    MONEY_CHANGED = "opx77:client:moneyChanged",
    JOB_CHANGED = "opx77:client:jobChanged",
    GANG_CHANGED = "opx77:client:gangChanged",
    APPEARANCE_SAVED = "opx77:client:appearanceSaved",
    REFUSED = "opx77:client:refused",
    APPEARANCE_REQUIRED = "opx77:client:appearanceRequired",
    APPEARANCE_CHANGED = "opx77:client:appearanceChanged",
  },

  --- Resource-local, between core files. These never cross the wire.
  Internal = {
    PLAYER_LOADED = "opx77:player:loaded",
    PLAYER_UNLOADED = "opx77:player:unloaded",
    MONEY_CHANGE = "opx77:player:moneyChange",
    JOB_UPDATE = "opx77:player:jobUpdate",
    GANG_UPDATE = "opx77:player:gangUpdate",
    APPEARANCE_CHANGE = "opx77:player:appearanceChange",
    PAYCHECK = "opx77:player:paycheck",
  },
}

--- Which request a refusal answers: on `Events.Client.NOTIFY`, and the third argument of
--- `Events.Local.REFUSED`. Named after the `Events.Server` request that starts it.
OPX.Operations = {
  ENTRY = "entry",
  ROSTER = "ready",
  SELECT_CHARACTER = "selectCharacter",
  CREATE_CHARACTER = "createCharacter",
  DELETE_CHARACTER = "deleteCharacter",
  SAVE_APPEARANCE = "saveAppearance",
  SPAWN_VEHICLE = "spawnVehicle",
  STORE_VEHICLE = "storeVehicle",
}
