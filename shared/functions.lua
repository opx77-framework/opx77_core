--- Shared helpers: both runtimes, no platform API beyond what OPX.Log wraps.

local Result = OPX.Result

---@param name string
---@return JobDefinition|nil
function OPX.GetJob(name)
  return OPX.Jobs[name]
end

---@param name string
---@return GangDefinition|nil
function OPX.GetGang(name)
  return OPX.Gangs[name]
end

--- Resolves a job and grade into the shape carried on `PlayerData.job`. A Result rather than
--- nil, so the caller can tell "no such job" from "no such grade in that job".
---@param name string
---@param grade integer|string|nil
---@return Result  ok value is a PlayerJob
function OPX.ResolveJob(name, grade)
  local job = OPX.Jobs[name]
  if not job then return Result.err("job.notFound", tostring(name)) end

  grade = tonumber(grade) or 0
  local rank = job.grades[grade]
  if not rank then return Result.err("job.gradeNotFound", ("%s:%s"):format(name, grade)) end

  return Result.ok({
    name = name,
    label = job.label,
    type = job.type,
    payment = rank.payment or 0,
    onDuty = job.defaultDuty == true,
    isBoss = rank.isBoss == true,
    bankAuth = rank.bankAuth == true,
    grade = { name = rank.name, level = grade },
  })
end

---@param name string
---@param grade integer|string|nil
---@return Result  ok value is a PlayerGang
function OPX.ResolveGang(name, grade)
  local gang = OPX.Gangs[name]
  if not gang then return Result.err("gang.notFound", tostring(name)) end

  grade = tonumber(grade) or 0
  local rank = gang.grades[grade]
  if not rank then return Result.err("gang.gradeNotFound", ("%s:%s"):format(name, grade)) end

  return Result.ok({
    name = name,
    label = gang.label,
    isBoss = rank.isBoss == true,
    bankAuth = rank.bankAuth == true,
    grade = { name = rank.name, level = grade },
  })
end

--- Highest grade defined for a group, so a caller can clamp instead of failing.
---@param grades table<integer, JobGrade|GangGrade> contiguous from 0
---@return integer
function OPX.TopGrade(grades)
  local top = 0
  while grades[top + 1] do top = top + 1 end
  return top
end

--- A byte range rather than `%a`, which is ASCII-only and would refuse "Éloïse". \194-\239
--- plus the \128-\191 continuations covers accented Latin, Greek, Cyrillic and CJK; the
--- four-byte lead bytes are left out because that is where emoji live. A literal space, not
--- `%s`, which also matches newline and tab.
local LETTER = "%a\194-\239\128-\191"

OPX.NAME_PATTERN = ("^[%s][%s '%%-]*$"):format(LETTER, LETTER)

--- Validates one half of a character name against the configured bounds.
---@param value any
---@return Result
function OPX.ValidateName(value)
  local bounds = OPX.Config.SHARED.CHARACTERS.NAME
  return OPX.Validate.text(value, {
    min = bounds.MIN,
    max = bounds.MAX,
    pattern = OPX.NAME_PATTERN,
  })
end

--- True when `moneyType` is one this server actually has, resolved against config so an
--- operator who adds a type gets it accepted everywhere.
---@param moneyType any
---@return boolean
function OPX.IsMoneyType(moneyType)
  return OPX.Config.SHARED.MONEY.TYPES[moneyType] ~= nil
end

--- Formats an amount for display: "12 500 €$".
---@param amount number
---@param moneyType? MoneyType anything but EDDIES is shown with its own name
---@return string
function OPX.FormatMoney(amount, moneyType)
  local grouped = OPX.Math.groupDigits(math.floor(amount + 0.5))
  if moneyType == nil or moneyType == "EDDIES" then
    return grouped .. " \u{20AC}$"
  end
  return ("%s %s"):format(grouped, moneyType)
end

local gameTimer

--- Process-monotonic milliseconds. `Open77.time.monotonic()` is the same clock in SECONDS.
---@return integer
function OPX.Now()
  -- resolved on first use, not at load: during boot the global may not be installed yet
  if gameTimer then return gameTimer() end
  local timer = rawget(_G, "GetGameTimer")
  if not timer then return 0 end
  gameTimer = timer
  return timer()
end
