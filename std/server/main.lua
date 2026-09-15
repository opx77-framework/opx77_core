---@meta

--- Every connected machine by player id, character or not.
---@type table<Source, Session>
OPX.Sessions = {}

--- Every loaded character by player id.
---@type table<Source, Player>
OPX.Players = {}

--- Player ids by citizen id and by user id, maintained by RegisterPlayer and UnregisterPlayer.
---@type { byCitizenId: table<CitizenId, Source>, byUserId: table<UserId, Source> }
OPX.PlayerRegistry = {}

--- The durable user id the host vouches for behind a player id.
---@type fun(playerId: Source): UserId|nil
OPX.UserIdOf = nil

--- Set once the boot thread has settled the schema, degraded or not.
---@type boolean|nil
OPX.Booted = nil

--- Why characters cannot be loaded this run ("no database", "schema failed: <table>"), or nil.
---@type string|nil
OPX.BootError = nil

--- The session for a player id: created when this VM has not seen them, evicted when the slot
--- now belongs to another user id, nil without a verified identity.
---@param playerId Source|string
---@return Session|nil
function OPX.EnsureSession(playerId) end

--- Drops a session, logging out any character still attached to the slot.
---@param playerId Source
function OPX.ForgetSession(playerId) end

--- Puts a loaded character into the roster and both reverse indexes.
---@param player Player
function OPX.RegisterPlayer(player) end

--- Takes a character out of the roster, and each index entry that still points at it.
---@param player Player
function OPX.UnregisterPlayer(player) end
