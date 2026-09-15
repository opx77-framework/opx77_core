---@meta

--- The loaded character at a player id, or nil. Nil includes somebody still choosing one,
--- which is not an error.
---@param source Source|string
---@return Player|nil
function OPX.GetPlayer(source) end

--- The loaded character carrying a citizen id, or nil.
---@param citizenId CitizenId
---@return Player|nil
function OPX.GetPlayerByCitizenId(citizenId) end

--- The loaded character of an account, or nil.
---@param userId UserId
---@return Player|nil
function OPX.GetPlayerByUserId(userId) end

--- Every loaded character. Iterate this rather than `pairs(OPX.Players)`: the walk also evicts
--- any slot whose userId no longer matches, which logs that character out and saves it.
---@return Player[]
function OPX.GetPlayers() end

--- How many characters are in the world, building no table.
---@return integer
function OPX.GetPlayerCount() end

--- A character online or not: `{ player, offline = false }` or `{ entity, offline = true }`,
--- the offline shape being a bare entity with no `Functions`. Yields when offline.
---@param citizenId CitizenId
---@return Result
function OPX.GetCharacter(citizenId) end

--- A toast through `Open77.notifications`. Degrades to nothing when no resource draws them; an
--- identical toast to the same player within two seconds is swallowed.
---@param source Source
---@param message string
---@param kind? "info"|"success"|"warning"|"error"
---@param durationMs? integer
function OPX.Notify(source, message, kind, durationMs) end

--- The code when the catalogue carries it, `error.unavailable` otherwise (with a warning), so
--- a storage or validator code never reaches a player.
---@param code any
---@return string
function OPX.RefusalKey(code) end

--- A toast rendered from a locale key; a key with no entry becomes `error.unavailable`.
---@param source Source
---@param key string
---@param params? table<string, string|number>
---@param kind? "info"|"success"|"warning"|"error"
function OPX.NotifyLocale(source, key, params, kind) end

--- Answers a command with a report someone asked to read, as a chat line; source nil or 0
--- prints to the console.
---@param source Source|nil
---@param raw string|nil
---@param accepted boolean
---@param message string
function OPX.CommandResult(source, raw, accepted, message) end

--- Answers a command with what it did, as a toast the core's client half raises through
--- opx77_notify, or the chat line on a client without it. `toasted` says the action already
--- raised the same toast through `OPX.Notify`.
---@param source Source|nil
---@param raw string|nil
---@param kind "success"|"warning"|"error"
---@param message string
---@param toasted? boolean
function OPX.CommandNotice(source, raw, kind, message, toasted) end

--- True when this player ran `key` less than `everyMs` ago; records the attempt when not.
---@param source Source
---@param key string
---@param everyMs integer
---@return boolean
function OPX.Cooling(source, key, everyMs) end

--- Drops a departing player's cooldowns and answer windows: a player id is recycled.
---@param source Source
function OPX.ForgetCooldowns(source) end

--- Tells a client a request was refused on `OPX.Events.Client.NOTIFY`: the operation and a code
--- the catalogue carries, nothing else.
---@param source Source
---@param code string a locale key
---@param operation? string a value of `OPX.Operations`
function OPX.Refuse(source, code, operation) end
