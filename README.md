# opx77_core

> [!WARNING]
> **This project is currently in early development and is not considered production-ready.**
>
> The API, architecture, features, and internal systems are subject to change at any time without prior notice. Breaking changes may be introduced as development progresses.
>
> **Do not rely on the current API for production resources yet.**

The core resource of **Opx77**, providing the essential systems and APIs required to build resources and gameplay for Open77.

Opx77 core is designed to provide a **simple, flexible, and reliable foundation** for developers. It handles the core functionality that resources can build upon while keeping the framework lightweight and easy to extend.

## Features

- Character creation, selection and deletion, with a per-account slot limit
- Multi-job and multi-gang membership, with grades and duty state
- Money, metadata and stored position, autosaved and written on departure
- Readiness-gate integration, so nothing places a player before the core has chosen where
- Live tunables, editable from the operator panel without a restart
- Export-based API to read core data from any resource
- Locales, with every refusal answered as a key a satellite can render

## Exports

Client-side, because the Open77 server runtime installs no export mechanism. A server resource that needs core data sends a net event to its own client half, which calls these.

| Export | Answers |
|---|---|
| `GetPlayerData` | the whole loaded character |
| `IsLoggedIn` | whether a character is loaded |
| `HasJob(name, onDutyOnly?, minGrade?)` | job membership, with an optional duty flag and minimum grade |
| `HasGang(name, minGrade?)` | gang membership, with an optional minimum grade — no duty flag, a gang has no shifts |
| `GetJobs` / `GetGangs` / `GetOrigins` | the static definitions, with grades as a 1-based array carrying an explicit `level` |
| `GetVersion` | the core's version, for a compatibility check |
| `GetSharedConfig` | server name, locale in force, money types and default, character name bounds, notification position |
| `Locale` | one rendered line for a refusal code |
| `GetCharacters` | the roster last sent to this client |
| `RequestCharacters` | ask for it again |
| `SelectCharacter` / `CreateCharacter` / `DeleteCharacter` | the character screen |

Static definitions come from `GetJobs`, `GetGangs` and `GetOrigins`; everything else is one field of `GetPlayerData` or one key of `GetSharedConfig`.

The last four are requests, not reads: they fire an `opx77:server:*` net event and answer only that it was sent. The result arrives on the events below.

## Events

The core publishes its state on two channels, both listed in `shared/main.lua` under `OPX.Events`. A satellite picks one.

| Channel | Table | How to listen | Permission |
|---|---|---|---|
| networked | `OPX.Events.Client` | `RegisterNetEvent` | `network.events` |
| local | `OPX.Events.Local` | `AddEventHandler` | none |

The local channel is fired by the core's own client half straight after it has updated its mirror, so a handler can call `GetPlayerData` and see the change that woke it. The client's local event bus is host-wide, so it reaches any resource, not only this one.

No name appears on both channels, and that is load-bearing rather than tidy: this platform's dispatcher matches an event by name and ignores the network flag, so a `TriggerEvent` also reaches every `RegisterNetEvent` handler of the same name. A local re-emission that reused its own wire name would re-enter the handler that fired it — tick-paced rather than recursive, so it would be a silent permanent busy loop, not a crash.

| Local event | Fired when |
|---|---|
| `opx77:client:charactersReady` | the roster arrived |
| `opx77:client:onPlayerLoaded` | a character entered the world |
| `opx77:client:onPlayerUnloaded` | the character left |
| `opx77:client:playerDataChanged` | any field of `PlayerData` changed |
| `opx77:client:moneyChanged` | a balance moved |
| `opx77:client:jobChanged` / `opx77:client:gangChanged` | a group or grade changed |
| `opx77:client:refused` | the server refused something, with a locale key |
| `opx77:client:appearanceRequired` / `opx77:client:appearanceChanged` | the appearance service wants a creator run, or switched look |

## Configuration

Three files, split by who may read them:

| File | Scope |
|---|---|
| `config/shared.lua` | values both sides need |
| `config/server.lua` | slots, autosave, paychecks, entry deadlines |
| `config/client.lua` | client cadences — **never loaded by the server VM** |

Anything an operator may want to change mid-session is a tunable instead, and lives in `server/tunables.lua`.

## Community & Support

Join the Open77 and Opx77 communities to discover the platform, share your projects, and connect with other developers.

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
