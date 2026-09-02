--- Every server-to-client handler: mirror the state, then fire the local event, so a handler
--- woken by one reads the change rather than the value it replaced.

local Events = OPX.Events
local Local = Events.Local

RegisterNetEvent(Events.Client.CHARACTERS, function(payload)
  if type(payload) ~= "table" then return end

  -- typed before they are stored: `#` on a non-table and `%d` on a non-integer both raise,
  -- and a raise between the state write and the broadcast leaves a half-applied roster
  local list = type(payload.characters) == "table" and payload.characters or {}
  local slots = tonumber(payload.slots)
  slots = OPX.Math.isFinite(slots) and math.floor(slots) or 0
  if slots < 0 then slots = 0 end

  -- fields, never the table: every export holds a reference to OPX.Characters
  OPX.Characters.list = list
  OPX.Characters.slots = slots
  OPX.Characters.origins = type(payload.origins) == "table" and payload.origins or {}

  Open77.log.info(("[events] %d character(s) available, %d slot(s)"):format(#list, slots))
  TriggerEvent(Local.CHARACTERS_READY, OPX.Characters)
end)

RegisterNetEvent(Events.Client.PLAYER_LOADED, function(playerData)
  if type(playerData) ~= "table" then return end
  OPX.PlayerData = playerData
  OPX.IsLoggedIn = true

  Open77.log.info(("[events] loaded %s (%s %s)"):format(
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

--- The core stored a new face for the live character.
RegisterNetEvent(Events.Client.APPEARANCE_UPDATE, function(snapshot)
  if type(snapshot) ~= "table" then return end
  OPX.PlayerData.appearance = snapshot
  TriggerEvent(Local.APPEARANCE_SAVED, snapshot)
end)

--- A refusal: which request it answers, and a code. The code is always a locale key, so a UI
--- renders it with `locale(code)` and gets the player's language for free.
RegisterNetEvent(Events.Client.NOTIFY, function(payload)
  if type(payload) ~= "table" then return end
  Open77.log.warn(("[events] server refused %s: %s")
    :format(tostring(payload.operation), tostring(payload.code)))
  TriggerEvent(Local.REFUSED, payload.code, payload.kind, payload.operation)
end)
