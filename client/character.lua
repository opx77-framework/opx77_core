--- Character selection, client side. It does not open the character creator: opx77_appearance
--- owns that bootstrap transaction.

--- Asks the server to enter the world as `citizenId`. Returns as soon as the request is sent;
--- the answer arrives as `OPX.Events.Local.PLAYER_LOADED` or `.REFUSED`.
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
