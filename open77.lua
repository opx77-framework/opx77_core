--- @author DemiAutomatic
--- @file open77.lua
--- @description Resource manifest declaring scripts, permissions and reload policy.

resource "opx77_core"
version "0.6.0"
open77_version ">=0.0.1"
auto_start true

reload_policy "local"

shared_script "shared/main.lua"
shared_script "shared/result.lua"
shared_script "shared/table.lua"
shared_script "shared/string.lua"
shared_script "shared/math.lua"
shared_script "shared/validate.lua"
shared_script "shared/hooks.lua"

shared_script "config/shared.lua"
server_script "config/server.lua"
server_script "config/vehicles.lua"
client_script "config/client.lua"

shared_script "data/jobs.lua"
shared_script "data/gangs.lua"
shared_script "data/origins.lua"

shared_script "shared/locale.lua"
shared_script "locales/en.lua"
shared_script "locales/fr.lua"
shared_script "shared/citizenid.lua"
shared_script "shared/functions.lua"

server_script "server/tunables.lua"
server_script "server/storage/main.lua"
server_script "server/storage/schema.lua"
server_script "server/storage/players.lua"
server_script "server/storage/vehicles.lua"
server_script "server/storage/inventories.lua"
server_script "server/logger.lua"
server_script "server/main.lua"
server_script "server/functions.lua"
server_script "server/buckets.lua"
server_script "server/player.lua"
server_script "server/groups.lua"
server_script "server/character.lua"
server_script "server/lifecycle.lua"
server_script "server/appearance.lua"
server_script "server/clothing.lua"
server_script "server/vehicles.lua"
server_script "server/events.lua"
server_script "server/commands.lua"
server_script "server/loops.lua"
server_script "server/exports.lua"

client_script "client/main.lua"
client_script "client/functions.lua"
client_script "client/character.lua"
client_script "client/events.lua"
client_script "client/loops.lua"
client_script "client/exports.lua"

permissions {
  "network.events",

  "database.access",

  "players.life.read",

  "players.life.kill",
  "players.life.respawn",
  "players.life.revive",

  "players.damage.apply",
  "world.vehicles",

  "acl.read",
}
