---@meta

--- The player audit log: what an operator will be asked to account for, as `[audit]` lines on
--- the platform log, the only sink.
OPX.Logger = {}

--- Truncates a value and strips its control characters, so client-chosen text cannot forge a
--- log line.
---@param value any
---@param maximum? integer defaults to 64
---@return string
function OPX.Logger.safe(value, maximum) end

--- Forgets the dedupe windows keyed by a departing source, and by a citizen id when given.
---@param source Source
---@param citizenId? CitizenId
function OPX.Logger.forget(source, citizenId) end

--- Writes one entry. Identical entries within ten seconds collapse into a count, except info
--- and debug entries under the `money.` and `character.` ledger prefixes.
---@param entry LogEntry
function OPX.Logger.log(entry) end

--- Writes an entry attributed to a loaded character's source, citizen id and user id.
---@param player Player|nil
---@param event string
---@param message? string
---@param data? table
function OPX.Logger.player(player, event, message, data) end

--- Writes a `warn` entry. Pass `source`, or the dedupe key is global per event and one
--- player looping a refusal swallows every other player's.
---@param event string
---@param message? string
---@param data? table
---@param source? Source
function OPX.Logger.security(event, message, data, source) end
