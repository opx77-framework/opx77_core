--- The join-time readiness gate: nothing may teleport, spawn, kill or respawn a player until
--- it opens.
---
--- `GATE_MS` is NOT a budget for the player. It is the liveness interval the host watches this
--- resource on, clamped by the host to [1000, 600000] ms, and `hold` is what refreshes it. A
--- hold stands indefinitely for as long as it is refreshed -- somebody may spend an hour in a
--- character creator and that is correct -- and is only ever broken by evidence the holder is
--- gone: the resource died, was reloaded away, or the client it was waiting on stopped
--- answering. The gate then opens by itself and the detail reads `liveness_lost:opx77_core`.
---
--- This core takes its hold once per join and never heartbeats, so in practice the interval
--- IS the deadline it has. `SELECTION_MS` -- the core's own limit on the selection screen --
--- is therefore capped below `GATE_MS` in server/tunables.lua, so the core always gives up
--- first and can say why rather than being declared dead with the player holding no puppet.

local log = OPX.Log.scope("lifecycle")
local Config = OPX.Config.SERVER

local Lifecycle = {}

local HAS_GATE = type(Open77.ready) == "table"
  and type(Open77.ready.participate) == "function"
  and type(Open77.ready.hold) == "function"
  and type(Open77.ready.release) == "function"
  and type(Open77.ready.status) == "function"

--- Declared once, at load, so every later connection arrives with a hold in our name.
function Lifecycle.participate()
  if not HAS_GATE then
    log.warn("this server has no Open77.ready gate")
    log.warn("  characters will still load, but nothing stops another resource from")
    log.warn("  placing a player before the core has chosen where they belong.")
    return
  end
  Open77.ready.participate({
    livenessIntervalMs = Config.ENTRY.GATE_MS,
    reason = "opx77_character_selection",
  })
  log.info(("declaring a %d ms liveness interval on the readiness gate")
    :format(Config.ENTRY.GATE_MS))

  -- Every joiner also arrives held by `__platform`, a hold no Lua may take or release and
  -- which has no deadline at all. It clears on one thing only: the client announcing
  -- `open77:session:gameplayReady`, which an appearance resource emits once it has seen that
  -- the local puppet is attached, alive and past the "press any key to continue" screen.
  -- Nothing on this server emits it, so on this build the gate never opens for anybody:
  -- `Open77.ready.isReady` stays false forever and `onPlayerReady` never fires. Said out loud
  -- because it is otherwise undiagnosable -- the core still loads and places characters, since
  -- it neither reads `isReady` nor waits on that event, but anything that does will hang.
  local appearance = GetResourceState("open77_appearance")
  if appearance ~= "running" and appearance ~= "starting" then
    log.warn("no resource here emits `open77:session:gameplayReady`")
    log.warn("  so the platform's own `__platform` hold never clears: the readiness gate")
    log.warn("  never opens, `Open77.ready.isReady` is permanently false and the")
    log.warn("  `onPlayerReady` handler in server/events.lua can never fire. The core is")
    log.warn("  unaffected -- it reads neither -- but do not build on either of them. Once")
    log.warn("  our own hold is released the host starts warning: one WRN naming __platform")
    log.warn("  per connected player, every 60 seconds, for the whole session.")
  end
end

--- Takes the hold for one player and remembers the session number, which is what keeps a
--- release honest: releasing by a recycled id alone could clear somebody else's hold.
---@param source Source
---@param reason? string
function Lifecycle.hold(source, reason)
  if not HAS_GATE then return end
  local session = OPX.Sessions[source]
  if not session then return end

  local gateSession = Open77.ready.hold(source, reason or "opx77_character_selection")
  if gateSession ~= nil then
    session.gateSession = gateSession
    session.heldAt = OPX.Now()
  end
end

--- Releases it. Idempotent, and safe for a player who never had one. The note reaches every
--- running resource as the `detail` of `onPlayerReady`, which is the one channel this core
--- has for telling another resource what happened.
---@param source Source
---@param note? string
function Lifecycle.release(source, note)
  if not HAS_GATE then return end
  local session = OPX.Sessions[source]

  local gateSession = session and session.gateSession
  if gateSession == nil then
    -- ask the host rather than skip: a hold nobody releases is not on a clock, so it stalls
    -- that player until the host decides this resource has stopped answering -- which, on a
    -- core that is still running, is never
    local status = Open77.ready.status(source)
    gateSession = status and status.session or nil
  end

  if session then
    session.gateSession = nil
    session.released = true
  end

  Open77.ready.release(source, gateSession, "opx77_core:" .. (note or "done"))
  log.debug(("gate released for %d (%s)"):format(source, note or "done"))
end

--- Everything the core does for a player who has just connected. On its own thread because it
--- reads the database, and every failure path releases the gate rather than leaving them held.
---@param source Source
function Lifecycle.beginEntry(source)
  local session = OPX.EnsureSession(source)
  if not session then
    log.error(("no verified identity for %d, refusing entry"):format(source))
    Lifecycle.release(source, "no-identity")
    return
  end

  Lifecycle.hold(source, "opx77_character_selection")

  CreateThread(function()
    local sent = OPX.SendCharacters(source)
    if not sent.ok then
      log.error(("could not send the character list to %d: %s")
        :format(source, tostring(sent.error)))
      OPX.Refuse(source, "entry.failed")
      Lifecycle.release(source, "roster-failed")
      return
    end
    Lifecycle.watch(source)
  end)
end

--- Gives up on a player who never chooses. One thread per joining player against a 1 024
--- budget, so it exits the moment the gate is released or the slot changes hands.
---@param source Source
function Lifecycle.watch(source)
  local session = OPX.Sessions[source]
  if not session then return end
  local userId = session.userId
  local deadline = OPX.Now() + OPX.TuneNumber("SELECTION_MS", 30000)

  CreateThread(function()
    while true do
      Wait(1000)

      local live = OPX.Sessions[source]
      if not live or live.userId ~= userId or live.released then return end
      if live.citizenId then return end

      if OPX.Now() >= deadline then
        log.warn(("%d spent too long choosing a character; releasing the gate")
          :format(source))
        OPX.Refuse(source, "entry.timedOut")
        Lifecycle.release(source, "selection-timeout")
        return
      end
    end
  end)
end

OPX.Lifecycle = Lifecycle

Lifecycle.participate()
