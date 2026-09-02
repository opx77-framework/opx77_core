--- The core's public API for satellite client resources. Seven of these read the mirrored
--- state or the static definitions; the four character-screen ones are requests that fire an
--- `opx77:server:*` net event, where the server validates them, and answer only that the
--- request was sent.
---
---   CreateThread(function()
---     local promise, reason = Open77.exports.call("opx77_core", "GetPlayerData")
---     if not promise then return print(reason) end        -- dispatch failed
---     local result, callError = promise:await()           -- resolution failed
---     if callError or not result.ok then return end
---     print(result.data.citizenId)
---   end)
---
--- There is no `exports.<resource>:<name>()` proxy, the call is always asynchronous, and
--- failure has two levels: checking only the first turns a remote error into a silent nil.
--- Every export answers a plain `{ ok = boolean, ... }`, because the value crosses a codec
--- and lands in code that does not have `OPX.Result` loaded.

--- `ok = false` rather than an empty table, so a caller cannot mistake "not logged in yet"
--- for "logged in with nothing".
---@return { ok: boolean, data?: PlayerData, error?: string }
exports("GetPlayerData", function()
  if not OPX.IsLoggedIn then return { ok = false, error = "error.notLoggedIn" } end
  return { ok = true, data = OPX.PlayerData }
end)

---@return { ok: true, loggedIn: boolean }
exports("IsLoggedIn", function()
  return { ok = true, loggedIn = OPX.IsLoggedIn }
end)

--- A duty check and a grade comparison, which is why this is an export and a plain field
--- read is not. `minGrade` is read with `tonumber`, so a value that is not a number is
--- treated as absent rather than as grade 0.
---@param name string
---@param onDutyOnly? boolean
---@param minGrade? integer
---@return { ok: true, result: boolean }
exports("HasJob", function(name, onDutyOnly, minGrade)
  return { ok = true, result = OPX.HasJob(name, onDutyOnly == true, tonumber(minGrade)) }
end)

--- No duty flag: a gang has no shifts, so `minGrade` is the second parameter here and the
--- third on `HasJob`.
---@param name string
---@param minGrade? integer
---@return { ok: true, result: boolean }
exports("HasGang", function(name, minGrade)
  return { ok = true, result = OPX.HasGang(name, tonumber(minGrade)) }
end)

-- The selection screen's API. Everything here is a request, and the return value only says
-- the request was sent -- the answer arrives as an event, so a caller watches for one.
-- Listen on `OPX.Events.Local.PLAYER_LOADED` ("opx77:client:onPlayerLoaded") and
-- `.REFUSED` ("opx77:client:refused") with a plain `AddEventHandler`: the client's local
-- event bus is host-wide, so that reaches you and costs no permission. The wire names the
-- server actually sends are `opx77:client:playerLoaded` and `opx77:client:notify`, and a
-- caller that would rather take the wire itself needs `network.events` in its manifest.

---@return { ok: true, characters: CharacterSummary[], slots: integer, origins: table }
exports("GetCharacters", function()
  return {
    ok = true,
    characters = OPX.Characters.list,
    slots = OPX.Characters.slots,
    origins = OPX.Characters.origins,
  }
end)

---@return { ok: true }
exports("RequestCharacters", function()
  OPX.RequestCharacters()
  return { ok = true }
end)

---@param citizenId CitizenId
---@return { ok: boolean, error?: string }
exports("SelectCharacter", function(citizenId)
  local sent, reason = OPX.SelectCharacter(citizenId)
  return { ok = sent, error = reason }
end)

---@param registration table
---@return { ok: boolean, error?: string }
exports("CreateCharacter", function(registration)
  local sent, reason = OPX.CreateCharacter(registration)
  return { ok = sent, error = reason }
end)

---@param citizenId CitizenId
---@return { ok: boolean, error?: string }
exports("DeleteCharacter", function(citizenId)
  local sent, reason = OPX.DeleteCharacter(citizenId)
  return { ok = sent, error = reason }
end)

local log = OPX.Log.scope("exports")

--- Checked once, at load, rather than on every call: it is a config value, it cannot change
--- without a restart, and a UI that asks a hundred times should not get a hundred lines.
--- Warned about and still published -- see OPX.IsNotifyPosition for why it is not dropped.
if not OPX.IsNotifyPosition(OPX.Config.SHARED.NOTIFY_POSITION) then
  log.warn(("NOTIFY_POSITION %q is not one of the documented open77_notifications positions; "
    .. "expected one of middle_left, top_left, top_center, top_right, bottom_left, "
    .. "bottom_center, bottom_right"):format(tostring(OPX.Config.SHARED.NOTIFY_POSITION)))
end

--- The configuration a UI legitimately needs, and only that -- not `OPX.Config` wholesale.
--- The static definitions are NOT here: they are large, they never change, and a UI that
--- wants them wants them once. `GetJobs`, `GetGangs` and `GetOrigins` answer those.
---@return { ok: true, config: table }
exports("GetSharedConfig", function()
  local shared = OPX.Config.SHARED
  return {
    ok = true,
    config = {
      serverName = shared.SERVER_NAME,
      -- the locale in force, not the one configured: they differ after Locale.set
      locale = OPX.Locale.current(),
      moneyTypes = shared.MONEY.TYPES,
      defaultMoneyType = shared.MONEY.DEFAULT,
      nameBounds = shared.CHARACTERS.NAME,
      notifyPosition = shared.NOTIFY_POSITION,
    },
  }
end)

--- Translation, so a refusal code renders identically wherever it is shown.
---@param key string
---@param params? table<string, string|number>
---@return { ok: boolean, text?: string, error?: string }
exports("Locale", function(key, params)
  -- a real catalogue key, not "bad-key": `error` doubles as one wherever it is shown
  if type(key) ~= "string" then return { ok = false, error = "error.badRequest" } end
  return { ok = true, text = locale(key, params) }
end)

-- The static definitions, which are shipped to the client VM as `shared_script` and until now
-- had no way out of it. A boss menu, a duty board and a paycheck preview all need them, and
-- none of them belongs in the core.

--- Static job definitions. `grades` is a 1-based array carrying an explicit `level`, not the
--- 0-keyed source table: the value codec documents "string or integer keys" but no table
--- with a 0 key has ever crossed it in this framework, and an export is not the place to
--- find out. Read `grade.level`, never the array index.
---@return { ok: true, jobs: table }
exports("GetJobs", function()
  local out = {}
  for name, job in pairs(OPX.Jobs) do
    local grades, n = {}, 0
    for level = 0, OPX.TopGrade(job.grades) do
      local rank = job.grades[level]
      if rank then
        n = n + 1
        grades[n] = { level = level, name = rank.name, payment = rank.payment,
          isBoss = rank.isBoss == true, bankAuth = rank.bankAuth == true }
      end
    end
    out[name] = { label = job.label, type = job.type, defaultDuty = job.defaultDuty == true,
      offDutyPay = job.offDutyPay == true, grades = grades }
  end
  return { ok = true, jobs = out }
end)

--- Static gang definitions, same grade shape as `GetJobs` and for the same reason. Gangs
--- carry no payment and no duty: a gang is not an employer.
---@return { ok: true, gangs: table }
exports("GetGangs", function()
  local out = {}
  for name, gang in pairs(OPX.Gangs) do
    local grades, n = {}, 0
    for level = 0, OPX.TopGrade(gang.grades) do
      local rank = gang.grades[level]
      if rank then
        n = n + 1
        grades[n] = { level = level, name = rank.name,
          isBoss = rank.isBoss == true, bankAuth = rank.bankAuth == true }
      end
    end
    out[name] = { label = gang.label, grades = grades }
  end
  return { ok = true, gangs = out }
end)

--- Lifepaths. Flat and string-keyed, so it is returned as it stands: this exact table already
--- crosses the codec on the character roster (`GetCharacters().origins`). Published anyway,
--- because reading it off a roster is not a place a resource should have to look.
---@return { ok: true, origins: table }
exports("GetOrigins", function()
  return { ok = true, origins = OPX.Origins }
end)

--- The core's version, so a satellite can refuse to run against one it does not know.
---@return { ok: true, version: string }
exports("GetVersion", function()
  return { ok = true, version = OPX.VERSION }
end)
