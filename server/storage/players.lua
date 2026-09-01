--- Every statement the core runs about a character, in one file, so a schema change touches
--- one file and a server owner can read the statements without the rules that call them.
--- Everything here returns a Result and yields: coroutine only.

local Result = OPX.Result
local Storage = OPX.Storage

local Players = {}

--- Accepts a string or an already-decoded table, because a bridge build may do either. A
--- column that fails to decode is absent rather than fatal: one corrupted character must not
--- stop a server booting.
local function decode(value, fallback)
  if type(value) == "table" then return value end
  if type(value) ~= "string" or value == "" then return fallback end
  local ok, decoded = pcall(json.decode, value)
  if not ok or type(decoded) ~= "table" then return fallback end
  return decoded
end

--- The inverse, so no call site has to remember that the columns are JSON.
local function encode(value)
  return json.encode(value or {})
end

--- One statement, so two connections racing cannot both insert. display_name is assigned
--- unconditionally because ON UPDATE CURRENT_TIMESTAMP only fires when a column changes.
---@param userId UserId
---@param displayName? string
---@return Result
function Players.upsertAccount(userId, displayName)
  return Storage.execute([[
INSERT INTO opx77_accounts (user_id, display_name)
VALUES (@user, @name)
ON DUPLICATE KEY UPDATE
    display_name = VALUES(display_name),
    last_seen_at = CURRENT_TIMESTAMP
  ]], { user = userId, name = displayName or "" })
end

--- Turns one database row into the shape the rest of the core passes around. Every JSON
--- column gets a default: a row written by an older core is a shape this one must survive.
local function toEntity(row)
  if not row then return nil end
  return {
    citizenId = row.citizen_id,
    userId = row.user_id,
    cid = row.cid,
    name = row.name,
    charInfo = decode(row.char_info, {}),
    money = decode(row.money, {}),
    job = decode(row.job, {}),
    gang = decode(row.gang, {}),
    position = decode(row.position, nil),
    metadata = decode(row.metadata, {}),
    lastLoggedOut = row.last_logged_out,
  }
end

Players.toEntity = toEntity

--- Every living character on an account, most recently played first; never-played characters
--- sort to the top, where the player is looking.
---@param userId UserId
---@return Result  ok value is a list of character entities
function Players.fetchAll(userId)
  local rows = Storage.query([[
SELECT citizen_id, user_id, cid, name, char_info, money, job, gang,
       position, metadata, last_logged_out
  FROM opx77_players
 WHERE user_id = @user AND deleted_at IS NULL
 ORDER BY last_logged_out IS NULL DESC, last_logged_out DESC, cid ASC
  ]], { user = userId })
  if not rows.ok then return rows end

  local list = rows.value or {}
  local out = {}
  for i = 1, #list do out[i] = toEntity(list[i]) end
  return Result.ok(out)
end

--- One character by citizen id, whoever owns it. Ownership is the caller's check.
---@param citizenId CitizenId
---@return Result
function Players.fetchOne(citizenId)
  local row = Storage.single([[
SELECT citizen_id, user_id, cid, name, char_info, money, job, gang,
       position, metadata, last_logged_out
  FROM opx77_players
 WHERE citizen_id = @citizen AND deleted_at IS NULL
 LIMIT 1
  ]], { citizen = citizenId })
  if not row.ok then return row end
  if not row.value then return Result.err("character.notFound", citizenId) end
  return Result.ok(toEntity(row.value))
end

--- The lowest free slot number on an account. Lowest free rather than highest plus one, so a
--- deleted slot is reused instead of the numbers climbing past the configured limit.
---@param userId UserId
---@param slots integer
---@return Result  err character.limit when the account is full
function Players.nextCid(userId, slots)
  local rows = Storage.query([[
SELECT cid FROM opx77_players
 WHERE user_id = @user AND deleted_at IS NULL
  ]], { user = userId })
  if not rows.ok then return rows end

  local taken = {}
  local list = rows.value or {}
  for i = 1, #list do taken[list[i].cid] = true end

  for cid = 1, slots do
    if not taken[cid] then return Result.ok(cid) end
  end
  return Result.err("character.limit", tostring(slots))
end

--- Creates a character. Collisions are decided by the unique key on `citizen_id`, not by a
--- SELECT first: two players creating in the same tick would both pass that check.
---@param entity table
---@return Result
function Players.insert(entity)
  return Storage.execute([[
INSERT INTO opx77_players
    (citizen_id, user_id, cid, name, char_info, money, job, gang, position, metadata)
VALUES
    (@citizen, @user, @cid, @name, @charInfo, @money, @job, @gang, @position, @metadata)
  ]], {
    citizen = entity.citizenId,
    user = entity.userId,
    cid = entity.cid,
    name = entity.name or "",
    charInfo = encode(entity.charInfo),
    money = encode(entity.money),
    job = encode(entity.job),
    gang = encode(entity.gang),
    position = entity.position and encode(entity.position) or nil,
    metadata = encode(entity.metadata),
  })
end

--- Writes a loaded character back. `citizen_id` and `user_id` are not in the SET list: an
--- UPDATE that could move a character to another account is how characters get stolen.
---@param entity table
---@param loggedOut? boolean stamps last_logged_out
---@return Result
function Players.save(entity, loggedOut)
  return Storage.execute([[
UPDATE opx77_players
   SET name = @name,
       char_info = @charInfo,
       money = @money,
       job = @job,
       gang = @gang,
       position = @position,
       metadata = @metadata,
       last_logged_out = CASE WHEN @loggedOut = 1 THEN CURRENT_TIMESTAMP ELSE last_logged_out END
 WHERE citizen_id = @citizen
  ]], {
    citizen = entity.citizenId,
    name = entity.name or "",
    charInfo = encode(entity.charInfo),
    money = encode(entity.money),
    job = encode(entity.job),
    gang = encode(entity.gang),
    position = entity.position and encode(entity.position) or nil,
    metadata = encode(entity.metadata),
    loggedOut = loggedOut and 1 or 0,
  })
end

--- How many rows this account has ever owned, soft-deleted ones included -- the one read in
--- the core that does not filter `deleted_at`. Create-delete-create writes a new row each
--- time, and this is what bounds it.
---@param userId UserId
---@return Result  ok value is the count
function Players.countRows(userId)
  local row = Storage.single([[
SELECT COUNT(*) AS total FROM opx77_players WHERE user_id = @user
  ]], { user = userId })
  if not row.ok then return row end
  return Result.ok(tonumber(row.value and row.value.total) or 0)
end

--- Soft delete: the row stays, so a mistake is recoverable and the citizen id is never
--- reissued to a stranger.
---@param citizenId CitizenId
---@return Result
function Players.softDelete(citizenId)
  return Storage.execute([[
UPDATE opx77_players SET deleted_at = CURRENT_TIMESTAMP
 WHERE citizen_id = @citizen AND deleted_at IS NULL
  ]], { citizen = citizenId })
end

--- Every job and gang a character belongs to, as two `name -> grade` maps: every caller asks
--- "is this character in X" and never "what is the third one".
---@param citizenId CitizenId
---@return Result  ok value is { jobs = table, gangs = table }
function Players.fetchGroups(citizenId)
  local rows = Storage.query([[
SELECT group_type, group_name, grade
  FROM opx77_player_groups
 WHERE citizen_id = @citizen
  ]], { citizen = citizenId })
  if not rows.ok then return rows end

  local jobs, gangs = {}, {}
  local list = rows.value or {}
  for i = 1, #list do
    local row = list[i]
    if row.group_type == "job" then
      jobs[row.group_name] = row.grade
    else
      gangs[row.group_name] = row.grade
    end
  end
  return Result.ok({ jobs = jobs, gangs = gangs })
end

--- Joining a group you are already in is a promotion, not a duplicate row -- enforced by the
--- composite primary key rather than by whichever call site remembered to check.
---@param citizenId CitizenId
---@param groupType GroupType
---@param groupName string
---@param grade integer
---@return Result
function Players.upsertGroup(citizenId, groupType, groupName, grade)
  return Storage.execute([[
INSERT INTO opx77_player_groups (citizen_id, group_type, group_name, grade)
VALUES (@citizen, @type, @name, @grade)
ON DUPLICATE KEY UPDATE grade = VALUES(grade)
  ]], { citizen = citizenId, type = groupType, name = groupName, grade = grade })
end

---@param citizenId CitizenId
---@param groupType GroupType
---@param groupName string
---@return Result
function Players.removeGroup(citizenId, groupType, groupName)
  return Storage.execute([[
DELETE FROM opx77_player_groups
 WHERE citizen_id = @citizen AND group_type = @type AND group_name = @name
  ]], { citizen = citizenId, type = groupType, name = groupName })
end

--- Everyone in a group, online or not, for a boss menu or the `opx77.group` diagnostic.
--- Bounded at 200: an unbounded result set is a stall on the database worker.
---@param groupType GroupType
---@param groupName string
---@return Result
function Players.membersOf(groupType, groupName)
  local rows = Storage.query([[
SELECT g.citizen_id, g.grade, p.name, p.char_info
  FROM opx77_player_groups g
  JOIN opx77_players p ON p.citizen_id = g.citizen_id
 WHERE g.group_type = @type AND g.group_name = @name AND p.deleted_at IS NULL
 ORDER BY g.grade DESC, p.name ASC
 LIMIT 200
  ]], { type = groupType, name = groupName })
  if not rows.ok then return rows end

  local list = rows.value or {}
  local out = {}
  for i = 1, #list do
    local row = list[i]
    local charInfo = decode(row.char_info, {})
    out[i] = {
      citizenId = row.citizen_id,
      grade = row.grade,
      name = ("%s %s"):format(charInfo.firstName or "?", charInfo.lastName or "?"),
    }
  end
  return Result.ok(out)
end

OPX.Storage.Players = Players
