--- The selection bucket: a player with no character loaded waits in a routing bucket of their
--- own, so nobody choosing a character sees anybody else or is seen. See README, "The selection
--- bucket".
---
--- A bucket move is not a placement. It changes which bodies, props and vehicles the host
--- replicates to and from a player; it does not write the transform, the life state or the
--- puppet, which are what the readiness gate protects a non-incarnated client from. So it is
--- done while the gate is closed, from the first moment the core knows the player.

local Config = OPX.Config.SERVER

local Buckets = {}
OPX.Buckets = Buckets

--- The host's bucket ids are uint32, and player ids are small recycled integers. A selection
--- bucket is BASE + id, so the whole range is BASE + 1 .. BASE + ID_SPAN.
local UINT32_MAX = 4294967295
local ID_SPAN = 65535

local LOCKDOWN_MODES = { inactive = true, relaxed = true, strict = true, full = true }

--- Operator configuration, resolved once at load; a bad value is said once and the shipped one
--- used. `isolate` false turns the whole feature off: nobody is moved, and a stored bucket is
--- honoured as it always was.
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

--- The namespaced API where the host installs it, the globals otherwise. Both are
--- documented as equivalent, and neither needs a manifest permission.
local api = {}
do
	local ns = type(Open77.routingBuckets) == 'table' and Open77.routingBuckets or {}
	api.getPlayer = ns.getPlayer or rawget(_G, 'GetPlayerRoutingBucket')
	api.setPlayer = ns.setPlayer or rawget(_G, 'SetPlayerRoutingBucket')
	api.setPopulationEnabled = ns.setPopulationEnabled or
		rawget(_G, 'SetRoutingBucketPopulationEnabled')
	api.setLockdownMode = ns.setLockdownMode or rawget(_G, 'SetRoutingBucketEntityLockdownMode')
	if isolate and (type(api.getPlayer) ~= 'function' or type(api.setPlayer) ~= 'function') then
		Open77.log.warn('[bucket] this server has no routing bucket API: players choosing a ' ..
			'character are not isolated')
		isolate = false
	end
end

--- Selection buckets whose policy this VM has already set. The policy is per bucket and
--- outlives the player, so it is set once per bucket, and again after a reload.
---@type table<integer, boolean>
local prepared = {}

--- Whether players choosing a character are isolated at all on this server.
---@return boolean
function Buckets.enabled()
	return isolate
end

--- The bucket a character goes to when nothing else names one.
---@return integer
function Buckets.world()
	return world
end

--- A player's own selection bucket, or nil when isolation is off or the id cannot have one.
---@param source Source
---@return integer|nil
function Buckets.selectionOf(source)
	source = tonumber(source)
	if not isolate or not source or source < 1 or source > ID_SPAN or source % 1 ~= 0 then
		return nil
	end
	return base + source
end

--- Whether a bucket id is in the selection range. Answered even with isolation off, so a
--- stored position left there by an earlier configuration is still recognised.
---@param bucket any
---@return boolean
function Buckets.isSelection(bucket)
	return type(bucket) == 'number' and bucket > base and bucket <= base + ID_SPAN
end

--- The bucket a player is in, or nil where the host cannot say.
---@param source Source
---@return integer|nil
function Buckets.current(source)
	if type(api.getPlayer) ~= 'function' then return nil end
	local read, bucket = pcall(api.getPlayer, source)
	return read and tonumber(bucket) or nil
end

--- Where a stored position puts a character: the bucket it names, unless that is a selection
--- bucket, which belongs to whoever holds that player id now and never to a character.
---@param stored any the `bucket` of a stored Position
---@return integer
function Buckets.placementOf(stored)
	local bucket = tonumber(stored)
	if bucket == nil or bucket % 1 ~= 0 or bucket < 0 or bucket > UINT32_MAX then return world end
	if Buckets.isSelection(bucket) then return world end
	return bucket
end

--- Move one player. Logged at debug either way; a refusal also at warn, since a player then
--- waits in, or enters, the wrong world.
---@param source Source
---@param bucket integer
---@param why string
---@return boolean moved
function Buckets.move(source, bucket, why)
	if type(api.setPlayer) ~= 'function' then return false end
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

--- Set a selection bucket's policy: no ambient population, and the configured lockdown, as the
--- platform's own isolated rounds are prepared.
---@param bucket integer
local function prepare(bucket)
	if prepared[bucket] then return end
	prepared[bucket] = true
	if type(api.setPopulationEnabled) == 'function' then
		pcall(api.setPopulationEnabled, bucket, population)
	end
	if lockdown ~= nil and type(api.setLockdownMode) == 'function' then
		pcall(api.setLockdownMode, bucket, lockdown)
	end
end

--- Put a player with no character in their own selection bucket. Refused for a player who has
--- one loaded or is leaving: the first is in the world, the second may already hand their id
--- to somebody else.
---@param source Source
---@param why string
---@return boolean isolated
function Buckets.isolate(source, why)
	local bucket = Buckets.selectionOf(source)
	if bucket == nil then return false end
	local session = OPX.Sessions[source]
	if not session or session.departing or OPX.Players[source] then return false end
	prepare(bucket)
	return Buckets.move(source, bucket, why)
end

--- Take a player out of their selection bucket into the world one. Nothing happens to a player
--- who is not in it, so a bucket another resource chose since is left alone.
---@param source Source
---@param why string
---@return boolean released  true also when there was nothing to release
---@return boolean moved     whether a move was made
function Buckets.release(source, why)
	local current = Buckets.current(source)
	if current == nil or not Buckets.isSelection(current) then return true, false end
	local moved = Buckets.move(source, world, why)
	return moved, moved
end

--- A stop hands back what the core took: nobody is left in a bucket no running resource knows
--- about. A reload re-isolates, from the client's READY, whoever is still behind the gate.
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
