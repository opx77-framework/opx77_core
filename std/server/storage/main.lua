---@meta

--- Database access through the MySQL bridge. Every call yields: coroutine only. A bridge raise
--- is answered as `query-failed`, a missing bridge as `no-database`.
OPX.Storage = {}

--- Optional migrations that failed this run, by name. Never recorded, so the next start tries
--- them again; what reads their tables asks here first.
---@type table<string, boolean>
OPX.Storage.skipped = {}

--- Runs a statement; the ok value is a list of rows.
---@param sql string
---@param params? table
---@return Result
function OPX.Storage.query(sql, params) end

--- Runs a statement; the ok value is one row, or nil for no such row.
---@param sql string
---@param params? table
---@return Result
function OPX.Storage.single(sql, params) end

--- Runs a statement; the ok value is one column of one row, or nil.
---@param sql string
---@param params? table
---@return Result
function OPX.Storage.scalar(sql, params) end

--- Runs an insert; the ok value is the inserted id.
---@param sql string
---@param params? table
---@return Result
function OPX.Storage.insert(sql, params) end

--- Runs a write or a DDL statement; the ok value is the number of rows affected.
---@param sql string
---@param params? table
---@return Result
function OPX.Storage.update(sql, params) end

--- Same as `update`, for statements whose answer nobody reads.
---@param sql string
---@param params? table
---@return Result
function OPX.Storage.execute(sql, params) end

--- Commits the statements as one unit or rolls them all back. Errors: `no-database`,
--- `transaction-raised`, `transaction-failed`.
---@param statements ({ query: string, values: table }|string)[]
---@return Result
function OPX.Storage.transaction(statements) end

--- Probes the database once and caches the answer for the run.
---@return boolean ready
---@return string reason
function OPX.Storage.ready() end

--- Applies pending migrations in order, keyed by name. Stops at the first failure of a
--- migration that is not optional (`migration-failed`); the ok value is the number applied.
---@param migrations Migration[]
---@return Result
function OPX.Storage.migrate(migrations) end
