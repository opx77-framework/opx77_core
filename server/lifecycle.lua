--- The join-time readiness gate: nothing may teleport, spawn, kill or respawn a player until
--- it opens. See README, "The entry gate", for what `GATE_MS` actually bounds.

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
    Open77.log.warn("[lifecycle] this server has no Open77.ready gate: characters still " ..
      "load, but nothing stops another resource placing a player first")
    return
  end
  Open77.ready.participate({
    livenessIntervalMs = Config.ENTRY.GATE_MS,
    reason = "opx77_character_selection",
  })
  Open77.log.info(("[lifecycle] declaring a %d ms liveness interval on the readiness gate")
    :format(Config.ENTRY.GATE_MS))

  -- every joiner also arrives held by `__platform`, which clears only on a client emitting
  -- `open77:session:gameplayReady`
  local function running(name)
    local state = GetResourceState(name)
    return state == "running" or state == "starting"
  end
  if not running("opx77_appearance") and not running("open77_appearance") then
    Open77.log.warn("[lifecycle] no resource here emits `open77:session:gameplayReady`, so " ..
      "the platform's `__platform` hold never clears and `Open77.ready.isReady` stays false")
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
--- running resource as the `detail` of `onPlayerReady`.
---@param source Source
---@param note? string
function Lifecycle.release(source, note)
  if not HAS_GATE then return end
  local session = OPX.Sessions[source]

  local gateSession = session and session.gateSession
  if gateSession == nil then
    -- asked rather than skipped: a hold nobody releases is not on a clock, so it stalls that
    -- player for as long as this resource keeps answering
    local status = Open77.ready.status(source)
    gateSession = status and status.session or nil
  end

  if session then
    session.gateSession = nil
    session.released = true
  end

  Open77.ready.release(source, gateSession, "opx77_core:" .. (note or "done"))
  Open77.log.debug(("[lifecycle] gate released for %d (%s)"):format(source, note or "done"))
end

--- Gives up on a player the core cannot bring in, and closes their session.
---
--- Releasing the gate on its own is not a refusal: it drops the player into Night City with
--- no character, no persistence and no way to get one -- and, because opx77_charselector
--- never sees `onPlayerLoaded`, with a roster it cannot close. The three player-facing
--- strings this is called with were written for a disconnect ("Try reconnecting."); until
--- the platform exposed `Open77.players.disconnect`, there was no way to perform one.
---
--- The gate is released first so that a host which does not clear holds on departure is not
--- left holding one, and the old notify-and-release behaviour is the fallback for a host
--- that predates the call.
---@param source Source
---@param code string  a locale key, and the sentence the player reads
---@param note string  the release note, for the platform log
local function refuseEntry(source, code, note)
  local players = Open77.players
  if type(players) ~= "table" or type(players.disconnect) ~= "function" then
    OPX.Refuse(source, code, OPX.Operations.ENTRY)
    Lifecycle.release(source, note)
    return
  end
  Lifecycle.release(source, note)
  -- the reason is shown on the player's own screen and delivered to onPlayerDisconnected,
  -- so the departure explains itself in the audit line without any extra bookkeeping
  local ok, failure = pcall(players.disconnect, source, locale(code))
  if not ok then
    Open77.log.error(("[lifecycle] could not disconnect %d: %s"):format(source, tostring(failure)))
  end
end

--- Everything the core does for a player who has just connected. On its own thread because it
--- reads the database, and every failure path closes the session rather than leaving them held
--- or stranded in the world with no character.
---@param source Source
function Lifecycle.beginEntry(source)
  local session = OPX.EnsureSession(source)
  if not session then
    Open77.log.error(("[lifecycle] no verified identity for %d, refusing entry"):format(source))
    refuseEntry(source, "entry.noIdentity", "no-identity")
    return
  end

  Lifecycle.hold(source, "opx77_character_selection")

  CreateThread(function()
    local sent = OPX.SendCharacters(source)
    if not sent.ok then
      Open77.log.error(("[lifecycle] could not send the character list to %d: %s")
        :format(source, tostring(sent.error)))
      refuseEntry(source, "entry.failed", "roster-failed")
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

      -- pcall: a raise here would leave this player holding the gate for the session
      local ok, timedOut = pcall(function()
        if OPX.Now() < deadline then return false end
        Open77.log.warn(("[lifecycle] %d spent too long choosing a character; closing the " ..
          "session"):format(source))
        refuseEntry(source, "entry.timedOut", "selection-timeout")
        return true
      end)
      if not ok then
        Open77.log.error(("[lifecycle] the selection watch for %d raised: %s")
          :format(source, tostring(timedOut)))
        return
      end
      if timedOut then return end
    end
  end)
end

OPX.Lifecycle = Lifecycle

Lifecycle.participate()
