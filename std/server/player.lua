---@meta

--- Fills in anything a stored entity is missing, in place: money types at zero, starting
--- metadata keys, and a job or gang no longer defined resolved to the default.
---@type fun(entity: table): table
OPX.NormaliseEntity = nil

--- Resolves a Player, a player id or a citizen id into a loaded Player.
---@type fun(identifier: Player|Source|CitizenId): Player|nil
OPX.ResolvePlayer = nil

--- Builds a Player around a stored entity. An offline Player sends and places nothing, and the
--- money mutators refuse it.
---@param entity table
---@param offline? boolean
---@return Player
function OPX.CreatePlayer(entity, offline) end

--- Adds money to a loaded character, through the `money:beforeAdd` hook and the audit log.
---@param identifier Player|Source|CitizenId
---@param moneyType MoneyType
---@param amount number
---@param reason? string
---@return boolean ok
---@return string? reason a locale key naming the refusal
function OPX.AddMoney(identifier, moneyType, amount, reason) end

--- Removes money, refusing rather than truncating when there is not enough, unless the type
--- may go negative.
---@param identifier Player|Source|CitizenId
---@param moneyType MoneyType
---@param amount number
---@param reason? string
---@return boolean ok
---@return string? reason a locale key naming the refusal
function OPX.RemoveMoney(identifier, moneyType, amount, reason) end

--- Sets a balance outright; zero is allowed here and nowhere else.
---@param identifier Player|Source|CitizenId
---@param moneyType MoneyType
---@param amount number
---@param reason? string
---@return boolean ok
---@return string? reason a locale key naming the refusal
function OPX.SetMoney(identifier, moneyType, amount, reason) end

--- One balance, or the whole money table when `moneyType` is nil.
--- The client half defines its own `OPX.GetMoney`; this field describes the server one.
---@type fun(identifier: Player|Source|CitizenId, moneyType?: MoneyType): integer|table|nil
OPX.GetMoney = OPX.GetMoney

--- Sets one key of the free-form metadata; `health`, `armor`, `isDead` and `inLastStand` live
--- there too.
---@param identifier Player|Source|CitizenId
---@param key string
---@param value any
---@return boolean ok
function OPX.SetMetadata(identifier, key, value) end

--- One metadata key, or the whole metadata table when `key` is nil.
--- The client half defines its own `OPX.GetMetadata`; this field describes the server one.
---@type fun(identifier: Player|Source|CitizenId, key?: string): any
OPX.GetMetadata = OPX.GetMetadata

--- Re-derives a position from `Open77.players.position`, keeping the client's reported heading.
--- False leaves the last known position in place.
---@param player Player
---@return boolean sampled
function OPX.SamplePosition(player) end

--- Puts a character the session owns into the world. Refuses `entry.noIdentity` when the
--- session departed or changed hands during the reads. Coroutine only.
---@param source Source
---@param citizenId CitizenId
---@return Result
function OPX.Login(source, citizenId) end

--- Writes a character back, sampling the position first. Coroutine only.
---@param identifier Player|Source|CitizenId
---@param loggedOut? boolean
---@return Result
function OPX.Save(identifier, loggedOut) end

--- Takes a character out of the world and dispatches its save. Idempotent.
---@param source Source
function OPX.Logout(source) end

--- Takes a character out of the world and waits for its row to be written. Coroutine only.
---@param source Source
---@return Result
function OPX.LogoutAndWait(source) end
