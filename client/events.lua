--- Every server-to-client handler: update the mirrored state, re-emit a resource-local event,
--- log. The re-emitted names are the same strings the server sends, so a satellite that would
--- rather not hold `network.events` can listen locally instead.

local log = OPX.Log.scope("events")
local Events = OPX.Events

RegisterNetEvent(Events.Client.CHARACTERS, function(payload)
  if type(payload) ~= "table" then return end

  -- fields, never the table: every export holds a reference to OPX.Characters
  OPX.Characters.list = payload.characters or {}
  OPX.Characters.slots = payload.slots or 0
  OPX.Characters.origins = payload.origins or {}

  log.info(("%d character(s) available, %d slot(s)")
    :format(#OPX.Characters.list, OPX.Characters.slots))
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
