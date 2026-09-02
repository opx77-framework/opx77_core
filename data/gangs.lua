-- Gangs. Same rules as data/jobs.lua: the key is stored on the character row, so add freely
-- and rename never. `none` is the absence of a gang, kept as an entry so nothing handles nil.

OPX.Gangs = {
  none = {
    label = "No affiliation",
    grades = {
      [0] = { name = "Civilian" },
    },
  },

  maelstrom = {
    label = "Maelstrom",
    grades = {
      [0] = { name = "Chromehead" },
      [1] = { name = "Enforcer" },
      [2] = { name = "Cyberpsycho" },
      [3] = { name = "Warlord", isBoss = true, bankAuth = true },
    },
  },

  valentinos = {
    label = "Valentinos",
    grades = {
      [0] = { name = "Novato" },
      [1] = { name = "Soldado" },
      [2] = { name = "Teniente" },
      [3] = { name = "Jefe", isBoss = true, bankAuth = true },
    },
  },

  tygerclaws = {
    label = "Tyger Claws",
    grades = {
      [0] = { name = "Kouhai" },
      [1] = { name = "Senpai" },
      [2] = { name = "Kyodai" },
      [3] = { name = "Oyabun", isBoss = true, bankAuth = true },
    },
  },

  sixthstreet = {
    label = "6th Street",
    grades = {
      [0] = { name = "Recruit" },
      [1] = { name = "Veteran" },
      [2] = { name = "Sergeant" },
      [3] = { name = "Colonel", isBoss = true, bankAuth = true },
    },
  },

  voodooboys = {
    label = "Voodoo Boys",
    grades = {
      [0] = { name = "Initiate" },
      [1] = { name = "Runner" },
      [2] = { name = "Houngan" },
      [3] = { name = "Mambo", isBoss = true, bankAuth = true },
    },
  },

  animals = {
    label = "Animals",
    grades = {
      [0] = { name = "Cub" },
      [1] = { name = "Bruiser" },
      [2] = { name = "Beast" },
      [3] = { name = "Alpha", isBoss = true, bankAuth = true },
    },
  },

  scavengers = {
    label = "Scavengers",
    grades = {
      [0] = { name = "Scav" },
      [1] = { name = "Harvester" },
      [2] = { name = "Ringleader", isBoss = true },
    },
  },

  moxes = {
    label = "The Mox",
    grades = {
      [0] = { name = "Regular" },
      [1] = { name = "Bouncer" },
      [2] = { name = "Matron", isBoss = true, bankAuth = true },
    },
  },

  wraiths = {
    label = "Wraiths",
    grades = {
      [0] = { name = "Raider" },
      [1] = { name = "Outrider" },
      [2] = { name = "Chief", isBoss = true, bankAuth = true },
    },
  },

  barghest = {
    label = "Barghest",
    grades = {
      [0] = { name = "Conscript" },
      [1] = { name = "Trooper" },
      [2] = { name = "Zealot" },
      [3] = { name = "Commander", isBoss = true, bankAuth = true },
    },
  },

  aldecaldos = {
    label = "Aldecaldos",
    grades = {
      [0] = { name = "Kin" },
      [1] = { name = "Rider" },
      [2] = { name = "Elder", isBoss = true, bankAuth = true },
    },
  },
}
