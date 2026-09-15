--- @author DemiAutomatic
--- @file shared/functions.lua
--- @description Shared helpers for both runtimes that call no platform API.

--- @author DemiAutomatic
--- @type {table}
--- @description The Result constructors, read through a local.
local Result = OPX.Result

--- @author DemiAutomatic
--- @method OPX.GetJob
--- @description Answers a job definition by name, or nil.
--- @param name {string}
--- @returns {JobDefinition|nil}
function OPX.GetJob(name)
	return OPX.Jobs[name]
end

--- @author DemiAutomatic
--- @method OPX.GetGang
--- @description Answers a gang definition by name, or nil.
--- @param name {string}
--- @returns {GangDefinition|nil}
function OPX.GetGang(name)
	return OPX.Gangs[name]
end

--- @author DemiAutomatic
--- @method OPX.ResolveJob
--- @description Resolves a job and grade into the PlayerData.job shape.
--- @param name {string}
--- @param grade {integer|string|nil}
--- @returns {Result}
function OPX.ResolveJob(name, grade)
	local job = OPX.Jobs[name]
	if not job then return Result.err('job.notFound', tostring(name)) end

	grade = tonumber(grade) or 0
	local rank = job.grades[grade]
	if not rank then return Result.err('job.gradeNotFound', ('%s:%s'):format(name, grade)) end

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

--- @author DemiAutomatic
--- @method OPX.ResolveGang
--- @description Resolves a gang and grade into the PlayerData.gang shape.
--- @param name {string}
--- @param grade {integer|string|nil}
--- @returns {Result}
function OPX.ResolveGang(name, grade)
	local gang = OPX.Gangs[name]
	if not gang then return Result.err('gang.notFound', tostring(name)) end

	grade = tonumber(grade) or 0
	local rank = gang.grades[grade]
	if not rank then return Result.err('gang.gradeNotFound', ('%s:%s'):format(name, grade)) end

	return Result.ok({
		name = name,
		label = gang.label,
		isBoss = rank.isBoss == true,
		bankAuth = rank.bankAuth == true,
		grade = { name = rank.name, level = grade },
	})
end

--- @author DemiAutomatic
--- @method OPX.TopGrade
--- @description Answers the highest grade a contiguous grade table defines.
--- @param grades {table<integer, JobGrade|GangGrade>}
--- @returns {integer}
function OPX.TopGrade(grades)
	local top = 0
	while grades[top + 1] do top = top + 1 end
	return top
end

--- @author DemiAutomatic
--- @type {string}
--- @description Pattern class for a letter, accented ones included.
local LETTER = '%a\194-\239\128-\191'

--- @author DemiAutomatic
--- @type {string}
--- @description The pattern each half of a character name must match.
OPX.NAME_PATTERN = ("^[%s][%s '%%-]*$"):format(LETTER, LETTER)

--- @author DemiAutomatic
--- @method OPX.ValidateName
--- @description Validates one half of a character name against the bounds.
--- @param value {any}
--- @returns {Result}
function OPX.ValidateName(value)
	local bounds = OPX.Config.SHARED.CHARACTERS.NAME
	return OPX.Validate.text(value, {
		min = bounds.MIN,
		max = bounds.MAX,
		pattern = OPX.NAME_PATTERN,
	})
end

--- @author DemiAutomatic
--- @method OPX.IsMoneyType
--- @description Whether a money type exists on this server.
--- @param moneyType {any}
--- @returns {boolean}
function OPX.IsMoneyType(moneyType)
	return OPX.Config.SHARED.MONEY.TYPES[moneyType] ~= nil
end

--- @author DemiAutomatic
--- @type {table<string, boolean>}
--- @description The seven toast positions the platform documents.
OPX.NOTIFY_POSITIONS = {
	middle_left = true,
	top_left = true, top_center = true, top_right = true,
	bottom_left = true, bottom_center = true, bottom_right = true,
}

--- @author DemiAutomatic
--- @method OPX.IsNotifyPosition
--- @description Whether a position is one of the documented toast positions.
--- @param position {any}
--- @returns {boolean}
function OPX.IsNotifyPosition(position)
	return OPX.NOTIFY_POSITIONS[position] == true
end

--- @author DemiAutomatic
--- @method OPX.FormatMoney
--- @description Formats an amount for display with its currency.
--- @param amount {number}
--- @param moneyType {MoneyType|nil}
--- @returns {string}
function OPX.FormatMoney(amount, moneyType)
	local grouped = OPX.Math.groupDigits(math.floor(amount + 0.5))
	if moneyType == nil or moneyType == 'EDDIES' then
		return grouped .. ' \u{20AC}$'
	end
	return ('%s %s'):format(grouped, moneyType)
end

--- @author DemiAutomatic
--- @type {fun(): integer|nil}
--- @description GetGameTimer, once it has been found installed.
local gameTimer

--- @author DemiAutomatic
--- @method OPX.Now
--- @description Answers process-monotonic milliseconds from the host clock.
--- @returns {integer}
function OPX.Now()
	if gameTimer then return gameTimer() end
	local timer = rawget(_G, 'GetGameTimer')
	if not timer then
		local monotonic = Open77 and Open77.time and Open77.time.monotonic
		local seconds = monotonic and monotonic()
		if type(seconds) ~= 'number' then return 0 end
		return math.floor(seconds * 1000)
	end
	gameTimer = timer
	return timer()
end
