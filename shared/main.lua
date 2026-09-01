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

--- Event names, in one place. Naming is `opx77:<side>:<subject>`.
OPX.Events = {
  --- Owned by Open2077, not by us; listed so there is one place to update if they move.
  Platform = {
    PLAYER_CONNECTED = "onPlayerConnected",
    PLAYER_READY = "onPlayerReady",
    RESOURCE_START = "onClientResourceStart",
    RESOURCE_STOP = "onClientResourceStop",
    WORLD_READY = "open77:worldReady",
  },

  --- server -> client
  Client = {
    CHARACTERS = "opx77:client:characters",
    PLAYER_LOADED = "opx77:client:playerLoaded",
    PLAYER_UNLOADED = "opx77:client:playerUnloaded",
    SET_PLAYER_DATA = "opx77:client:setPlayerData",
    MONEY_CHANGE = "opx77:client:onMoneyChange",
    JOB_UPDATE = "opx77:client:onJobUpdate",
    GANG_UPDATE = "opx77:client:onGangUpdate",
    NOTIFY = "opx77:client:notify",
  },

  --- client -> server. Every payload is attacker-controlled; only `source` cannot be forged.
  Server = {
    READY = "opx77:server:ready",
    SELECT_CHARACTER = "opx77:server:selectCharacter",
    CREATE_CHARACTER = "opx77:server:createCharacter",
    DELETE_CHARACTER = "opx77:server:deleteCharacter",
    REPORT_POSITION = "opx77:server:reportPosition",
    SPAWN_VEHICLE = "opx77:server:spawnVehicle",
    STORE_VEHICLE = "opx77:server:storeVehicle",
  },

  --- Resource-local, between core files. These never cross the wire.
  Internal = {
    PLAYER_LOADED = "opx77:player:loaded",
    PLAYER_UNLOADED = "opx77:player:unloaded",
    MONEY_CHANGE = "opx77:player:moneyChange",
    JOB_UPDATE = "opx77:player:jobUpdate",
    GANG_UPDATE = "opx77:player:gangUpdate",
    PAYCHECK = "opx77:player:paycheck",
  },
}
