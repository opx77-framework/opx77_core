--- The core's server exports: what another server resource may ask of it, and who may ask.
--- Every export answers `{ ok = true, ... }` or `{ ok = false, error = <locale key> }` and never
--- raises; a raise is logged and answered `error.unavailable`. See README, "Server exports".
---
--- Loaded last: publishing the surface claims everything it reads exists.

local Config = OPX.Config.SERVER.EXPORTS
local Limits = OPX.Config.SERVER.INVENTORY
local Store = OPX.Storage.Inventories

--- Bumped on any breaking change to an export's arguments or answer. A name is never reused.
local CONTRACT = 1

local MAX_RESULT_BYTES = math.floor(tonumber(Config.MAX_RESULT_BYTES) or 32768)

-- ---------------------------------------------------------------------------
-- The caller, the gates, the answer
-- ---------------------------------------------------------------------------

--- Who is calling, read from the host once, at entry, and handed down: exported coroutines
--- interleave at every yield, so a module-level copy would name whichever call resumed last.
---@return { name: string, generation: integer }|nil
local function callerOf()
	local name = GetInvokingResource()
	local generation = GetInvokingResourceGeneration()
	if type(name) ~= 'string' or name == '' or #name > 64 or not name:match('^[%w_%-%.]+$') then
		return nil
	end
	return { name = name, generation = tonumber(generation) or 0 }
end

---@param name string
---@return boolean
local function mayRead(name)
	if Config.READ == '*' then return true end
	return type(Config.READ) == 'table' and Config.READ[name] == true
end

---@param name string
---@param scope string
---@return boolean
local function mayWrite(name, scope)
	local entry = type(Config.CALLERS) == 'table' and Config.CALLERS[name] or nil
	local scopes = type(entry) == 'table' and entry.scopes or nil
	return type(scopes) == 'table' and scopes[scope] == true
end

---@param code string
---@return table
local function refused(code)
	return { ok = false, error = code }
end

--- The answer, unless it would not fit the host's transfer budget. Past that the caller would
--- see an opaque codec refusal instead of a code it can branch on.
---@param value table
---@return table
local function sized(value)
	local encoded, text = pcall(json.encode, value)
	if not encoded or type(text) ~= 'string' then return refused('export.tooLarge') end
	if #text > MAX_RESULT_BYTES then return refused('export.tooLarge') end
	return value
end

--- Publishes one export behind the caller check, the boot gate and its scope. `scope` nil
--- makes it a read.
---@param name string
---@param scope string|nil
---@param fn fun(caller: table, ...): table
local function publish(name, scope, fn)
	exports(name, function(...)
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
	end)
end

-- ---------------------------------------------------------------------------
-- Argument checks. Every argument is checked, a known caller's included.
-- ---------------------------------------------------------------------------

--- A whole number inside `[low, high]`, or nil. NaN fails `value == value`.
---@param value any
---@param low number
---@param high number
---@return integer|nil
local function integer(value, low, high)
	if type(value) ~= 'number' or value ~= value or value % 1 ~= 0 then return nil end
	if value < low or value > high then return nil end
	return math.floor(value)
end

---@param value any
---@param maximum integer
---@param pattern string
---@return string|nil
local function token(value, maximum, pattern)
	if type(value) ~= 'string' or #value == 0 or #value > maximum then return nil end
	if not value:match(pattern) then return nil end
	return value
end

-- ---------------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------------

publish('GetVersion', nil, function(caller)
	local scopes = {}
	local entry = type(Config.CALLERS) == 'table' and Config.CALLERS[caller.name] or nil
	if type(entry) == 'table' and type(entry.scopes) == 'table' then
		for scope, granted in pairs(entry.scopes) do
			if granted == true then scopes[#scopes + 1] = scope end
		end
		table.sort(scopes)
	end
	return { ok = true, version = OPX.VERSION, exports = CONTRACT, scopes = scopes }
end)

--- The identity of a connection, from the session the core keeps for it.
---@param source Source
---@return table
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

--- `target` is a player id, which is online only, or a citizen id, which is also found when
--- the character is offline: then `online` and `loaded` are false and `source` is absent.
publish('GetIdentity', nil, function(_, target)
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
end)

--- Which owned vehicle a runtime vehicle id is. `plate` is absent for a vehicle the core did
--- not spawn, which has no row to key anything durable on.
publish('GetVehiclePlate', nil, function(_, vehicleId)
	local id = integer(vehicleId, 1, math.maxinteger)
	if not id then return refused('export.badArgument') end
	local plate, citizenId = OPX.Vehicles.PlateOf(id)
	return { ok = true, plate = plate, citizenId = citizenId }
end)

-- ---------------------------------------------------------------------------
-- The change cursor: what happened to characters, for resources whose VM cannot hear
-- `Events.Internal`. A bounded ring, read from a cursor, not a callback bus.
-- ---------------------------------------------------------------------------

local JOURNAL_SIZE = 512
local EVENTS_PER_READ = 16

---@type table<integer, table>
local journal = {}
local cursor = 0

---@param kind "loaded"|"unloaded"|"deleted"
---@param source Source|nil
---@param citizenId CitizenId|nil
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

AddEventHandler(OPX.Events.Internal.PLAYER_LOADED, function(source, playerData)
	record('loaded', source, type(playerData) == 'table' and playerData.citizenId or nil)
end)

AddEventHandler(OPX.Events.Internal.PLAYER_UNLOADED, function(source, playerData)
	record('unloaded', source, type(playerData) == 'table' and playerData.citizenId or nil)
end)

AddEventHandler(OPX.Events.Internal.CHARACTER_DELETED, function(source, citizenId)
	record('deleted', source, citizenId)
end)

--- Events after `since`, oldest first, at most EVENTS_PER_READ of them. `reset` says the
--- caller's cursor is not this journal's: the core reloaded, or the ring moved past it, and
--- the caller must re-read whatever it keeps instead of trusting the events alone.
publish('GetChanges', nil, function(_, since)
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
end)

-- ---------------------------------------------------------------------------
-- Inventory storage, scope `inventory`. The core stores what it is handed; what may go in a
-- container is opx77_inventory's to decide.
-- ---------------------------------------------------------------------------

local KIND = '^[a-z][a-z0-9_]*$'
local OWNER = '^[%w_%-%.:]+$'
local ITEM = '^[%w_%-%.]+$'
local TOKEN = '^[%w_%-]+$'
local MAX_COUNT = 2147483647

--- The size of a container as the caller asks for it at creation.
---@param options any
---@return integer|nil slots, integer|nil maxWeight
local function sizeOf(options)
	if type(options) ~= 'table' then return nil, nil end
	return integer(options.slots, 1, Limits.MAX_SLOTS),
		integer(options.maxWeight, 0, Limits.MAX_WEIGHT)
end

--- Finds or creates a container. The size is used only when it is created; an existing one
--- answers the size it was created with.
publish('InventoryEnsure', 'inventory', function(_, kind, owner, options)
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
end)

--- One page of a container's stacks after slot `after`, trimmed to what fits an answer.
--- `nextAfter` is present while there may be more: pass it back as `after`.
publish('InventoryRead', 'inventory', function(_, id, after)
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

	-- trimmed a row at a time against half the budget: the rest is headroom for node overhead
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
end)

--- caller name -> token -> { atMs, containers = { [id] = rows }, order = { id, ... } }. A save
--- is staged across calls, because one argument carries at most 48 KiB, and committed as one
--- transaction.
local staged = {}
local STAGE_TTL_MS = 30000
local TOKENS_PER_CALLER = 8
local CONTAINERS_PER_TOKEN = 64

local function sweepStaged()
	local now = OPX.Now()
	for name, tokens in pairs(staged) do
		for key, stage in pairs(tokens) do
			if now - stage.atMs > STAGE_TTL_MS then tokens[key] = nil end
		end
		if next(tokens) == nil then staged[name] = nil end
	end
end

--- One stack off the wire, checked, or nil.
---@param row any
---@return table|nil
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

--- Appends stacks to a container's staged save. The first stage of a container under a token
--- empties it, so a container staged with no rows is saved empty.
publish('InventoryStage', 'inventory', function(caller, key, id, rows)
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
end)

--- Writes everything staged under a token as one transaction, then forgets the token. A
--- failed commit writes nothing; the caller stages again and retries.
publish('InventoryCommit', 'inventory', function(caller, key)
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
end)

publish('InventoryResize', 'inventory', function(_, id, slots, maxWeight)
	id = integer(id, 1, 4294967295)
	slots = integer(slots, 1, Limits.MAX_SLOTS)
	maxWeight = integer(maxWeight, 0, Limits.MAX_WEIGHT)
	if not id or not slots or not maxWeight then return refused('export.badArgument') end
	local resized = Store.resize(id, slots, maxWeight)
	if not resized.ok then return refused('error.unavailable') end
	return { ok = true }
end)

publish('InventoryDelete', 'inventory', function(_, id)
	id = integer(id, 1, 4294967295)
	if not id then return refused('export.badArgument') end
	local deleted = Store.delete(id)
	if not deleted.ok then return refused('error.unavailable') end
	return { ok = true }
end)

--- Which containers hold an item, the largest stacks first, at most 50.
publish('InventoryHolders', 'inventory', function(_, name, limit)
	name = token(name, 48, ITEM)
	limit = limit == nil and 20 or integer(limit, 1, 50)
	if not name or not limit then return refused('export.badArgument') end
	local rows = Store.holders(name, limit)
	if not rows.ok then return refused('error.unavailable') end
	return { ok = true, holders = rows.value }
end)

Open77.log.info('[exports] server exports published: GetVersion, GetIdentity, GetVehiclePlate, ' ..
	'GetChanges, InventoryEnsure, InventoryRead, InventoryStage, InventoryCommit, ' ..
	'InventoryResize, InventoryDelete, InventoryHolders')
