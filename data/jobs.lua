-- Jobs. Definitions, not settings: the key is stored on the character row, so add freely and
-- rename never. Grades are keyed from 0 and must be contiguous.

OPX.Jobs = {
  unemployed = {
    label = "Unemployed",
    defaultDuty = true, -- nothing to clock into, so its tiny paycheck needs no shift
    offDutyPay = true,
    grades = {
      [0] = { name = "Freelancer", payment = 25 },
    },
  },

  merc = {
    label = "Mercenary",
    type = "merc",
    defaultDuty = true,
    offDutyPay = false,
    grades = {
      [0] = { name = "Street Merc", payment = 120 },
      [1] = { name = "Solo", payment = 220 },
      [2] = { name = "Edgerunner", payment = 380 },
      [3] = { name = "Legend", payment = 600, isBoss = true },
    },
  },

  fixer = {
    label = "Fixer",
    type = "fixer",
    defaultDuty = true,
    offDutyPay = false,
    grades = {
      [0] = { name = "Runner", payment = 100 },
      [1] = { name = "Broker", payment = 260 },
      [2] = { name = "Fixer", payment = 500, isBoss = true, bankAuth = true },
    },
  },

  ripperdoc = {
    label = "Ripperdoc",
    type = "medical",
    defaultDuty = false,
    offDutyPay = false,
    grades = {
      [0] = { name = "Apprentice", payment = 140 },
      [1] = { name = "Ripperdoc", payment = 300 },
      [2] = { name = "Chrome Surgeon", payment = 520, isBoss = true, bankAuth = true },
    },
  },

  netrunner = {
    label = "Netrunner",
    type = "tech",
    defaultDuty = false,
    offDutyPay = false,
    grades = {
      [0] = { name = "Script Kiddie", payment = 110 },
      [1] = { name = "Netrunner", payment = 280 },
      [2] = { name = "Blackwall Diver", payment = 540, isBoss = true },
    },
  },

  trauma = {
    label = "Trauma Team",
    type = "medical",
    defaultDuty = false,
    offDutyPay = true,
    grades = {
      [0] = { name = "Paramedic", payment = 180 },
      [1] = { name = "Trauma Specialist", payment = 320 },
      [2] = { name = "Team Lead", payment = 480 },
      [3] = { name = "Regional Director", payment = 700, isBoss = true, bankAuth = true },
    },
  },

  ncpd = {
    label = "NCPD",
    type = "leo",
    defaultDuty = false,
    offDutyPay = true,
    grades = {
      [0] = { name = "Cadet", payment = 150 },
      [1] = { name = "Officer", payment = 260 },
      [2] = { name = "Detective", payment = 400 },
      [3] = { name = "Captain", payment = 620, isBoss = true, bankAuth = true },
    },
  },

  maxtac = {
    label = "MaxTac",
    type = "leo",
    defaultDuty = false,
    offDutyPay = true,
    grades = {
      [0] = { name = "Operator", payment = 460 },
      [1] = { name = "Squad Lead", payment = 720, isBoss = true },
    },
  },

  arasaka = {
    label = "Arasaka",
    type = "corpo",
    defaultDuty = false,
    offDutyPay = true,
    grades = {
      [0] = { name = "Junior Analyst", payment = 200 },
      [1] = { name = "Field Agent", payment = 380 },
      [2] = { name = "Counterintel", payment = 600 },
      [3] = { name = "Executive", payment = 950, isBoss = true, bankAuth = true },
    },
  },

  militech = {
    label = "Militech",
    type = "corpo",
    defaultDuty = false,
    offDutyPay = true,
    grades = {
      [0] = { name = "Contractor", payment = 200 },
      [1] = { name = "Operative", payment = 380 },
      [2] = { name = "Handler", payment = 600 },
      [3] = { name = "Executive", payment = 950, isBoss = true, bankAuth = true },
    },
  },

  cabbie = {
    label = "Delamain Driver",
    type = "transport",
    defaultDuty = true,
    offDutyPay = false,
    grades = {
      [0] = { name = "Driver", payment = 90 },
      [1] = { name = "Dispatcher", payment = 180, isBoss = true },
    },
  },

  bartender = {
    label = "Bartender",
    type = "service",
    defaultDuty = true,
    offDutyPay = false,
    grades = {
      [0] = { name = "Barback", payment = 70 },
      [1] = { name = "Bartender", payment = 140 },
      [2] = { name = "Owner", payment = 260, isBoss = true, bankAuth = true },
    },
  },
}
