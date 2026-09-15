---@meta

--- Records the account behind a session and sends its living characters, as summaries, on
--- `OPX.Events.Client.CHARACTERS`. Cooled per source on its own `roster` key, except for the
--- core's own push on connect, which neither is cooled nor cools. Coroutine only.
---@param source Source
---@param pushed? boolean true for the core's own send on connect
---@return Result ok value is a list of CharacterSummary
function OPX.SendCharacters(source, pushed) end

--- Creates a character on the caller's own account, with the default job and gang and the
--- starting money and metadata. A citizen id collision is settled by the unique key and drawn
--- again, up to five times. Coroutine only.
--- `payload`: { firstName, lastName, origin, gender, birthDate }
--- The ok value is a CharacterSummary.
--- The client half defines its own `OPX.CreateCharacter`; this field describes the server one.
---@type fun(source: Source, payload: table): Result
OPX.CreateCharacter = OPX.CreateCharacter

--- Soft-deletes one of the caller's own characters, logging it out first, and deletes its rows
--- in `CHARACTERS.CASCADE_TABLES`. Another account's character answers `character.notFound`.
--- Coroutine only.
--- The ok value is the citizen id.
--- The client half defines its own `OPX.DeleteCharacter`; this field describes the server one.
---@type fun(source: Source, citizenId: CitizenId): Result
OPX.DeleteCharacter = OPX.DeleteCharacter

--- Puts a loaded character at its stored position, or at `DEFAULT_SPAWN`, by kill then respawn
--- into the placement bucket. Turns `MaySample` on when the world agrees with the row.
--- Coroutine only.
---@param player Player
---@return boolean placed
---@return string|nil reason
function OPX.PlaceCharacter(player) end

--- The whole selection sequence: switch away from a loaded character (awaiting its save), log
--- in, place, move the player out of the selection bucket and release the readiness gate.
--- Coroutine only.
--- The ok value is the Player.
--- The client half defines its own `OPX.SelectCharacter`; this field describes the server one.
---@type fun(source: Source, citizenId: CitizenId): Result
OPX.SelectCharacter = OPX.SelectCharacter
