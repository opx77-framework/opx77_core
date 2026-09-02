# opx77_core

> [!WARNING]
> **Early development, not production-ready.** The API, schema and internals change without
> notice. Do not build production resources against them yet.

The core resource of **OPX//77** for the Open77 platform. It owns everything durable about a
character — the schema, every write, and the events that publish the result. A satellite draws
and reacts; it does not persist anything of its own and does not own a table.

## Features

- Character creation, selection and deletion, with a per-account slot limit
- Multi-job and multi-gang membership, with grades and duty state
- Money, metadata, appearance and stored position, autosaved and written on departure
- Readiness-gate integration, so nothing places a player before the core has chosen where
- Live tunables, editable from the operator panel without a restart
- Export-based API to read core data from any client resource
- Locales, with every refusal answered as a key a satellite can render

## The schema

One file per table in [`sql/`](sql/), which is where an operator reads it:

| File | Table |
|---|---|
| `sql/users.sql` | `opx77_users` — one Master account |
| `sql/characters.sql` | `opx77_characters` — one character, keyed on `citizen_id` |
| `sql/character_groups.sql` | `opx77_character_groups` — job and gang memberships |
| `sql/vehicles.sql` | `opx77_vehicles` — owned vehicles, keyed on the plate |

`server/storage/schema.lua` carries the same statements and applies them at boot. **The two
are edited together.** The Open77 *server* runtime installs no file-reading API — `Open77.resource`
is `{ name, state }` and the sandbox removes `io`, `os` and `loadfile` — so the migration runner
cannot load `sql/` itself; a `.sql` file is not a script a manifest can list either.

The runner keys on the migration name and skips one a database already has. `sql/` and the Lua
long strings are byte-identical apart from the trailing `;` and the file's header comment:
`schema.lua` is what runs, `sql/` is what an operator reads, and neither is generated from the
other. `python3 tools/check_sql_parity.py` proves it and exits non-zero when the two drift.

`opx77_characters` carries one nullable JSON column beyond the obvious ones: `appearance`, the
character's face, written only by `server/appearance.lua`. It travels inside `PlayerData` and is
therefore in every event the core publishes.

**A database from before this version cannot be upgraded in place.** The table renames
(`opx77_accounts` → `opx77_users`, `opx77_players` → `opx77_characters`,
`opx77_player_groups` → `opx77_character_groups`) were made inside migrations 0001–0004 rather
than added as new ones, so a database created earlier keeps the old tables while the code
queries the new names. Drop it and let the runner recreate it: there is no automatic migration
path and none is planned.

## Exports

Client-side, because the Open77 server runtime installs no export mechanism. A server resource
that needs core data sends a net event to its own client half, which calls these. There is no
`exports.<resource>:<name>()` proxy — the call is `Open77.exports.call(resource, name, ...)`,
it is always asynchronous, and every export answers `{ ok = boolean, ... }`.

| Export | Answers |
|---|---|
| `GetPlayerData` | the whole loaded character |
| `IsLoggedIn` | whether a character is loaded |
| `HasJob(name, onDutyOnly?, minGrade?)` | job membership, with an optional duty flag and minimum grade |
| `HasGang(name, minGrade?)` | gang membership, with an optional minimum grade — no duty flag, a gang has no shifts |
| `GetAppearance` | the stored face for the live character, or nil |
| `GetJobs` / `GetGangs` / `GetOrigins` | the static definitions, with grades as a 1-based array carrying an explicit `level` |
| `GetVersion` | the core's version, for a compatibility check |
| `GetSharedConfig` | server name, locale in force, money types and default, character name bounds, notification position |
| `Locale` | one rendered line for a refusal code |
| `GetCharacters` | the roster last sent to this client |
| `RequestCharacters` | ask for it again |
| `SelectCharacter` / `CreateCharacter` / `DeleteCharacter` | the character screen |

The last four are requests, not reads: they fire an `opx77:server:*` net event and answer only
that it was sent. The result arrives on the events below.

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
| `opx77:client:refused` | the server refused something: `(code, kind, operation)` |
| `opx77:client:appearanceRequired` / `opx77:client:appearanceChanged` | the platform's appearance service wants a creator run, or switched look |

### Refusals

`opx77:client:refused` carries three arguments — a `code`, a `kind`, and the `operation` the
refusal answers. The `operation` is one of `OPX.Operations` (`entry`, `ready`,
`selectCharacter`, `createCharacter`, `deleteCharacter`, `saveAppearance`, `spawnVehicle`,
`storeVehicle`), named after the `opx77:server:*` request that starts it. A client waiting on
one of several requests must branch on it: `error.tooFast` is raised by all of them, and
without the operation a satellite cannot tell whose answer arrived. A handler that only reads
`code` keeps working — the field was added after `code` and `kind`.

The `code` is always a key the core's catalogue carries. A refusal whose underlying cause has
no entry — a storage failure answering `query-failed`, a validator answering `too-short` — is
logged with its real code and sent as `error.unavailable`, so `locale(code)` never renders a
raw code at a player.

### Writing to the core

A satellite that needs something written sends a net event **from its client half** to a name
the core's server half has registered. It never asks the core from its own server half — the
runtime installs no cross-resource server bus.

| Server event | Payload | Effect |
|---|---|---|
| `opx77:server:ready` | none | re-sends the roster, or `playerLoaded` if one is already in |
| `opx77:server:selectCharacter` | `{ citizenId }` | enters the world as that character |
| `opx77:server:createCharacter` | `{ firstName, lastName, origin, gender, birthDate }` | creates one |
| `opx77:server:deleteCharacter` | `{ citizenId }` | soft-deletes one |
| `opx77:server:reportPosition` | `{ heading }` | a heading hint; x/y/z are re-derived server-side |
| `opx77:server:saveAppearance` | `{ snapshot }` | validates and stores a captured face |
| `opx77:server:spawnVehicle` / `opx77:server:storeVehicle` | `{ plate }` | brings a car out, or puts it away |

`opx77:server:saveAppearance` takes a canonical snapshot: `schemaVersion = 1`, a `gameBuild`
listed in `APPEARANCE.GAME_BUILDS`, a 64-hex `catalogDigest`, a `gender` engine hash
(`0x` + 16 hex), and a dense `options` array of 1–256 `{ part, name, value, choices }` entries.
Anything else is refused with `appearance.invalid` and a code naming the field.

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
| `OPX.Storage.Players.*` | the statements, if a plug-in genuinely needs its own read |
| `OPX.Hooks.register` | veto a money movement or a paycheck before it lands |

`PlayerData.metadata` is a free-form bag, and the core keeps its own `health`, `armor`, `isDead`
and `inLastStand` in it. The gameplay needs — hunger, thirst, stamina, ram, street cred — are
`opx77_status`'s, not the core's.

## Configuration

| File | Scope |
|---|---|
| `config/shared.lua` | values both sides need — never put a secret in it |
| `config/server.lua` | slots, autosave, paychecks, entry deadlines, starting metadata |
| `config/vehicles.lua` | plate format and spawn ceiling, server-only |
| `config/client.lua` | client cadences — **never loaded by the server VM** |

Anything an operator may want to change mid-session is a tunable instead, in
`server/tunables.lua`. Logging level is not configured here: the host owns it, and the core
calls `Open77.log` directly.

### The entry gate

`ENTRY.GATE_MS` is the liveness interval the host watches *this resource* on, not a budget for
the player. The core takes one hold per join and never refreshes it, so in practice that
interval is the deadline it has — which is why `ENTRY.PIPELINE_MS`, the core's own selection
deadline and the ceiling of the `SELECTION_MS` tunable, is held below it. The core then always
gives up first and can say why.

Every joiner is also held by the platform's own `__platform` hold, which clears only when some
client emits `open77:session:gameplayReady`. With no resource emitting it, `Open77.ready.isReady`
stays false and `onPlayerReady` never fires. The core reads neither, so it is unaffected.

### Placement conflicts

`CONFLICTING_PLACERS` names resources that would fight the core over where a player stands. The
core disables nothing; it checks `GetResourceState` at boot and prints once what to do:

- `open77_playerstate` — stop it, or add `opx77_core` to its `spawnOwners` tunable
- `freeroam` — turn `forceOnJoin` off
- `pursuit`, `race` — round-based gamemodes; two gamemodes on the same players is a bug

## Community & Support

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
