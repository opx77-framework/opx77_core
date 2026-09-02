--- The core's public API for satellite client resources. Every export answers a plain
--- `{ ok = boolean, ... }`, never an `OPX.Result`. See README, "Exports".

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

--- A duty check and a grade comparison, which is why this is an export and a plain field read
--- is not.
---@param name string
---@param onDutyOnly? boolean
---@param minGrade? integer read with `tonumber`, so a non-number is absent rather than grade 0
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

--- The stored face for the live character, mirrored. nil for one never captured.
---@return { ok: boolean, appearance?: AppearanceSnapshot, error?: string }
exports("GetAppearance", function()
  if not OPX.IsLoggedIn then return { ok = false, error = "error.notLoggedIn" } end
  return { ok = true, appearance = OPX.GetAppearance() }
end)

-- The selection screen's API. Everything below is a request: the return value says only that
-- it was sent, and the answer arrives on `OPX.Events.Local.PLAYER_LOADED` or `.REFUSED`.

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

-- checked once, at load: it is a config value, it cannot change without a restart, and a UI
-- that asks a hundred times should not get a hundred lines
if not OPX.IsNotifyPosition(OPX.Config.SHARED.NOTIFY_POSITION) then
  Open77.log.warn(("[exports] NOTIFY_POSITION %q is not one of the documented " ..
    "open77_notifications positions"):format(tostring(OPX.Config.SHARED.NOTIFY_POSITION)))
end

--- The configuration a UI legitimately needs, and only that. The static definitions are not
--- here: `GetJobs`, `GetGangs` and `GetOrigins` answer those.
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

--- Static job definitions.
---@return { ok: true, jobs: table }  `grades` is a 1-based array carrying an explicit
---        `level`, not the 0-keyed source table: read `grade.level`, never the array index
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

--- Static gang definitions, same grade shape as `GetJobs`. Gangs carry no payment and no
--- duty: a gang is not an employer.
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

--- Lifepaths.
---@return { ok: true, origins: table }
exports("GetOrigins", function()
  return { ok = true, origins = OPX.Origins }
end)

--- The core's version, so a satellite can refuse to run against one it does not know.
---@return { ok: true, version: string }
exports("GetVersion", function()
  return { ok = true, version = OPX.VERSION }
end)
