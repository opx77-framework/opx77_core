-- Server-only: nothing here is ever distributed to a client. Numbers an operator might change
-- at runtime are re-declared as tunables in server/tunables.lua; the values below stay the
-- default and the source of truth for a host with no tunables support.

OPX.Config.SERVER = {
  AUTOSAVE_SECONDS = 300, -- how often a loaded player is written back; bounds what a crash costs

  MONEY = {
    -- money types that may go below zero. A type not listed is clamped at zero and the
    -- removal refused rather than truncated. BANK only: an overdraft is a feature, carried
    -- cash going negative never is.
    ALLOW_NEGATIVE = { BANK = true },

    PAYCHECK_MINUTES = 10, -- minutes between paychecks; zero disables them entirely
    PAYCHECK_REQUIRES_DUTY = true, -- only pay a player who is on duty
  },

  --- Hunger and thirst. opx77_hud draws them; opx77_status owns the effect strip and not
  --- these, because these are character metadata and only this VM holds it.
  NEEDS = {
    TICK_SECONDS = 300, -- how often they fall
    DAMAGE_AT_ZERO = 2, -- health lost per tick per empty need; 0 to make them cosmetic
    hunger = { PER_TICK = 1.0 },
    thirst = { PER_TICK = 1.4 }, -- thirst outruns hunger, as in every survival system
  },

  --- An easter egg: `/dop` pays once per ACCOUNT, ever. Set REWARD to 0 to turn it off.
  EASTER_EGG = {
    COMMAND = "dop", -- the command name, or false to register none
    REWARD = 20, -- eddies, paid the first time and never again
  },

  CHARACTERS = {
    DEFAULT_SLOTS = 3, -- how many characters one account may hold

    -- per-account overrides, keyed by durable userId. `opx77.whois` prints a player's.
    SLOTS_BY_USER = {},

    -- the most rows one account may ever write to `opx77_players`. Deleting is a soft delete
    -- that frees the slot but keeps the row, so this is a lifetime ceiling, not a roster
    -- size: keep it well above DEFAULT_SLOTS.
    ROW_CEILING = 60,

    -- tables whose rows are deleted with a character, as `{ TABLE, COLUMN }` pairs matched
    -- against the citizen id. For gameplay files added to this resource; the core's own
    -- tables use ON DELETE CASCADE.
    CASCADE_TABLES = {},
  },

  ENTRY = {
    -- how long the core holds the readiness gate for a joining player, in ms. This is what is
    -- declared to `Open77.ready.participate`; at the deadline the host opens the gate itself.
    GATE_MS = 300000,

    -- the core's own deadline for the whole join sequence, in ms. Below GATE_MS so the core
    -- gives up first and can say why.
    PIPELINE_MS = 240000,
  },

  PLAYER = {
    -- what a brand new character starts with. Becomes the initial `PlayerData.metadata`;
    -- anything a gameplay file adds later is merged on top and survives every save.
    -- opx77_status owns hunger and thirst from here on: it decays them and applies what
    -- running out costs. This file only says where a new character starts.
    STARTING_METADATA = {
      health = 100,
      armor = 0,
      stamina = 100,
      hunger = 100,
      thirst = 100,
      streetCred = 0, -- nothing in the core spends it; an agreed name for gameplay files
      isDead = false,
      inLastStand = false,
    },

    DEFAULT_JOB = "unemployed", -- must exist in data/jobs.lua
    DEFAULT_GANG = "none", -- must exist in data/gangs.lua
  },


  -- resources that would fight the core over where a player stands. The core disables
  -- nothing: it checks GetResourceState at boot and prints, once, what to do about each.
  --   open77_playerstate  stop it, or add opx77_core to its `spawnOwners` tunable
  --   freeroam            turn `forceOnJoin` off
  --   pursuit, race       round-based gamemodes; two gamemodes on the same players is a bug
  CONFLICTING_PLACERS = { "open77_playerstate", "freeroam", "pursuit", "race" },
}
