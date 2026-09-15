--- @author DemiAutomatic
--- @file server/storage/players.lua
--- @description Every statement the core runs about a character.

--- @author DemiAutomatic
--- @type {table}
--- @description The Result constructors every statement answers with.
local Result = OPX.Result

--- @author DemiAutomatic
--- @type {table}
--- @description The database access every statement runs through.
local Storage = OPX.Storage

OPX.Storage.Players = {}
local Players = OPX.Storage.Players

--- @author DemiAutomatic
--- @type {fun(value: any, fallback: table|nil): table|nil}
--- @description Decodes a JSON column, answering the fallback when it cannot.
local decode = Storage.Decode

--- @author DemiAutomatic
--- @method encode
--- @description Encodes a JSON column, an absent value as an empty object.
--- @param value {table|nil}
--- @returns {string}
local function encode(value)
	return json.encode(value or {})
end

--- @author DemiAutomatic
--- @type {fun(value: any): string}
--- @description Binds a nullable JSON column, absence as an empty string.
local nullable = Storage.Nullable

--- @author DemiAutomatic
--- @method OPX.Storage.Players.upsertAccount
--- @description Records the account behind a session and stamps its visit.
--- @param userId {UserId}
--- @param displayName {string|nil}
--- @returns {Result}
function OPX.Storage.Players.upsertAccount(userId, displayName)
	return Storage.execute([[
INSERT INTO opx77_users (user_id, display_name)
VALUES (@user, @name)
ON DUPLICATE KEY UPDATE
    display_name = VALUES(display_name),
    last_seen_at = CURRENT_TIMESTAMP
  ]], { user = userId, name = displayName or '' })
end

--- @author DemiAutomatic
--- @method toEntity
--- @description Turns a character row into the entity the core passes around.
--- @param row {table|nil}
--- @returns {table|nil}
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
		appearance = decode(row.appearance, nil),
		lastLoggedOut = row.last_logged_out,
	}
end

--- @author DemiAutomatic
--- @type {fun(row: table|nil): table|nil}
--- @description Turns a character row into an entity, for plug-ins.
Players.toEntity = toEntity

--- @author DemiAutomatic
--- @method OPX.Storage.Players.fetchAll
--- @description Lists an account's living characters, never-played and recent first.
--- @param userId {UserId}
--- @returns {Result}
function OPX.Storage.Players.fetchAll(userId)
	local rows = Storage.query([[
SELECT citizen_id, user_id, cid, name, char_info, money, job, gang,
       position, metadata, appearance, last_logged_out
  FROM opx77_characters
 WHERE user_id = @user AND deleted_at IS NULL
 ORDER BY last_logged_out IS NULL DESC, last_logged_out DESC, cid ASC
  ]], { user = userId })
	if not rows.ok then return rows end

	local list = rows.value or {}
	local out = {}
	for i = 1, #list do out[i] = toEntity(list[i]) end
	return Result.ok(out)
end

--- @author DemiAutomatic
--- @method OPX.Storage.Players.fetchOne
--- @description Reads one living character by citizen id, whoever owns it.
--- @param citizenId {CitizenId}
--- @returns {Result}
function OPX.Storage.Players.fetchOne(citizenId)
	local row = Storage.single([[
SELECT citizen_id, user_id, cid, name, char_info, money, job, gang,
       position, metadata, appearance, last_logged_out
  FROM opx77_characters
 WHERE citizen_id = @citizen AND deleted_at IS NULL
 LIMIT 1
  ]], { citizen = citizenId })
	if not row.ok then return row end
	if not row.value then return Result.err('character.notFound', citizenId) end
	return Result.ok(toEntity(row.value))
end

--- @author DemiAutomatic
--- @method OPX.Storage.Players.nextCid
--- @description Answers the lowest free slot number on an account.
--- @param userId {UserId}
--- @param slots {integer}
--- @returns {Result}
function OPX.Storage.Players.nextCid(userId, slots)
	local rows = Storage.query([[
SELECT cid FROM opx77_characters
 WHERE user_id = @user AND deleted_at IS NULL
  ]], { user = userId })
	if not rows.ok then return rows end

	local taken = {}
	local list = rows.value or {}
	for i = 1, #list do taken[list[i].cid] = true end

	for cid = 1, slots do
		if not taken[cid] then return Result.ok(cid) end
	end
	return Result.err('character.limit', tostring(slots))
end

--- @author DemiAutomatic
--- @method OPX.Storage.Players.insert
--- @description Inserts a new character row, the key deciding a collision.
--- @param entity {table}
--- @returns {Result}
function OPX.Storage.Players.insert(entity)
	return Storage.execute([[
INSERT INTO opx77_characters
    (citizen_id, user_id, cid, name, char_info, money, job, gang, position, metadata)
VALUES
    (@citizen, @user, @cid, @name, @charInfo, @money, @job, @gang, NULLIF(@position, ''),
     @metadata)
  ]], {
		citizen = entity.citizenId,
		user = entity.userId,
		cid = entity.cid,
		name = entity.name or '',
		charInfo = encode(entity.charInfo),
		money = encode(entity.money),
		job = encode(entity.job),
		gang = encode(entity.gang),
		position = nullable(entity.position),
		metadata = encode(entity.metadata),
	})
end

--- @author DemiAutomatic
--- @method OPX.Storage.Players.save
--- @description Writes a loaded character back, never its identity columns.
--- @param entity {table}
--- @param loggedOut {boolean|nil} Stamps last_logged_out.
--- @returns {Result}
function OPX.Storage.Players.save(entity, loggedOut)
	return Storage.execute([[
UPDATE opx77_characters
   SET name = @name,
       char_info = @charInfo,
       money = @money,
       job = @job,
       gang = @gang,
       position = NULLIF(@position, ''),
       metadata = @metadata,
       appearance = NULLIF(@appearance, ''),
       last_logged_out = CASE WHEN @loggedOut = 1 THEN CURRENT_TIMESTAMP ELSE last_logged_out END
 WHERE citizen_id = @citizen
  ]], {
		citizen = entity.citizenId,
		name = entity.name or '',
		charInfo = encode(entity.charInfo),
		money = encode(entity.money),
		job = encode(entity.job),
		gang = encode(entity.gang),
		position = nullable(entity.position),
		metadata = encode(entity.metadata),
		appearance = nullable(entity.appearance),
		loggedOut = loggedOut and 1 or 0,
	})
end

--- @author DemiAutomatic
--- @method OPX.Storage.Players.saveAppearance
--- @description Writes a character's appearance column at once; nil clears it.
--- @param citizenId {CitizenId}
--- @param appearance {AppearanceSnapshot|nil}
--- @returns {Result}
function OPX.Storage.Players.saveAppearance(citizenId, appearance)
	return Storage.execute([[
UPDATE opx77_characters
   SET appearance = NULLIF(@appearance, '')
 WHERE citizen_id = @citizen AND deleted_at IS NULL
  ]], {
		citizen = citizenId,
		appearance = nullable(appearance),
	})
end

--- @author DemiAutomatic
--- @method OPX.Storage.Players.fetchClothing
--- @description Reads a character's stored clothing document, or nil for none.
--- @param citizenId {CitizenId}
--- @returns {Result}
function OPX.Storage.Players.fetchClothing(citizenId)
	local row = Storage.single([[
SELECT clothing FROM opx77_character_clothing
 WHERE citizen_id = @citizen
 LIMIT 1
  ]], { citizen = citizenId })
	if not row.ok then return row end
	if not row.value then return Result.ok(nil) end
	local decoded = decode(row.value.clothing, nil)
	if decoded == nil then return Result.err('clothing-unreadable', citizenId) end
	return Result.ok(decoded)
end

--- @author DemiAutomatic
--- @method OPX.Storage.Players.saveClothing
--- @description Writes a character's encoded clothing record at once.
--- @param citizenId {CitizenId}
--- @param encoded {string} A validated record, already encoded.
--- @returns {Result}
function OPX.Storage.Players.saveClothing(citizenId, encoded)
	return Storage.execute([[
INSERT INTO opx77_character_clothing (citizen_id, clothing)
VALUES (@citizen, @clothing)
ON DUPLICATE KEY UPDATE clothing = VALUES(clothing)
  ]], { citizen = citizenId, clothing = encoded })
end

--- @author DemiAutomatic
--- @method OPX.Storage.Players.countRows
--- @description Counts every character row an account ever wrote, deleted included.
--- @param userId {UserId}
--- @returns {Result}
function OPX.Storage.Players.countRows(userId)
	local row = Storage.single([[
SELECT COUNT(*) AS total FROM opx77_characters WHERE user_id = @user
  ]], { user = userId })
	if not row.ok then return row end
	return Result.ok(tonumber(row.value and row.value.total) or 0)
end

--- @author DemiAutomatic
--- @method OPX.Storage.Players.softDelete
--- @description Marks a character deleted, keeping its row.
--- @param citizenId {CitizenId}
--- @returns {Result}
function OPX.Storage.Players.softDelete(citizenId)
	return Storage.execute([[
UPDATE opx77_characters SET deleted_at = CURRENT_TIMESTAMP
 WHERE citizen_id = @citizen AND deleted_at IS NULL
  ]], { citizen = citizenId })
end

--- @author DemiAutomatic
--- @method OPX.Storage.Players.fetchGroups
--- @description Reads a character's job and gang memberships as grade maps.
--- @param citizenId {CitizenId}
--- @returns {Result}
function OPX.Storage.Players.fetchGroups(citizenId)
	local rows = Storage.query([[
SELECT group_type, group_name, grade
  FROM opx77_character_groups
 WHERE citizen_id = @citizen
  ]], { citizen = citizenId })
	if not rows.ok then return rows end

	local jobs, gangs = {}, {}
	local list = rows.value or {}
	for i = 1, #list do
		local row = list[i]
		if row.group_type == 'job' then
			jobs[row.group_name] = row.grade
		else
			gangs[row.group_name] = row.grade
		end
	end
	return Result.ok({ jobs = jobs, gangs = gangs })
end

--- @author DemiAutomatic
--- @method OPX.Storage.Players.upsertGroup
--- @description Joins a group, or changes the grade held in it.
--- @param citizenId {CitizenId}
--- @param groupType {GroupType}
--- @param groupName {string}
--- @param grade {integer}
--- @returns {Result}
function OPX.Storage.Players.upsertGroup(citizenId, groupType, groupName, grade)
	return Storage.execute([[
INSERT INTO opx77_character_groups (citizen_id, group_type, group_name, grade)
VALUES (@citizen, @type, @name, @grade)
ON DUPLICATE KEY UPDATE grade = VALUES(grade)
  ]], { citizen = citizenId, type = groupType, name = groupName, grade = grade })
end

--- @author DemiAutomatic
--- @method OPX.Storage.Players.removeGroup
--- @description Removes one job or gang membership row.
--- @param citizenId {CitizenId}
--- @param groupType {GroupType}
--- @param groupName {string}
--- @returns {Result}
function OPX.Storage.Players.removeGroup(citizenId, groupType, groupName)
	return Storage.execute([[
DELETE FROM opx77_character_groups
 WHERE citizen_id = @citizen AND group_type = @type AND group_name = @name
  ]], { citizen = citizenId, type = groupType, name = groupName })
end

--- @author DemiAutomatic
--- @method OPX.Storage.Players.membersOf
--- @description Lists at most 200 living members of a group, highest grade first.
--- @param groupType {GroupType}
--- @param groupName {string}
--- @returns {Result}
function OPX.Storage.Players.membersOf(groupType, groupName)
	local rows = Storage.query([[
SELECT g.citizen_id, g.grade, c.name, c.char_info
  FROM opx77_character_groups g
  JOIN opx77_characters c ON c.citizen_id = g.citizen_id
 WHERE g.group_type = @type AND g.group_name = @name AND c.deleted_at IS NULL
 ORDER BY g.grade DESC, c.name ASC
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
			name = ('%s %s'):format(charInfo.firstName or '?', charInfo.lastName or '?'),
		}
	end
	return Result.ok(out)
end
