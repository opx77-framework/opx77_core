# opx77_core

> [!WARNING]
> **This project is currently in early development and is not considered production-ready.**
>
> The API, architecture, features, and internal systems are subject to change at any time
> without prior notice. Breaking changes may be introduced as development progresses.
>
> **Do not rely on the current API for production resources yet.**

The core resource of **OPX//77** for the Open77 platform. It owns everything durable about a
character — the schema, every write, and the events that publish the result. A satellite draws
and reacts; it does not persist anything of its own and does not own a table.

Why the code is written the way it is — load order, permissions, invariants, known limits — is in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) (in French).

## Features

- Character creation, selection and deletion, with a per-account slot limit
- Multi-job and multi-gang membership, with grades and duty state
- Money, metadata, appearance and stored position, autosaved and written on departure
- The clothing a character wears, written when it changes and put back on at the next login
- Readiness-gate integration, so nothing places a player before the core has chosen where
- A routing bucket of their own for every player without a character, so nobody choosing one
  sees or is seen by anybody else
- Live tunables, editable from the operator panel without a restart
- Export-based API: reads for client resources, and identity, a change cursor and the inventory
  storage for server resources
- Locales, with every refusal answered as a key a satellite can render

## The schema

One file per table in [`sql/`](sql/), which is where an operator reads it:

| File | Table |
|---|---|
| `sql/users.sql` | `opx77_users` — one Master account |
| `sql/characters.sql` | `opx77_characters` — one character, keyed on `citizen_id` |
| `sql/character_groups.sql` | `opx77_character_groups` — job and gang memberships |
| `sql/vehicles.sql` | `opx77_vehicles` — owned vehicles, keyed on the plate |
| `sql/inventories.sql` | `opx77_inventories` — one container: a bag, a stash, a vehicle's trunk or glovebox |
| `sql/inventory_items.sql` | `opx77_inventory_items` — one item stack in one slot of one container |
| `sql/character_clothing.sql` | `opx77_character_clothing` — what one character wears |

`server/storage/schema.lua` carries the same statements and applies them at boot. **The two
are edited together.** The Open77 *server* runtime installs no file-reading API — `Open77.resource`
is `{ name, state }` and the sandbox removes `io`, `os` and `loadfile` — so the migration runner
cannot load `sql/` itself; a `.sql` file is not a script a manifest can list either.

The runner keys on the migration name and skips one a database already has. `sql/` and the Lua
long strings are byte-identical apart from the trailing `;` and the file's header comment:
`schema.lua` is what runs, `sql/` is what an operator reads, and neither is generated from the
other. `python3 tools/check_sql_parity.py` proves it and exits non-zero when the two drift.

A migration marked `optional` does not stop the boot when it fails: the runner logs the failure
and what goes without it, does not record it, and tries it again at the next start. Only
`0007_character_clothing` is optional — a look is not worth locking every player out for.

`opx77_characters` carries one nullable JSON column beyond the obvious ones: `appearance`, the
character's face, written only by `server/appearance.lua`. It travels inside `PlayerData` and is
therefore in every event the core publishes.

The two inventory tables hold what `opx77_inventory` decides and nothing the core reads itself.
A container is unique on `(kind, owner)`. A character's bag (`kind = "character"`) carries its
citizen id, and a vehicle's trunk or glovebox its plate, each under a cascading foreign key: the
container goes when that row is really deleted. Deleting a character is soft, so its bag stays,
exactly as its vehicles and memberships do, and nobody can open it while the character is
deleted. A stash has neither column and stands alone. `slots` and `max_weight` (grams) are the
size a container was created with. Every stack is one row keyed on `(inventory_id, slot)`, and a
save rewrites a container's rows in one transaction. The core touches these tables only through
the storage exports below; see `opx77_inventory` for everything they mean.

`opx77_character_clothing` holds one JSON document per character, written only by
`server/clothing.lua`: the nine equipment slots, the seven wardrobe outfits and the active one,
in the shape the platform's own presentation service stores. It is a table of its own rather
than a column beside `appearance`, so a database without it still loads every character and the
autosave that rewrites a character row never rewrites what it wears. It is read at login into
`PlayerData.clothing` — the record, `false` when none is stored, or absent when it could not be
read, which nothing dresses or overwrites. A character's delete is soft, so its row stays; the
foreign key cascades when the character row is really deleted.

**A database from before this version cannot be upgraded in place.** The table renames
(`opx77_accounts` → `opx77_users`, `opx77_players` → `opx77_characters`,
`opx77_player_groups` → `opx77_character_groups`) were made inside migrations 0001–0004 rather
than added as new ones, so a database created earlier keeps the old tables while the code
queries the new names. Drop it and let the runner recreate it: there is no automatic migration
path and none is planned.

## Commands

Every command is registered with `RegisterCommand`'s restricted flag, so the host resolves
`command.<name>` against the caller's ACL **before this resource runs at all**. The four a
player uses are open and take a cooldown instead.

| Command | Gated |
|---|---|
| `opx77.characters` | open — list your own characters |
| `opx77.select` | open — enter the world as one of them |
| `opx77.create` | open — create one |
| `opx77.delete` | open — soft-delete one |
| `opx77.duty` | open — clock in or out |
| `opx77` | ACL — who is in the world, and the boot state |
| `opx77.where` / `opx77.whois` / `opx77.here` | ACL — diagnostics; the reports are English only |
| `opx77.money` / `opx77.job` / `opx77.gang` | ACL — staff edits, audited |
| `opx77.group` | ACL — the members of a job or gang |
| `opx77.save` | ACL — write every loaded character back now |

Every one of them is offered in the chat's autocomplete with its arguments and a line of help
for each, from `locales/`, when the chat announces itself with `chat:ready`. An ACL command is
offered only to a player the ACL grants it, read with `Open77.acl.isAllowed` — the one reason
the manifest declares `acl.read`. A host without that reader offers the open five alone.

A command answers what it did as a toast and what it reads as a chat line. Selecting, creating
or deleting a character, clocking in, a money, job or gang edit and a save answer with a toast
through `opx77_notify`, raised by the core's client half at `NOTIFY_POSITION`: a success, a
warning for a usage, an unknown player or a command run again too fast, an error when it could
not be done. `opx77`, `opx77.where`, `opx77.whois`, `opx77.here`, `opx77.characters` and
`opx77.group` are reports someone asked to read — lists, a dump, a config block to copy — so
they are a chat line, sent with `chat:addMessage`; their bodies stay English where the table
says so. Neither goes on `open77:command:result`, whose accepted answers `opx77_chat` does not
print. `opx77_notify` stays optional: while it is not running a toast is the chat line it
replaced, and the client log says so once. The console reads every answer as a printed line.

## Exports

### Client exports

For client resources. There is no `exports.<resource>:<name>()` proxy — the call is
`Open77.exports.call(resource, name, ...)`, it is always asynchronous, and every export answers
`{ ok = boolean, ... }`.

| Export | Answers |
|---|---|
| `GetPlayerData` | the whole loaded character |
| `IsLoggedIn` | whether a character is loaded |
| `HasJob(name, onDutyOnly?, minGrade?)` | job membership, with an optional duty flag and minimum grade |
| `HasGang(name, minGrade?)` | gang membership, with an optional minimum grade — no duty flag, a gang has no shifts |
| `GetAppearance` | the stored face for the live character, or nil |
| `GetClothing` | the stored clothing for the live character: a record, `false` for none stored, or nil |
| `GetJobs` / `GetGangs` / `GetOrigins` | the static definitions, with grades as a 1-based array carrying an explicit `level` |
| `GetVersion` | the core's version, for a compatibility check |
| `GetSharedConfig` | server name, locale in force, money types and default, character name bounds, notification position |
| `Locale` | one rendered line for a refusal code |
| `GetCharacters` | the roster last sent to this client |
| `RequestCharacters` | ask for it again |
| `SelectCharacter` / `CreateCharacter` / `DeleteCharacter` | the character screen |

The last four are requests, not reads: they fire an `opx77:server:*` net event and answer only
that it was sent. The result arrives on the events below.

### Server exports

For server resources, from `server/exports.lua`, with the same call and the same answer shape.
The caller is read from the host with `GetInvokingResource()`, never from an argument, and every
argument is checked whoever sent it. Call them from a `CreateThread`, an event handler or a
command handler, never at file scope, and keep the promise until it is awaited. Every export
answers `core.booting` until the boot thread has settled the schema.

Reads go to the resources `EXPORTS.READ` names, every server resource by default. Everything
else needs its caller listed in `EXPORTS.CALLERS` with the export's scope, and a refusal is an
`export.denied` security line naming the caller. An answer heavier than
`EXPORTS.MAX_RESULT_BYTES` encoded is refused with `export.tooLarge` rather than reaching the
caller as a codec error.

| Export | Scope | Answers |
|---|---|---|
| `GetVersion()` | read | `version`, `exports` (the contract number, bumped on a breaking change), and the `scopes` this caller holds |
| `GetIdentity(target)` | read | `source`, `userId`, `citizenId`, `online`, `loaded`, `gateHeld`, `released`. A player id is online only; a citizen id is also found offline |
| `GetVehiclePlate(vehicleId)` | read | `plate` and `citizenId` of an owned vehicle the core spawned, absent for any other |
| `GetChanges(since)` | read | `cursor`, `reset`, `more`, `generation`, and at most 16 `events` of kind `loaded`, `unloaded` or `deleted`, each with `source` and `citizenId` |
| `InventoryEnsure(kind, owner, { slots, maxWeight })` | `inventory` | `id`, `slots`, `maxWeight`, `created`. The size is used only when it creates |
| `InventoryRead(id, after?)` | `inventory` | one page of `items` (`slot`, `name`, `count`, `metadata`) after slot `after`, the header on the first page, and `nextAfter` while there may be more |
| `InventoryStage(token, id, rows)` | `inventory` | appends stacks to a save staged under `token`; the first stage of a container empties it |
| `InventoryCommit(token)` | `inventory` | writes everything staged under `token` as one transaction |
| `InventoryResize(id, slots, maxWeight)` | `inventory` | `ok` |
| `InventoryDelete(id)` | `inventory` | `ok`; the stacks go by cascade |
| `InventoryHolders(name, limit?)` | `inventory` | `holders`: container `id`, `kind`, `owner`, `slot`, `count`, largest first, at most 50 |

`GetChanges` is a cursor, not a callback bus: server VMs cannot hear each other's events. Start
from `0`, keep the `cursor` each answer gives, and treat `reset = true` as "the core reloaded or
the ring moved past you": re-read whatever you keep rather than trusting the events alone. The
ring holds the last 512 changes.

A save is staged across calls because one argument carries at most 48 KiB. Stage every
container of a batch under one token, then commit it; a token nobody commits is forgotten after
30 seconds, and a failed commit writes nothing. `InventoryEnsure` on a `character` kind checks
that a living character carries the citizen id, and on `trunk` or `glovebox` that the plate is
owned, answering `inventory.noOwner` otherwise.

```lua
CreateThread(function()
  local promise, reason = Open77.exports.call("opx77_core", "GetIdentity", playerId)
  if not promise then return print("not dispatched: " .. tostring(reason)) end
  local answer, callError = promise:await()
  if callError then return print("call failed: " .. tostring(callError)) end
  if not answer.ok then return print("refused: " .. tostring(answer.error)) end
  print(answer.citizenId, answer.loaded)
end)
```

A reload of the core rejects calls in flight with `export_resource_stopped`, and a call may have
written before it timed out. The inventory writes are safe to retry: a commit rewrites a
container whole.

## Events

The core publishes its state on two channels, both listed in `shared/main.lua` under
`OPX.Events`. A satellite picks one. No name appears on both: this platform's dispatcher
matches an event by name and ignores the network flag, so a local re-emission reusing its own
wire name would re-enter the handler that fired it.

| Channel | Table | How to listen | Permission |
|---|---|---|---|
| networked | `OPX.Events.Client` | `RegisterNetEvent` | `network.events` |
| local | `OPX.Events.Local` | `AddEventHandler` | none |

The local channel is fired by the core's own client half straight after it has updated its
mirror, so a handler can call `GetPlayerData` and see the change that woke it. The client's
local event bus is host-wide, so it reaches any resource.

| Local event | Fired when |
|---|---|
| `opx77:client:charactersReady` | the roster arrived |
| `opx77:client:onPlayerLoaded` | a character entered the world |
| `opx77:client:onPlayerUnloaded` | the character left |
| `opx77:client:playerDataChanged` | any field of `PlayerData` changed |
| `opx77:client:moneyChanged` | a balance moved |
| `opx77:client:jobChanged` / `opx77:client:gangChanged` | a group or grade changed |
| `opx77:client:appearanceSaved` | the core stored a new face; carries the snapshot |
| `opx77:client:clothingSaved` | the core stored new clothing; carries the record |
| `opx77:client:refused` | the server refused something: `(code, kind, operation)` |

### Refusals

`opx77:client:refused` carries three arguments — a `code`, a `kind`, and the `operation` the
refusal answers. The `operation` is one of `OPX.Operations` (`entry`, `ready`,
`selectCharacter`, `createCharacter`, `deleteCharacter`, `saveAppearance`, `saveClothing`,
`spawnVehicle`, `storeVehicle`), named after the `opx77:server:*` request that starts it. A
client waiting on one of several requests must branch on it: `error.tooFast` is raised by all of
them, and without the operation a satellite cannot tell whose answer arrived. A handler that only reads
`code` keeps working — the field was added after `code` and `kind`.

The `code` is always a key the core's catalogue carries. A refusal whose underlying cause has
no entry — a storage failure answering `query-failed`, a validator answering `too-short` — is
logged with its real code and sent as `error.unavailable`, so `locale(code)` never renders a
raw code at a player.

### Writing to the core

A satellite that needs something written for a player sends a net event **from its client
half** to a name the core's server half has registered: only a net event carries the
authenticated `source`. What the server exports above offer is the other road, for a server
resource acting on its own authority.

| Server event | Payload | Effect |
|---|---|---|
| `opx77:server:ready` | none | re-sends the roster, or `playerLoaded` if one is already in |
| `opx77:server:selectCharacter` | `{ citizenId }` | enters the world as that character |
| `opx77:server:createCharacter` | `{ firstName, lastName, origin, gender, birthDate }` | creates one |
| `opx77:server:deleteCharacter` | `{ citizenId }` | soft-deletes one |
| `opx77:server:reportPosition` | `{ heading }` | a heading hint; x/y/z are re-derived server-side |
| `opx77:server:saveAppearance` | `{ snapshot }` | validates and stores a captured face |
| `opx77:server:saveClothing` | `{ citizenId, clothing }` | validates and stores what the character wears |
| `opx77:server:spawnVehicle` / `opx77:server:storeVehicle` | `{ plate }` | brings a car out, or puts it away |

`opx77:server:saveAppearance` takes a canonical snapshot: `schemaVersion = 1`, a `gameBuild`
listed in `APPEARANCE.GAME_BUILDS`, a 64-hex `catalogDigest`, a `gender` engine hash
(`0x` + 16 hex), and a dense `options` array of 1–256 `{ part, name, value, choices }` entries.
Anything else is refused with `appearance.invalid` and a code naming the field.

`opx77:server:saveClothing` takes `clothing = { schemaVersion = 1, equipment, wardrobe }`:
`equipment` names only the nine slots (`Head`, `Face`, `InnerChest`, `OuterChest`, `Legs`,
`Feet`, `Outfit`, `UnderwearTop`, `UnderwearBottom`), each a record name of 1–160 letters,
digits, `_`, `.` or `-`, or `false`; `wardrobe` is `{ active, outfits }`, `active` an integer 0–6
or absent, `outfits` at most seven keyed `0`–`6`, each overriding only the seven visible slots.
Anything else is refused with `clothing.invalid`, a document over 16 KiB encoded with
`clothing.tooLarge`. The row written is the connection's character: `citizenId` never selects
it, and a save naming another one — captured before a character switch — is refused with
`clothing.stale`. A character whose stored clothing could not be read at login answers
`error.unavailable` rather than overwriting it unseen. The cooldown is 2000 ms, on its own key.

## For a server plug-in

A file added to `server/` and one line in `open77.lua` runs in the core's own Lua state, where
`OPX` is simply in scope. The surfaces a plug-in should use rather than writing `PlayerData`
directly:

| Call | Does |
|---|---|
| `OPX.AddMoney` / `RemoveMoney` / `SetMoney` / `GetMoney` | balances, hooked and audited |
| `OPX.SetMetadata` / `GetMetadata` | free-form character state |
| `OPX.SetJob` / `SetGang` / `AddPlayerToJob` / `RemovePlayerFromJob` and the gang equivalents | memberships |
| `OPX.SaveAppearance` / `GetAppearance` | the character's face |
| `OPX.SaveClothing` / `GetClothing` | what the character wears |
| `OPX.Storage.Players.*` | the statements, if a plug-in genuinely needs its own read |
| `OPX.Hooks.register` | veto a money movement or a paycheck before it lands |

`PlayerData.metadata` is a free-form bag, and the core keeps its own `health`, `armor`, `isDead`
and `inLastStand` in it. The gameplay needs — hunger, thirst, stamina, ram, street cred — are
`opx77_status`'s, not the core's.

## Configuration

| File | Scope |
|---|---|
| `config/shared.lua` | values both sides need — never put a secret in it |
| `config/server.lua` | slots, autosave, paychecks, entry deadlines, the selection bucket, starting metadata, who may call the server exports, and the inventory storage bounds |
| `config/vehicles.lua` | plate format and spawn ceiling, server-only |
| `config/client.lua` | client cadences — **never loaded by the server VM** |

Every file lives on `OPX.Config` — `SHARED`, `SERVER`, `VEHICLES`, `CLIENT`. `SHARED.LOCALE`
sets the language of everything a player reads; server logs stay English.
`SERVER.MONEY.PAYCHECK_TYPE` names which of `SHARED.MONEY.TYPES` a salary lands in, and the
paycheck toast names it too; a value that is not a money type falls back to
`SHARED.MONEY.DEFAULT` with a warning at boot.

Anything an operator may want to change mid-session is a tunable instead, in
`server/tunables.lua`. Logging level is not configured here: the host owns it, and the core
calls `Open77.log` directly.

`config/shared.lua` is shipped to every client in the signed resource set, so everything in it
is public: credentials, webhooks and admin identifiers belong in `config/server.lua`.
`config/client.lua` is not authoritative either: a modified client can change any of it, and the
server re-derives anything that matters.

### `config/shared.lua` — `OPX.Config.SHARED`

| Key | Default | Meaning |
|---|---|---|
| `SERVER_NAME` | `"OPX//77"` | shown in the launcher and in player-facing text |
| `LOCALE` | `"en"` | language of player-facing text; server logs stay English |
| `MONEY.TYPES` | `{ EDDIES = 500, BANK = 5000 }` | money type names and each one's starting amount for a new character. The names are durable: they become keys in the `money` JSON column, so adding one is free and renaming one orphans every balance stored under the old name. `EDDIES` is carried on the person and losable, `BANK` is held by a bank |
| `MONEY.DEFAULT` | `"EDDIES"` | the type a payment falls back to when a caller does not name one |
| `CHARACTERS.NAME.MIN` / `MAX` | `2` / `32` | bounds on each half of a character name, counted in characters, not bytes |
| `APPEARANCE.GAME_BUILDS` | `{ ["2.31"] = true }` | which game builds a stored face may be read back into. A snapshot captured on another build is refused; widening this does not make an old one fit |
| `APPEARANCE.MAX_JSON_BYTES` | `49152` | the largest appearance document accepted, in bytes of encoded JSON; a canonical snapshot of 256 options is far below it |
| `DEFAULT_SPAWN` | `SET = false`, `X`/`Y`/`Z`/`HEADING` `0.0` | where a character with no stored position is placed. Nobody is placed there until `SET` is true; run `opx77.here` in game to print your own coordinate in this exact shape |
| `NOTIFY_POSITION` | `"top_right"` | where toasts go: `middle_left`, `top_left`, `top_center`, `top_right`, `bottom_left`, `bottom_center` or `bottom_right`. An unknown value is warned about and still sent |

### `config/server.lua` — `OPX.Config.SERVER`

| Key | Default | Meaning |
|---|---|---|
| `AUTOSAVE_SECONDS` | `300` | how often a loaded character is written back; bounds what a crash costs |
| `MONEY.ALLOW_NEGATIVE` | `{ BANK = true }` | money types that may go below zero; a removal from a type not listed is refused rather than truncated |
| `MONEY.PAYCHECK_MINUTES` | `10` | minutes between paychecks; `0` disables them entirely |
| `MONEY.PAYCHECK_REQUIRES_DUTY` | `true` | pay only a player who is on duty |
| `MONEY.PAYCHECK_TYPE` | `"BANK"` | which of `SHARED.MONEY.TYPES` a salary lands in (see above) |
| `CHARACTERS.DEFAULT_SLOTS` | `3` | how many characters one account may hold |
| `CHARACTERS.SLOTS_BY_USER` | `{}` | per-account overrides, keyed by durable `userId`; `opx77.whois` prints a player's |
| `CHARACTERS.ROW_CEILING` | `60` | the most rows one account may ever write to `opx77_characters`. A lifetime ceiling, not a roster size, because a delete is soft: keep it well above `DEFAULT_SLOTS` |
| `CHARACTERS.CASCADE_TABLES` | `{}` | extra tables whose rows go with a deleted character, as `{ TABLE, COLUMN }` pairs matched on the citizen id. The core's own tables use `ON DELETE CASCADE` and are not listed |
| `ENTRY.GATE_MS` | `300000` | the liveness interval declared to `Open77.ready.participate`, in ms, clamped by the host to 1000–600000 (see "The entry gate") |
| `ENTRY.PIPELINE_MS` | `240000` | the core's own deadline for the join sequence, in ms; below `GATE_MS` so the core gives up first, and the ceiling of the `SELECTION_MS` tunable |
| `ENTRY.BUCKET.ISOLATE` | `true` | one routing bucket per player without a character; `false` leaves everybody in `WORLD` and moves nobody (see "The selection bucket") |
| `ENTRY.BUCKET.BASE` | `77000` | a player's own bucket is `BASE` + their player id, up to `BASE + 65535`. Keep that range clear of other resources' buckets: the platform's Deathmatch uses 4100–4287 and its Race 6500 |
| `ENTRY.BUCKET.WORLD` | `0` | where a character goes when its stored position names no bucket, or one in the selection range; the shared world is `0` |
| `ENTRY.BUCKET.POPULATION` | `false` | ambient population in a selection bucket |
| `ENTRY.BUCKET.LOCKDOWN` | `"relaxed"` | `inactive`, `relaxed`, `strict` or `full`; `false` leaves the mode alone |
| `PLAYER.STARTING_METADATA` | `health = 100`, `armor = 0`, `isDead = false`, `inLastStand = false` | the initial `PlayerData.metadata`, and the four keys the core itself reads. A gameplay file's own keys merge on top and survive every save |
| `PLAYER.DEFAULT_JOB` / `DEFAULT_GANG` | `"unemployed"` / `"none"` | must exist in `data/jobs.lua` / `data/gangs.lua` |
| `CONFLICTING_PLACERS` | `{ "open77_playerstate", "freeroam", "pursuit", "race" }` | resources that would fight the core over where a player stands (see "Placement conflicts") |
| `EXPORTS.READ` | `"*"` | who may call the read exports (identity, the change cursor, a vehicle's plate): `"*"` for any server resource, or a set such as `{ opx77_inventory = true }` |
| `EXPORTS.CALLERS` | `{ opx77_inventory = { scopes = { inventory = true } } }` | every other export is refused unless its caller is listed with the scope it needs; the name is read from the host, never from an argument |
| `EXPORTS.MAX_RESULT_BYTES` | `32768` | the most an answer may weigh encoded; the host's budget is 48 KiB with its own overhead |
| `INVENTORY.MAX_SLOTS` | `1000` | slots one container may have |
| `INVENTORY.MAX_WEIGHT` | `4000000000` | grams; the column is `INT UNSIGNED` |
| `INVENTORY.MAX_METADATA_BYTES` | `4096` | one stack's metadata, encoded |
| `INVENTORY.PAGE_ROWS` | `64` | stacks one read answers at most, before the size guard trims it |
| `INVENTORY.LINKED_KINDS` | `{ character = "citizen", trunk = "plate", glovebox = "plate" }` | kinds whose owner is another row, which must exist and whose deletion takes the container with it; any other kind stands alone |

The `INVENTORY` bounds guard the tables, not the gameplay: `opx77_inventory` decides sizes and
weights.

### `config/vehicles.lua` — `OPX.Config.VEHICLES`

| Key | Default | Meaning |
|---|---|---|
| `PER_CHARACTER` | `8` | the most vehicles one character may own; `0` for no ceiling |
| `PLATE_FORMAT` | `"11AAA111"` | `1` a digit, `A` a letter, `.` either, anything else stays as written |
| `DEFAULT_GARAGE` | `"impound"` | where a vehicle created with no garage belongs |
| `SPAWN_OFFSET` | `3.0` | metres to the side of the player a vehicle appears |
| `SAVE_SECONDS` | `120` | how often the condition of every vehicle that is out is written |

### `config/client.lua` — `OPX.Config.CLIENT`

| Key | Default | Meaning |
|---|---|---|
| `POSITION_REPORT_MS` | `5000` | how often the client reports its heading for the autosave. The server re-reads the authoritative position before writing, so this only decides how fresh the hint is |

### The entry gate

`ENTRY.GATE_MS` is the liveness interval the host watches *this resource* on, not a budget for
the player. The core takes one hold per join and never refreshes it, so in practice that
interval is the deadline it has — which is why `ENTRY.PIPELINE_MS`, the core's own selection
deadline and the ceiling of the `SELECTION_MS` tunable, is held below it. The core then always
gives up first and can say why.

Every joiner is also held by the platform's own `__platform` hold, which clears only when some
client emits `open77:session:gameplayReady`. With no resource emitting it, `Open77.ready.isReady`
stays false and `onPlayerReady` never fires. The core reads neither, so it is unaffected.

### The selection bucket

A player with no character loaded waits in a routing bucket of their own, `ENTRY.BUCKET.BASE`
plus their player id (77001 for player 1 as shipped), with ambient population off and the
entity lockdown `relaxed`, as the platform prepares its own isolated rounds. Nobody else is
replicated to them and they are replicated to nobody, so two players on the roster at the same
spot never see each other. `server/buckets.lua`; every move is one `[bucket]` debug line.

| When | Bucket |
|---|---|
| the player connects | their own, at once. Taken again at their client's `READY` if refused |
| a character is selected | `WORLD` or the stored bucket, set just before the kill → respawn, which names the same one |
| the character could not be placed | `WORLD` all the same: it is loaded, and plays where it stands |
| the character is unloaded (logout, deletion of the loaded one) | their own again; the position is sampled before the move, so the row keeps the world bucket |
| a switch from one character to another | no move: the player never goes back to the roster, unless the switch fails after the first character was torn down |
| the player disconnects | none: the host drops the player and their bucket with them |
| `opx77_core` stops | everybody in a selection bucket goes to `WORLD`, so nobody is left where no running resource looks |
| `opx77_core` starts again | a player still behind the readiness gate is isolated again at their `READY`. One past it has been in the world this session and stays in `WORLD` |

A stored position whose bucket is in the selection range, `BASE + 1` to `BASE + 65535`, is
placed in `WORLD`: that bucket belongs to whoever holds the player id now, never to a character.
It happens to a staff member who teleports to a player on the roster and saves there.

**A bucket move under the closed gate.** The gate's rule is never to teleport, spawn, kill or
force a respawn on a player whose gate is closed, because acting on the body of a client that is
not incarnated crashes it. A bucket move is none of those: the host's `setPlayer` "moves
authoritative visibility scope" — which bodies, vehicles and props are replicated to and from
the player — and writes no transform, life state or puppet. The platform's own resources treat
it that way: `open77_appearance` replays bodies on `onPlayerBucketChange` with no life or gate
check, and no bucket refusal in the host names readiness. So the core moves a player at connect,
before their world has loaded, which is also the only moment at which nothing from the shared
world has been replicated to them yet.

The routing bucket API needs no manifest permission. `ISOLATE = false` turns it all off.

**Other resources.** `opx77_elevators` answers `wrong_bucket` to a player outside its lift's
bucket, and `opx77_animations` plays and replicates within a bucket, which is the point: neither
is reachable from the roster. `opx77_admin`'s `goto`, `bring` and `observe` place through
kill → respawn into the target's bucket, and refuse a target whose readiness gate is closed —
every player on the roster for the first time. A player back on the roster after an unload has an
open gate, so `goto` puts the staff member in that player's selection bucket, and `bring` takes
the player into the staff member's. Neither is undone by the core; the next selection places the
character in the world as usual.

The face editor of a character with no stored face opens after the character is placed, so it
opens in `WORLD`.

### Placement conflicts

`CONFLICTING_PLACERS` names resources that would fight the core over where a player stands. The
core disables nothing; it checks `GetResourceState` at boot and prints once what to do:

- `open77_playerstate` — stop it, or add `opx77_core` to its `spawnOwners` tunable
- `freeroam` — turn `forceOnJoin` off
- `pursuit`, `race` — round-based gamemodes; two gamemodes on the same players is a bug

## Locales

`LOCALE` in `config.lua` picks the catalogue player-facing text is read from — `"en"` or `"fr"` as shipped. Each resource carries its own catalogue, so this is set here as well as in `opx77_core`: the core's `Locale` export is client-only and asynchronous, and a resource that renders text at load cannot wait on it.

To add a language, copy `locales/en.lua` to `locales/<code>.lua`, change the code in the `register` call, translate the values, add a `shared_script "locales/<code>.lua"` line to `open77.lua` beside the others, and set `LOCALE` to it. A key missing from a catalogue falls back to English, then to the key itself. `Open77.log` lines and console output stay English whatever the setting.

## Community & Support

Join the Open77 and Opx77 communities to discover the platform, share your projects, and
connect with other developers.

<!-- TODO: replace with the final URLs before publication. -->

* [Open77](#)
* [Open77 GitHub](#)
* [OPX Discord](#)

## License

opx77_core is licensed under the [**MIT License**](LICENSE).

Copyright © 2026 **Luis MOUTA**.

<p align="center">
    <sub>opx77_core is an independent community project and is not affiliated with or endorsed by CD PROJEKT RED.</sub>
</p>
