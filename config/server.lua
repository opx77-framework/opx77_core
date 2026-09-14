-- Server-only: nothing here is ever distributed to a client. Numbers an operator may change
-- at runtime are re-declared as tunables in server/tunables.lua, defaulting to these.

OPX.Config.SERVER = {
  AUTOSAVE_SECONDS = 300, -- how often a loaded player is written back; bounds what a crash costs

  MONEY = {
    -- money types that may go below zero; a type not listed has the removal refused rather
    -- than truncated
    ALLOW_NEGATIVE = { BANK = true },

    PAYCHECK_MINUTES = 10, -- minutes between paychecks; zero disables them entirely
    PAYCHECK_REQUIRES_DUTY = true, -- only pay a player who is on duty

    -- which of SHARED.MONEY.TYPES a salary lands in, and the type its toast names; an
    -- unknown name falls back to SHARED.MONEY.DEFAULT with a warning at boot
    PAYCHECK_TYPE = "BANK",
  },

  CHARACTERS = {
    DEFAULT_SLOTS = 3, -- how many characters one account may hold

    -- per-account overrides, keyed by durable userId. `opx77.whois` prints a player's.
    SLOTS_BY_USER = {},

    -- the most rows one account may ever write to `opx77_characters`. A lifetime ceiling,
    -- not a roster size, because a delete is soft: keep it well above DEFAULT_SLOTS.
    ROW_CEILING = 60,

    -- extra tables whose rows go with a character, as `{ TABLE, COLUMN }` pairs matched on
    -- the citizen id. The core's own tables use ON DELETE CASCADE and are not listed.
    CASCADE_TABLES = {},
  },

  ENTRY = {
    -- the liveness interval declared to `Open77.ready.participate`, in ms, clamped by the
    -- host to [1000, 600000]. Not a budget for the player -- see README, "The entry gate".
    GATE_MS = 300000,

    -- the core's own deadline for the whole join sequence, in ms. Below GATE_MS so the core
    -- gives up first and can say why. Also the ceiling of the SELECTION_MS tunable.
    PIPELINE_MS = 240000,

    -- the routing bucket a player waits in while no character is loaded: from connect, and
    -- again after an unload, until a character is placed. See README, "The selection bucket".
    BUCKET = {
      -- one bucket per player, so nobody choosing sees or is seen by anybody. false leaves
      -- everybody in WORLD and moves nobody
      ISOLATE = true,

      -- a player's own bucket is BASE + their player id, up to BASE + 65535. Keep that range
      -- clear of every other resource's buckets: the platform's Deathmatch uses 4100-4287 and
      -- its Race 6500
      BASE = 77000,

      -- where a character goes when its stored position names no bucket, or names one in the
      -- selection range; the shared world is 0
      WORLD = 0,

      POPULATION = false, -- ambient population in a selection bucket
      LOCKDOWN = "relaxed", -- inactive, relaxed, strict or full; false leaves the mode alone
    },
  },

  PLAYER = {
    -- The initial `PlayerData.metadata`, and the four keys the core itself reads. A gameplay
    -- file's own keys merge on top and survive every save; the needs belong to opx77_status.
    STARTING_METADATA = {
      health = 100,
      armor = 0,
      isDead = false,
      inLastStand = false,
    },

    DEFAULT_JOB = "unemployed", -- must exist in data/jobs.lua
    DEFAULT_GANG = "none", -- must exist in data/gangs.lua
  },

  -- resources that would fight the core over where a player stands. The core disables
  -- nothing; it prints once what to do about each. See README, "Placement conflicts".
  CONFLICTING_PLACERS = { "open77_playerstate", "freeroam", "pursuit", "race" },

  -- Who may call the core's server exports. See README, "Server exports".
  EXPORTS = {
    -- the reads -- identity, the change cursor, a vehicle's plate: "*" for any server
    -- resource, or a set such as { opx77_inventory = true }
    READ = "*",

    -- everything else is refused unless the calling resource is listed here with the scope
    -- the export needs. The name is read from the host, never from an argument.
    CALLERS = {
      opx77_inventory = { scopes = { inventory = true } }, -- the container and item tables
    },

    -- the most an answer may weigh encoded, in bytes; the host's budget is 48 KiB with its own
    -- overhead, and an answer past it would reach the caller as an opaque codec refusal
    MAX_RESULT_BYTES = 32768,
  },

  -- Bounds on what the inventory storage exports accept. They guard the tables, not the
  -- gameplay: opx77_inventory decides sizes and weights.
  INVENTORY = {
    MAX_SLOTS = 1000, -- slots one container may have
    MAX_WEIGHT = 4000000000, -- grams; the column is INT UNSIGNED
    MAX_METADATA_BYTES = 4096, -- one stack's metadata, encoded
    PAGE_ROWS = 64, -- stacks one read answers at most, before the size guard trims it

    -- kinds whose owner is another row: a character's citizen id or a vehicle's plate, which
    -- must exist, and whose deletion takes the container with it. Any other kind stands alone.
    LINKED_KINDS = { character = "citizen", trunk = "plate", glovebox = "plate" },
  },
}
