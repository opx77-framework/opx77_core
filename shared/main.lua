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
---
--- A satellite has TWO ways to hear the core, and they are different channels with
--- different requirements. `Client` is the networked one: the server sends it, so a listener
--- must hold `network.events` and register with `RegisterNetEvent`. `Local` is fired by the
--- core's own client half right after it has updated its mirror; a listener registers with a
--- plain `AddEventHandler` and needs no permission at all. Both are public and supported.
---
--- No name appears in both tables. On this platform a `TriggerEvent` also reaches
--- `RegisterNetEvent` handlers of the same name -- the dispatcher matches on the name and
--- never looks at the network flag -- so a local re-emission that reused its own wire name
--- would re-enter the handler that fired it. It is tick-paced rather than recursive, which
--- makes it a silent permanent busy loop instead of a stack overflow: nothing crashes and
--- nothing is logged. Keeping the two vocabularies disjoint is what prevents it.
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

  --- Fired by the core's client half with `TriggerEvent`, after the mirrored state has
  --- already been updated -- so a handler can read `OPX.GetPlayerData()` and see the change
  --- that woke it. Heard with a plain `AddEventHandler`, from any resource: the CLIENT local
  --- event bus is host-wide, which the platform's own resources rely on (open77_zones fires a
  --- caller-supplied event name and pursuit receives it with a bare `AddEventHandler`).
  --- This is the channel a satellite should prefer; `Client` below is for one that would
  --- rather take the wire itself.
  Local = {
    CHARACTERS_READY = "opx77:client:charactersReady",
    PLAYER_LOADED = "opx77:client:onPlayerLoaded",
    PLAYER_UNLOADED = "opx77:client:onPlayerUnloaded",
    PLAYER_DATA_CHANGED = "opx77:client:playerDataChanged",
    MONEY_CHANGED = "opx77:client:moneyChanged",
    JOB_CHANGED = "opx77:client:jobChanged",
    GANG_CHANGED = "opx77:client:gangChanged",
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
    PAYCHECK = "opx77:player:paycheck",
  },
}
