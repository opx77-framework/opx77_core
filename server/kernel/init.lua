--- The kernel: builds the shared services once, hands each module a context,
--- and sequences the boot. `Synk.module` is the only entry point a module
--- author needs.

local Result = require("shared.result")
local Log = require("shared.log")
local Registry = require("server.kernel.module")
local Lifecycle = require("server.kernel.lifecycle")
local Session = require("server.core.session")
local Db = require("server.core.db")
local schema = require("server.core.schema")

local Kernel = {}
local log = Log.scope("kernel")

local registry = Registry.new()
local sessions = Session.new()
local config = require("config")
local lifecycle = Lifecycle.new({
  sessions = sessions,
  gateMs = config.entry.gateMs,
  pipelineMs = config.entry.pipelineMs,
})

--- Called at file scope, before boot.
function Kernel.module(id, definition)
  return registry:define(id, definition)
end

--- A module receives services, never the kernel: it cannot reorder boot or
--- reach into another module's state.
local function buildContext(definition)
  local declared = {}
  local requires = definition.requires
  for i = 1, #requires do declared[requires[i]] = true end

  return {
    id = definition.id,
    log = Log.scope(definition.id),
    db = Db,
    sessions = sessions,

    entryStep = function(name, fn)
      lifecycle:addEntryStep(("%s:%s"):format(definition.id, name), fn)
    end,

    --- Reaching for an undeclared module is an error, not a nil: an
    --- undeclared dependency is invisible to the boot ordering.
    use = function(id)
      if not declared[id] then
        error(("module %q used %q without declaring it in requires")
          :format(definition.id, id), 2)
      end
      return registry:get(id)
    end,
  }
end

--- Schema, then modules, then the gate. The gate goes last so no player can
--- enter before every entry step is registered.
function Kernel.boot(opts)
  opts = opts or {}
  Log.setLevel(opts.logLevel or config.logLevel or "info")
  log.info(("SYNK %s starting"):format(Synk.VERSION))

  local migrated = Db.migrate(schema)
  if not migrated.ok then
    log.error("schema migration failed; refusing to boot with an unknown schema")
    return migrated
  end

  local booted = registry:boot(buildContext)
  if not booted.ok then return booted end

  lifecycle:participate()
  lifecycle:listen()

  local loaded, disabled = 0, 0
  for _ in pairs(booted.value.loaded) do loaded = loaded + 1 end
  for _ in pairs(booted.value.disabled) do disabled = disabled + 1 end

  if disabled > 0 then
    log.warn(("%d module(s) ready, %d disabled"):format(loaded, disabled))
  else
    log.info(("%d module(s) ready"):format(loaded))
  end
  return Result.ok({ loaded = loaded, disabled = disabled })
end

function Kernel.shutdown()
  registry:shutdown()
end

Kernel.registry = registry
Kernel.sessions = sessions
Kernel.lifecycle = lifecycle

return Kernel
