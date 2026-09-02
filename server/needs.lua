--- Hunger and thirst: how fast they fall and what running out costs.
---
--- It lives here and not in opx77_status because there is nowhere else it CAN live. The
--- numbers are `PlayerData.metadata`, which only this VM holds -- a server resource cannot
--- read another's players, so a decay loop written in a satellite calls a nil `OPX` and its
--- own pcall swallows the raise. opx77_status still owns the effect strip; the two needs are
--- character state and belong to the character.

local Config = OPX.Config.SERVER.NEEDS
local log = OPX.Log.scope("needs")

--- The two needs, and what each does at zero. Health is not here: the engine owns it, and a
--- need that emptied it directly would fight whatever else is writing to it.
local NEEDS = { "hunger", "thirst" }

--- The same predicate as `finite` elsewhere in this framework, coercing first and answering
--- with the number: anything `tonumber` accepts, so long as it is neither NaN nor either
--- infinity. It carries no range of its own -- a caller that needs one applies it to the
--- answer -- so that "finite" means exactly one thing everywhere and a bound stays visible
--- where it bites.
---
--- It used to stop at NaN, which left a helper called "finite" accepting both infinities. That
--- was not academic here: a `metadata.health` of `math.huge` passed the `health > 0` test
--- below and `SetMetaData` wrote `math.huge` straight back into the character, where the
--- autosave then has to JSON-encode it.
---@param value any
---@return number|nil
local function finiteNumber(value)
  value = tonumber(value)
  -- `value ~= value` is the NaN check, not a typo: NaN is the one value unequal to itself
  if value == nil or value ~= value or value == math.huge or value == -math.huge then
    return nil
  end
  return value
end

--- Drop every loaded character's needs by one tick's worth.
---
--- Written through `Functions.SetMetaData` rather than into the table, so the core marks the
--- character changed and the autosave carries it. A character at zero stays at zero; the
--- damage below is what running out costs, not a further drop.
local function tick()
  local players = OPX.GetPlayers()
  for index = 1, #players do
    local player = players[index]
    local data = player.PlayerData
    local metadata = data.metadata or {}
    -- counted, not collected: only the number was ever read, and a list built for it was a
    -- table per character per tick that nothing looked inside
    local emptied = 0

    for position = 1, #NEEDS do
      local need = NEEDS[position]
      local held = finiteNumber(metadata[need])
      local rule = Config[need]
      if held ~= nil and type(rule) == "table" then
        -- not `next`: that is the global `pairs` is built on, and shadowing it here would
        -- wait for the first person to reach for it in this scope
        local left = math.max(0, held - (tonumber(rule.PER_TICK) or 0))
        if left ~= held then player.Functions.SetMetaData(need, left) end
        if left <= 0 then emptied = emptied + 1 end
      end
    end

    if emptied > 0 and Config.DAMAGE_AT_ZERO > 0 then
      local health = finiteNumber(metadata.health)
      if health ~= nil and health > 0 then
        player.Functions.SetMetaData("health",
          math.max(0, health - Config.DAMAGE_AT_ZERO * emptied))
      end
    end
  end
end

CreateThread(function()
  while true do
    Wait(Config.TICK_SECONDS * 1000)
    -- wrapped: one character with a malformed metadata row must not stop the tick for
    -- everybody else, and this loop never gets a second chance if it raises
    local ok, err = pcall(tick)
    if not ok then log.error("needs tick: " .. tostring(err)) end
  end
end)

log.info(("hunger -%g and thirst -%g every %ds"):format(
  Config.hunger.PER_TICK, Config.thirst.PER_TICK, Config.TICK_SECONDS))
