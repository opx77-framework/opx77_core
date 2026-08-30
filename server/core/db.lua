--- Database access and schema migrations.
---
--- Prefers the documented `await` form (`.await(sql, params?)`), which resumes
--- on this resource's scheduler rather than the database worker, so a query
--- costs no frames. Falls back to the callback form parked on `Wait(0)` for a
--- build that does not expose it.
---
--- Both forms yield: **every call here must be made from inside a
--- CreateThread**.

local Result = require("shared.result")
local Log = require("shared.log")

local Db = {}
local log = Log.scope("db")

--- A query that never calls back would otherwise hang an entry pipeline.
local TIMEOUT_MS = 15000

local function database()
  local ns = rawget(_G, "Open77")
  return ns and ns.database or rawget(_G, "MySQL")
end

--- Parks until `isDone()` or the deadline.
local function waitFor(isDone, what)
  local deadline = GetGameTimer() + TIMEOUT_MS
  while not isDone() do
    if GetGameTimer() > deadline then
      return Result.err("timeout", what)
    end
    Wait(0)
  end
  return Result.ok(true)
end

--- The platform convention: `value` on success, `nil, reason` on failure.
--- `nil` with no reason is an empty result, not an error -- `byPublicCode`
--- reads exactly that as "no such row".
local function settle(value, reason)
  if value == nil and reason ~= nil then
    return Result.err("query-failed", tostring(reason))
  end
  return Result.ok(value)
end

--- The await form hangs off the method itself, so the method has to be a
--- callable table. Indexing a plain function raises, hence the pcall.
local function awaitFormOf(method)
  local ok, form = pcall(function() return method.await end)
  if ok and type(form) == "function" then return form end
  return nil
end

--- Runs one database method and blocks until it answers.
local function runAndWait(method, sql, params)
  local db = database()
  if not db or not db[method] then
    return Result.err("no-database", "Open77.database." .. method .. " is unavailable")
  end

  local await = awaitFormOf(db[method])
  if await then
    local ok, value, reason = pcall(await, sql, params or {})
    if not ok then return Result.err("query-raised", tostring(value)) end
    return settle(value, reason)
  end

  local done, value, failure = false, nil, nil
  local started, err = pcall(db[method], sql, params or {}, function(rows, reason)
    value, failure, done = rows, reason, true
  end)
  if not started then
    return Result.err("query-raised", tostring(err))
  end

  local waited = waitFor(function() return done end, sql:sub(1, 120))
  if not waited.ok then return waited end

  return settle(value, failure)
end

function Db.query(sql, params) return runAndWait("query", sql, params) end
function Db.single(sql, params) return runAndWait("single", sql, params) end
function Db.scalar(sql, params) return runAndWait("scalar", sql, params) end
function Db.insert(sql, params) return runAndWait("insert", sql, params) end
function Db.update(sql, params) return runAndWait("update", sql, params) end

--- `statements` is a list of `{ sql, params }` pairs.
---
--- Stays on the poll: the docs give the await form as `.await(sql, params?)`
--- only, and a transaction takes neither. Guessing its signature here would
--- fail at runtime, on a live server.
function Db.transaction(statements)
  local db = database()
  if not db or not db.transaction then
    return Result.err("no-database", "transactions are unavailable")
  end

  local done, value, failure = false, nil, nil
  local started, err = pcall(db.transaction, statements, function(result, reason)
    value, failure, done = result, reason, true
  end)
  if not started then return Result.err("transaction-raised", tostring(err)) end

  local waited = waitFor(function() return done end, "transaction")
  if not waited.ok then return waited end

  if value == false or (value == nil and failure ~= nil) then
    return Result.err("transaction-failed", tostring(failure))
  end
  return Result.ok(value)
end

--- Applies pending migrations. They are keyed by name, never by position: an
--- index would renumber the moment someone inserts one, and migrations that
--- already ran on a live database would run again.
function Db.migrate(migrations)
  local created = Db.query([[
    CREATE TABLE IF NOT EXISTS synk_migrations (
      name       VARCHAR(190) NOT NULL PRIMARY KEY,
      applied_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
  ]])
  if not created.ok then
    log.error("cannot create the migration table: " .. tostring(created.detail))
    return created
  end

  local rows = Db.query("SELECT name FROM synk_migrations")
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
        local run = Db.query(statements[j])
        if not run.ok then
          log.error(("migration %s failed: %s"):format(migration.name, tostring(run.detail)))
          return Result.err("migration-failed", migration.name)
        end
      end

      local recorded = Db.insert("INSERT INTO synk_migrations (name) VALUES (?)",
        { migration.name })
      if not recorded.ok then return recorded end
      count = count + 1
    end
  end

  log.info(count == 0 and "schema is up to date" or ("%d migration(s) applied"):format(count))
  return Result.ok(count)
end

return Db
