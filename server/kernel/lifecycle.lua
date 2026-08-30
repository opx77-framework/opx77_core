--- Player arrival: the readiness gate and the entry pipeline.
---
--- The platform rule is explicit: do not teleport, spawn, kill or respawn a
--- player until their gate has opened. SYNK declares participation once, which
--- holds everyone who connects afterwards, runs its entry steps, then releases.
---
--- Our own deadline sits below the gate's so we give up first and can say why.
--- A gate that opens on timeout may leave the player in a modal with no puppet
--- at all, which is why anything placing a player must check life state.

local Result = require("shared.result")
local Log = require("shared.log")
local Events = require("shared.events")

local Lifecycle = {}
Lifecycle.__index = Lifecycle

local log = Log.scope("lifecycle")

local function readyApi()
  local ns = rawget(_G, "Open77")
  return ns and ns.ready or nil
end

local function userIdOf(playerId)
  local ns = rawget(_G, "Open77")
  if ns and ns.players and ns.players.identifier then
    return ns.players.identifier(playerId)
  end
  local alias = rawget(_G, "GetPlayerIdentifier")
  return alias and alias(playerId) or nil
end

function Lifecycle.new(opts)
  opts = opts or {}
  return setmetatable({
    sessions = opts.sessions,
    steps = {},
    heldSessions = {},
    gateMs = opts.gateMs or 60000,
    pipelineMs = opts.pipelineMs or 45000,
  }, Lifecycle)
end

--- Steps run in registration order, which is module boot order, so a step can
--- rely on everything its module required. `fn(session)` returns a Result.
function Lifecycle:addEntryStep(name, fn)
  self.steps[#self.steps + 1] = { name = name, fn = fn }
end

--- Declared once, at boot.
function Lifecycle:participate()
  local ready = readyApi()
  if not (ready and ready.participate) then
    log.warn("Open77.ready is unavailable; entry runs without a gate")
    return Result.err("no-gate")
  end
  ready.participate({ timeoutMs = self.gateMs, reason = "synk_entry" })
  log.info(("participating in the readiness gate (%d ms)"):format(self.gateMs))
  return Result.ok(true)
end

--- Idempotent: the gate may already have opened on a timeout.
function Lifecycle:release(playerId, note)
  local ready = readyApi()
  if not (ready and ready.release) then return end

  local gateSession = self.heldSessions[playerId]
  if gateSession == nil and ready.status then
    local status = ready.status(playerId)
    gateSession = status and status.session or nil
  end

  self.heldSessions[playerId] = nil
  ready.release(playerId, gateSession, note)
  log.debug(("gate released for %d (%s)"):format(playerId, note or "done"))
end

--- Runs the whole entry sequence for one player.
function Lifecycle:runEntry(playerId, displayName)
  local opened = self.sessions:open(playerId, userIdOf(playerId), displayName)
  if not opened.ok then
    --- No verified identity means no account to load, and letting them in
    --- anonymous would create an unowned character.
    log.error(("no identity for %d, refusing entry"):format(playerId))
    self:release(playerId, "no-identity")
    return opened
  end

  local ready = readyApi()
  if ready and ready.hold then
    self.heldSessions[playerId] = ready.hold(playerId, "synk_entry")
  end

  local session = opened.value
  local deadline = self.sessions:now() + self.pipelineMs

  local steps = self.steps
  for i = 1, #steps do
    local step = steps[i]
    if self.sessions:now() > deadline then
      log.error(("entry timed out at step %q for %d"):format(step.name, playerId))
      self:release(playerId, "pipeline-timeout")
      return Result.err("timeout", step.name)
    end

    local ok, outcome = pcall(step.fn, session)
    if not ok then
      log.error(("entry step %q raised for %d: %s"):format(step.name, playerId, tostring(outcome)))
      self:release(playerId, "step-error")
      return Result.err("step-failed", step.name)
    end
    if Result.is(outcome) and not outcome.ok then
      log.warn(("entry step %q refused %d: %s"):format(step.name, playerId, tostring(outcome.error)))
      self:release(playerId, "step-refused")
      return outcome
    end
  end

  self:release(playerId, "entry-complete")
  TriggerEvent(Events.internal.sessionOpened, session)
  return Result.ok(session)
end

--- Wired after modules boot, so every step is registered before the first
--- player can connect.
function Lifecycle:listen()
  AddEventHandler(Events.platform.playerConnected, function(rawPlayerId, playerName)
    local playerId = tonumber(rawPlayerId)
    if not playerId then
      log.error(("unusable player id %q on connect"):format(tostring(rawPlayerId)))
      return
    end

    CreateThread(function()
      local entered = self:runEntry(playerId, playerName)
      if not entered.ok then
        log.warn(("entry failed for %d: %s"):format(playerId, tostring(entered.error)))
      end
    end)
  end)

  AddEventHandler(Events.platform.playerReady, function(rawPlayerId, detail)
    local playerId = tonumber(rawPlayerId)
    if not playerId then return end
    if type(detail) == "string" and detail:sub(1, 8) == "timeout:" then
      log.warn(("gate opened on timeout for %d (%s); player may have no puppet")
        :format(playerId, detail))
    end
    TriggerEvent(Events.internal.characterLoaded, playerId, detail)
  end)
end

return Lifecycle
