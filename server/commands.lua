--- Commands. The third argument to `RegisterCommand` is `restricted`, which gates it on the
--- ACL permission `command.<name>`; the unrestricted ones are the handful a player runs on
--- their own character.

local Config = OPX.Config.SERVER

--- Console runs as source 0, which is not a player and has no character.
---@param source Source
---@param raw string
---@return Player|nil
local function requirePlayer(source, raw)
  local player = OPX.GetPlayer(source)
  if not player then
    OPX.CommandResult(source, raw, false, locale("error.notLoggedIn"))
    return nil
  end
  return player
end

--- Resolves a command argument that may be a player id or a citizen id.
---@param argument string|nil nil falls back to the caller
---@param fallbackSource Source
---@return Player|nil
local function targetOf(argument, fallbackSource)
  if argument == nil then return OPX.GetPlayer(fallbackSource) end
  local asId = tonumber(argument)
  if asId then return OPX.GetPlayer(asId) end
  return OPX.GetPlayerByCitizenId(tostring(argument):upper())
end

RegisterCommand("opx77", function(source, _, raw)
  local players = OPX.GetPlayers()
  local lines = {
    ("opx77_core %s -- %d character(s) in the world, %d session(s) connected")
      :format(OPX.VERSION, #players, OPX.Table.count(OPX.Sessions)),
  }
  if OPX.BootError then
    lines[#lines + 1] = ("  DEGRADED: %s"):format(OPX.BootError)
  end
  for i = 1, #players do
    local data = players[i].PlayerData
    lines[#lines + 1] = ("  %-4d %-10s %s %s  %s")
      :format(data.source, data.citizenId,
        data.charInfo.firstName or "?", data.charInfo.lastName or "?",
        data.job.label or "?")
  end
  OPX.CommandResult(source, raw, true, table.concat(lines, "\n"))
end, true)

--- One player's whole situation in one answer, all of it what the SERVER believes: a report
--- agreeing with the client would be useless for diagnosing a disagreement between them.
RegisterCommand("opx77.where", function(source, args, raw)
  local target = tonumber(args[1]) or source
  local session = OPX.Sessions[target]
  if not session then
    return OPX.CommandResult(source, raw, false, ("player %s has no session"):format(target))
  end

  local player = OPX.GetPlayer(target)
  local position = Open77.players.position(target)
  local life = Open77.players.getLifeState(target)

  local lines = {
    ("player %d  user=%s  name=%s"):format(target, tostring(session.userId), session.displayName),
    ("  character : %s"):format(player and player.PlayerData.citizenId or "none loaded"),
    ("  gate      : %s"):format(session.gateSession and "held" or "released"),
    ("  life      : %s"):format(life and life.phase or "unreadable"),
    ("  position  : %s"):format(position
      and ("%.1f %.1f %.1f  bucket=%d"):format(position.x, position.y, position.z,
        position.bucket or 0)
      or "unreadable"),
  }
  if player then
    local data = player.PlayerData
    lines[#lines + 1] = ("  job       : %s %s")
      :format(data.job.name, data.job.onDuty and "(on duty)" or "")
    lines[#lines + 1] = ("  gang      : %s"):format(data.gang.name)
    for moneyType, balance in pairs(data.money) do
      lines[#lines + 1] = ("  %-10s: %d"):format(moneyType, balance)
    end
  end
  OPX.CommandResult(source, raw, true, table.concat(lines, "\n"))
end, true)

--- Prints the caller's position in the exact shape config/shared.lua wants, because a
--- transposed digit puts every new character on the server inside a building.
RegisterCommand("opx77.here", function(source, _, raw)
  if source <= 0 then
    return OPX.CommandResult(source, raw, false, "opx77.here must be run in game")
  end
  local position = Open77.players.position(source)
  if not position then
    return OPX.CommandResult(source, raw, false, "your position is not readable right now")
  end

  local player = OPX.GetPlayer(source)
  local heading = player and player.PlayerData.reportedHeading or 0.0
  OPX.CommandResult(source, raw, true, ([[
DEFAULT_SPAWN = {
  SET = true,
  X = %.2f,
  Y = %.2f,
  Z = %.2f,
  HEADING = %.2f,
},]]):format(position.x, position.y, position.z, heading))
end, true)

RegisterCommand("opx77.whois", function(source, args, raw)
  local target = tonumber(args[1]) or source
  local session = OPX.Sessions[target]
  if not session then
    return OPX.CommandResult(source, raw, false, ("player %s has no session"):format(target))
  end
  OPX.CommandResult(source, raw, true,
    ("player %d  user=%s  name=%s"):format(target, session.userId, session.displayName))
end, true)

RegisterCommand("opx77.characters", function(source, _, raw)
  if source <= 0 then
    return OPX.CommandResult(source, raw, false, "opx77.characters must be run in game")
  end
  CreateThread(function()
    local sent = OPX.SendCharacters(source)
    if not sent.ok then
      return OPX.CommandResult(source, raw, false, tostring(sent.error))
    end
    local lines = { ("%d character(s):"):format(#sent.value) }
    for i = 1, #sent.value do
      local character = sent.value[i]
      lines[#lines + 1] = ("  %-10s %s %s")
        :format(character.citizenId, character.firstName, character.lastName)
    end
    OPX.CommandResult(source, raw, true, table.concat(lines, "\n"))
  end)
end, false)

RegisterCommand("opx77.select", function(source, args, raw)
  if source <= 0 or not args[1] then
    return OPX.CommandResult(source, raw, false, "usage: opx77.select <citizenId>")
  end
  CreateThread(function()
    local selected = OPX.SelectCharacter(source, args[1])
    OPX.CommandResult(source, raw, selected.ok,
      selected.ok and ("entered as %s"):format(selected.value.PlayerData.citizenId)
        or locale(selected.error))
  end)
end, false)

RegisterCommand("opx77.create", function(source, args, raw)
  if source <= 0 or not (args[1] and args[2]) then
    return OPX.CommandResult(source, raw, false,
      "usage: opx77.create <firstName> <lastName> [nomad|streetkid|corpo] [female|male]")
  end
  CreateThread(function()
    local created = OPX.CreateCharacter(source, {
      firstName = args[1],
      lastName = args[2],
      origin = args[3] or "streetkid",
      gender = args[4] or "female",
      birthDate = args[5],
    })
    -- the locale line only: this command is UNRESTRICTED and `detail` can be a raw exception
    OPX.CommandResult(source, raw, created.ok,
      created.ok and ("created %s"):format(created.value.citizenId)
        or locale(created.error))
  end)
end, false)

RegisterCommand("opx77.delete", function(source, args, raw)
  if source <= 0 or not args[1] then
    return OPX.CommandResult(source, raw, false, "usage: opx77.delete <citizenId>")
  end
  CreateThread(function()
    local deleted = OPX.DeleteCharacter(source, args[1])
    OPX.CommandResult(source, raw, deleted.ok,
      deleted.ok and locale("character.deleted") or locale(deleted.error))
  end)
end, false)

RegisterCommand("opx77.duty", function(source, _, raw)
  local src = tonumber(source) or 0
  -- unrestricted, and each run costs two full-PlayerData outbound events
  if src > 0 and OPX.Cooling(src, "duty", 2000) then
    return OPX.NotifyLocale(src, "error.tooFast", nil, "error")
  end
  local player = requirePlayer(source, raw)
  if not player then return end
  CreateThread(function()
    local toggled = OPX.SetJobDuty(player, not player.PlayerData.job.onDuty)
    OPX.CommandResult(source, raw, toggled.ok,
      toggled.ok and (toggled.value and locale("job.onDuty") or locale("job.offDuty"))
        or tostring(toggled.error))
  end)
end, false)

RegisterCommand("opx77.money", function(source, args, raw)
  local target = targetOf(args[1], source)
  local moneyType = args[2] and args[2]:upper()
  local amount = tonumber(args[3])
  if not target or not moneyType or not amount then
    return OPX.CommandResult(source, raw, false,
      "usage: opx77.money <playerId|citizenId> <TYPE> <amount>   (negative removes)")
  end

  local reason = ("staff command by %s"):format(tostring(source))

  -- an if/else: in `a >= 0 and Add() or Remove()` a false from Add runs Remove as well
  local ok
  if amount >= 0 then
    ok = OPX.AddMoney(target, moneyType, amount, reason)
  else
    ok = OPX.RemoveMoney(target, moneyType, -amount, reason)
  end

  OPX.CommandResult(source, raw, ok, ok
    and ("%s now holds %s"):format(target.PlayerData.citizenId,
      OPX.FormatMoney(target.PlayerData.money[moneyType] or 0, moneyType))
    or "refused: unknown money type, bad amount, or insufficient balance")
end, true)

RegisterCommand("opx77.job", function(source, args, raw)
  local target = targetOf(args[1], source)
  if not target or not args[2] then
    return OPX.CommandResult(source, raw, false,
      "usage: opx77.job <playerId|citizenId> <job> [grade]")
  end
  CreateThread(function()
    local set = OPX.SetJob(target, args[2], tonumber(args[3]) or 0)
    OPX.CommandResult(source, raw, set.ok,
      set.ok and ("%s is now %s at %s"):format(target.PlayerData.citizenId,
        set.value.grade.name, set.value.label)
        or ("%s (%s)"):format(locale(set.error), tostring(set.detail)))
  end)
end, true)

RegisterCommand("opx77.gang", function(source, args, raw)
  local target = targetOf(args[1], source)
  if not target or not args[2] then
    return OPX.CommandResult(source, raw, false,
      "usage: opx77.gang <playerId|citizenId> <gang> [grade]")
  end
  CreateThread(function()
    local set = OPX.SetGang(target, args[2], tonumber(args[3]) or 0)
    OPX.CommandResult(source, raw, set.ok,
      set.ok and ("%s is now %s in %s"):format(target.PlayerData.citizenId,
        set.value.grade.name, set.value.label)
        or ("%s (%s)"):format(locale(set.error), tostring(set.detail)))
  end)
end, true)

RegisterCommand("opx77.group", function(source, args, raw)
  local groupType, name = args[1], args[2]
  if groupType ~= "job" and groupType ~= "gang" or not name then
    return OPX.CommandResult(source, raw, false, "usage: opx77.group <job|gang> <name>")
  end
  CreateThread(function()
    local members = OPX.GetGroupMembers(groupType, name)
    if not members.ok then
      return OPX.CommandResult(source, raw, false, tostring(members.error))
    end
    local lines = { ("%s %s -- %d member(s)"):format(groupType, name, #members.value) }
    for i = 1, #members.value do
      local member = members.value[i]
      lines[#lines + 1] = ("  %-10s grade %d  %s")
        :format(member.citizenId, member.grade, member.name)
    end
    OPX.CommandResult(source, raw, true, table.concat(lines, "\n"))
  end)
end, true)

--- Writes every loaded character back right now, for the minute before a planned restart.
RegisterCommand("opx77.save", function(source, _, raw)
  CreateThread(function()
    local players = OPX.GetPlayers()
    local saved = 0
    for i = 1, #players do
      if OPX.Save(players[i]).ok then saved = saved + 1 end
    end
    OPX.CommandResult(source, raw, true,
      ("saved %d of %d character(s)"):format(saved, #players))
  end)
end, true)

--- Suggestions for the chat autocomplete. Sent on the client's `chat:ready` rather than at
--- boot: suggestions sent before that resource's surface is up land nowhere.
RegisterNetEvent("chat:ready", function()
  -- cooled like the rest: a net event anyone can send, answered with several hundred bytes
  local src = tonumber(source)
  if not src then return end
  if OPX.Cooling(src, "chat_suggestions", 10000) then return end

  TriggerClientEvent("chat:addSuggestions", src, {
    { command = "/opx77.characters", help = "List your characters." },
    { command = "/opx77.select", help = "Enter the world as one of your characters.",
      parameters = { { name = "citizenId" } } },
    { command = "/opx77.create", help = "Create a character.",
      parameters = {
        { name = "firstName" }, { name = "lastName" },
        { name = "nomad|streetkid|corpo", optional = true },
        { name = "female|male", optional = true },
      } },
    { command = "/opx77.delete", help = "Delete one of your characters.",
      parameters = { { name = "citizenId" } } },
    { command = "/opx77.duty", help = "Clock in or out of your job." },
  })
end)
