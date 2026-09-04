--- Every net-event handler the core registers. Nothing here decides anything: each handler
--- validates and calls into server/character.lua or server/player.lua.

local Events = OPX.Events

--- `source` is not populated for a host-fanned event, so the id arrives as an argument and as
--- a string. `onPlayerConnected` carries the id and nothing else: the name this used to print
--- was always nil, because there was never a second argument to read it from.
AddEventHandler(Events.Platform.PLAYER_CONNECTED, function(rawPlayerId)
  local source = tonumber(rawPlayerId)
  if not source or source <= 0 then
    Open77.log.error(("[events] unusable player id %q on connect"):format(tostring(rawPlayerId)))
    return
  end
  local identity = OPX.IdentityOf(source)
  Open77.log.debug(("[events] %s (%s) connected as %d"):format(
    OPX.Logger.safe(identity and identity.name or "?", 64),
    identity and identity.userId or "?", source))
  OPX.Lifecycle.beginEntry(source)
end)

local forgetThrottle -- forward-declared: defined below, used by the handler above it

---@param source Source|string
---@param reason? any  `connection_closed` for a quit or a dropped link, otherwise the text
---        the disconnect was queued with by disconnect, kick or ban
local function departed(source, reason)
  source = tonumber(source)
  if not source then return end

  -- read before OPX.Logout, which is what puts the character down: an audit entry logged
  -- without a source is keyed by citizen id, and afterwards there is no citizen id to name
  local player = OPX.Players[source]
  local session = OPX.Sessions[source]
  local citizenId = player and player.PlayerData and player.PlayerData.citizenId or nil

  OPX.Logger.log({
    event = "session.disconnect",
    severity = "info",
    source = source,
    citizenId = citizenId,
    userId = session and session.userId or nil,
    message = OPX.Logger.safe(reason or "connection_closed", 128),
  })

  OPX.Logout(source)
  OPX.ForgetSession(source)
  forgetThrottle(source, citizenId)
end

--- Best-effort: a departure nobody reports is covered by the `userId` re-check in
--- `OPX.EnsureSession`, and `OPX.Logout` is idempotent.
---
--- This is the departure of an ADMITTED player. A connection refused at the door never
--- reaches here; that is `onPlayerRejected`, which the core deliberately does not listen for.
AddEventHandler("onPlayerDisconnected", function(rawPlayerId, reason)
  departed(rawPlayerId, reason)
end)

--- The gate opened. `liveness_lost:<res>[,<res>...]` means a hold passed its liveness deadline
--- and the platform concluded the holder was gone.
AddEventHandler(Events.Platform.PLAYER_READY, function(rawPlayerId, detail)
  local source = tonumber(rawPlayerId)
  if not source then return end

  if type(detail) == "string" and detail:sub(1, 14) == "liveness_lost:" then
    Open77.log.warn(("[events] the readiness gate for %d opened on lost liveness (%s)")
      :format(source, detail))
    local ours = GetCurrentResourceName()
    for name in detail:sub(15):gmatch("[^,]+") do
      if name == ours then
        Open77.log.warn("[events] that hold was ours: the player may be in the world with " ..
          "no character")
        break
      end
    end
  end
end)

--- Clears everything keyed by a departing source, including the doorway cooldowns below.
---@param source Source
---@param citizenId? CitizenId  the character they were holding, captured before logout
function forgetThrottle(source, citizenId)
  OPX.ForgetCooldowns(source)
  -- the audit dedupe is keyed by source too, and a source is recycled. Entries logged
  -- without a source are keyed by citizen id, which is why it is passed through.
  if OPX.Logger and OPX.Logger.forget then OPX.Logger.forget(source, citizenId) end
end

-- Every handler below checks a cooldown BEFORE its `CreateThread`, on a `.request` key of its
-- own: `OPX.Cooling` records the attempt it allows, so sharing a key makes it refuse itself.

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
  local operation = OPX.Operations.SELECT_CHARACTER
  if type(citizenId) ~= "string" then
    return OPX.Refuse(src, "error.badRequest", operation)
  end
  if OPX.Cooling(src, "select.request", 1000) then
    return OPX.Refuse(src, "error.tooFast", operation)
  end

  CreateThread(function()
    local selected = OPX.SelectCharacter(src, citizenId)
    if not selected.ok then
      -- not on the cooldown's own refusal: that branch is the one an attacker takes, so
      -- logging it turns the limit into a line-per-message writer
      if selected.error ~= "error.tooFast" then
        Open77.log.warn(("[events] %d could not select %s: %s")
          :format(src, OPX.Logger.safe(citizenId), tostring(selected.error)))
      end
      OPX.Refuse(src, selected.error, operation)
      OPX.NotifyLocale(src, selected.error, nil, "error")
    end
  end)
end)

RegisterNetEvent(Events.Server.CREATE_CHARACTER, function(payload)
  local src = tonumber(source)
  if not src then return end

  local operation = OPX.Operations.CREATE_CHARACTER
  if OPX.Cooling(src, "create.request", 1000) then
    return OPX.Refuse(src, "error.tooFast", operation)
  end

  CreateThread(function()
    local created = OPX.CreateCharacter(src, payload)
    if not created.ok then
      OPX.Refuse(src, created.error, operation)
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
  local operation = OPX.Operations.DELETE_CHARACTER
  if type(citizenId) ~= "string" then
    return OPX.Refuse(src, "error.badRequest", operation)
  end
  if OPX.Cooling(src, "delete.request", 1000) then
    return OPX.Refuse(src, "error.tooFast", operation)
  end

  CreateThread(function()
    local deleted = OPX.DeleteCharacter(src, citizenId)
    if not deleted.ok then
      OPX.Refuse(src, deleted.error, operation)
      return
    end
    OPX.NotifyLocale(src, "character.deleted", nil, "success")
    OPX.SendCharacters(src)
  end)
end)

--- A position report is a hint. Only the heading is kept: x, y and z are re-derived from the
--- server snapshot at save time, so a client that lies about them lies to nobody.
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
