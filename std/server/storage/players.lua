---@meta

--- Every statement the core runs about a character. Everything returns a Result and yields.
OPX.Storage.Players = {}

--- Turns a character row into the entity the core passes around.
---@type fun(row: table|nil): table|nil
OPX.Storage.Players.toEntity = nil

--- Records the account behind a session and stamps `last_seen_at`.
---@param userId UserId
---@param displayName? string
---@return Result
function OPX.Storage.Players.upsertAccount(userId, displayName) end

--- Every living character on an account, never-played first, then most recently played.
---@param userId UserId
---@return Result
function OPX.Storage.Players.fetchAll(userId) end

--- One living character by citizen id, whoever owns it; err `character.notFound`.
---@param citizenId CitizenId
---@return Result
function OPX.Storage.Players.fetchOne(citizenId) end

--- The lowest free slot number on an account; err `character.limit` when it is full.
---@param userId UserId
---@param slots integer
---@return Result
function OPX.Storage.Players.nextCid(userId, slots) end

--- Inserts a new character row. A citizen id collision fails on the unique key.
---@param entity table
---@return Result
function OPX.Storage.Players.insert(entity) end

--- Writes a loaded character back; `citizen_id` and `user_id` are never in the SET list.
---@param entity table
---@param loggedOut? boolean stamps last_logged_out
---@return Result
function OPX.Storage.Players.save(entity, loggedOut) end

--- Writes the appearance column at once; nil clears it.
---@param citizenId CitizenId
---@param appearance AppearanceSnapshot|nil
---@return Result
function OPX.Storage.Players.saveAppearance(citizenId, appearance) end

--- The stored clothing document, or nil for none; err `clothing-unreadable` for a row whose
--- JSON does not decode.
---@param citizenId CitizenId
---@return Result
function OPX.Storage.Players.fetchClothing(citizenId) end

--- Writes an already validated and encoded clothing record.
---@param citizenId CitizenId
---@param encoded string
---@return Result
function OPX.Storage.Players.saveClothing(citizenId, encoded) end

--- How many character rows an account ever wrote, soft-deleted ones included.
---@param userId UserId
---@return Result
function OPX.Storage.Players.countRows(userId) end

--- Marks a character deleted; the row stays.
---@param citizenId CitizenId
---@return Result
function OPX.Storage.Players.softDelete(citizenId) end

--- Every membership of a character, as `{ jobs = name -> grade, gangs = name -> grade }`.
---@param citizenId CitizenId
---@return Result
function OPX.Storage.Players.fetchGroups(citizenId) end

--- Joins a group, or changes the grade held in it.
---@param citizenId CitizenId
---@param groupType GroupType
---@param groupName string
---@param grade integer
---@return Result
function OPX.Storage.Players.upsertGroup(citizenId, groupType, groupName, grade) end

--- Removes one membership row.
---@param citizenId CitizenId
---@param groupType GroupType
---@param groupName string
---@return Result
function OPX.Storage.Players.removeGroup(citizenId, groupType, groupName) end

--- At most 200 living members of a group as `{ citizenId, grade, name }`, highest grade first.
---@param groupType GroupType
---@param groupName string
---@return Result
function OPX.Storage.Players.membersOf(groupType, groupName) end
