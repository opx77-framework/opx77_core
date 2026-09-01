--- Extension points, so a gameplay file added to this resource stays additive instead of
--- editing server/player.lua. A hook runs inside the operation it guards, so one that yields
--- stalls a money transfer.
---
---   OPX.Hooks.register("money:beforeRemove", function(payload)
---     if payload.moneyType == "BANK" and payload.player.PlayerData.metadata.frozen then
---       return false
---     end
---   end)

local Hooks = {}

---@type table<string, { id: integer, fn: function, priority: number }[]>
local registry = {}
local nextId = 0

--- Lower `priority` runs first; equal priorities run in registration (manifest) order.
---@param name string
---@param fn fun(payload: HookPayload): boolean? return false to veto
---@param priority? number
---@return integer id  pass to `remove`
function Hooks.register(name, fn, priority)
  if type(name) ~= "string" or type(fn) ~= "function" then
    error("OPX.Hooks.register expects (name: string, fn: function)", 2)
  end

  nextId = nextId + 1
  local entry = { id = nextId, fn = fn, priority = tonumber(priority) or 0 }

  local list = registry[name]
  if not list then
    list = {}
    registry[name] = list
  end

  -- sorted on write, not on read: the list is written at load and read every call
  local at = #list + 1
  for i = 1, #list do
    if list[i].priority > entry.priority then
      at = i
      break
    end
  end
  table.insert(list, at, entry)

  return entry.id
end

---@param id integer
---@return boolean
function Hooks.remove(id)
  for _, list in pairs(registry) do
    for i = 1, #list do
      if list[i].id == id then
        table.remove(list, i)
        return true
      end
    end
  end
  return false
end

--- Runs every hook at `name`, stopping at the first veto.
---@param name string
---@param payload HookPayload
---@return boolean allowed  false only when a hook returned an explicit false
function Hooks.trigger(name, payload)
  local list = registry[name]
  if not list then return true end

  for i = 1, #list do
    -- pcall: a hook belongs to somebody else's file, and a broken one is no opinion
    local ok, verdict = pcall(list[i].fn, payload)
    if not ok then
      OPX.Log.error(("hook %s (#%d) raised: %s"):format(name, list[i].id, tostring(verdict)))
    elseif verdict == false then
      return false
    end
  end
  return true
end

--- Whether anything is listening, for skipping a payload nobody will read.
---@param name string
---@return boolean
function Hooks.has(name)
  local list = registry[name]
  return list ~= nil and #list > 0
end

OPX.Hooks = Hooks
