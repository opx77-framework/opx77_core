--- The module registry.
---
--- Open2077 server resources cannot call each other, so a framework cannot be
--- a resource others talk to. SYNK is a host instead: what would be a plugin
--- resource elsewhere is a module inside this one.
---
---   return Synk.module("money", {
---     requires = { "characters" },
---     setup = function(ctx) return { deposit = deposit } end,
---   })

local Result = require("shared.result")
local Log = require("shared.log")

local Registry = {}
Registry.__index = Registry

--- Lua patterns cannot quantify a group, so kebab-case is checked in parts.
local function isValidId(id)
  if type(id) ~= "string" then return false end
  if not id:match("^[a-z][a-z0-9%-]*$") then return false end
  if id:sub(-1) == "-" then return false end
  return id:find("%-%-") == nil
end

function Registry.new()
  return setmetatable({
    definitions = {},
    declared = {},   -- declaration order, for stable messages
    loaded = {},
    disabled = {},
    log = Log.scope("kernel"),
  }, Registry)
end

--- Validated here rather than at boot, so a typo is reported at the file that
--- caused it.
function Registry:define(id, definition)
  if not isValidId(id) then
    error(("invalid module id %q: expected lowercase kebab-case"):format(tostring(id)), 3)
  end
  if self.definitions[id] then
    error(("module %q is already defined"):format(id), 3)
  end
  if type(definition) ~= "table" or type(definition.setup) ~= "function" then
    error(("module %q must provide a setup function"):format(id), 3)
  end

  definition.id = id
  definition.requires = definition.requires or {}
  self.definitions[id] = definition
  self.declared[#self.declared + 1] = id
  return definition
end

--- Depth-first topological sort. A cycle is reported by name: a stack overflow
--- at boot tells nobody which modules are at fault.
function Registry:sortByDependencies()
  local sorted, state = {}, {}

  local function visit(id, path)
    if state[id] == "done" then return Result.ok(true) end
    if state[id] == "visiting" then
      return Result.err("cycle", table.concat(path, " -> ") .. " -> " .. id)
    end

    local definition = self.definitions[id]
    if not definition then return Result.err("missing", id) end

    state[id] = "visiting"
    path[#path + 1] = id
    local requires = definition.requires
    for i = 1, #requires do
      local visited = visit(requires[i], path)
      if not visited.ok then
        if visited.error == "missing" then
          return Result.err("missing",
            ("%s requires %s, which is not defined"):format(id, visited.detail))
        end
        return visited
      end
    end
    path[#path] = nil
    state[id] = "done"
    sorted[#sorted + 1] = id
    return Result.ok(true)
  end

  local declared = self.declared
  for i = 1, #declared do
    local visited = visit(declared[i], {})
    if not visited.ok then return visited end
  end
  return Result.ok(sorted)
end

--- Boots in dependency order. `buildContext(definition)` is owned by the
--- kernel; the registry only sequences the calls.
function Registry:boot(buildContext)
  local sorted = self:sortByDependencies()
  if not sorted.ok then
    self.log.error(("cannot resolve modules: %s (%s)")
      :format(sorted.error, tostring(sorted.detail)))
    return sorted
  end

  local order = sorted.value
  for i = 1, #order do
    local id = order[i]
    local definition = self.definitions[id]

    --- A module running without a service it declared is worse than one that
    --- never started, so a failed dependency disables everything downstream.
    local blockedBy
    local requires = definition.requires
    for j = 1, #requires do
      local dependency = requires[j]
      if self.disabled[dependency] then
        blockedBy = dependency
        break
      end
    end

    if blockedBy then
      self.disabled[id] = ("dependency %s is disabled"):format(blockedBy)
      self.log.warn(("module %s disabled: %s"):format(id, self.disabled[id]))
    else
      local ok, produced = pcall(definition.setup, buildContext(definition))
      if ok then
        self.loaded[id] = produced or {}
        self.log.info(("module %s ready"):format(id))
      else
        self.disabled[id] = tostring(produced)
        self.log.error(("module %s failed: %s"):format(id, tostring(produced)))
      end
    end
  end

  return Result.ok({ loaded = self.loaded, disabled = self.disabled })
end

--- Reverse boot order, so a module is never stopped before its dependents.
function Registry:shutdown()
  local sorted = self:sortByDependencies()
  if not sorted.ok then return end

  local order = sorted.value
  for i = #order, 1, -1 do
    local id = order[i]
    local definition = self.definitions[id]
    if self.loaded[id] and definition.teardown then
      local ok, err = pcall(definition.teardown)
      if not ok then
        self.log.error(("module %s teardown failed: %s"):format(id, tostring(err)))
      end
    end
    self.loaded[id] = nil
  end
end

function Registry:get(id)
  return self.loaded[id]
end

return Registry
