--- @author DemiAutomatic
--- @file server/exports.lua
--- @description The server exports other server resources call, and their gates.

--- @author DemiAutomatic
--- @type {table}
--- @description Who may call the server exports, and the answer size bound.
local Config = OPX.Config.SERVER.EXPORTS

--- @author DemiAutomatic
--- @type {table}
--- @description Bounds on what the inventory storage exports accept.
local Limits = OPX.Config.SERVER.INVENTORY

--- @author DemiAutomatic
--- @type {table}
--- @description The inventory storage statements.
local Store = OPX.Storage.Inventories

--- @author DemiAutomatic
--- @type {integer}
--- @description Contract number, bumped on any breaking export change.
local CONTRACT = 1

--- @author DemiAutomatic
--- @type {integer}
--- @description Largest encoded answer an export may return, in bytes.
local MAX_RESULT_BYTES = math.floor(tonumber(Config.MAX_RESULT_BYTES) or 32768)

--- @author DemiAutomatic
--- @method callerOf
--- @description Reads the invoking resource and its generation from the host.
--- @returns {table|nil}
local function callerOf()
	local name = GetInvokingResource()
	local generation = GetInvokingResourceGeneration()
	if type(name) ~= 'string' or name == '' or #name > 64 or not name:match('^[%w_%-%.]+$') then
		return nil
	end
	return { name = name, generation = tonumber(generation) or 0 }
end

--- @author DemiAutomatic
--- @method mayRead
--- @description Answers whether EXPORTS.READ lets a resource call the reads.
--- @param name {string}
--- @returns {boolean}
local function mayRead(name)
	if Config.READ == '*' then return true end
	return type(Config.READ) == 'table' and Config.READ[name] == true
end

--- @author DemiAutomatic
--- @method mayWrite
--- @description Answers whether EXPORTS.CALLERS grants a resource a scope.
--- @param name {string}
--- @param scope {string}
--- @returns {boolean}
local function mayWrite(name, scope)
	local entry = type(Config.CALLERS) == 'table' and Config.CALLERS[name] or nil
	local scopes = type(entry) == 'table' and entry.scopes or nil
	return type(scopes) == 'table' and scopes[scope] == true
end

--- @author DemiAutomatic
--- @method refused
--- @description Builds a refusal answer carrying a locale key code.
--- @param code {string}
--- @returns {table}
local function refused(code)
	return { ok = false, error = code }
end

--- @author DemiAutomatic
--- @method sized
--- @description Answers the value, or export.tooLarge when it would not fit.
--- @param value {table}
--- @returns {table}
local function sized(value)
	local encoded, text = pcall(json.encode, value)
	if not encoded or type(text) ~= 'string' then return refused('export.tooLarge') end
	if #text > MAX_RESULT_BYTES then return refused('export.tooLarge') end
	return value
end

--- @author DemiAutomatic
--- @method guard
--- @description Wraps an export body in the caller, boot and scope checks.
--- @param name {string}
--- @param scope {string|nil} Nil makes the export a read.
--- @param fn {fun(caller: table, ...): table}
--- @returns {function}
local function guard(name, scope, fn)
	return function(...)
		local caller = callerOf()
		if caller == nil then return refused('export.callerDenied') end
		if not OPX.Booted then return refused('core.booting') end

		local allowed
		if scope then allowed = mayWrite(caller.name, scope) else allowed = mayRead(caller.name) end
		if not allowed then
			OPX.Logger.security('export.denied', ('%s called %s'):format(caller.name, name),
				{ caller = caller.name, generation = caller.generation, export = name, scope = scope })
			return refused('export.callerDenied')
		end

		local ran, answer = pcall(fn, caller, ...)
		if not ran then
			Open77.log.error(('[exports] %s raised for %s: %s')
				:format(name, caller.name, tostring(answer)))
			return refused('error.unavailable')
		end
		if type(answer) ~= 'table' then return refused('error.unavailable') end
		return sized(answer)
	end
end

--- @author DemiAutomatic
--- @method integer
--- @description Answers a whole number inside the bounds, or nil.
--- @param value {any}
--- @param low {number}
--- @param high {number}
--- @returns {integer|nil}
local function integer(value, low, high)
	if type(value) ~= 'number' or value ~= value or value % 1 ~= 0 then return nil end
	if value < low or value > high then return nil end
	return math.floor(value)
end

--- @author DemiAutomatic
--- @method token
--- @description Answers a non-empty bounded string matching a pattern, or nil.
--- @param value {any}
--- @param maximum {integer}
--- @param pattern {string}
--- @returns {string|nil}
local function token(value, maximum, pattern)
	if type(value) ~= 'string' or #value == 0 or #value > maximum then return nil end
	if not value:match(pattern) then return nil end
	return value
end

--- @author DemiAutomatic
--- @export GetVersion
--- @description Answers the core version, contract number and the caller's scopes.
exports('GetVersion', guard('GetVersion', nil, function(caller)
	local scopes = {}
	local entry = type(Config.CALLERS) == 'table' and Config.CALLERS[caller.name] or nil
	if type(entry) == 'table' and type(entry.scopes) == 'table' then
		for scope, granted in pairs(entry.scopes) do
			if granted == true then scopes[#scopes + 1] = scope end
		end
		table.sort(scopes)
	end
	return { ok = true, version = OPX.VERSION, exports = CONTRACT, scopes = scopes }
end))

--- @author DemiAutomatic
--- @method identityOfSource
--- @description Answers the identity of a connection from its session.
--- @param source {integer}
--- @returns {table}
local function identityOfSource(source)
	local session = OPX.Sessions[source]
	local player = OPX.GetPlayer(source)
	if not session then
		return { ok = true, source = source, online = false, loaded = false }
	end
	return {
		ok = true,
		source = source,
		userId = session.userId,
		citizenId = player and player.PlayerData.citizenId or nil,
		online = true,
		loaded = player ~= nil,
		gateHeld = session.gateSession ~= nil,
		released = session.released == true,
	}
end

--- @author DemiAutomatic
--- @export GetIdentity
--- @description Answers who a player id or citizen id is, online or not.
--- @param target {integer|string}
exports('GetIdentity', guard('GetIdentity', nil, function(_, target)
	if type(target) == 'number' then
		local source = integer(target, 1, 2147483647)
		if not source then return refused('export.badArgument') end
		return identityOfSource(source)
	end

	local parsed = OPX.CitizenId.parse(target)
	if not parsed.ok then return refused('export.badArgument') end

	local online = OPX.GetPlayerByCitizenId(parsed.value)
	if online then return identityOfSource(online.PlayerData.source) end

	local fetched = OPX.Storage.Players.fetchOne(parsed.value)
	if not fetched.ok then
		if fetched.error == 'character.notFound' then return refused('character.notFound') end
		Open77.log.error('[exports] GetIdentity read failed: ' .. tostring(fetched.detail))
		return refused('error.unavailable')
	end
	return {
		ok = true,
		userId = fetched.value.userId,
		citizenId = fetched.value.citizenId,
		online = false,
		loaded = false,
	}
end))

--- @author DemiAutomatic
--- @export GetVehiclePlate
--- @description Answers the plate and owner of a vehicle the core spawned.
--- @param vehicleId {integer}
exports('GetVehiclePlate', guard('GetVehiclePlate', nil, function(_, vehicleId)
	local id = integer(vehicleId, 1, math.maxinteger)
	if not id then return refused('export.badArgument') end
	local plate, citizenId = OPX.Vehicles.PlateOf(id)
	return { ok = true, plate = plate, citizenId = citizenId }
end))

--- @author DemiAutomatic
--- @type {integer}
--- @description Changes the journal ring keeps before dropping the oldest.
local JOURNAL_SIZE = 512

--- @author DemiAutomatic
--- @type {integer}
--- @description Most changes one GetChanges answer carries.
local EVENTS_PER_READ = 16

--- @author DemiAutomatic
--- @type {table<integer, CoreChange>}
--- @description The change ring, keyed by cursor.
local journal = {}

--- @author DemiAutomatic
--- @type {integer}
--- @description The cursor of the newest recorded change.
local cursor = 0

--- @author DemiAutomatic
--- @method record
--- @description Appends one change to the journal ring.
--- @param kind {string} loaded, unloaded or deleted.
--- @param source {integer|nil}
--- @param citizenId {string|nil}
local function record(kind, source, citizenId)
	cursor = cursor + 1
	journal[cursor] = {
		cursor = cursor,
		kind = kind,
		source = tonumber(source),
		citizenId = citizenId,
		at = OPX.Now(),
	}
	journal[cursor - JOURNAL_SIZE] = nil
end

--- @author DemiAutomatic
--- @event opx77:player:loaded
--- @description Records a loaded character in the change journal.
--- @param source {integer}
--- @param playerData {PlayerData}
AddEventHandler(OPX.Events.Internal.PLAYER_LOADED, function(source, playerData)
	record('loaded', source, type(playerData) == 'table' and playerData.citizenId or nil)
end)

--- @author DemiAutomatic
--- @event opx77:player:unloaded
--- @description Records an unloaded character in the change journal.
--- @param source {integer}
--- @param playerData {PlayerData}
AddEventHandler(OPX.Events.Internal.PLAYER_UNLOADED, function(source, playerData)
	record('unloaded', source, type(playerData) == 'table' and playerData.citizenId or nil)
end)

--- @author DemiAutomatic
--- @event opx77:player:characterDeleted
--- @description Records a deleted character in the change journal.
--- @param source {integer}
--- @param citizenId {string}
AddEventHandler(OPX.Events.Internal.CHARACTER_DELETED, function(source, citizenId)
	record('deleted', source, citizenId)
end)

--- @author DemiAutomatic
--- @export GetChanges
--- @description Answers the character changes recorded after a cursor.
--- @param since {integer}
exports('GetChanges', guard('GetChanges', nil, function(_, since)
	since = integer(since, 0, math.maxinteger)
	if since == nil then return refused('export.badArgument') end

	local oldest = math.max(1, cursor - JOURNAL_SIZE + 1)
	local reset = since > cursor or since < oldest - 1
	local from = reset and oldest or since + 1

	local events = {}
	local last = from - 1
	for at = from, math.min(cursor, from + EVENTS_PER_READ - 1) do
		local entry = journal[at]
		if entry then events[#events + 1] = entry end
		last = at
	end

	return {
		ok = true,
		cursor = reset and math.max(last, 0) or math.max(last, since),
		head = cursor,
		reset = reset,
		more = last < cursor,
		generation = GetCurrentResourceGeneration(),
		events = events,
	}
end))

--- @author DemiAutomatic
--- @type {string}
--- @description Pattern a container kind must match.
local KIND = '^[a-z][a-z0-9_]*$'
--- @author DemiAutomatic
--- @type {string}
--- @description Pattern a container owner must match.
local OWNER = '^[%w_%-%.:]+$'
--- @author DemiAutomatic
--- @type {string}
--- @description Pattern an item name must match.
local ITEM = '^[%w_%-%.]+$'
--- @author DemiAutomatic
--- @type {string}
--- @description Pattern a staged save token must match.
local TOKEN = '^[%w_%-]+$'
--- @author DemiAutomatic
--- @type {integer}
--- @description Largest count one stack may carry.
local MAX_COUNT = 2147483647

--- @author DemiAutomatic
--- @method sizeOf
--- @description Reads a container's requested slots and weight from the options.
--- @param options {any}
--- @returns {integer|nil, integer|nil}
local function sizeOf(options)
	if type(options) ~= 'table' then return nil, nil end
	return integer(options.slots, 1, Limits.MAX_SLOTS),
		integer(options.maxWeight, 0, Limits.MAX_WEIGHT)
end

--- @author DemiAutomatic
--- @export InventoryEnsure
--- @description Finds or creates a container, checking a linked owner exists.
--- @param kind {string}
--- @param owner {string}
--- @param options {table}
exports('InventoryEnsure', guard('InventoryEnsure', 'inventory', function(_, kind, owner, options)
	kind = token(kind, 32, KIND)
	owner = token(owner, 64, OWNER)
	local slots, maxWeight = sizeOf(options)
	if not kind or not owner or not slots or not maxWeight then
		return refused('export.badArgument')
	end

	local entity = { kind = kind, owner = owner, slots = slots, maxWeight = maxWeight }
	local link = Limits.LINKED_KINDS[kind]
	if link == 'citizen' then
		local parsed = OPX.CitizenId.parse(owner)
		if not parsed.ok or parsed.value ~= owner then return refused('export.badArgument') end
		local exists = Store.characterExists(owner)
		if not exists.ok then return refused('error.unavailable') end
		if not exists.value then return refused('inventory.noOwner') end
		entity.citizenId = owner
	elseif link == 'plate' then
		if #owner > 12 then return refused('export.badArgument') end
		local exists = Store.vehicleExists(owner)
		if not exists.ok then return refused('error.unavailable') end
		if not exists.value then return refused('inventory.noOwner') end
		entity.plate = owner
	end

	local ensured = Store.ensure(entity)
	if not ensured.ok then
		if ensured.error == 'inventory.noOwner' then return refused('inventory.noOwner') end
		Open77.log.error(('[exports] InventoryEnsure %s/%s failed: %s')
			:format(kind, owner, tostring(ensured.detail)))
		return refused('error.unavailable')
	end
	local header = ensured.value.header
	return {
		ok = true,
		id = header.id,
		kind = header.kind,
		owner = header.owner,
		slots = header.slots,
		maxWeight = header.maxWeight,
		created = ensured.value.created,
	}
end))

--- @author DemiAutomatic
--- @export InventoryRead
--- @description Answers one page of a container's stacks after a slot.
--- @param id {integer}
--- @param after {integer|nil}
exports('InventoryRead', guard('InventoryRead', 'inventory', function(_, id, after)
	id = integer(id, 1, 4294967295)
	after = after == nil and 0 or integer(after, 0, 65535)
	if not id or not after then return refused('export.badArgument') end

	local answer = { ok = true, id = id, items = {} }
	if after == 0 then
		local header = Store.header(id)
		if not header.ok then return refused('error.unavailable') end
		if not header.value then return refused('inventory.notFound') end
		answer.kind = header.value.kind
		answer.owner = header.value.owner
		answer.slots = header.value.slots
		answer.maxWeight = header.value.maxWeight
	end

	local page = Limits.PAGE_ROWS
	local rows = Store.contents(id, after, page)
	if not rows.ok then
		Open77.log.error(('[exports] InventoryRead %d failed: %s'):format(id, tostring(rows.detail)))
		return refused('error.unavailable')
	end

	local budget, used = MAX_RESULT_BYTES // 2, 0
	local list = rows.value
	for i = 1, #list do
		local encoded, text = pcall(json.encode, list[i])
		local size = encoded and #text or MAX_RESULT_BYTES
		if i > 1 and used + size > budget then
			answer.nextAfter = list[i - 1].slot
			return answer
		end
		used = used + size
		answer.items[i] = list[i]
	end
	if #list == page then answer.nextAfter = list[#list].slot end
	return answer
end))

--- @author DemiAutomatic
--- @type {table<string, table<string, table>>}
--- @description Staged saves, keyed by caller name then token.
local staged = {}

--- @author DemiAutomatic
--- @type {integer}
--- @description Milliseconds an uncommitted token is kept.
local STAGE_TTL_MS = 30000

--- @author DemiAutomatic
--- @type {integer}
--- @description Most open tokens one caller may hold.
local TOKENS_PER_CALLER = 8

--- @author DemiAutomatic
--- @type {integer}
--- @description Most containers one token may stage.
local CONTAINERS_PER_TOKEN = 64

--- @author DemiAutomatic
--- @method sweepStaged
--- @description Forgets staged saves nobody committed in time.
local function sweepStaged()
	local now = OPX.Now()
	for name, tokens in pairs(staged) do
		for key, stage in pairs(tokens) do
			if now - stage.atMs > STAGE_TTL_MS then tokens[key] = nil end
		end
		if next(tokens) == nil then staged[name] = nil end
	end
end

--- @author DemiAutomatic
--- @method stackOf
--- @description Answers one checked stack from the wire, or nil.
--- @param row {any}
--- @returns {InventoryStack|nil}
local function stackOf(row)
	if type(row) ~= 'table' then return nil end
	local slot = integer(row.slot, 1, Limits.MAX_SLOTS)
	local name = token(row.name, 48, ITEM)
	local count = integer(row.count, 1, MAX_COUNT)
	if not slot or not name or not count then return nil end
	local metadata = row.metadata
	if metadata ~= nil then
		if type(metadata) ~= 'table' then return nil end
		local encoded, text = pcall(json.encode, metadata)
		if not encoded or #text > Limits.MAX_METADATA_BYTES then return nil end
		if next(metadata) == nil then metadata = nil end
	end
	return { slot = slot, name = name, count = count, metadata = metadata }
end

--- @author DemiAutomatic
--- @export InventoryStage
--- @description Appends stacks to a container's save staged under a token.
--- @param key {string}
--- @param id {integer}
--- @param rows {InventoryStack[]}
exports('InventoryStage', guard('InventoryStage', 'inventory', function(caller, key, id, rows)
	key = token(key, 32, TOKEN)
	id = integer(id, 1, 4294967295)
	if not key or not id or type(rows) ~= 'table' or #rows > Limits.MAX_SLOTS then
		return refused('export.badArgument')
	end

	sweepStaged()
	local tokens = staged[caller.name]
	if not tokens then
		tokens = {}
		staged[caller.name] = tokens
	end
	local stage = tokens[key]
	if not stage then
		local count = 0
		for _ in pairs(tokens) do count = count + 1 end
		if count >= TOKENS_PER_CALLER then return refused('export.tooLarge') end
		stage = { atMs = OPX.Now(), containers = {}, slots = {}, order = {} }
		tokens[key] = stage
	end

	local list = stage.containers[id]
	if not list then
		if #stage.order >= CONTAINERS_PER_TOKEN then return refused('export.tooLarge') end
		list = {}
		stage.containers[id] = list
		stage.slots[id] = {}
		stage.order[#stage.order + 1] = id
	end
	local taken = stage.slots[id]
	if #list + #rows > Limits.MAX_SLOTS then return refused('export.tooLarge') end

	for i = 1, #rows do
		local stack = stackOf(rows[i])
		if not stack or taken[stack.slot] then
			tokens[key] = nil
			return refused('export.badArgument')
		end
		taken[stack.slot] = true
		list[#list + 1] = stack
	end
	stage.atMs = OPX.Now()
	return { ok = true, staged = #list }
end))

--- @author DemiAutomatic
--- @export InventoryCommit
--- @description Writes everything staged under a token as one transaction.
--- @param key {string}
exports('InventoryCommit', guard('InventoryCommit', 'inventory', function(caller, key)
	key = token(key, 32, TOKEN)
	if not key then return refused('export.badArgument') end
	sweepStaged()
	local tokens = staged[caller.name]
	local stage = tokens and tokens[key]
	if not stage then return refused('inventory.unknownToken') end
	tokens[key] = nil

	local containers = {}
	for i = 1, #stage.order do
		local id = stage.order[i]
		containers[i] = { id = id, rows = stage.containers[id] }
	end
	local saved = Store.save(containers)
	if not saved.ok then
		Open77.log.error(('[exports] InventoryCommit of %d container(s) failed: %s')
			:format(#containers, tostring(saved.detail)))
		return refused('inventory.saveFailed')
	end
	return { ok = true, saved = #containers }
end))

--- @author DemiAutomatic
--- @export InventoryResize
--- @description Changes a container's slot count and weight limit.
--- @param id {integer}
--- @param slots {integer}
--- @param maxWeight {integer}
exports('InventoryResize', guard('InventoryResize', 'inventory', function(_, id, slots, maxWeight)
	id = integer(id, 1, 4294967295)
	slots = integer(slots, 1, Limits.MAX_SLOTS)
	maxWeight = integer(maxWeight, 0, Limits.MAX_WEIGHT)
	if not id or not slots or not maxWeight then return refused('export.badArgument') end
	local resized = Store.resize(id, slots, maxWeight)
	if not resized.ok then return refused('error.unavailable') end
	return { ok = true }
end))

--- @author DemiAutomatic
--- @export InventoryDelete
--- @description Deletes a container, its stacks going by cascade.
--- @param id {integer}
exports('InventoryDelete', guard('InventoryDelete', 'inventory', function(_, id)
	id = integer(id, 1, 4294967295)
	if not id then return refused('export.badArgument') end
	local deleted = Store.delete(id)
	if not deleted.ok then return refused('error.unavailable') end
	return { ok = true }
end))

--- @author DemiAutomatic
--- @export InventoryHolders
--- @description Answers which containers hold an item, largest stacks first.
--- @param name {string}
--- @param limit {integer|nil}
exports('InventoryHolders', guard('InventoryHolders', 'inventory', function(_, name, limit)
	name = token(name, 48, ITEM)
	limit = limit == nil and 20 or integer(limit, 1, 50)
	if not name or not limit then return refused('export.badArgument') end
	local rows = Store.holders(name, limit)
	if not rows.ok then return refused('error.unavailable') end
	return { ok = true, holders = rows.value }
end))

Open77.log.info('[exports] server exports published: GetVersion, GetIdentity, GetVehiclePlate, ' ..
	'GetChanges, InventoryEnsure, InventoryRead, InventoryStage, InventoryCommit, ' ..
	'InventoryResize, InventoryDelete, InventoryHolders')
