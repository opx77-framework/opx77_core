--- @author DemiAutomatic
--- @file server/storage/main.lua
--- @description Database access through the MySQL bridge, answering Result values.

--- @author DemiAutomatic
--- @type {table}
--- @description The Result constructors every call answers with.
local Result = OPX.Result

OPX.Storage = {}
local Storage = OPX.Storage

--- @author DemiAutomatic
--- @type {boolean|nil}
--- @description Whether the database answered its probe; nil until probed.
local ready = nil

--- @author DemiAutomatic
--- @type {string}
--- @description Why the database is or is not ready.
local readyReason = 'not probed'

--- @author DemiAutomatic
--- @method run
--- @description Runs one bridge method, turning a raise into a Result.
--- @param method {string}
--- @param sql {string}
--- @param params {table|nil}
--- @returns {Result}
local function run(method, sql, params)
	local api = rawget(_G, 'MySQL')
	local fn = api and api[method]
	if not fn or type(fn.await) ~= 'function' then
		return Result.err('no-database', ('MySQL.%s.await is unavailable'):format(method))
	end

	local ok, value = pcall(fn.await, sql, params)
	if not ok then
		return Result.err('query-failed', tostring(value))
	end
	return Result.ok(value)
end

--- @author DemiAutomatic
--- @method OPX.Storage.query
--- @description Runs a statement answering a list of rows.
--- @param sql {string}
--- @param params {table|nil}
--- @returns {Result}
function OPX.Storage.query(sql, params) return run('query', sql, params) end

--- @author DemiAutomatic
--- @method OPX.Storage.single
--- @description Runs a statement answering one row, or nil.
--- @param sql {string}
--- @param params {table|nil}
--- @returns {Result}
function OPX.Storage.single(sql, params) return run('single', sql, params) end

--- @author DemiAutomatic
--- @method OPX.Storage.scalar
--- @description Runs a statement answering one column of one row.
--- @param sql {string}
--- @param params {table|nil}
--- @returns {Result}
function OPX.Storage.scalar(sql, params) return run('scalar', sql, params) end

--- @author DemiAutomatic
--- @method OPX.Storage.insert
--- @description Runs an insert answering the inserted id.
--- @param sql {string}
--- @param params {table|nil}
--- @returns {Result}
function OPX.Storage.insert(sql, params) return run('insert', sql, params) end

--- @author DemiAutomatic
--- @method OPX.Storage.update
--- @description Runs a write or DDL statement answering the rows affected.
--- @param sql {string}
--- @param params {table|nil}
--- @returns {Result}
function OPX.Storage.update(sql, params) return run('update', sql, params) end

--- @author DemiAutomatic
--- @method OPX.Storage.execute
--- @description Runs a write whose answer nobody reads, like update.
--- @param sql {string}
--- @param params {table|nil}
--- @returns {Result}
function OPX.Storage.execute(sql, params) return run('update', sql, params) end

--- @author DemiAutomatic
--- @method OPX.Storage.transaction
--- @description Commits several statements as one unit, or none of them.
--- @param statements {table[]}
--- @returns {Result}
function OPX.Storage.transaction(statements)
	local api = rawget(_G, 'MySQL')
	local fn = api and api.transaction
	if not fn or type(fn.await) ~= 'function' then
		return Result.err('no-database', 'MySQL.transaction.await is unavailable')
	end

	local ok, committed, reason = pcall(fn.await, statements)
	if not ok then
		return Result.err('transaction-raised', tostring(committed))
	end
	if committed ~= true then
		return Result.err('transaction-failed', tostring(reason))
	end
	return Result.ok(true)
end

--- @author DemiAutomatic
--- @method OPX.Storage.ready
--- @description Probes the database once and answers whether it answered.
--- @returns {boolean, string}
function OPX.Storage.ready()
	if ready ~= nil then return ready, readyReason end

	local probe = Storage.scalar('SELECT 1')
	if not probe.ok then
		ready = false
		readyReason = tostring(probe.detail)
		Open77.log.error('[storage] no database: ' .. readyReason)
		Open77.log.error('[storage] the core will boot, but nobody can be logged in until this ' ..
			'is fixed')
		return false, readyReason
	end

	ready = true
	readyReason = 'ready'
	return true, readyReason
end

--- @author DemiAutomatic
--- @method OPX.Storage.applySchema
--- @description Runs every CREATE TABLE statement in order, stopping at a failure.
--- @param statements {string[]}
--- @returns {Result}
function OPX.Storage.applySchema(statements)
	for i = 1, #statements do
		local statement = statements[i]
		local created = Storage.execute(statement)
		if not created.ok then
			local tableName = statement:match('CREATE TABLE IF NOT EXISTS ([%w_]+)') or ('#' .. i)
			Open77.log.error(('[storage] creating %s failed: %s')
				:format(tableName, tostring(created.detail)))
			return Result.err('schema-failed', tableName)
		end
	end

	Open77.log.info(('[storage] schema ready: %d table(s)'):format(#statements))
	return Result.ok(#statements)
end
