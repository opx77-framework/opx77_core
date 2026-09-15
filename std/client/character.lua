---@meta

--- Asks the server to enter the world as `citizenId`. Returns as soon as the request is sent;
--- the answer arrives as `OPX.Events.Local.PLAYER_LOADED` or `OPX.Events.Local.REFUSED`.
---@param citizenId CitizenId
---@return boolean sent
---@return string|nil reason
function OPX.SelectCharacter(citizenId) end

--- Checks a registration with the same rules the server applies, then asks the server to create
--- it. The local check only spares a round trip and gives a UI something to mark.
---@param registration { firstName: string, lastName: string, origin: Origin, gender: Gender, birthDate: string }
---@return boolean sent
---@return string|nil reason
function OPX.CreateCharacter(registration) end

--- Asks the server to soft-delete one of this player's characters.
---@param citizenId CitizenId
---@return boolean sent
---@return string|nil reason
function OPX.DeleteCharacter(citizenId) end

--- Asks the server for the roster again, for a selection UI that started after it was sent.
function OPX.RequestCharacters() end
