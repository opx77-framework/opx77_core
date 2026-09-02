--- The two background jobs: keeping positions fresh, and paying people.

-- sampled this often because by the time a disconnect handler runs the session is usually
-- gone and Open77.players.position answers nil
local SAMPLE_MS = 1000

--- Metres. Not zero: a standing player's position wobbles by centimetres as the animation
--- settles, and zero would make every idle character a moving one.
local MOVED_METRES = 1.0

--- citizenId -> the position and revision at the last successful write.
local lastWritten = {}

--- True when the row would come out different. Two questions, because position sits outside
--- the revision count: a 1 Hz sample routed through a mutator would dirty everyone every tick.
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

--- Records what was written.
---@param player Player
---@param revision integer the number the character was at when the statement was built, not
---        the one it holds when the write comes back
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
    Open77.log.debug(("[loops] autosave wrote %d of %d character(s)")
      :format(written, #players))
  end
end

--- The money type a salary lands in. Resolved once, so a name that is not a money type is
--- warned about at boot rather than once per cycle.
local PAYCHECK_TYPE = OPX.Config.SERVER.MONEY.PAYCHECK_TYPE
if not OPX.IsMoneyType(PAYCHECK_TYPE) then
  Open77.log.warn(("[loops] MONEY.PAYCHECK_TYPE %s is not a money type; paying into %s")
    :format(tostring(PAYCHECK_TYPE), OPX.Config.SHARED.MONEY.DEFAULT))
  PAYCHECK_TYPE = OPX.Config.SHARED.MONEY.DEFAULT
end

--- Pays everyone their job's grade payment, into the configured paycheck money type.
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
        if OPX.AddMoney(player, PAYCHECK_TYPE, payment, "paycheck:" .. job.name) then
          OPX.NotifyLocale(player.PlayerData.source, "money.paycheck",
            { amount = payment, type = PAYCHECK_TYPE, job = job.label }, "success")
          TriggerEvent(OPX.Events.Internal.PAYCHECK,
            player.PlayerData.source, payment, job.name)
        end
      end
    end
  end
end

--- Forgets the write-tracking for characters nobody is playing.
local function prune()
  for citizenId in pairs(lastWritten) do
    if not OPX.PlayerRegistry.byCitizenId[citizenId] then
      lastWritten[citizenId] = nil
    end
  end
end

local nextSaveAt, nextPaycheckAt, nextPruneAt

--- One pass of the background loop. Every job is wrapped on its own, so one failing job does
--- not skip the others, and the whole pass is wrapped again by its caller.
local function tick()
  -- deliberately `pairs(OPX.Players)` and not `OPX.GetPlayers()`: that walk evicts, and an
  -- eviction here would put a database write inside a 1 Hz loop
  local sampled, sampleError = pcall(function()
    for _, player in pairs(OPX.Players) do
      OPX.SamplePosition(player)
    end
  end)
  if not sampled then
    Open77.log.error("[loops] position sampling raised: " .. tostring(sampleError))
  end

  local now = OPX.Now()

  if now >= nextSaveAt then
    -- re-read every interval: a live tunable captured in a local freezes at load
    nextSaveAt = now + OPX.TuneNumber("AUTOSAVE_SECONDS", 30) * 1000
    local ok, err = pcall(autosave)
    if not ok then Open77.log.error("[loops] autosave raised: " .. tostring(err)) end
  end

  local paycheckMinutes = OPX.TuneNumber("PAYCHECK_MINUTES", 0)
  if paycheckMinutes > 0 and now >= nextPaycheckAt then
    nextPaycheckAt = now + paycheckMinutes * 60000
    local ok, err = pcall(paycheck)
    if not ok then Open77.log.error("[loops] paycheck raised: " .. tostring(err)) end
  end

  if now >= nextPruneAt then
    nextPruneAt = now + 300000
    prune()
  end
end

CreateThread(function()
  nextSaveAt = OPX.Now() + OPX.TuneNumber("AUTOSAVE_SECONDS", 30) * 1000
  nextPaycheckAt = OPX.Now() + math.max(OPX.TuneNumber("PAYCHECK_MINUTES", 0), 1) * 60000
  nextPruneAt = OPX.Now() + 300000

  while true do
    Wait(SAMPLE_MS)

    if not OPX.BootError then
      -- the whole pass, not only its jobs: `OPX.Now` and `OPX.TuneNumber` are host reads too,
      -- and a raise from one of them would end autosaving for the session
      local ok, err = pcall(tick)
      if not ok then Open77.log.error("[loops] the background pass raised: " .. tostring(err)) end
    end
  end
end)

--- A stop is the last chance to write anything. One thread per character, not one loop: a
--- single loop would dispatch the first UPDATE, suspend, and never be resumed.
AddEventHandler("onResourceStop", function(name)
  if name ~= GetCurrentResourceName() then return end
  local players = OPX.GetPlayers()

  for i = 1, #players do
    local player = players[i]
    CreateThread(function() OPX.Save(player, false) end)
  end

  Open77.log.info(("[loops] stopping: dispatched a save for %d character(s), best effort")
    :format(#players))
end)
