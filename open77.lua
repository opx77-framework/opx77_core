resource "opx77_core"
version "0.2.0"
open77_version ">=0.0.1"
auto_start true

reload_policy "local" -- a reload is a script reload, not a reconnect: both halves rebuild

-- No dependencies declared: a declared dependency is hard, and this core must install on a
-- bare server. open77_appearance and open77_playerstate are consulted through the host.

-- The OPX namespace. shared/main.lua creates it, the files below fill it in.
-- Order inside this block is dependency order.
shared_script "shared/main.lua"
shared_script "shared/result.lua"
shared_script "shared/table.lua"
shared_script "shared/string.lua"
shared_script "shared/math.lua"
shared_script "shared/log.lua"
shared_script "shared/validate.lua"
shared_script "shared/hooks.lua"

-- Configuration. The only files a server owner edits.
shared_script "config/shared.lua" -- shipped to every client: never put a secret in it
server_script "config/server.lua"
server_script "config/vehicles.lua"
client_script "config/client.lua"

-- Static data. Definitions, not settings: changing one renames things players already hold.
shared_script "data/jobs.lua"
shared_script "data/gangs.lua"
shared_script "data/origins.lua"

shared_script "shared/locale.lua"
shared_script "locales/en.lua" -- registered right after the catalogue, so no file below calls
shared_script "locales/fr.lua" -- locale() against an empty one
shared_script "shared/citizenid.lua"
shared_script "shared/functions.lua"

server_script "server/tunables.lua"
server_script "server/storage/main.lua"
server_script "server/storage/schema.lua"
server_script "server/storage/players.lua"
server_script "server/storage/vehicles.lua"
server_script "server/logger.lua" -- after storage, because it writes through it
server_script "server/main.lua"
server_script "server/functions.lua" -- the getters: every file below reaches for OPX.GetPlayer
server_script "server/player.lua"
server_script "server/groups.lua" -- after player.lua: a group change writes through the Player
server_script "server/character.lua"
server_script "server/lifecycle.lua" -- after character.lua: the gate releases by loading one
server_script "server/needs.lua" -- after player.lua: it writes through SetMetaData
server_script "server/vehicles.lua" -- after character.lua: ownership reads PlayerData
server_script "server/events.lua"
server_script "server/commands.lua"
server_script "server/loops.lua"

client_script "client/main.lua"
client_script "client/functions.lua"
client_script "client/character.lua"
client_script "client/events.lua"
client_script "client/loops.lua"
client_script "client/exports.lua" -- last: publishing the surface claims everything it reads

permissions {
  "network.events", -- RegisterNetEvent and TriggerClientEvent; local.events is not needed

  -- Open77.database. Safe on a server with no database: OPX.Storage degrades to one logged
  -- line and a refusal to log anybody in.
  "database.access",

  -- Acting server-side on a client that is not incarnated crashes that client, and the gate
  -- can open on a timeout with the player holding no puppet.
  "players.life.read",

  -- Placement is kill -> respawn, never a transform write: respawn carries the fade and the
  -- streaming preload that a teleport skips.
  "players.life.kill",
  "players.life.respawn",

  -- the recovery for a placement that killed and then could not respawn: without it a failed
  -- respawn leaves the player dead with nothing in this resource able to undo it
  "players.life.revive",

  "players.damage.apply", -- armour is re-applied after respawn; nothing here reads it back

  -- Spawning a character's own car, and writing back what happened to it. The runtime id is
  -- not durable -- a reload removes every vehicle this resource owns -- so the plate is.
  "world.vehicles",

  -- Deliberately not requested: world.props, world.elevators, combat.config,
  -- players.damage.read, players.disconnect.
}
