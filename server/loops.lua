--- The two background jobs: keeping positions fresh, and paying people.

local log = OPX.Log.scope("loops")

-- sampled this often because by the time a disconnect handler runs the session is usually
-- gone and Open77.players.position answers nil
local SAMPLE_MS = 1000

--- Metres. Not zero: a standing player's position wobbles by centimetres as the animation
--- settles, and zero would make every idle character a moving one.
local MOVED_METRES = 1.0

--- citizenId -> the position and revision at the last successful write, so "has this changed"
--- is answered against the database rather than against the previous sample.
local lastWritten = {}

--- True when the row would come out different. Two questions, because "has not moved" is not
--- "has not changed": position is outside the revision count, since routing a 1 Hz sample
--- through a mutator would mark every player dirty on every tick.
---@param player Player
---@return boolean
local function needsWriting(player)
  local mark = lastWritten[player.PlayerData.citizenId]
  if not mark then return true end
  if player.Revision ~= mark.revision then return true end

  local current = player.PlayerData.position
  if not current then return false end
  if not mark.position then return true end
  return OPX.Math.distanceSquared(current, mark.position) >= MOVED_METRES * MOVED_METRES
end

--- `revision` is passed in rather than read here: it must be the number the character was at
--- when the statement was built, not the one it holds when the write comes back.
---@param player Player
---@param revision integer
local function remember(player, revision)
  local position = player.PlayerData.position
  lastWritten[player.PlayerData.citizenId] = {
    revision = revision,
    position = position and { x = position.x, y = position.y, z = position.z } or nil,
  }
end

--- Writes every loaded character whose row would come out different. A logout still saves
--- unconditionally.
local function autosave()
  local players = OPX.GetPlayers()
  local written = 0

  for i = 1, #players do
    local player = players[i]
    if needsWriting(player) then
      -- read BEFORE the write: Save yields, and a payment landing then would be marked written
      local revision = player.Revision
      local saved = OPX.Save(player, false)
      if saved.ok then
        remember(player, revision)
        written = written + 1
      end
    end
  end

  if written > 0 then
    log.debug(("autosave wrote %d of %d character(s)"):format(written, #players))
  end
end

--- Pays everyone their job's grade payment, into BANK rather than EDDIES: a salary that lands
--- as carried cash can be taken off the body of whoever logged in at the wrong moment.
local function paycheck()
  local players = OPX.GetPlayers()
  local requireDuty = OPX.Tune.PAYCHECK_REQUIRES_DUTY

  for i = 1, #players do
    local player = players[i]
    local job = player.PlayerData.job
    local definition = OPX.GetJob(job.name)
    local payment = math.floor(job.payment or 0)

    -- offDutyPay is the job's own override, and the server-wide switch does not overrule it
    local eligible = payment > 0
      and (not requireDuty or job.onDuty or (definition and definition.offDutyPay))

    if eligible then
      if OPX.Hooks.trigger("paycheck:before", { player = player, amount = payment }) then
        if OPX.AddMoney(player, "BANK", payment, "paycheck:" .. job.name) then
          OPX.NotifyLocale(player.PlayerData.source, "money.paycheck",
            { amount = payment, job = job.label }, "success")
          TriggerEvent(OPX.Events.Internal.PAYCHECK,
            player.PlayerData.source, payment, job.name)
        end
      end
    end
  end
end

--- Forgets the write-tracking for characters nobody is playing: without it `lastWritten`
--- grows by one entry per character ever loaded.
local function prune()
  for citizenId in pairs(lastWritten) do
    if not OPX.PlayerRegistry.byCitizenId[citizenId] then
      lastWritten[citizenId] = nil
    end
  end
end

CreateThread(function()
  local nextSaveAt = OPX.Now() + OPX.TuneNumber("AUTOSAVE_SECONDS", 30) * 1000
  local nextPaycheckAt = OPX.Now() + math.max(OPX.TuneNumber("PAYCHECK_MINUTES", 0), 1) * 60000
  local nextPruneAt = OPX.Now() + 300000

  while true do
    Wait(SAMPLE_MS)

    if not OPX.BootError then
      -- deliberately `pairs(OPX.Players)` and not `OPX.GetPlayers()`: that walk evicts, and
      -- an eviction here would put a database write inside a 1 Hz loop. Nothing is lost by
      -- not evicting, because `OPX.SamplePosition` re-checks that the slot still belongs to
      -- this character before it reads a coordinate.
      for _, player in pairs(OPX.Players) do
        OPX.SamplePosition(player)
      end

      local now = OPX.Now()

      if now >= nextSaveAt then
        -- re-read every interval: a live tunable captured in a local freezes at load
        nextSaveAt = now + OPX.TuneNumber("AUTOSAVE_SECONDS", 30) * 1000
        local ok, err = pcall(autosave)
        if not ok then log.error("autosave raised: " .. tostring(err)) end
      end

      local paycheckMinutes = OPX.TuneNumber("PAYCHECK_MINUTES", 0)
      if paycheckMinutes > 0 and now >= nextPaycheckAt then
        nextPaycheckAt = now + paycheckMinutes * 60000
        local ok, err = pcall(paycheck)
        if not ok then log.error("paycheck raised: " .. tostring(err)) end
      end

      if now >= nextPruneAt then
        nextPruneAt = now + 300000
        prune()
      end
    end
  end
end)

--- A stop is the last chance to write anything, and it is worth about a tick. One thread per
--- character, not one loop: `OPX.Save` yields inside the await, and a single loop would
--- dispatch the first player's UPDATE, suspend, and never be resumed. What is logged is what
--- was dispatched, not what committed. AUTOSAVE_SECONDS is the number that actually bounds
--- what anybody can lose.
AddEventHandler("onResourceStop", function(name)
  if name ~= GetCurrentResourceName() then return end
  local players = OPX.GetPlayers()

  for i = 1, #players do
    local player = players[i]
    CreateThread(function() OPX.Save(player, false) end)
  end

  log.info(("stopping: dispatched a save for %d character(s), best effort")
    :format(#players))
end)
