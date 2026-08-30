--- Server entry point. Load order is the contract: shared table, kernel, then
--- every module file (each calls `Synk.module` at file scope), then boot.
--- A module not required below simply does not exist.

require("shared.init")

local Kernel = require("server.kernel.init")
local Result = require("shared.result")
local Validate = require("shared.validate")
local Events = require("shared.events")
local Log = require("shared.log")

-- `Synk.module` has to exist before a module file runs.
Synk.module = Kernel.module

-- ── Modules ───────────────────────────────────────────────────────────────
-- Add one line per module. Order is irrelevant: the kernel sorts by `requires`.
require("server.modules.characters.init")

local log = Log.scope("main")

--- `source` comes from the authenticated connection and is the only field in
--- a network handler a client cannot forge.
local function sessionOf()
  local playerId = tonumber(source)
  if not playerId then return Result.err("no-source") end
  return Kernel.sessions:get(playerId)
end

--- A refusal the client can show, without leaking detail.
local function refuse(playerId, code)
  TriggerClientEvent(Events.toClient.notify, playerId, { kind = "error", code = code })
end

RegisterNetEvent(Events.toServer.selectCharacter, function(payload)
  local session = sessionOf()
  if not session.ok then return end
  local playerId = session.value.playerId

  local characterId = Validate.number(payload and payload.characterId,
    { integer = true, min = 1 })
  if not characterId.ok then return refuse(playerId, "bad-request") end

  local characters = Kernel.registry:get("characters")
  if not characters then return refuse(playerId, "unavailable") end

  local claimed = characters.claim(session.value, characterId.value)
  if not claimed.ok then
    log.warn(("%d could not claim character %d: %s")
      :format(playerId, characterId.value, tostring(claimed.error)))
    return refuse(playerId, claimed.error)
  end

  TriggerClientEvent(Events.toClient.entered, playerId, { characterId = claimed.value })
end)

RegisterNetEvent(Events.toServer.createCharacter, function(payload)
  local session = sessionOf()
  if not session.ok then return end
  local playerId = session.value.playerId

  local characters = Kernel.registry:get("characters")
  if not characters then return refuse(playerId, "unavailable") end

  local created = characters.create(session.value.userId,
    payload and payload.firstName, payload and payload.lastName)
  if not created.ok then
    return refuse(playerId, created.error)
  end

  local claimed = characters.claim(session.value, created.value.id)
  if not claimed.ok then return refuse(playerId, claimed.error) end

  TriggerClientEvent(Events.toClient.entered, playerId, {
    characterId = created.value.id,
    publicCode = created.value.publicCode,
  })
end)

--- Diagnostics: the fastest way to answer "why is this player stuck".
RegisterCommand("synk.where", function(commandSource, args)
  local target = tonumber(args and args[1]) or tonumber(commandSource)
  if not target then return print("usage: synk.where <playerId>") end

  local session = Kernel.sessions:get(target)
  if not session.ok then
    return print(("player %d: no session (%s)"):format(target, tostring(session.error)))
  end
  print(("player %d: user=%s character=%s")
    :format(target, session.value.userId, tostring(session.value.characterId)))
end, true)

RegisterCommand("synk.status", function()
  local live = Kernel.sessions:all()
  print(("SYNK %s — %d session(s)"):format(Synk.VERSION, #live))
  for i = 1, #live do
    local session = live[i]
    print(("  %d  %s  character=%s")
      :format(session.playerId, session.userId, tostring(session.characterId)))
  end
end, true)

CreateThread(function()
  -- On a thread: migrations block on database round-trips and the main chunk
  -- must return promptly.
  local booted = Kernel.boot({ logLevel = "info" })
  if not booted.ok then
    log.error(("SYNK did not start: %s"):format(tostring(booted.error)))
  end
end)
