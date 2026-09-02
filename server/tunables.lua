--- Numbers an operator may change from the Warden panel while people are playing. Read
--- `OPX.Tune.KEY` at the point of use: a file-scope local freezes for the life of the run.

local Config = OPX.Config.SERVER

local DECLARATION = {
  AUTOSAVE_SECONDS = {
    value = Config.AUTOSAVE_SECONDS,
    type = "integer", min = 30, max = 3600, step = 30, unit = "s", apply = "live",
    label = "Autosave interval", group = "Persistence", order = 1,
    description =
      "How often a loaded character is written back to the database. Saving only on " ..
      "logout is lossy in exactly the cases people care about most -- a crash, a power " ..
      "cut, a server killed rather than stopped -- so this is what bounds how much " ..
      "anyone can lose. Lower costs more database writes.",
  },

  PAYCHECK_MINUTES = {
    value = Config.MONEY.PAYCHECK_MINUTES,
    type = "integer", min = 0, max = 240, step = 1, unit = "min", apply = "live",
    label = "Paycheck interval", group = "Economy", order = 1,
    description =
      "Minutes between paychecks. Zero turns paychecks off entirely without touching " ..
      "the job definitions, so switching it back on resumes the same salaries.",
  },

  PAYCHECK_REQUIRES_DUTY = {
    value = Config.MONEY.PAYCHECK_REQUIRES_DUTY,
    apply = "live",
    label = "Only pay players on duty", group = "Economy", order = 2,
    description =
      "On means a job pays only while its holder is clocked in. Off pays everyone " ..
      "employed, which is what a low-population server usually wants -- a job nobody " ..
      "can clock into on an empty server otherwise pays nothing at all.",
  },

  CHARACTER_SLOTS = {
    value = Config.CHARACTERS.DEFAULT_SLOTS,
    type = "integer", min = 1, max = 20, step = 1, apply = "live",
    label = "Characters per account", group = "Characters", order = 1,
    description =
      "How many characters one account may hold. Lowering this never deletes anything: " ..
      "an account already over the limit keeps every character and simply cannot make " ..
      "another one.",
  },

  CHARACTER_ROWS = {
    value = Config.CHARACTERS.ROW_CEILING,
    type = "integer", min = 5, max = 500, step = 5, apply = "live",
    label = "Character rows per account", group = "Characters", order = 2,
    description =
      "The most rows one account may ever write to opx77_characters. Deleting a character " ..
      "is a soft delete -- the row stays so it can be undone and so a citizen ID is " ..
      "never reissued -- and the slot is freed, so create-and-delete writes a new row " ..
      "every time. This is what stops that being unbounded. Keep it well above " ..
      "\"Characters per account\": it is a ceiling on a lifetime, not on a roster.",
  },

  SELECTION_MS = {
    value = Config.ENTRY.PIPELINE_MS,
    -- ceiling is PIPELINE_MS, below GATE_MS: the core never refreshes its gate hold, so a
    -- longer selection would have the host declare it dead mid-screen
    type = "integer", min = 30000, max = Config.ENTRY.PIPELINE_MS, step = 15000,
    unit = "ms", apply = "live",
    label = "Character selection deadline", group = "Characters", order = 2,
    description =
      "How long a joining player may sit in the character screen before the core gives " ..
      "up and releases the readiness gate without them. The maximum is held below the " ..
      "gate's liveness interval in config/server.lua, so the core always gives up first " ..
      "and can say why rather than being declared dead by the host.",
  },
}

--- The fallback for a host with no tunables support, built from the same declaration so a key
--- cannot exist in one and not the other.
local defaults = {}
for key, entry in pairs(DECLARATION) do defaults[key] = entry.value end

--- A binary predating tunables has no `Open77.tunables` at all. Detected once, here.
local HAS_TUNABLES = type(Open77.tunables) == "table"
  and type(Open77.tunables.declare) == "function"

if HAS_TUNABLES then
  -- declare raises, and that is wanted: better than running on a value the panel cannot set
  OPX.Tune = Open77.tunables.declare(DECLARATION)
else
  OPX.Tune = defaults
  Open77.log.warn("[tunables] this server has no Open77.tunables; using config/server.lua " ..
    "values as fixed")
end

--- Re-reads a value with a floor. The panel enforces min and max, but a host without
--- tunables hands back whatever config/server.lua says.
---@param key string
---@param floor number also the answer for a key with no declaration, so no caller is handed
---        a nil to compare against a number
---@return number
function OPX.TuneNumber(key, floor)
  local value = OPX.Tune[key]
  -- isFinite, not `value ~= value`: an infinity passes a NaN test and freezes an interval
  if not OPX.Math.isFinite(value) then value = defaults[key] end
  if not OPX.Math.isFinite(value) then return floor end
  if floor and value < floor then return floor end
  return value
end
