---@meta

--- A job definition by name.
---@param name string
---@return JobDefinition|nil
function OPX.GetJob(name) end

--- A gang definition by name.
---@param name string
---@return GangDefinition|nil
function OPX.GetGang(name) end

--- Resolves a job and grade into the shape carried on `PlayerData.job`. Errors `job.notFound`
--- and `job.gradeNotFound`.
---@param name string
---@param grade integer|string|nil
---@return Result ok value is a PlayerJob
function OPX.ResolveJob(name, grade) end

--- Resolves a gang and grade into the shape carried on `PlayerData.gang`. Errors
--- `gang.notFound` and `gang.gradeNotFound`.
---@param name string
---@param grade integer|string|nil
---@return Result ok value is a PlayerGang
function OPX.ResolveGang(name, grade) end

--- Highest grade defined for a group, so a caller can clamp instead of failing.
---@param grades table<integer, JobGrade|GangGrade> contiguous from 0
---@return integer
function OPX.TopGrade(grades) end

--- The pattern each half of a character name must match: a letter, accented ones included, then
--- letters, spaces, apostrophes and hyphens.
---@type string
OPX.NAME_PATTERN = ''

--- Validates one half of a character name against `SHARED.CHARACTERS.NAME`.
---@param value any
---@return Result
function OPX.ValidateName(value) end

--- True when `moneyType` is one this server actually has.
---@param moneyType any
---@return boolean
function OPX.IsMoneyType(moneyType) end

--- The seven toast positions the platform documents.
---@type table<string, boolean>
OPX.NOTIFY_POSITIONS = {}

--- True when `position` is one of the documented notification positions. Advisory only.
---@param position any
---@return boolean
function OPX.IsNotifyPosition(position) end

--- Formats an amount for display: "12 500 €$", or the type's own name for anything but EDDIES.
---@param amount number
---@param moneyType? MoneyType
---@return string
function OPX.FormatMoney(amount, moneyType) end

--- Process-monotonic milliseconds.
---@return integer
function OPX.Now() end
