--- Character selection, client side. This file does not open the character creator:
--- open77_appearance owns that bootstrap transaction and it can only be resolved once. The
--- core decides which character is live -- the citizen id is the `character_key` -- and the
--- appearance events below are re-emitted onto the core's local channel
--- (`OPX.Events.Local`), not handled. Their names differ from the `open77:appearance:*`
--- names that triggered them, so re-emitting cannot re-enter the handler that fired it.

local log = OPX.Log.scope("character")

--- Asks the server to enter the world as `citizenId`. Returns as soon as the request is sent;
--- the answer arrives on the wire as `opx77:client:playerLoaded`, or a refusal as
--- `opx77:client:notify`. This file hears those; a satellite hears the local re-emissions
--- `OPX.Events.Local.PLAYER_LOADED` and `.REFUSED` instead, which need no permission.
---@param citizenId CitizenId
---@return boolean sent, string? reason
function OPX.SelectCharacter(citizenId)
  if type(citizenId) ~= "string" then return false, "bad-citizen-id" end
  TriggerServerEvent(OPX.Events.Server.SELECT_CHARACTER, { citizenId = citizenId })
  return true
end

--- Asks the server to create a character. The fields are checked again server-side against
--- the same rules; checking here only spares a round trip and gives the UI something to mark.
---@param registration { firstName: string, lastName: string, origin: Origin, gender: Gender,
---        birthDate: string }
---@return boolean sent, string? reason
function OPX.CreateCharacter(registration)
  if type(registration) ~= "table" then return false, "bad-request" end

  local firstName = OPX.ValidateName(registration.firstName)
  if not firstName.ok then return false, "character.badName" end
  local lastName = OPX.ValidateName(registration.lastName)
  if not lastName.ok then return false, "character.badName" end
  if not OPX.Origins[registration.origin] then return false, "character.badOrigin" end

  TriggerServerEvent(OPX.Events.Server.CREATE_CHARACTER, {
    firstName = firstName.value,
    lastName = lastName.value,
    origin = registration.origin,
    gender = registration.gender,
    birthDate = registration.birthDate,
  })
  return true
end

---@param citizenId CitizenId
---@return boolean sent, string? reason
function OPX.DeleteCharacter(citizenId)
  if type(citizenId) ~= "string" then return false, "bad-citizen-id" end
  TriggerServerEvent(OPX.Events.Server.DELETE_CHARACTER, { citizenId = citizenId })
  return true
end

--- Asks the server for the roster again, for a selection UI that started after it was sent.
function OPX.RequestCharacters()
  TriggerServerEvent(OPX.Events.Server.READY)
end

--- The appearance service has no stored look for the live character and wants the creator
--- run. Re-emitted so a selection UI can step out of the way first.
RegisterNetEvent("open77:appearance:createRequired", function(nonce, characterKey)
  log.info(("appearance wants a creator run for %s"):format(tostring(characterKey)))
  TriggerEvent(OPX.Events.Local.APPEARANCE_REQUIRED, characterKey, nonce)
end)

--- The live character's look changed, which is what a successful `setCharacter` looks like.
RegisterNetEvent("open77:appearance:characterChanged", function(characterKey)
  log.debug(("appearance switched to %s"):format(tostring(characterKey)))
  TriggerEvent(OPX.Events.Local.APPEARANCE_CHANGED, characterKey)
end)
