--- @author DemiAutomatic
--- @file server/logger.lua
--- @description The player audit log, written as greppable platform log lines.

OPX.Logger = {}
local Logger = OPX.Logger

--- @author DemiAutomatic
--- @type {table<string, boolean>}
--- @description The severities an entry may carry; anything else reads info.
local SEVERITIES = { debug = true, info = true, warn = true, error = true }

--- @author DemiAutomatic
--- @type {integer}
--- @description Longest message or data text one entry carries, in characters.
local MAX_MESSAGE = 200

--- @author DemiAutomatic
--- @type {integer}
--- @description Window in which repeated identical entries are collapsed.
local DEDUPE_MS = 10000

--- @author DemiAutomatic
--- @type {integer}
--- @description How long a closed window is kept to report its count.
local RETAIN_MS = DEDUPE_MS * 6

--- @author DemiAutomatic
--- @type {table<string, table>}
--- @description Recent entries by key, with their time, count and owner.
local recent = {}

--- @author DemiAutomatic
--- @type {string[]}
--- @description Event prefixes whose info entries are never collapsed.
local LEDGER_PREFIXES = { 'money.', 'character.' }

--- @author DemiAutomatic
--- @method span
--- @description Byte length of the first characters, bounded at four bytes each.
--- @param text {string}
--- @param maximum {integer} Characters to keep.
--- @returns {integer}
local function span(text, maximum)
	local size = math.min(#text, maximum * 4)
	local characters = 0
	for index = 1, size do
		local byte = text:byte(index)
		if byte < 0x80 or byte > 0xBF then
			if characters >= maximum then return index - 1 end
			characters = characters + 1
		end
	end
	return size
end

--- @author DemiAutomatic
--- @method bounded
--- @description Turns a value into text without control characters, truncated.
--- @param value {any}
--- @param maximum {integer} Characters to keep.
--- @returns {string}
local function bounded(value, maximum)
	local text = tostring(value or '')
	text = text:gsub('[%c]', ' ')
	local cut = span(text, maximum)
	if cut < #text then text = text:sub(1, cut) .. '...' end
	return text
end

--- @author DemiAutomatic
--- @method OPX.Logger.safe
--- @description Truncates a value and strips its control characters for logging.
--- @param value {any}
--- @param maximum {integer|nil}
--- @returns {string}
function OPX.Logger.safe(value, maximum)
	return bounded(value, maximum or 64)
end

--- @author DemiAutomatic
--- @method toLine
--- @description Formats an entry as one key=value audit line.
--- @param entry {LogEntry}
--- @returns {string}
local function toLine(entry)
	local parts = {
		('event=%s'):format(entry.event),
		('severity=%s'):format(entry.severity),
	}
	if entry.citizenId then parts[#parts + 1] = ('citizen=%s'):format(entry.citizenId) end
	if entry.userId then parts[#parts + 1] = ('user=%s'):format(entry.userId) end
	if entry.source then parts[#parts + 1] = ('player=%d'):format(entry.source) end
	if entry.message and entry.message ~= '' then
		parts[#parts + 1] = ('message=%q'):format(entry.message)
	end
	if entry.data then
		parts[#parts + 1] = ('data=%s'):format(bounded(json.encode(entry.data), MAX_MESSAGE))
	end
	return table.concat(parts, ' ')
end

--- @author DemiAutomatic
--- @method isLedger
--- @description Answers whether an entry must be written every time.
--- @param entry {LogEntry}
--- @returns {boolean}
local function isLedger(entry)
	if entry.severity ~= 'info' and entry.severity ~= 'debug' then return false end
	for i = 1, #LEDGER_PREFIXES do
		local prefix = LEDGER_PREFIXES[i]
		if entry.event:sub(1, #prefix) == prefix then return true end
	end
	return false
end

--- @author DemiAutomatic
--- @type {integer}
--- @description When the recent entries may next be swept.
local nextSweepAt = 0

--- @author DemiAutomatic
--- @method sweep
--- @description Drops recent entries past their retention, at most once a window.
--- @param now {integer}
local function sweep(now)
	if now < nextSweepAt then return end
	nextSweepAt = now + DEDUPE_MS
	for key, seen in pairs(recent) do
		if now - seen.at >= RETAIN_MS then recent[key] = nil end
	end
end

--- @author DemiAutomatic
--- @method repeated
--- @description Counts an entry and answers whether its window is still open.
--- @param key {string}
--- @param owner {string}
--- @returns {boolean, integer}
local function repeated(key, owner)
	local now = OPX.Now()
	sweep(now)
	local seen = recent[key]
	if seen and now - seen.at < DEDUPE_MS then
		seen.count = seen.count + 1
		return true, seen.count
	end
	local carried = seen and seen.count or 0
	recent[key] = { at = now, count = 0, owner = owner }
	return false, carried
end

--- @author DemiAutomatic
--- @method OPX.Logger.forget
--- @description Forgets the dedupe windows a departing player or character owns.
--- @param source {Source}
--- @param citizenId {CitizenId|nil}
function OPX.Logger.forget(source, citizenId)
	local bySource = tostring(source)
	local byCitizen = citizenId ~= nil and tostring(citizenId) or nil
	for key, seen in pairs(recent) do
		if seen.owner == bySource or (byCitizen and seen.owner == byCitizen) then
			recent[key] = nil
		end
	end
end

--- @author DemiAutomatic
--- @method OPX.Logger.log
--- @description Writes one audit entry, collapsing repeats outside the ledger.
--- @param entry {LogEntry}
function OPX.Logger.log(entry)
	if type(entry) ~= 'table' or type(entry.event) ~= 'string' then return end
	entry.severity = SEVERITIES[entry.severity] and entry.severity or 'info'
	entry.message = entry.message ~= nil and bounded(entry.message, MAX_MESSAGE) or nil

	if not isLedger(entry) then
		local owner = tostring(entry.source or entry.citizenId or '-')
		local again, carried = repeated(entry.event .. '\1' .. owner, owner)
		if again then return end
		if carried > 0 then
			entry.message = ('%s [+%d suppressed]'):format(entry.message or '', carried)
		end
	end

	Open77.log[entry.severity](('[audit] %s'):format(toLine(entry)))
end

--- @author DemiAutomatic
--- @method OPX.Logger.player
--- @description Writes an audit entry attributed to a loaded character.
--- @param player {Player|nil}
--- @param event {string}
--- @param message {string|nil}
--- @param data {table|nil}
function OPX.Logger.player(player, event, message, data)
	local playerData = player and player.PlayerData
	Logger.log({
		event = event,
		message = message,
		data = data,
		source = playerData and playerData.source,
		citizenId = playerData and playerData.citizenId,
		userId = playerData and playerData.userId,
	})
end

--- @author DemiAutomatic
--- @method OPX.Logger.security
--- @description Writes a warn audit entry for a refused or suspicious request.
--- @param event {string}
--- @param message {string|nil}
--- @param data {table|nil}
--- @param source {Source|nil} Who caused it, keying the dedupe window.
function OPX.Logger.security(event, message, data, source)
	Logger.log({ event = event, severity = 'warn', message = message, data = data,
		source = source })
end
