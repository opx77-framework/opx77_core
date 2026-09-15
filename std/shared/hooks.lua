---@meta

--- Extension points, so a gameplay file added to the core stays additive. A hook runs inside the
--- operation it guards: one that yields stalls it. Points the core triggers: money:beforeAdd,
--- money:beforeRemove, money:beforeSet, paycheck:before.
OPX.Hooks = {}

--- Registers a hook. Lower `priority` runs first; equal priorities run in registration order.
---@param name string
---@param fn fun(payload: HookPayload): boolean? return false to veto
---@param priority? number
---@return integer id pass to `remove`
function OPX.Hooks.register(name, fn, priority) end

--- Removes a hook by the id `register` answered.
---@param id integer
---@return boolean removed
function OPX.Hooks.remove(id) end

--- Runs every hook at `name`, stopping at the first veto. A hook that raises is logged and has
--- no opinion.
---@param name string
---@param payload HookPayload
---@return boolean allowed false only when a hook returned an explicit false
function OPX.Hooks.trigger(name, payload) end

--- Whether anything is listening, for skipping a payload nobody will read.
---@param name string
---@return boolean
function OPX.Hooks.has(name) end
