--- Commands. `RegisterCommand`'s third argument gates one on the ACL permission
--- `command.<name>`; every unrestricted one takes a doorway cooldown first.

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

--- The doorway guard for an unrestricted command that answers on its own thread.
---@param source Source console callers pass 0, for which `OPX.Cooling` is always false
---@param raw string
---@param key string the SAME `<operation>.request` key the wire doorway takes, so the two
---        entry points share one window; never the operation's own key, which `OPX.Cooling`
---        would then consume and make the operation refuse itself
---@param everyMs integer
---@return boolean refused true when the caller has already been answered
local function tooFast(source, raw, key, everyMs)
  if not OPX.Cooling(source, key, everyMs) then return false end
  OPX.CommandResult(source, raw, false, locale("error.tooFast"))
  return true
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

--- One player's whole situation, all of it what the SERVER believes.
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
    -- sorted, so two runs of this command can be compared line for line
    local moneyTypes = {}
    for moneyType in pairs(data.money) do moneyTypes[#moneyTypes + 1] = moneyType end
    table.sort(moneyTypes)
    for i = 1, #moneyTypes do
      lines[#lines + 1] = ("  %-10s: %d"):format(moneyTypes[i], data.money[moneyTypes[i]])
    end
  end
  OPX.CommandResult(source, raw, true, table.concat(lines, "\n"))
end, true)

--- Prints the caller's position in the exact shape config/shared.lua wants.
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
    return OPX.CommandResult(source, raw, false, locale("command.inGameOnly"))
  end
  if tooFast(source, raw, "ready", 2000) then return end
  CreateThread(function()
    local sent = OPX.SendCharacters(source)
    if not sent.ok then
      return OPX.CommandResult(source, raw, false, locale(OPX.RefusalKey(sent.error)))
    end
    local lines = { locale("command.characterCount", { count = #sent.value }) }
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
    return OPX.CommandResult(source, raw, false, locale("command.usage.select"))
  end
  if tooFast(source, raw, "select.request", 1000) then return end
  CreateThread(function()
    local selected = OPX.SelectCharacter(source, args[1])
    OPX.CommandResult(source, raw, selected.ok,
      selected.ok and locale("command.entered",
        { citizenId = selected.value.PlayerData.citizenId })
        or locale(OPX.RefusalKey(selected.error)))
  end)
end, false)

RegisterCommand("opx77.create", function(source, args, raw)
  if source <= 0 or not (args[1] and args[2]) then
    return OPX.CommandResult(source, raw, false, locale("command.usage.create"))
  end
  if tooFast(source, raw, "create.request", 1000) then return end
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
      created.ok and locale("character.created", { citizenId = created.value.citizenId })
        or locale(OPX.RefusalKey(created.error)))
  end)
end, false)

RegisterCommand("opx77.delete", function(source, args, raw)
  if source <= 0 or not args[1] then
    return OPX.CommandResult(source, raw, false, locale("command.usage.delete"))
  end
  if tooFast(source, raw, "delete.request", 1000) then return end
  CreateThread(function()
    local deleted = OPX.DeleteCharacter(source, args[1])
    OPX.CommandResult(source, raw, deleted.ok,
      deleted.ok and locale("character.deleted") or locale(OPX.RefusalKey(deleted.error)))
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
        or locale(OPX.RefusalKey(toggled.error)))
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
  local ok, why
  if amount >= 0 then
    ok, why = OPX.AddMoney(target, moneyType, amount, reason)
  else
    ok, why = OPX.RemoveMoney(target, moneyType, -amount, reason)
  end

  -- one params table covers every code the mutators return: `money.insufficient` carries a
  -- {type} placeholder, the others do not, and a spare parameter is ignored
  OPX.CommandResult(source, raw, ok, ok
    and ("%s now holds %s"):format(target.PlayerData.citizenId,
      OPX.FormatMoney(target.PlayerData.money[moneyType] or 0, moneyType))
    or locale(why or "error.badRequest", { type = moneyType }))
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

--- Suggestions for the chat autocomplete, sent on `chat:ready`: ones sent at boot land
--- nowhere.
RegisterNetEvent("chat:ready", function()
  -- cooled like the rest: a net event anyone can send, answered with several hundred bytes
  local src = tonumber(source)
  if not src then return end
  if OPX.Cooling(src, "chat_suggestions", 10000) then return end

  TriggerClientEvent("chat:addSuggestions", src, {
    { command = "/opx77.characters", help = locale("command.help.characters") },
    { command = "/opx77.select", help = locale("command.help.select"),
      parameters = { { name = "citizenId" } } },
    { command = "/opx77.create", help = locale("command.help.create"),
      parameters = {
        { name = "firstName" }, { name = "lastName" },
        { name = "nomad|streetkid|corpo", optional = true },
        { name = "female|male", optional = true },
      } },
    { command = "/opx77.delete", help = locale("command.help.delete"),
      parameters = { { name = "citizenId" } } },
    { command = "/opx77.duty", help = locale("command.help.duty") },
  })
end)
