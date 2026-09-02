--- Every server-to-client handler, in the same three steps: update the mirrored state, fire
--- the local event, log. The order matters -- the state is written before the event, so a
--- handler woken by it reads the change rather than the value it replaced.
---
--- This publishes the core's state on TWO channels, and a satellite picks one:
---
---   networked -- `OPX.Events.Client.*`, the `opx77:client:*` names the server sends. A
---     listener holds `network.events` and registers with `RegisterNetEvent`. These are the
---     wire and they do not change.
---   local -- `OPX.Events.Local.*`, fired below with `TriggerEvent`. A listener registers
---     with a plain `AddEventHandler` and needs no permission. The client's local event bus
---     is host-wide, so this reaches any resource, not only this one.
---
--- The two vocabularies are deliberately disjoint. A `TriggerEvent` here would also reach
--- every `RegisterNetEvent` handler of the same name -- the dispatcher matches on the name
--- and ignores the network flag -- so re-emitting a wire name from inside its own handler
--- re-enters that handler. Tick-paced rather than recursive, so it is a silent permanent busy
--- loop rather than a crash. `playerLoaded` and `playerUnloaded` used to do exactly that.

local log = OPX.Log.scope("events")
local Events = OPX.Events
local Local = Events.Local

RegisterNetEvent(Events.Client.CHARACTERS, function(payload)
  if type(payload) ~= "table" then return end

  -- Typed before they are stored, and before the log line. `#` on a non-table and `%d` on a
  -- non-integer both raise, and the raise landed BETWEEN the state write and the broadcast --
  -- leaving a half-applied roster no listener was ever told about.
  local list = type(payload.characters) == "table" and payload.characters or {}
  local slots = math.floor(tonumber(payload.slots) or 0)
  if slots < 0 then slots = 0 end

  -- fields, never the table: every export holds a reference to OPX.Characters
  OPX.Characters.list = list
  OPX.Characters.slots = slots
  OPX.Characters.origins = type(payload.origins) == "table" and payload.origins or {}

  log.info(("%d character(s) available, %d slot(s)"):format(#list, slots))
  TriggerEvent(Local.CHARACTERS_READY, OPX.Characters)
end)

RegisterNetEvent(Events.Client.PLAYER_LOADED, function(playerData)
  if type(playerData) ~= "table" then return end
  OPX.PlayerData = playerData
  OPX.IsLoggedIn = true

  log.info(("loaded %s (%s %s)"):format(
    tostring(playerData.citizenId),
    tostring(playerData.charInfo and playerData.charInfo.firstName),
    tostring(playerData.charInfo and playerData.charInfo.lastName)))
  TriggerEvent(Local.PLAYER_LOADED, playerData)
end)

RegisterNetEvent(Events.Client.PLAYER_UNLOADED, function()
  OPX.PlayerData = {}
  OPX.IsLoggedIn = false
  TriggerEvent(Local.PLAYER_UNLOADED)
end)

--- The whole of PlayerData, resent after any change. Whole rather than a patch: a merge
--- protocol is a class of bug where the two copies drift and neither can tell.
RegisterNetEvent(Events.Client.SET_PLAYER_DATA, function(playerData)
  if type(playerData) ~= "table" then return end
  OPX.PlayerData = playerData
  TriggerEvent(Local.PLAYER_DATA_CHANGED, playerData)
end)

RegisterNetEvent(Events.Client.MONEY_CHANGE, function(moneyType, amount, action, balance)
  if OPX.PlayerData.money then OPX.PlayerData.money[moneyType] = balance end
  TriggerEvent(Local.MONEY_CHANGED, moneyType, amount, action, balance)
end)

RegisterNetEvent(Events.Client.JOB_UPDATE, function(job)
  OPX.PlayerData.job = job
  TriggerEvent(Local.JOB_CHANGED, job)
end)

RegisterNetEvent(Events.Client.GANG_UPDATE, function(gang)
  OPX.PlayerData.gang = gang
  TriggerEvent(Local.GANG_CHANGED, gang)
end)

--- A refusal carrying a code and nothing else. The code is a locale key, so a UI renders it
--- with `locale(code)` and gets the player's language for free.
RegisterNetEvent(Events.Client.NOTIFY, function(payload)
  if type(payload) ~= "table" then return end
  log.warn(("server refused: %s"):format(tostring(payload.code)))
  TriggerEvent(Local.REFUSED, payload.code, payload.kind)
end)
