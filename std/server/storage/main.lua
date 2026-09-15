---@meta

--- Database access through the MySQL bridge. Every call yields: coroutine only. A bridge raise
--- is answered as `query-failed`, a missing bridge as `no-database`.
OPX.Storage = {}

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

--- Decodes a JSON column. A table is answered as it is (a bridge build may hand one over already
--- decoded); an empty, non-string or undecodable value answers `fallback`.
---@param value any
---@param fallback? table
---@return table|nil
function OPX.Storage.Decode(value, fallback) end

--- The parameter for a nullable JSON column: the encoded value, or "" for nil, which the
--- statement turns back into NULL with `NULLIF(@x, '')` because the bridge drops a nil parameter.
---@param value any
---@return string
function OPX.Storage.Nullable(value) end

--- Probes the database once and caches the answer for the run.
---@return boolean ready
---@return string reason
function OPX.Storage.ready() end

--- Runs every `CREATE TABLE IF NOT EXISTS` statement in order and stops at the first failure,
--- answering `schema-failed` with the table name as the detail; the ok value is the count.
--- A statement never alters an existing table.
---@param statements string[]
---@return Result
function OPX.Storage.applySchema(statements) end
