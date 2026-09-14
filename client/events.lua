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

local NOTIFY = "opx77_notify"

--- Whether a toast that could not be raised has been logged: one line, not one per answer.
local toastReported = false

--- The chat line a command answer was before it was a toast, for a client with no toast.
---@param kind string
---@param message string
local function answerLine(kind, message)
  local accepted = kind == "success"
  TriggerEvent("chat:addMessage", {
    type = accepted and "info" or "error",
    author = OPX.Config.SHARED.SERVER_NAME,
    text = message,
    color = accepted and { 120, 220, 232 } or { 255, 76, 92 },
  })
end

--- A toast through opx77_notify; coroutine only. Nil when it is up, the reason otherwise.
---@param definition table
---@return string|nil failure
local function toast(definition)
  if GetResourceState(NOTIFY) ~= "running" then return "not_running" end
  if Open77.exports == nil then return "not_dispatched" end
  -- the wrapping stops here: `await` below yields, and a yield is not safe under a pcall
  local dispatched, promise, reason = pcall(Open77.exports.call, NOTIFY, "show", definition)
  if not dispatched then return tostring(promise) end
  -- tested for presence, never for its Lua type: the host's promise is userdata, not a table
  if not promise then return tostring(reason or "not_dispatched") end
  local result, callError = promise:await()
  if callError then return tostring(callError) end
  if type(result) ~= "table" then return "malformed_answer" end
  if result.ok == false then return tostring(result.error or "refused") end
  return nil
end

--- What a command this player typed did, already in the configured locale: a toast while
--- opx77_notify runs, the chat line otherwise. `toasted` means the action raised the same
--- toast itself, through the server's notifications, so only a client without one needs it.
RegisterNetEvent(Events.Client.ANSWER, function(raw, kind, message, toasted)
  if type(raw) ~= "string" or type(message) ~= "string" or message == "" then return end
  if kind ~= "success" and kind ~= "warning" and kind ~= "error" then kind = "error" end
  CreateThread(function()
    if toasted == true then
      if GetResourceState(NOTIFY) ~= "running" then answerLine(kind, message) end
      return
    end
    local failure = toast({
      -- one slot, replaced: a player retrying a command sees one answer, not a stack
      id = "opx77_core.command",
      replace = true,
      type = kind,
      title = OPX.Config.SHARED.SERVER_NAME,
      message = message,
      durationMs = 5000,
      position = OPX.Config.SHARED.NOTIFY_POSITION,
    })
    if failure == nil then return end
    if not toastReported then
      toastReported = true
      Open77.log.warn(("[events] no toast (%s): command answers go to the chat box instead")
        :format(failure))
    end
    answerLine(kind, message)
  end)
end)
