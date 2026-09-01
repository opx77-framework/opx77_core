-- Server-only: a plate format and a spawn ceiling are not a client's business.

OPX_VEHICLES = {
  PER_CHARACTER = 8, -- the most vehicles one character may own; 0 for no ceiling
  PLATE_FORMAT = "11AAA111", -- 1 becomes a digit, A a letter, anything else stays as written
  DEFAULT_GARAGE = "impound", -- where a vehicle created with no garage belongs
  SPAWN_OFFSET = 3.0, -- metres to the side of the player a vehicle appears
  DESPAWN_RADIUS = 0.0, -- metres past which an unoccupied vehicle is stored; 0 never does
  SAVE_SECONDS = 120, -- how often the condition of every vehicle that is out is written
}
