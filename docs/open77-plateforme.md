# Open2077 — ce qui contraint l'architecture

Relevé le 2026-08-30 depuis <https://open2077.net/docs> (37 pages, synchro du
26 août 2026, statut pré-alpha : l'API peut bouger).

Tout ce qui suit est cité ou vérifié dans la doc. Rien n'est supposé.

## Le runtime

PUC **Lua 5.4.8**. Chaque ressource reçoit *son propre état Lua*, son
ordonnanceur, son allocateur, son jeu de permissions et son cycle de vie.

Le bac à sable retire `io`, `os`, `debug`, `package`, `dofile`, `loadfile`, la
FFI et la création directe de coroutines.

Budgets par ressource, côté client : 32 Mio de mémoire Lua, 500 000
instructions par reprise, 2 ms de budget par frame, 4 Mio par fichier source.
Dépasser le budget lève `Open77 script execution budget exceeded` et la
coroutine n'est jamais reprise.

Enveloppe réseau : 32 arguments maximum, 48 Kio. 1 024 tâches et 2 048
gestionnaires par ressource.

## La contrainte qui décide de tout

> « Server resources cannot call each other. The server runtime installs no
> `exports`, no `GetInvokingResource`, and no cross-resource event bus. »

`TriggerEvent` **ne franchit pas** les frontières de ressource côté serveur :
il opère par VM. La doc recommande explicitement de regrouper toute la logique
serveur d'un mode dans **une seule ressource**, organisée en fichiers.

Conséquence directe : un core façon `es_extended`, que des ressources tierces
appelleraient, est impossible. Open2077 a d'ailleurs abandonné son propre
`open77_gamemode` pour cette raison, et distribue les motifs communs par
génération de code plutôt que par liaison à l'exécution.

**Côté client, c'est l'inverse** : les exports existent.

```lua
exports("openMenu", function(id) return { opened = true, id = id } end)
local promise, reason = Open77.exports.call("garage", "openMenu", 42)
local result, callError = promise:await()
```

Il n'y a **pas** de proxy façon FiveM `exports.<resource>:<name>()`.
Les 80 exports officiels des 17 paquets sont **tous côté client**.

## Manifeste

```lua
resource "garage"
version "1.0.0"
auto_start true

shared_script "shared/config.lua"
server_script "server/main.lua"
client_script "client/main.lua"

web_ui_page "web/index.html"
web_files { "web/**" }
files { "assets/blips/*.png" }
permissions { "network.events" }
```

`require("shared.helpers")` résout vers `<resource>/shared/helpers.lua` ou
`<resource>/shared/helpers/init.lua`. Les scripts se chargent dans l'ordre du
manifeste, donc seuls les points d'entrée ont besoin d'y figurer.

Un fichier n'est accessible que s'il correspond exactement à une déclaration
`files` : `Open77.assets.texture("assets/blips/x.png")` échoue sinon.

## Identité — vérifiée cryptographiquement

Trois valeurs distinctes :

- **`userId`** — identifiant durable lié à l'installation, stable entre
  sessions. C'est la clé de compte.
- **`playerId`** (alias `source`) — valable pour la session en cours seulement.
- **`displayName`** — modifiable par le joueur.

Le Master délivre un certificat Ed25519 couvrant
`userId || clé publique P-256 || displayName`. Renommer dans un client modifié
invalide le certificat et la session est rejetée avant d'être active.

```lua
AddEventHandler("onPlayerConnected", function(playerId, playerName)
    local player = tonumber(playerId) or 0
    print(GetPlayerIdentifier(player)) -- userId durable
    print(GetPlayerName(player))       -- displayName vérifié par le Master
end)
```

`source` **n'est pas défini** dans `onPlayerConnected` : il n'est peuplé que
dans les gestionnaires atteints par un événement réseau.

Pendant un gestionnaire réseau, `source` vient de la connexion authentifiée,
jamais de la charge utile du client.

## Barrière d'entrée

> « do not teleport, spawn, kill or force a respawn on a player until their
> readiness gate has opened. »

```lua
Open77.ready.participate({ timeoutMs = 30000, reason = "character_creation" })
local session, failure = Open77.ready.hold(playerId, "character_creation")
Open77.ready.release(playerId, session)
```

`participate` pose automatiquement un verrou sur chaque joueur qui se connecte
ensuite. Le numéro de session évite les confusions quand les `playerId` sont
recyclés.

Si un verrou n'est jamais relâché, la plateforme ouvre la barrière au bout du
délai et émet `timeout:<resource>` — potentiellement avec le joueur encore dans
une fenêtre modale et **sans pantin du tout**. Il faut donc vérifier l'état de
vie avant tout placement.

`onPlayerReady(playerId, detail)` est émis dans toutes les ressources quand le
dernier verrou tombe. `detail` vaut `cleared`, `no_holds`, `resource_reloaded`,
`resource_stopped` ou `timeout:<resource>`.

## Base de données

Permission `database.access`. `MySQL` est un alias de `Open77.database`.

```lua
Open77.database.query(sql, params?, callback?)
Open77.database.single(sql, params?, callback?)
Open77.database.scalar(sql, params?, callback?)
Open77.database.insert(sql, params?, callback?)
Open77.database.update(sql, params?, callback?)
Open77.database.transaction(statements, callback?)
```

Forme `await` disponible : `.await(sql, params?)`. Elle reprend sur
l'ordonnanceur de la ressource propriétaire, jamais sur le worker base.

## Commandes et ACL

```lua
RegisterCommand("garage.delete", function(source, args, rawCommand)
    -- source = playerId authentifié, ou 0 pour la console serveur
end, true)  -- true = restreinte, soumise a l'ACL
```

Permission `command.<nom>`. Un joker `*` ou un joker terminal
`command.garage.*` autorise aussi. L'ACL vit dans `acl.jsonc`, désigné par
`server.jsonc`, et compare la clé publique de 64 octets de la poignée de main.

Console : `acl.reload`, `acl.list`, `acl.check <playerId> <permission>`.

## Conventions imposées par la plateforme

1. Les identifiants moteur sont **opaques** : stocker les entiers 64 bits tels
   quels, ne jamais passer par `tonumber`.
2. Les échecs sont des valeurs : la plupart des API renvoient `value` ou
   `nil, reason`, sans exception.
3. Les permissions sont explicites dans le manifeste.
4. Le code serveur n'atteint jamais les clients ; les scripts clients sont
   signés.

## Les huit conventions de gamemode

Éprouvées sur Pursuit et Race, à respecter faute de kernel partagé :

1. Adoption paresseuse du roster — repeupler depuis le prochain événement.
2. Convertir les `playerId` des événements réseau avec `tonumber`.
3. Transitions d'état gardées par une fonction unique.
4. Placement uniquement par kill → respawn, jamais de transform brut.
5. Re-dériver les conditions client côté serveur : ce sont des indices.
6. Échantillonner les positions en continu, pas un instantané.
7. Fournir une commande de diagnostic `<mode>.where`.
8. Buckets de routage isolés par manche, population ambiante coupée.

## Corrections apportées par la lecture des ressources officielles

Relevé le 2026-08-31 sur `open77-server-2.31.4+op77.11`. Le code livré
contredit la doc sur plusieurs points, et c'est lui qui fait foi.

- **Il existe deux événements de déconnexion**, ni l'un ni l'autre documenté :
  `onPlayerDisconnected(playerIdStr)` et `playerDropped()`. Le core écoute les
  deux. Détail dans `docs/unknowns.md`.
- **`server_script` prend une entrée par ligne**, et les globs sont à
  proscrire : un glob vide empêche la ressource entière de démarrer. Toutes
  les ressources livrées listent leurs fichiers un par ligne.
- **`MySQL.<méthode>.await` lève** au lieu de rendre `nil, reason`, sauf
  `transaction.await` qui rend `false, reason`.
- **Les paramètres nommés `@nom` sont préférés à `?`**, et aucun commentaire
  ne doit apparaître dans une chaîne SQL.
- **`Open77.tunables.declare(table)`** rend un proxy vivant, et
  `onTunableChanged(clé)` signale un changement depuis le panneau Warden.
- **Il n'existe pas de `Open77.players.all()`** : pas de liste des joueurs,
  d'où l'adoption paresseuse du roster.
- **`setmetatable` n'apparaît dans aucune des 37 ressources livrées.**

## Ce qui reste à vérifier

- Qu'un nom d'événement arbitraire émis par une ressource serveur atteigne une
  autre ressource. Seuls les noms d'intégration connus de l'hôte sont
  démontrés (`open77:appearance:setCharacter`).
- Les limites chiffrées du codec d'exports : taille d'argument, profondeur,
  délai d'expiration d'un appel.
- L'unité rendue par `Open77.time.monotonic()` côté serveur : la doc dit des
  millisecondes, `open77_playerstate` la traite comme des secondes.
