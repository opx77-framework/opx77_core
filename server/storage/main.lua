--- Database access. Every call yields, so every one must be made from inside a CreateThread.
--- `MySQL.<method>.await` RAISES rather than answering `value, reason`, so each is wrapped in
--- pcall and turned into a Result. Named parameters throughout, never positional `?`, because
--- the bridge rewrites `?` by scanning the statement -- which is also why no SQL string in
--- this resource carries a comment.

local Result = OPX.Result
local log = OPX.Log.scope("storage")

local Storage = {}

--- nil until probed, then true or false for the rest of the run.
local ready = nil
local readyReason = "not probed"

--- Runs one bridge method and blocks until it answers. The pcall is not optional: an await
--- that raises inside a CreateThread kills it silently, and that thread is usually a login.
local function run(method, sql, params)
  local api = rawget(_G, "MySQL")
  local fn = api and api[method]
  if not fn or type(fn.await) ~= "function" then
    return Result.err("no-database", ("MySQL.%s.await is unavailable"):format(method))
  end

  local ok, value = pcall(fn.await, sql, params)
  if not ok then
    return Result.err("query-failed", tostring(value))
  end
  -- a nil value is an empty result, not a failure: `single` answers nil for "no such row"
  return Result.ok(value)
end

---@param sql string
---@param params? table
---@return Result  ok value is a list of rows
function Storage.query(sql, params) return run("query", sql, params) end

---@param sql string
---@param params? table
---@return Result  ok value is one row, or nil
function Storage.single(sql, params) return run("single", sql, params) end

---@param sql string
---@param params? table
---@return Result  ok value is one column of one row, or nil
function Storage.scalar(sql, params) return run("scalar", sql, params) end

---@param sql string
---@param params? table
---@return Result  ok value is the inserted id
function Storage.insert(sql, params) return run("insert", sql, params) end

--- Also the right method for DDL.
---@param sql string
---@param params? table
---@return Result  ok value is the number of rows affected
function Storage.update(sql, params) return run("update", sql, params) end

--- Alias for `update`, for statements whose return value nobody reads.
---@param sql string
---@param params? table
---@return Result
function Storage.execute(sql, params) return run("update", sql, params) end

--- Committed or rolled back as one unit. Separate from `run` because this is the one method
--- that resolves `false, reason` instead of raising, so `run` would read a rollback as a win.
---@param statements ({ query: string, values: table }|string)[]
---@return Result
function Storage.transaction(statements)
  local api = rawget(_G, "MySQL")
  local fn = api and api.transaction
  if not fn or type(fn.await) ~= "function" then
    return Result.err("no-database", "MySQL.transaction.await is unavailable")
  end

  local ok, committed, reason = pcall(fn.await, statements)
  if not ok then
    return Result.err("transaction-raised", tostring(committed))
  end
  if committed ~= true then
    return Result.err("transaction-failed", tostring(reason))
  end
  return Result.ok(true)
end

--- Whether the database answered, with the reason if it did not. Probes once, then caches.
--- Coroutine only.
---@return boolean ready, string reason
function Storage.ready()
  if ready ~= nil then return ready, readyReason end

  local probe = Storage.scalar("SELECT 1")
  if not probe.ok then
    ready = false
    readyReason = tostring(probe.detail)
    log.error("no database: " .. readyReason)
    log.error("the core will boot, but nobody can be logged in until this is fixed")
    return false, readyReason
  end

  ready = true
  readyReason = "ready"
  return true, readyReason
end

--- Applies pending migrations in order, keyed by name and never by position: an index
--- renumbers the moment one is inserted in the middle. Stops at the first failure, because a
--- half-applied schema is the one state neither rolling forward nor back is safe from.
---@param migrations Migration[]
---@return Result  ok value is the number applied
function Storage.migrate(migrations)
  local created = Storage.execute([[
CREATE TABLE IF NOT EXISTS opx77_migrations (
    name VARCHAR(190) CHARACTER SET ascii COLLATE ascii_bin NOT NULL PRIMARY KEY,
    applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB
  ]])
  if not created.ok then
    log.error("cannot create the migration table: " .. tostring(created.detail))
    return created
  end

  local rows = Storage.query("SELECT name FROM opx77_migrations")
  if not rows.ok then return rows end

  local applied = {}
  local names = rows.value or {}
  for i = 1, #names do applied[names[i].name] = true end

  local count = 0
  for i = 1, #migrations do
    local migration = migrations[i]
    if not applied[migration.name] then
      log.info(("applying migration %s"):format(migration.name))

      local statements = migration.statements
      for j = 1, #statements do
        local run_ = Storage.execute(statements[j])
        if not run_.ok then
          log.error(("migration %s statement %d failed: %s")
            :format(migration.name, j, tostring(run_.detail)))
          return Result.err("migration-failed", migration.name)
        end
      end

      local recorded = Storage.insert(
        "INSERT INTO opx77_migrations (name) VALUES (@name)", { name = migration.name })
      if not recorded.ok then return recorded end
      count = count + 1
    end
  end

  log.info(count == 0 and "schema is up to date" or ("%d migration(s) applied"):format(count))
  return Result.ok(count)
end

OPX.Storage = Storage
