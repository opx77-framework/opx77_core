--- Jobs and gangs, multi-membership, online or offline. Every function here yields when the
--- character is not in the world, so treat the whole file as coroutine only.

local Result = OPX.Result
local log = OPX.Log.scope("groups")

--- What an offline group change writes back to opx77_players: one column, never the row. Two
--- statements rather than one with the column name interpolated, because a concatenated SQL
--- string is a thing a reader has to re-verify every time.
local SAVE_PRIMARY = {
  job = [[
UPDATE opx77_players
   SET job = @value
 WHERE citizen_id = @citizen
  ]],
  gang = [[
UPDATE opx77_players
   SET gang = @value
 WHERE citizen_id = @citizen
  ]],
}

--- Runs `apply` against a Player, loading a temporary offline one when the character is not
--- in the world, and re-resolving after every await in case a login lands between two of the
--- three round trips.
---@param identifier Player|Source|CitizenId
---@param column "job"|"gang"|nil nil for an operation that only touches opx77_player_groups
---@param apply fun(player: Player, offline: boolean): Result
---@return Result
local function withCharacter(identifier, column, apply)
  local player = OPX.ResolvePlayer(identifier)
  if player then return apply(player, false) end

  if type(identifier) ~= "string" then
    return Result.err("error.notLoggedIn", tostring(identifier))
  end

  local fetched = OPX.Storage.Players.fetchOne(identifier)
  if not fetched.ok then return fetched end

  local groups = OPX.Storage.Players.fetchGroups(identifier)
  if not groups.ok then return groups end

  player = OPX.ResolvePlayer(identifier)
  if player then return apply(player, false) end

  local offline = OPX.CreatePlayer(fetched.value, true)
  offline.PlayerData.jobs = groups.value.jobs
  offline.PlayerData.gangs = groups.value.gangs

  local outcome = apply(offline, true)
  if not outcome.ok then return outcome end

  player = OPX.ResolvePlayer(identifier)
  if player then
    log.debug(("%s came online mid-change; re-applying against the live player")
      :format(identifier))
    return apply(player, false)
  end

  if not column then return outcome end

  local saved = OPX.Storage.execute(SAVE_PRIMARY[column], {
    citizen = identifier,
    value = json.encode(offline.PlayerData[column] or {}),
  })
  if not saved.ok then return saved end
  return outcome
end

--- The membership write, shared by jobs and gangs. The row goes first, and announcing is the
--- caller's job -- which no caller may skip: `.jobs` is mirrored, and it is also how a
--- membership change on a character who never moves reaches the autosave.
---@param player Player
---@param groupType GroupType
---@param name string
---@param grade integer
---@return Result
local function joinGroup(player, groupType, name, grade)
  local citizenId = player.PlayerData.citizenId
  local written = OPX.Storage.Players.upsertGroup(citizenId, groupType, name, grade)
  if not written.ok then return written end

  local bucket = groupType == "job" and player.PlayerData.jobs or player.PlayerData.gangs
  bucket[name] = grade
  return Result.ok(true)
end

---@param player Player
---@param groupType GroupType
---@param name string
---@return Result
local function leaveGroup(player, groupType, name)
  local citizenId = player.PlayerData.citizenId
  local removed = OPX.Storage.Players.removeGroup(citizenId, groupType, name)
  if not removed.ok then return removed end

  local bucket = groupType == "job" and player.PlayerData.jobs or player.PlayerData.gangs
  bucket[name] = nil
  return Result.ok(true)
end

--- Makes `name` at `grade` the primary job, joining it if needed. Duty comes from the job's
--- `defaultDuty` rather than being carried over.
---@param identifier Player|Source|CitizenId
---@param name string
---@param grade integer
---@return Result  ok value is the new PlayerJob
function OPX.SetJob(identifier, name, grade)
  return withCharacter(identifier, "job", function(player)
    local resolved = OPX.ResolveJob(name, grade)
    if not resolved.ok then return resolved end

    local joined = joinGroup(player, "job", name, resolved.value.grade.level)
    if not joined.ok then return joined end

    player.PlayerData.job = resolved.value
    player.Functions.UpdatePlayerData()

    if not player.Offline then
      TriggerClientEvent(OPX.Events.Client.JOB_UPDATE, player.PlayerData.source, resolved.value)
    end
    TriggerEvent(OPX.Events.Internal.JOB_UPDATE, player.PlayerData.source, resolved.value)

    OPX.Logger.player(player, "job.set", ("%s grade %d"):format(name, resolved.value.grade.level))
    return Result.ok(resolved.value)
  end)
end

--- Clocks a character in or out of their primary job. Refuses for a job whose `defaultDuty`
--- is true: those have no shift, and clocking out of "unemployed" is a state nothing reasons
--- about.
---@param identifier Player|Source|CitizenId
---@param onDuty boolean
---@return Result
function OPX.SetJobDuty(identifier, onDuty)
  return withCharacter(identifier, "job", function(player)
    local job = player.PlayerData.job
    local definition = OPX.GetJob(job.name)
    if not definition then return Result.err("job.notFound", job.name) end
    if definition.defaultDuty then
      return Result.err("job.noDuty", job.name)
    end

    job.onDuty = onDuty == true
    player.Functions.UpdatePlayerData()

    if not player.Offline then
      TriggerClientEvent(OPX.Events.Client.JOB_UPDATE, player.PlayerData.source, job)
      OPX.NotifyLocale(player.PlayerData.source, job.onDuty and "job.onDuty" or "job.offDuty")
    end
    TriggerEvent(OPX.Events.Internal.JOB_UPDATE, player.PlayerData.source, job)
    return Result.ok(job.onDuty)
  end)
end

--- Adds a membership without changing which job is primary.
---@param identifier Player|Source|CitizenId
---@param name string
---@param grade integer
---@return Result
function OPX.AddPlayerToJob(identifier, name, grade)
  return withCharacter(identifier, nil, function(player)
    local resolved = OPX.ResolveJob(name, grade)
    if not resolved.ok then return resolved end
    local joined = joinGroup(player, "job", name, resolved.value.grade.level)
    if not joined.ok then return joined end
    player.Functions.UpdatePlayerData()
    return joined
  end)
end

--- Removes a membership. If it was the primary job the character falls back to the default:
--- leaving them employed by a job they left is how a fired employee keeps drawing a salary.
---@param identifier Player|Source|CitizenId
---@param name string
---@return Result
function OPX.RemovePlayerFromJob(identifier, name)
  return withCharacter(identifier, "job", function(player)
    local left = leaveGroup(player, "job", name)
    if not left.ok then return left end

    local announced = false
    if player.PlayerData.job.name == name then
      local fallback = OPX.ResolveJob(OPX.Config.SERVER.PLAYER.DEFAULT_JOB, 0)
      if fallback.ok then
        player.PlayerData.job = fallback.value
        player.Functions.UpdatePlayerData()
        announced = true
        if not player.Offline then
          TriggerClientEvent(OPX.Events.Client.JOB_UPDATE,
            player.PlayerData.source, fallback.value)
        end
      end
    end

    -- announced even for a non-primary removal, because leaveGroup changed PlayerData.jobs
    if not announced then player.Functions.UpdatePlayerData() end

    OPX.Logger.player(player, "job.removed", name)
    return Result.ok(true)
  end)
end

--- Switches which of a character's existing jobs is primary. Refuses a job they are not a
--- member of rather than joining it: only one of those two requests is a promotion.
---@param identifier Player|Source|CitizenId
---@param name string
---@return Result
function OPX.SetPlayerPrimaryJob(identifier, name)
  return withCharacter(identifier, "job", function(player)
    local grade = player.PlayerData.jobs[name]
    if grade == nil then return Result.err("job.notMember", name) end
    return OPX.SetJob(player, name, grade)
  end)
end

--- Makes `name` at `grade` the character's primary gang, joining it if needed.
---@param identifier Player|Source|CitizenId
---@param name string
---@param grade integer
---@return Result  ok value is the new PlayerGang
function OPX.SetGang(identifier, name, grade)
  return withCharacter(identifier, "gang", function(player)
    local resolved = OPX.ResolveGang(name, grade)
    if not resolved.ok then return resolved end

    local joined = joinGroup(player, "gang", name, resolved.value.grade.level)
    if not joined.ok then return joined end

    player.PlayerData.gang = resolved.value
    player.Functions.UpdatePlayerData()

    if not player.Offline then
      TriggerClientEvent(OPX.Events.Client.GANG_UPDATE, player.PlayerData.source, resolved.value)
    end
    TriggerEvent(OPX.Events.Internal.GANG_UPDATE, player.PlayerData.source, resolved.value)

    OPX.Logger.player(player, "gang.set", ("%s grade %d"):format(name, resolved.value.grade.level))
    return Result.ok(resolved.value)
  end)
end

--- Adds a membership without changing which gang is primary.
---@param identifier Player|Source|CitizenId
---@param name string
---@param grade integer
---@return Result
function OPX.AddPlayerToGang(identifier, name, grade)
  return withCharacter(identifier, nil, function(player)
    local resolved = OPX.ResolveGang(name, grade)
    if not resolved.ok then return resolved end
    local joined = joinGroup(player, "gang", name, resolved.value.grade.level)
    if not joined.ok then return joined end
    player.Functions.UpdatePlayerData()
    return joined
  end)
end

--- Removes a membership; if it was the primary gang, the character falls back to the default.
---@param identifier Player|Source|CitizenId
---@param name string
---@return Result
function OPX.RemovePlayerFromGang(identifier, name)
  return withCharacter(identifier, "gang", function(player)
    local left = leaveGroup(player, "gang", name)
    if not left.ok then return left end

    local announced = false
    if player.PlayerData.gang.name == name then
      local fallback = OPX.ResolveGang(OPX.Config.SERVER.PLAYER.DEFAULT_GANG, 0)
      if fallback.ok then
        player.PlayerData.gang = fallback.value
        player.Functions.UpdatePlayerData()
        announced = true
        if not player.Offline then
          TriggerClientEvent(OPX.Events.Client.GANG_UPDATE,
            player.PlayerData.source, fallback.value)
        end
      end
    end

    -- announced even for a non-primary removal, because leaveGroup changed PlayerData.gangs
    if not announced then player.Functions.UpdatePlayerData() end

    OPX.Logger.player(player, "gang.removed", name)
    return Result.ok(true)
  end)
end

--- Switches which of a character's existing gangs is primary.
---@param identifier Player|Source|CitizenId
---@param name string
---@return Result
function OPX.SetPlayerPrimaryGang(identifier, name)
  return withCharacter(identifier, "gang", function(player)
    local grade = player.PlayerData.gangs[name]
    if grade == nil then return Result.err("gang.notMember", name) end
    return OPX.SetGang(player, name, grade)
  end)
end

--- Everyone in a group, online or not. Coroutine only.
---@param groupType GroupType
---@param name string
---@return Result
function OPX.GetGroupMembers(groupType, name)
  if groupType ~= "job" and groupType ~= "gang" then
    return Result.err("error.badRequest", tostring(groupType))
  end
  return OPX.Storage.Players.membersOf(groupType, name)
end

--- Loaded characters whose primary job is `name`. In-memory, so it does not yield: this is
--- what a dispatch or a radio calls, often.
---@param name string
---@param onDutyOnly? boolean
---@return Player[]
function OPX.GetPlayersByJob(name, onDutyOnly)
  local out, n = {}, 0
  local players = OPX.GetPlayers()
  for i = 1, #players do
    local job = players[i].PlayerData.job
    if job.name == name and (not onDutyOnly or job.onDuty) then
      n = n + 1
      out[n] = players[i]
    end
  end
  return out
end

--- Loaded characters whose primary gang is `name`. In-memory: it does not yield.
---@param name string
---@return Player[]
function OPX.GetPlayersByGang(name)
  local out, n = {}, 0
  local players = OPX.GetPlayers()
  for i = 1, #players do
    if players[i].PlayerData.gang.name == name then
      n = n + 1
      out[n] = players[i]
    end
  end
  return out
end

log.debug(("%d job(s) and %d gang(s) defined")
  :format(OPX.Table.count(OPX.Jobs), OPX.Table.count(OPX.Gangs)))
