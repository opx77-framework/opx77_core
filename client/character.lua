--- @author DemiAutomatic
--- @file client/character.lua
--- @description Client requests to select, create and delete characters.

--- @author DemiAutomatic
--- @method OPX.SelectCharacter
--- @description Asks the server to enter the world as one character.
--- @param citizenId {string}
--- @returns {boolean, string|nil}
function OPX.SelectCharacter(citizenId)
	if type(citizenId) ~= 'string' then return false, 'bad-citizen-id' end
	TriggerServerEvent(OPX.Events.Server.SELECT_CHARACTER, { citizenId = citizenId })
	return true
end

--- @author DemiAutomatic
--- @method OPX.CreateCharacter
--- @description Checks a registration locally, then asks the server to create it.
--- @param registration {table}
--- @returns {boolean, string|nil}
function OPX.CreateCharacter(registration)
	if type(registration) ~= 'table' then return false, 'bad-request' end

	local firstName = OPX.ValidateName(registration.firstName)
	if not firstName.ok then return false, 'character.badName' end
	local lastName = OPX.ValidateName(registration.lastName)
	if not lastName.ok then return false, 'character.badName' end
	if not OPX.Origins[registration.origin] then return false, 'character.badOrigin' end

	TriggerServerEvent(OPX.Events.Server.CREATE_CHARACTER, {
		firstName = firstName.value,
		lastName = lastName.value,
		origin = registration.origin,
		gender = registration.gender,
		birthDate = registration.birthDate,
	})
	return true
end

--- @author DemiAutomatic
--- @method OPX.DeleteCharacter
--- @description Asks the server to soft-delete one of this player's characters.
--- @param citizenId {string}
--- @returns {boolean, string|nil}
function OPX.DeleteCharacter(citizenId)
	if type(citizenId) ~= 'string' then return false, 'bad-citizen-id' end
	TriggerServerEvent(OPX.Events.Server.DELETE_CHARACTER, { citizenId = citizenId })
	return true
end

--- @author DemiAutomatic
--- @method OPX.RequestCharacters
--- @description Asks the server to send the roster again.
function OPX.RequestCharacters()
	TriggerServerEvent(OPX.Events.Server.READY)
end
