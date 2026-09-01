--- The core's public API for satellite client resources. Reads only: writes go over
--- `opx77:server:*` net events, where the server validates them.
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

--- A grade comparison, which is why this is an export and a plain field read is not.
---@param name string
---@param onDutyOnly? boolean
---@return { ok: true, result: boolean }
exports("HasJob", function(name, onDutyOnly)
  return { ok = true, result = OPX.HasJob(name, onDutyOnly == true) }
end)

---@param name string
---@return { ok: true, result: boolean }
exports("HasGang", function(name)
  return { ok = true, result = OPX.HasGang(name) }
end)

-- The selection screen's API. Everything here is a request: the server answers on
-- `opx77:client:playerLoaded` or refuses on `opx77:client:notify`, so a caller watches those
-- rather than the return value, which only says the request was sent.

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

--- The configuration a UI legitimately needs, and only that -- not `OPX.Config` wholesale.
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
