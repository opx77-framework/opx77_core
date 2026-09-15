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
--- @type {table<string, boolean>}
--- @description Optional migrations that failed this run, by name.
Storage.skipped = {}

--- @author DemiAutomatic
--- @method OPX.Storage.migrate
--- @description Applies pending migrations in order, keyed by their name.
--- @param migrations {Migration[]}
--- @returns {Result}
function OPX.Storage.migrate(migrations)
	local created = Storage.execute([[
CREATE TABLE IF NOT EXISTS opx77_migrations (
    name VARCHAR(190) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB
  ]])
	if not created.ok then
		Open77.log.error('[storage] cannot create the migration table: ' ..
			tostring(created.detail))
		return created
	end

	local rows = Storage.query('SELECT name FROM opx77_migrations')
	if not rows.ok then return rows end

	local applied = {}
	local names = rows.value or {}
	for i = 1, #names do applied[names[i].name] = true end

	local count = 0
	for i = 1, #migrations do
		local migration = migrations[i]
		if not applied[migration.name] then
			Open77.log.info(('[storage] applying migration %s'):format(migration.name))

			local statements = migration.statements
			local failed = false
			for j = 1, #statements do
				local run_ = Storage.execute(statements[j])
				if not run_.ok then
					if not migration.optional then
						Open77.log.error(('[storage] migration %s statement %d failed: %s')
							:format(migration.name, j, tostring(run_.detail)))
						return Result.err('migration-failed', migration.name)
					end
					Open77.log.warn(('[storage] optional migration %s statement %d failed: %s')
						:format(migration.name, j, tostring(run_.detail)))
					Open77.log.warn(('[storage] booting without it: %s'):format(migration.optional))
					Storage.skipped[migration.name] = true
					failed = true
					break
				end
			end

			if not failed then
				local recorded = Storage.insert(
					'INSERT INTO opx77_migrations (name) VALUES (@name)', { name = migration.name })
				if not recorded.ok then return recorded end
				count = count + 1
			end
		end
	end

	Open77.log.info('[storage] ' ..
		(count == 0 and 'schema is up to date' or ('%d migration(s) applied'):format(count)))
	return Result.ok(count)
end
