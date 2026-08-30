--- Minimal single-inheritance classes: metatable plumbing, nothing else.
--- A framework people have to read should not make them learn an object
--- system first.
---
---   local Wallet = class("Wallet")
---   function Wallet:init(balance) self.balance = balance end
---   local w = Wallet(100)

local function class(name, parent)
  local cls = { __name = name, __parent = parent }
  cls.__index = cls

  setmetatable(cls, {
    __index = parent,
    __call = function(c, ...) return c.new(...) end,
  })

  cls.__tostring = function(self)
    return ("%s: %s"):format(self.__name or name, self.id or "anonymous")
  end

  function cls.new(...)
    local self = setmetatable({}, cls)
    if cls.init then cls.init(self, ...) end
    return self
  end

  --- Explicit rather than a `super` global: you can see which class it reaches.
  function cls:callParent(method, ...)
    local base = cls.__parent
    if not base or not base[method] then
      error(("%s has no parent method %q"):format(name, method), 2)
    end
    return base[method](self, ...)
  end

  function cls:inheritsFrom(other)
    local current = getmetatable(self)
    while current do
      if current == other then return true end
      current = current.__parent
    end
    return false
  end

  return cls
end

return class
