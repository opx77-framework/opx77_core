--- The Player object: PlayerData, its Functions, and login/logout/save.
---
---   player.Functions.AddMoney("EDDIES", 500, "gig payout")
---   OPX.AddMoney(citizenId, "EDDIES", 500, "gig payout")
---
--- The module-level form is the implementation and `Functions` binds the player into it, so a
--- rule added to one is a rule both obey. Money is whole eddies: a fractional balance
--- round-tripped through a JSON column drifts.

local Result = OPX.Result
local log = OPX.Log.scope("player")

local Config = OPX.Config.SERVER
local Shared = OPX.Config.SHARED

--- Fills in anything a stored entity is missing: refusing to load a character because it
--- predates a field is, in effect, deleting it.
local function normalise(entity)
  entity.charInfo = entity.charInfo or {}
  entity.metadata = entity.metadata or {}
  entity.money = entity.money or {}

  -- zero, not the configured start: a starting amount is a new-character grant
  for moneyType in pairs(Shared.MONEY.TYPES) do
    entity.money[moneyType] = math.floor(tonumber(entity.money[moneyType]) or 0)
  end

  -- deep-copied: a table default by reference is one table every character shares
  for key, value in pairs(Config.PLAYER.STARTING_METADATA) do
    if entity.metadata[key] == nil then
      entity.metadata[key] = OPX.Table.deepCopy(value)
    end
  end

  -- a job deleted from data/ falls back; the membership row is left alone, mid-edit or not
  local job = OPX.ResolveJob(entity.job and entity.job.name, entity.job and entity.job.grade
    and entity.job.grade.level)
  if not job.ok then
    job = OPX.ResolveJob(Config.PLAYER.DEFAULT_JOB, 0)
  end
  entity.job = job.value

  local gang = OPX.ResolveGang(entity.gang and entity.gang.name, entity.gang and entity.gang.grade
    and entity.gang.grade.level)
  if not gang.ok then
    gang = OPX.ResolveGang(Config.PLAYER.DEFAULT_GANG, 0)
  end
  entity.gang = gang.value

  return entity
end

OPX.NormaliseEntity = normalise

--- Builds a Player around a stored entity. `Revision` and `MaySample` sit on the Player
--- rather than on PlayerData, which keeps them out of the client payload and every column.
---@param entity table
---@param offline? boolean an offline Player has the same Functions, but sends and places
---        nothing
---@return Player
function OPX.CreatePlayer(entity, offline)
  local self = { Offline = offline == true }

  --- The autosave's dirty flag, bumped by every change and never reset. It moves only in
  --- `Functions.UpdatePlayerData`, so a gameplay file assigning into PlayerData directly
  --- makes a change this counter cannot see.
  self.Revision = 0

  --- False until the world agrees with the stored row. A character whose placement failed is
  --- standing wherever the engine dropped them, and sampling that overwrites the very
  --- position placement was trying to restore. `OPX.PlaceCharacter` is the only setter.
  self.MaySample = false

  self.PlayerData = normalise(entity)

  -- not `offline and nil or entity.source`: that yields entity.source on both branches
  if self.Offline then
    self.PlayerData.source = nil
  else
    self.PlayerData.source = entity.source
  end

  local Functions = {}
  self.Functions = Functions

  --- Pushes the whole of PlayerData to the client that owns it. Called by every mutator
  --- below rather than left to the caller.
  function Functions.UpdatePlayerData()
    -- counted before the offline return: an offline promotion is a change too
    self.Revision = self.Revision + 1
    if self.Offline then return end
    TriggerClientEvent(OPX.Events.Client.SET_PLAYER_DATA, self.PlayerData.source, self.PlayerData)
  end

  function Functions.SetPlayerData(key, value)
    if key == "citizenId" or key == "userId" or key == "source" then
      -- identity is not data: this is how a character ends up owned by the wrong account
      error(("PlayerData.%s is identity and cannot be set"):format(key), 2)
    end
    self.PlayerData[key] = value
    Functions.UpdatePlayerData()
  end

  function Functions.SetMetaData(key, value)
    self.PlayerData.metadata[key] = value
    Functions.UpdatePlayerData()
  end

  function Functions.GetMetaData(key)
    if key == nil then return self.PlayerData.metadata end
    return self.PlayerData.metadata[key]
  end

  function Functions.SetCharInfo(key, value)
    self.PlayerData.charInfo[key] = value
    Functions.UpdatePlayerData()
  end

  function Functions.AddMoney(moneyType, amount, reason)
    return OPX.AddMoney(self, moneyType, amount, reason)
  end

  function Functions.RemoveMoney(moneyType, amount, reason)
    return OPX.RemoveMoney(self, moneyType, amount, reason)
  end

  function Functions.SetMoney(moneyType, amount, reason)
    return OPX.SetMoney(self, moneyType, amount, reason)
  end

  function Functions.GetMoney(moneyType)
    return OPX.GetMoney(self, moneyType)
  end

  function Functions.SetJob(name, grade)
    return OPX.SetJob(self, name, grade)
  end

  function Functions.SetGang(name, grade)
    return OPX.SetGang(self, name, grade)
  end

  function Functions.SetJobDuty(onDuty)
    return OPX.SetJobDuty(self, onDuty)
  end

  --- Coroutine only: it writes to the database.
  function Functions.Save()
    return OPX.Save(self)
  end

  function Functions.Logout()
    return OPX.Logout(self.PlayerData.source)
  end

  return self
end

--- Every module-level mutator starts with this, so no call site has to know which of the
--- three shapes it is holding.
---@param identifier Player|Source|CitizenId
---@return Player|nil
local function resolve(identifier)
  if type(identifier) == "table" and identifier.PlayerData then return identifier end
  if type(identifier) == "number" then return OPX.GetPlayer(identifier) end
  if type(identifier) == "string" then return OPX.GetPlayerByCitizenId(identifier) end
  return nil
end

OPX.ResolvePlayer = resolve

--- Refuses anything that is not a positive, finite, real amount. NaN is the case worth
--- naming: it arrives over JSON, passes every comparison, and once it is in a balance so does
--- the check that would stop the player spending it.
local function amountOf(value)
  local n = tonumber(value)
  if not OPX.Math.isFinite(n) then return nil end
  n = math.floor(n + 0.5)
  if n <= 0 then return nil end
  return n
end

--- Announces a balance change to its four audiences: the owning client, this resource's own
--- files, the audit log, and PlayerData itself.
local function announceMoney(player, moneyType, amount, action, reason)
  local data = player.PlayerData
  player.Functions.UpdatePlayerData()

  if not player.Offline then
    TriggerClientEvent(OPX.Events.Client.MONEY_CHANGE, data.source,
      moneyType, amount, action, data.money[moneyType])
  end

  -- data.source is nil offline, honestly: the citizen id is the field to key on
  TriggerEvent(OPX.Events.Internal.MONEY_CHANGE,
    data.source, data.citizenId, moneyType, amount, action, reason,
    data.money[moneyType])

  OPX.Logger.player(player, "money." .. action, reason, {
    moneyType = moneyType,
    amount = amount,
    balance = data.money[moneyType],
  })
end

---@param identifier Player|Source|CitizenId
---@param moneyType MoneyType
---@param amount number
---@param reason? string
---@return boolean ok
function OPX.AddMoney(identifier, moneyType, amount, reason)
  local player = resolve(identifier)
  if not player then return false end
  if not OPX.IsMoneyType(moneyType) then
    log.error(("AddMoney: %q is not a money type on this server"):format(tostring(moneyType)))
    return false
  end

  local value = amountOf(amount)
  if not value then
    OPX.Logger.security("money.badAmount",
      ("AddMoney refused %s"):format(tostring(amount)),
      { citizenId = player.PlayerData.citizenId, moneyType = moneyType })
    return false
  end

  if not OPX.Hooks.trigger("money:beforeAdd", {
    player = player, moneyType = moneyType, amount = value, reason = reason,
  }) then
    return false
  end

  local money = player.PlayerData.money
  money[moneyType] = money[moneyType] + value
  announceMoney(player, moneyType, value, "add", reason)
  return true
end

--- Refuses rather than truncating when there is not enough: a purchase that half-succeeds is
--- worse than one that fails.
---@param identifier Player|Source|CitizenId
---@param moneyType MoneyType
---@param amount number
---@param reason? string
---@return boolean ok
function OPX.RemoveMoney(identifier, moneyType, amount, reason)
  local player = resolve(identifier)
  if not player then return false end
  if not OPX.IsMoneyType(moneyType) then
    log.error(("RemoveMoney: %q is not a money type on this server"):format(tostring(moneyType)))
    return false
  end

  local value = amountOf(amount)
  if not value then
    OPX.Logger.security("money.badAmount",
      ("RemoveMoney refused %s"):format(tostring(amount)),
      { citizenId = player.PlayerData.citizenId, moneyType = moneyType })
    return false
  end

  local money = player.PlayerData.money
  if money[moneyType] - value < 0 and not Config.MONEY.ALLOW_NEGATIVE[moneyType] then
    return false
  end

  if not OPX.Hooks.trigger("money:beforeRemove", {
    player = player, moneyType = moneyType, amount = value, reason = reason,
  }) then
    return false
  end

  money[moneyType] = money[moneyType] - value
  announceMoney(player, moneyType, value, "remove", reason)
  return true
end

--- Sets a balance outright. Zero is allowed here and nowhere else: it is the only way to
--- empty an account, where in Add/Remove a zero is a caller's arithmetic having gone wrong.
---@param identifier Player|Source|CitizenId
---@param moneyType MoneyType
---@param amount number
---@param reason? string
---@return boolean ok
function OPX.SetMoney(identifier, moneyType, amount, reason)
  local player = resolve(identifier)
  if not player then return false end
  if not OPX.IsMoneyType(moneyType) then return false end

  local n = tonumber(amount)
  if not OPX.Math.isFinite(n) then return false end
  n = math.floor(n + 0.5)
  if n < 0 and not Config.MONEY.ALLOW_NEGATIVE[moneyType] then return false end

  if not OPX.Hooks.trigger("money:beforeSet", {
    player = player, moneyType = moneyType, amount = n, reason = reason,
  }) then
    return false
  end

  player.PlayerData.money[moneyType] = n
  announceMoney(player, moneyType, n, "set", reason)
  return true
end

---@param identifier Player|Source|CitizenId
---@param moneyType? MoneyType nil returns the whole money table
---@return integer|table|nil
function OPX.GetMoney(identifier, moneyType)
  local player = resolve(identifier)
  if not player then return nil end
  if moneyType == nil then return player.PlayerData.money end
  return player.PlayerData.money[moneyType]
end

---@param identifier Player|Source|CitizenId
---@param key string
---@param value any
---@return boolean ok
function OPX.SetMetadata(identifier, key, value)
  local player = resolve(identifier)
  if not player then return false end
  player.Functions.SetMetaData(key, value)
  return true
end

---@param identifier Player|Source|CitizenId
---@param key? string nil returns the whole metadata table
---@return any
function OPX.GetMetadata(identifier, key)
  local player = resolve(identifier)
  if not player then return nil end
  return player.Functions.GetMetaData(key)
end

--- Re-derives a position from `Open77.players.position`; the client's report is only ever a
--- hint, and `heading` is the one field taken from it. False leaves the last known position
--- in place rather than overwriting it with nothing -- "cannot tell" and "here" must never
--- collapse into each other.
---@param player Player
---@return boolean sampled
function OPX.SamplePosition(player)
  local data = player.PlayerData
  if not data.source then return false end
  if not player.MaySample then return false end

  local snapshot = Open77.players.position(data.source)
  if type(snapshot) ~= "table" or snapshot.x == nil then return false end

  local previous = data.position
  data.position = {
    x = snapshot.x,
    y = snapshot.y,
    z = snapshot.z,
    heading = data.reportedHeading or (previous and previous.heading) or 0.0,
    bucket = snapshot.bucket or 0,
  }
  return true
end

--- Puts a character into the world; coroutine only. Groups load before the Player is
--- registered, and the roster entry comes before the client is told.
---@param source Source
---@param citizenId CitizenId
---@return Result  ok value is the Player
function OPX.Login(source, citizenId)
  local session = OPX.EnsureSession(source)
  if not session then return Result.err("entry.noIdentity", tostring(source)) end

  if OPX.BootError then
    return Result.err("error.unavailable", OPX.BootError)
  end

  local fetched = OPX.Storage.Players.fetchOne(citizenId)
  if not fetched.ok then return fetched end

  local entity = fetched.value
  if entity.userId ~= session.userId then
    OPX.Logger.security("character.notYours",
      ("player %d asked for %s"):format(source, citizenId),
      { userId = session.userId, owner = entity.userId })
    -- the same code a missing character gets: "somebody else's" is an existence oracle
    return Result.err("character.notFound", citizenId)
  end

  local already = OPX.GetPlayerByCitizenId(citizenId)
  if already and already.PlayerData.source ~= source then
    -- two Players writing one row means the last save silently wins
    return Result.err("character.inUse", citizenId)
  end

  local groups = OPX.Storage.Players.fetchGroups(citizenId)
  if not groups.ok then return groups end

  entity.source = source
  local player = OPX.CreatePlayer(entity, false)
  player.PlayerData.jobs = groups.value.jobs
  player.PlayerData.gangs = groups.value.gangs

  OPX.RegisterPlayer(player)
  session.citizenId = citizenId

  -- a local event the host fans into open77_appearance's VM; the only channel there is
  TriggerEvent("open77:appearance:setCharacter", source, citizenId)

  TriggerClientEvent(OPX.Events.Client.PLAYER_LOADED, source, player.PlayerData)
  TriggerEvent(OPX.Events.Internal.PLAYER_LOADED, source, player.PlayerData)

  OPX.Logger.player(player, "character.login", "logged in")
  log.info(("%s (%s) logged in as %s %s"):format(
    session.displayName, citizenId,
    player.PlayerData.charInfo.firstName or "?",
    player.PlayerData.charInfo.lastName or "?"))

  return Result.ok(player)
end

--- Writes a character back, sampling the position first. Coroutine only.
---@param identifier Player|Source|CitizenId
---@param loggedOut? boolean
---@return Result
function OPX.Save(identifier, loggedOut)
  local player = resolve(identifier)
  if not player then return Result.err("error.notLoggedIn") end

  if not player.Offline then OPX.SamplePosition(player) end

  local saved = OPX.Storage.Players.save(player.PlayerData, loggedOut)
  if not saved.ok then
    log.error(("save failed for %s: %s")
      :format(player.PlayerData.citizenId, tostring(saved.detail)))
  end
  return saved
end

--- Takes a character out of the world, saving it on the way. Idempotent: both disconnect
--- events may fire for the same departure.
---@param source Source
function OPX.Logout(source)
  source = tonumber(source)
  local player = source and OPX.Players[source]
  if not player then return end

  -- out of the roster before the save, which yields: a lookup then answers "still present"
  OPX.UnregisterPlayer(player)

  local session = OPX.Sessions[source]
  if session then session.citizenId = nil end

  TriggerClientEvent(OPX.Events.Client.PLAYER_UNLOADED, source)
  TriggerEvent(OPX.Events.Internal.PLAYER_UNLOADED, source, player.PlayerData)

  CreateThread(function()
    OPX.Save(player, true)
    OPX.Logger.player(player, "character.logout", "logged out")
  end)
end

--- Log a character out and WAIT for its row, which is what a SWITCH needs: `OPX.Logout`
--- dispatches, and the read for the next character would beat that thread to the database.
---@param source Source
---@return Result
function OPX.LogoutAndWait(source)
  source = tonumber(source)
  local player = source and OPX.Players[source]
  if not player then return Result.ok(false) end

  OPX.UnregisterPlayer(player)

  local session = OPX.Sessions[source]
  if session then session.citizenId = nil end

  TriggerClientEvent(OPX.Events.Client.PLAYER_UNLOADED, source)
  TriggerEvent(OPX.Events.Internal.PLAYER_UNLOADED, source, player.PlayerData)

  local saved = OPX.Save(player, true)
  OPX.Logger.player(player, "character.logout", "logged out")
  return saved
end
