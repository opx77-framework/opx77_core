--- Client entry point. Presentation only: every decision that matters is made
--- on the server, and anything reported from here is a hint the server
--- re-derives, never a fact.

require("shared.init")

local Events = require("shared.events")
local Log = require("shared.log")
local state = require("client.state")

--- Publishing the export surface is a side effect of this require, which is
--- why it sits on its own line rather than among the locals above.
require("client.exports")

local log = Log.scope("client")

RegisterNetEvent(Events.toClient.characters, function(characters)
  state.characters = characters or {}
  log.info(("%d character(s) available"):format(#state.characters))
end)

RegisterNetEvent(Events.toClient.entered, function(payload)
  state.characterId = payload and payload.characterId
  log.info(("entered as character %s"):format(tostring(state.characterId)))
end)

RegisterNetEvent(Events.toClient.notify, function(payload)
  log.warn(("server refused: %s"):format(payload and tostring(payload.code) or "?"))
end)

--- Console entry, until the selection surface lands.
RegisterCommand("synk.select", function(_, args)
  local characterId = tonumber(args and args[1])
  if not characterId then return log.warn("usage: synk.select <characterId>") end
  TriggerServerEvent(Events.toServer.selectCharacter, { characterId = characterId })
end, false)

RegisterCommand("synk.create", function(_, args)
  if not (args and args[1] and args[2]) then
    return log.warn("usage: synk.create <firstName> <lastName>")
  end
  TriggerServerEvent(Events.toServer.createCharacter,
    { firstName = args[1], lastName = args[2] })
end, false)

RegisterCommand("synk.characters", function()
  local characters = state.characters
  for i = 1, #characters do
    local character = characters[i]
    log.info(("  %s  %s %s")
      :format(character.publicCode, character.firstName, character.lastName))
  end
end, false)

AddEventHandler(Events.platform.resourceStart, function(name)
  if name ~= GetCurrentResourceName() then return end
  log.info(("SYNK client %s ready"):format(Synk.VERSION))
end)
