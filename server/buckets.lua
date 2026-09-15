--- @author DemiAutomatic
--- @file server/buckets.lua
--- @description Isolates players without a character in a routing bucket of their own.

--- @author DemiAutomatic
--- @type {table}
--- @description The server configuration, read for ENTRY.BUCKET.
local Config = OPX.Config.SERVER

--- @author DemiAutomatic
--- @type {table}
--- @description The selection bucket module.
OPX.Buckets = {}

--- @author DemiAutomatic
--- @type {table}
--- @description Short alias of the selection bucket module.
local Buckets = OPX.Buckets

--- @author DemiAutomatic
--- @type {integer}
--- @description The largest bucket id the host accepts.
local UINT32_MAX = 4294967295

--- @author DemiAutomatic
--- @type {integer}
--- @description The largest player id that has a selection bucket.
local ID_SPAN = 65535

--- @author DemiAutomatic
--- @type {table<string, boolean>}
--- @description The entity lockdown modes the host accepts.
local LOCKDOWN_MODES = { inactive = true, relaxed = true, strict = true, full = true }

--- @author DemiAutomatic
--- @type {boolean, integer, integer, boolean, string|nil}
--- @description The bucket configuration as validated once at load.
local isolate, base, world, population, lockdown = true, 77000, 0, false, 'relaxed'
do
	local wanted = type(Config.ENTRY) == 'table' and Config.ENTRY.BUCKET or nil
	if type(wanted) ~= 'table' then
		if wanted ~= nil then
			Open77.log.warn('[bucket] ENTRY.BUCKET is not a table: the shipped selection bucket is used')
		end
		wanted = {}
	end

	if wanted.ISOLATE == false then
		isolate = false
	elseif wanted.ISOLATE ~= nil and wanted.ISOLATE ~= true then
		Open77.log.warn('[bucket] ENTRY.BUCKET.ISOLATE is not a boolean: players are isolated')
	end

	--- @author DemiAutomatic
	--- @method integer
	--- @description Answers whether a value is a whole number within bounds.
	--- @param value {any}
	--- @param low {number}
	--- @param high {number}
	--- @returns {boolean}
	local function integer(value, low, high)
		return OPX.Math.isFinite(value) and value % 1 == 0 and value >= low and value <= high
	end

	if wanted.WORLD ~= nil then
		if integer(wanted.WORLD, 0, UINT32_MAX) then
			world = wanted.WORLD
		else
			Open77.log.warn('[bucket] ENTRY.BUCKET.WORLD is not a bucket id: 0 is used')
		end
	end

	if wanted.BASE ~= nil then
		if integer(wanted.BASE, 0, UINT32_MAX - ID_SPAN) then
			base = wanted.BASE
		else
			Open77.log.warn(('[bucket] ENTRY.BUCKET.BASE is not a bucket id at most %d: %d is used')
				:format(UINT32_MAX - ID_SPAN, base))
		end
	end
	if world > base and world <= base + ID_SPAN then
		Open77.log.error(('[bucket] ENTRY.BUCKET.WORLD %d is inside the selection range %d..%d: ' ..
			'players are not isolated'):format(world, base + 1, base + ID_SPAN))
		isolate = false
	end

	if wanted.POPULATION ~= nil then
		if type(wanted.POPULATION) == 'boolean' then
			population = wanted.POPULATION
		else
			Open77.log.warn('[bucket] ENTRY.BUCKET.POPULATION is not a boolean: population is off')
		end
	end

	if wanted.LOCKDOWN == false then
		lockdown = nil
	elseif wanted.LOCKDOWN ~= nil then
		if LOCKDOWN_MODES[wanted.LOCKDOWN] then
			lockdown = wanted.LOCKDOWN
		else
			Open77.log.warn('[bucket] ENTRY.BUCKET.LOCKDOWN is not a lockdown mode: relaxed is used')
		end
	end
end

--- @author DemiAutomatic
--- @type {table}
--- @description The host's routing bucket API.
local api = Open77.routingBuckets

--- @author DemiAutomatic
--- @type {table<integer, boolean>}
--- @description Selection buckets whose policy this VM has already set.
local prepared = {}

--- @author DemiAutomatic
--- @method OPX.Buckets.selectionOf
--- @description Answers a player's own selection bucket, or nil.
--- @param source {Source}
--- @returns {integer|nil}
function OPX.Buckets.selectionOf(source)
	source = tonumber(source)
	if not isolate or not source or source < 1 or source > ID_SPAN or source % 1 ~= 0 then
		return nil
	end
	return base + source
end

--- @author DemiAutomatic
--- @method OPX.Buckets.isSelection
--- @description Answers whether a bucket id lies in the selection range.
--- @param bucket {any}
--- @returns {boolean}
function OPX.Buckets.isSelection(bucket)
	return type(bucket) == 'number' and bucket > base and bucket <= base + ID_SPAN
end

--- @author DemiAutomatic
--- @method OPX.Buckets.current
--- @description Answers the bucket a player is in, or nil.
--- @param source {Source}
--- @returns {integer|nil}
function OPX.Buckets.current(source)
	local read, bucket = pcall(api.getPlayer, source)
	return read and tonumber(bucket) or nil
end

--- @author DemiAutomatic
--- @method OPX.Buckets.placementOf
--- @description Answers the bucket a stored position places a character in.
--- @param stored {any} The bucket of a stored Position.
--- @returns {integer}
function OPX.Buckets.placementOf(stored)
	local bucket = tonumber(stored)
	if bucket == nil or bucket % 1 ~= 0 or bucket < 0 or bucket > UINT32_MAX then return world end
	if Buckets.isSelection(bucket) then return world end
	return bucket
end

--- @author DemiAutomatic
--- @method OPX.Buckets.move
--- @description Moves one player to a bucket, logging the move or refusal.
--- @param source {Source}
--- @param bucket {integer}
--- @param why {string}
--- @returns {boolean}
function OPX.Buckets.move(source, bucket, why)
	local from = Buckets.current(source)
	if from == bucket then return true end
	local called, moved, reason = pcall(api.setPlayer, source, bucket)
	if called and moved then
		Open77.log.debug(('[bucket] %d moved from %s to %d (%s)')
			:format(source, tostring(from), bucket, why))
		return true
	end
	Open77.log.warn(('[bucket] %d could not be moved from %s to %d (%s): %s')
		:format(source, tostring(from), bucket, why, tostring(called and reason or moved)))
	return false
end

--- @author DemiAutomatic
--- @method prepare
--- @description Sets a selection bucket's population and lockdown policy once.
--- @param bucket {integer}
local function prepare(bucket)
	if prepared[bucket] then return end
	prepared[bucket] = true
	pcall(api.setPopulationEnabled, bucket, population)
	if lockdown ~= nil then
		pcall(api.setLockdownMode, bucket, lockdown)
	end
end

--- @author DemiAutomatic
--- @method OPX.Buckets.isolate
--- @description Moves a player without a character into their selection bucket.
--- @param source {Source}
--- @param why {string}
--- @returns {boolean}
function OPX.Buckets.isolate(source, why)
	local bucket = Buckets.selectionOf(source)
	if bucket == nil then return false end
	local session = OPX.Sessions[source]
	if not session or session.departing or OPX.Players[source] then return false end
	prepare(bucket)
	return Buckets.move(source, bucket, why)
end

--- @author DemiAutomatic
--- @method OPX.Buckets.release
--- @description Moves a player out of their selection bucket into the world.
--- @param source {Source}
--- @param why {string}
--- @returns {boolean, boolean}
function OPX.Buckets.release(source, why)
	local current = Buckets.current(source)
	if current == nil or not Buckets.isSelection(current) then return true, false end
	local moved = Buckets.move(source, world, why)
	return moved, moved
end

--- @author DemiAutomatic
--- @event onResourceStop
--- @description Moves everybody out of a selection bucket when the core stops.
--- @param name {string}
AddEventHandler('onResourceStop', function(name)
	if name ~= GetCurrentResourceName() then return end
	local count = 0
	for source in pairs(OPX.Sessions) do
		local _, moved = Buckets.release(source, 'resource stopped')
		if moved then count = count + 1 end
	end
	if count > 0 then
		Open77.log.info(('[bucket] stopping: %d player(s) moved out of their selection bucket')
			:format(count))
	end
end)
