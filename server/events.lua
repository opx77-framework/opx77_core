--- Every handler the core registers, and the trust boundary: `source` is the only value a
--- client cannot forge, and nothing here decides anything -- each handler validates and calls
--- into server/character.lua or server/player.lua, so every doorway obeys the same rules.

local log = OPX.Log.scope("events")
local Events = OPX.Events

--- `source` is not populated here -- only in handlers reached by a network event -- so the id
--- arrives as an argument, and as a string.
AddEventHandler(Events.Platform.PLAYER_CONNECTED, function(rawPlayerId, playerName)
  local source = tonumber(rawPlayerId)
  if not source or source <= 0 then
    log.error(("unusable player id %q on connect"):format(tostring(rawPlayerId)))
    return
  end
  log.debug(("%s connected as %d"):format(tostring(playerName), source))
  OPX.Lifecycle.beginEntry(source)
end)

--- Both departure events are wired and both are best-effort: either may be the one that
--- fires. Logout is idempotent, and a departure nobody reports is covered by the userId
--- re-check in `OPX.EnsureSession`.
local forgetThrottle -- forward-declared: defined below, used by the handler above it

local function departed(source)
  source = tonumber(source)
  if not source then return end
  OPX.Logout(source)
  OPX.ForgetSession(source)
  forgetThrottle(source)
end

--- `onPlayerDisconnected` is the only departure event this platform raises, and the net under
--- it stays the `userId` re-check in `OPX.EnsureSession`: a missed departure has to become a
--- non-event rather than an unknown inheriting a session.
---
--- There used to be a second handler on `playerDropped` here, on the reading that the platform
--- raises both and documents neither. It does not. That name occurs in the shipped server
--- binary only inside the platform's own embedded Lua bootstrap, which registers a handler for
--- it that no assembly ever fires. Five official resources listen for it too, and are equally
--- covered only by `onPlayerDisconnected`. The handler also read the bare global `source`,
--- which is populated for network events and never for a host-fanned one, so its fallback
--- could only ever have been nil.
AddEventHandler("onPlayerDisconnected", function(rawPlayerId)
  departed(rawPlayerId)
end)

--- The gate opened. `liveness_lost:<res>[,<res>...]` means a hold passed its liveness deadline
--- and the platform concluded the holder was gone; if the list names this core, a player is in
--- the world without the core deciding where. The other details the platform sends are
--- `cleared`, `incarnated`, `resource_stopped`, `resource_reloaded`, or the sanitised `note` a
--- resource passed to `release`.
AddEventHandler(Events.Platform.PLAYER_READY, function(rawPlayerId, detail)
  local source = tonumber(rawPlayerId)
  if not source then return end

  if type(detail) == "string" and detail:sub(1, 14) == "liveness_lost:" then
    log.warn(("the readiness gate for %d opened on lost liveness (%s)"):format(source, detail))
    local ours = GetCurrentResourceName()
    for name in detail:sub(15):gmatch("[^,]+") do
      if name == ours then
        log.warn("  that hold was ours: the player may be in the world with no character.")
        break
      end
    end
  end
end)

--- Clears everything keyed by a departing source, including the doorway cooldowns below.
---@param source Source
function forgetThrottle(source)
  OPX.ForgetCooldowns(source)
  -- the audit dedupe is keyed by source too, and a source is recycled
  if OPX.Logger and OPX.Logger.forget then OPX.Logger.forget(source) end
end


-- Every handler below that answers on its own thread checks a cooldown BEFORE the
-- `CreateThread`, the order `server/vehicles.lua` already uses. A modified client can send one
-- of these thirty-two times a second, and a thread spawned per message spends the host's 1 024
-- task budget -- shared with the autosave and with every login -- before any of the validation
-- inside the thread gets a say.
--
-- The keys end in `.request` on purpose. The operations keep their own cooldowns in
-- server/character.lua, because each is also reachable from an unrestricted `/opx77.*`
-- command; `OPX.Cooling` RECORDS the attempt it allows, so a doorway checking the operation's
-- own key would consume that window and the operation would then refuse itself. These windows
-- bound how often a thread is created and nothing else -- the write is still guarded where it
-- is done.

--- The client announcing itself, which is what refills the roster after a reload:
--- `onPlayerConnected` does not re-fire for players who are already here.
RegisterNetEvent(Events.Server.READY, function()
  local src = tonumber(source)
  if not src then return end
  if OPX.Cooling(src, "ready", 2000) then return end

  local session = OPX.EnsureSession(src)
  if not session then return end

  -- already loaded means re-syncing: the roster would re-open the selection screen
  local player = OPX.GetPlayer(src)
  if player then
    TriggerClientEvent(Events.Client.PLAYER_LOADED, src, player.PlayerData)
    return
  end

  CreateThread(function() OPX.SendCharacters(src) end)
end)

RegisterNetEvent(Events.Server.SELECT_CHARACTER, function(payload)
  local src = tonumber(source)
  if not src then return end

  local citizenId = type(payload) == "table" and payload.citizenId or nil
  if type(citizenId) ~= "string" then return OPX.Refuse(src, "error.badRequest") end
  if OPX.Cooling(src, "select.request", 1000) then
    return OPX.Refuse(src, "error.tooFast")
  end

  CreateThread(function()
    local selected = OPX.SelectCharacter(src, citizenId)
    if not selected.ok then
      -- not on the cooldown's own refusal: that branch is the one an attacker takes, so
      -- logging it turns the limit into a line-per-message writer
      if selected.error ~= "error.tooFast" then
        log.warn(("%d could not select %s: %s"):format(src, OPX.Logger.safe(citizenId),
          tostring(selected.error)))
      end
      OPX.Refuse(src, selected.error)
      OPX.NotifyLocale(src, selected.error, nil, "error")
    end
  end)
end)

RegisterNetEvent(Events.Server.CREATE_CHARACTER, function(payload)
  local src = tonumber(source)
  if not src then return end

  -- the one doorway that had no guard at all, and the most expensive to leave open: the
  -- thread it spawns runs UTF-8 length work over names that came straight off the wire.
  -- A second is short enough that a player fixing a mistyped name is never refused, which
  -- is the reason `OPX.CreateCharacter` cools its own write only AFTER validation.
  if OPX.Cooling(src, "create.request", 1000) then
    return OPX.Refuse(src, "error.tooFast")
  end

  CreateThread(function()
    local created = OPX.CreateCharacter(src, payload)
    if not created.ok then
      OPX.Refuse(src, created.error)
      OPX.NotifyLocale(src, created.error,
        { max = OPX.TuneNumber("CHARACTER_SLOTS", 1) }, "error")
      return
    end

    OPX.NotifyLocale(src, "character.created",
      { citizenId = created.value.citizenId }, "success")

    OPX.SendCharacters(src)
  end)
end)

RegisterNetEvent(Events.Server.DELETE_CHARACTER, function(payload)
  local src = tonumber(source)
  if not src then return end

  local citizenId = type(payload) == "table" and payload.citizenId or nil
  if type(citizenId) ~= "string" then return OPX.Refuse(src, "error.badRequest") end
  if OPX.Cooling(src, "delete.request", 1000) then
    return OPX.Refuse(src, "error.tooFast")
  end

  CreateThread(function()
    local deleted = OPX.DeleteCharacter(src, citizenId)
    if not deleted.ok then
      OPX.Refuse(src, deleted.error)
      return
    end
    OPX.NotifyLocale(src, "character.deleted", nil, "success")
    OPX.SendCharacters(src)
  end)
end)

--- A position report is a hint. Only the heading is kept, because the server snapshot carries
--- none; x, y and z are re-derived at save time, so a client that lies about them lies to
--- nobody.
RegisterNetEvent(Events.Server.REPORT_POSITION, function(payload)
  local src = tonumber(source)
  if not src then return end

  -- literal, not CLIENT.POSITION_REPORT_MS: this VM never loads config/client.lua
  if OPX.Cooling(src, "heading", 1000) then return end

  local player = OPX.GetPlayer(src)
  if not player then return end

  local heading = OPX.Validate.number(
    type(payload) == "table" and payload.heading or nil, { min = -360, max = 360 })
  if heading.ok then player.PlayerData.reportedHeading = heading.value end
end)
