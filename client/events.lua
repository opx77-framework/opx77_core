--- Every server-to-client handler: update the mirrored state, re-emit a resource-local event,
--- log. The re-emitted names are the same strings the server sends, so a satellite that would
--- rather not hold `network.events` can listen locally instead.

local log = OPX.Log.scope("events")
local Events = OPX.Events

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
  TriggerEvent("opx77:client:charactersReady", OPX.Characters)
end)

RegisterNetEvent(Events.Client.PLAYER_LOADED, function(playerData)
  if type(playerData) ~= "table" then return end
  OPX.PlayerData = playerData
  OPX.IsLoggedIn = true

  log.info(("loaded %s (%s %s)"):format(
    tostring(playerData.citizenId),
    tostring(playerData.charInfo and playerData.charInfo.firstName),
    tostring(playerData.charInfo and playerData.charInfo.lastName)))
  TriggerEvent("opx77:client:playerLoaded", playerData)
end)

RegisterNetEvent(Events.Client.PLAYER_UNLOADED, function()
  OPX.PlayerData = {}
  OPX.IsLoggedIn = false
  TriggerEvent("opx77:client:playerUnloaded")
end)

--- The whole of PlayerData, resent after any change. Whole rather than a patch: a merge
--- protocol is a class of bug where the two copies drift and neither can tell.
RegisterNetEvent(Events.Client.SET_PLAYER_DATA, function(playerData)
  if type(playerData) ~= "table" then return end
  OPX.PlayerData = playerData
  TriggerEvent("opx77:client:playerDataChanged", playerData)
end)

RegisterNetEvent(Events.Client.MONEY_CHANGE, function(moneyType, amount, action, balance)
  if OPX.PlayerData.money then OPX.PlayerData.money[moneyType] = balance end
  TriggerEvent("opx77:client:moneyChanged", moneyType, amount, action, balance)
end)

RegisterNetEvent(Events.Client.JOB_UPDATE, function(job)
  OPX.PlayerData.job = job
  TriggerEvent("opx77:client:jobChanged", job)
end)

RegisterNetEvent(Events.Client.GANG_UPDATE, function(gang)
  OPX.PlayerData.gang = gang
  TriggerEvent("opx77:client:gangChanged", gang)
end)

--- A refusal carrying a code and nothing else. The code is a locale key, so a UI renders it
--- with `locale(code)` and gets the player's language for free.
RegisterNetEvent(Events.Client.NOTIFY, function(payload)
  if type(payload) ~= "table" then return end
  log.warn(("server refused: %s"):format(tostring(payload.code)))
  TriggerEvent("opx77:client:refused", payload.code, payload.kind)
end)
