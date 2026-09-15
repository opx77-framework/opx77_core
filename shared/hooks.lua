--- @author DemiAutomatic
--- @file shared/hooks.lua
--- @description Named extension points a gameplay file can veto through.

OPX.Hooks = {}
local Hooks = OPX.Hooks

--- @author DemiAutomatic
--- @type {table<string, table[]>}
--- @description Registered hooks per name, kept sorted by priority.
local registry = {}

--- @author DemiAutomatic
--- @type {integer}
--- @description The last id handed out by a registration.
local nextId = 0

--- @author DemiAutomatic
--- @method OPX.Hooks.register
--- @description Adds a hook, lower priority first, and answers its id.
--- @param name {string}
--- @param fn {fun(payload: HookPayload): boolean|nil}
--- @param priority {number|nil}
--- @returns {integer}
function OPX.Hooks.register(name, fn, priority)
	if type(name) ~= 'string' or type(fn) ~= 'function' then
		error('OPX.Hooks.register expects (name: string, fn: function)', 2)
	end

	nextId = nextId + 1
	local entry = { id = nextId, fn = fn, priority = tonumber(priority) or 0 }

	local list = registry[name]
	if not list then
		list = {}
		registry[name] = list
	end

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

--- @author DemiAutomatic
--- @method OPX.Hooks.remove
--- @description Removes a hook by the id its registration answered.
--- @param id {integer}
--- @returns {boolean}
function OPX.Hooks.remove(id)
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

--- @author DemiAutomatic
--- @method OPX.Hooks.trigger
--- @description Runs every hook at a name, stopping at the first veto.
--- @param name {string}
--- @param payload {HookPayload}
--- @returns {boolean}
function OPX.Hooks.trigger(name, payload)
	local list = registry[name]
	if not list then return true end

	for i = 1, #list do
		local ok, verdict = pcall(list[i].fn, payload)
		if not ok then
			Open77.log.error(('[hooks] %s (#%d) raised: %s')
				:format(name, list[i].id, tostring(verdict)))
		elseif verdict == false then
			return false
		end
	end
	return true
end

--- @author DemiAutomatic
--- @method OPX.Hooks.has
--- @description Whether any hook is registered at a name.
--- @param name {string}
--- @returns {boolean}
function OPX.Hooks.has(name)
	local list = registry[name]
	return list ~= nil and #list > 0
end
