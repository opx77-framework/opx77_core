--- SYNK's client export surface: the seam other client resources build
--- against, so a UI can be reloaded and versioned independently of the core.
---
--- Requiring this file *publishes* the exports. `main.lua` requires it on its
--- own line for that reason: the load order of the client is decided there.
---
--- Exports return a plain `{ ok = boolean, ... }` rather than a Result: the
--- value crosses a resource boundary and lands in code that does not require
--- SYNK's shared library.

local Events = require("shared.events")
local Validate = require("shared.validate")
local state = require("client.state")

exports("getCharacters", function()
  return { ok = true, characters = state.characters }
end)

exports("getCurrentCharacter", function()
  return { ok = true, characterId = state.characterId }
end)

--- Returns once the request is sent. The server answers with
--- `synk:entered`, so a consumer watches that event rather than this call.
exports("selectCharacter", function(characterId)
  local checked = Validate.number(characterId, { integer = true, min = 1 })
  if not checked.ok then return { ok = false, error = "bad-character-id" } end
  TriggerServerEvent(Events.toServer.selectCharacter, { characterId = checked.value })
  return { ok = true }
end)

--- Names are checked again server-side; this only spares a round trip.
exports("createCharacter", function(firstName, lastName)
  TriggerServerEvent(Events.toServer.createCharacter,
    { firstName = firstName, lastName = lastName })
  return { ok = true }
end)

exports("isReady", function()
  return { ok = true, ready = state.characterId ~= nil }
end)

--- So a UI can refuse to run against a core it does not understand.
exports("getVersion", function()
  return { ok = true, version = Synk.VERSION }
end)
