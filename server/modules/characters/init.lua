--- Accounts and characters.
---
--- The account is the Master-signed `userId`. There is no password and no
--- email: the platform proved who this is before the session became active.

local Result = require("shared.result")
local Validate = require("shared.validate")
local Code = require("shared.code")
local Events = require("shared.events")

local MAX_CHARACTERS = 3

--- Lua patterns are byte-oriented and `%a` is ASCII-only, so `^[%a]...` refused
--- "Éloïse" outright. The allow-list is widened by byte range instead: every
--- byte of a multi-byte UTF-8 character is >= 0x80, so \194-\239 (the two- and
--- three-byte lead bytes) plus \128-\191 (the continuations) covers accented
--- Latin, Greek, Cyrillic and CJK names. Four-byte lead bytes (\240-\244) are
--- left out on purpose: that is where emoji live.
---
--- This is a name field, not a trust boundary -- the boundary is upstream, in
--- `Validate.text`, which has already refused malformed UTF-8 and bounded the
--- length. What is left through is a symbol like U+2764 in a first name, which
--- would need a Unicode category table to catch and is not worth one here.
--- A literal space, not `%s`: that class also matches newline and tab, which
--- the original pattern let through into log lines and into every UI that
--- renders a name.
local LETTER = "%a\194-\239\128-\191"
local NAME = {
  min = 2,
  max = 32,
  pattern = ("^[%s][%s '%%-]*$"):format(LETTER, LETTER),
}

return Synk.module("characters", {
  setup = function(ctx)
    local db, log = ctx.db, ctx.log

    --- One statement, so two connections racing cannot both insert.
    local function ensureAccount(session)
      return db.query([[
        INSERT INTO synk_accounts (user_id, display_name)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE
          display_name = VALUES(display_name),
          last_seen_at = CURRENT_TIMESTAMP
      ]], { session.userId, session.displayName or "unknown" })
    end

    local function fetchRows(userId)
      return db.query([[
        SELECT id, public_code, first_name, last_name, last_played_at
        FROM synk_characters
        WHERE user_id = ? AND deleted_at IS NULL
        ORDER BY last_played_at IS NULL, last_played_at DESC, id ASC
      ]], { userId })
    end

    --- The unique key decides collisions, not a SELECT-then-INSERT: two
    --- players creating in the same tick would both pass that check.
    local function insertWithFreshCode(userId, firstName, lastName)
      for _ = 1, 5 do
        local code = Code.generate()
        local inserted = db.insert([[
          INSERT INTO synk_characters (user_id, public_code, first_name, last_name)
          VALUES (?, ?, ?, ?)
        ]], { userId, code, firstName, lastName })

        if inserted.ok then
          return Result.ok({ id = inserted.value, publicCode = code })
        end
        -- Any other failure is not worth retrying; only a collision is.
        if not tostring(inserted.detail or ""):lower():find("duplicate") then
          return inserted
        end
        log.warn("public code collision, drawing another")
      end
      return Result.err("code-exhausted", "no free public code after 5 attempts")
    end

    local Characters = {}

    --- Characters the account may play.
    function Characters.list(userId)
      local rows = fetchRows(userId)
      if not rows.ok then return rows end

      local out = {}
      local list = rows.value or {}
      for i = 1, #list do
        local row = list[i]
        out[i] = {
          id = row.id,
          publicCode = row.public_code,
          firstName = row.first_name,
          lastName = row.last_name,
          lastPlayedAt = row.last_played_at,
        }
      end
      return Result.ok(out)
    end

    --- Creates one, after validating the names as untrusted input.
    function Characters.create(userId, firstName, lastName)
      local checked = Validate.shape({ firstName = firstName, lastName = lastName }, {
        firstName = function(v) return Validate.text(v, NAME) end,
        lastName = function(v) return Validate.text(v, NAME) end,
      })
      if not checked.ok then return checked end

      local existing = Characters.list(userId)
      if not existing.ok then return existing end
      if #existing.value >= MAX_CHARACTERS then
        return Result.err("limit-reached", tostring(MAX_CHARACTERS))
      end

      return insertWithFreshCode(userId, checked.value.firstName, checked.value.lastName)
    end

    --- The check symbol already rejected the mistypes, so a miss here means
    --- the character genuinely does not exist.
    function Characters.byPublicCode(input)
      local parsed = Code.parse(input)
      if not parsed.ok then return parsed end

      local row = db.single([[
        SELECT id, user_id, public_code, first_name, last_name
        FROM synk_characters
        WHERE public_code = ? AND deleted_at IS NULL
      ]], { parsed.value })
      if not row.ok then return row end
      if not row.value then return Result.err("not-found", parsed.value) end
      return Result.ok(row.value)
    end

    --- Binds a character to a live session, refusing one owned by somebody else.
    function Characters.claim(session, characterId)
      local row = db.single([[
        SELECT id FROM synk_characters
        WHERE id = ? AND user_id = ? AND deleted_at IS NULL
      ]], { characterId, session.userId })
      if not row.ok then return row end
      if not row.value then return Result.err("not-yours") end

      local touched = db.update([[
        UPDATE synk_characters SET last_played_at = CURRENT_TIMESTAMP WHERE id = ?
      ]], { characterId })
      if not touched.ok then return touched end

      ctx.sessions:attachCharacter(session.playerId, characterId)
      TriggerEvent(Events.internal.characterLoaded, session.playerId, characterId)
      return Result.ok(characterId)
    end

    --- Sends the roster but does not wait for a choice: a player reading a
    --- list is no reason to hold every other resource. Selection continues
    --- over net events once the gate opens.
    ctx.entryStep("load-account", function(session)
      local account = ensureAccount(session)
      if not account.ok then return account end

      local characters = Characters.list(session.userId)
      if not characters.ok then return characters end

      TriggerClientEvent(Events.toClient.characters, session.playerId, characters.value)
      log.info(("%s has %d character(s)"):format(session.userId, #characters.value))
      return Result.ok(true)
    end)

    return Characters
  end,
})
