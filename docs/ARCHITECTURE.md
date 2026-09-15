# opx77_core — architecture

Un framework de jeu de rôle pour [OPEN//77](https://open2077.net), la
plateforme multijoueur de Cyberpunk 2077.

Le core possède tout ce qui dure d'un personnage : le schéma, chaque écriture et les événements
qui en publient le résultat. Personnages, argent, métiers, gangs, apparence, vêtements,
véhicules, stockage des inventaires, persistance, barrière d'entrée et bucket de sélection
tournent. Il ne dessine rien : l'écran de sélection est celui d'`opx77_charselector` et
d'`opx77_charcreator`, le HUD celui d'`opx77_hud`, l'inventaire celui d'`opx77_inventory`, et
aucun satellite ne possède de table.

Le code porte des blocs d'annotation en anglais ; cette documentation est en français, et le mode
d'emploi (exports, événements, commandes, configuration) est dans le `README.md`.

## Manifeste

`shared/main.lua` crée l'espace de noms `OPX`, et les fichiers partagés qui suivent le remplissent
dans l'ordre de leurs dépendances : `result`, `table`, `string`, `math`, `validate`, `hooks`. La
configuration vient ensuite : `config/shared.lua` part chez chaque client (jamais de secret
dedans), `config/server.lua` et `config/vehicles.lua` restent au serveur, `config/client.lua` au
client. Les données statiques (`data/`) sont des définitions et non des réglages : en changer une
renomme ce que des joueurs possèdent déjà. `shared/locale.lua` précède immédiatement les
catalogues `locales/en.lua` et `locales/fr.lua`, pour qu'aucun fichier plus bas n'appelle
`locale()` contre un catalogue vide.

Côté serveur, les fichiers de `server/storage/` chargent avant `server/logger.lua`, qui écrit à
travers eux. `server/functions.lua` (les accesseurs) précède tout ce qui cherche `OPX.GetPlayer`.
`server/buckets.lua` précède `server/player.lua`, parce qu'une déconnexion et un placement
déplacent des buckets. `server/groups.lua` vient après `server/player.lua` (un changement de
groupe écrit à travers le Player) ; `server/lifecycle.lua`, `server/appearance.lua` et
`server/vehicles.lua` viennent après `server/character.lua` (la barrière se relâche en chargeant
un personnage, l'apparence écrit une colonne du personnage, la propriété d'un véhicule lit
`PlayerData`) ; `server/clothing.lua` après le stockage. `server/exports.lua` et
`client/exports.lua` chargent en dernier : publier la surface affirme que tout ce qu'elle lit
existe.

`reload_policy "local"` : un rechargement est un rechargement de scripts, pas une reconnexion ;
les deux moitiés se reconstruisent (le client se réannonce avec `opx77:server:ready`).

Aucune `dependency` n'est déclarée : une dépendance déclarée est dure, et le core doit
s'installer sur un serveur nu.

- `network.events` — `RegisterNetEvent` et `TriggerClientEvent` ; `local.events` n'est pas
  nécessaire.
- `database.access` — `Open77.database`. Sans base, `OPX.Storage` se dégrade en une ligne de
  journal et un refus de connecter qui que ce soit.
- `players.life.read` — agir sur un client qui n'est pas incarné le fait planter : l'état de vie
  est lu avant chaque placement.
- `players.life.kill`, `players.life.respawn` — le placement est un kill suivi d'un respawn,
  jamais une écriture de transform : le respawn porte le fondu et le préchargement du streaming
  qu'un téléport saute.
- `players.life.revive` — le rattrapage d'un kill dont le respawn a échoué.
- `players.damage.apply` — l'armure est réappliquée après le respawn ; rien ne la relit.
- `world.vehicles` — faire apparaître le véhicule d'un personnage et réécrire ce qui lui est
  arrivé.
- `acl.read` — `Open77.acl.isAllowed` en lecture seule : une commande restreinte n'est suggérée
  dans le chat qu'à un joueur que l'ACL laisserait la lancer. Rien ici n'accorde de droit et aucun
  gestionnaire ne le vérifie : l'hôte résout `command.<nom>` avant que le gestionnaire tourne.
- `players.disconnect` — `server/lifecycle.lua` seulement, pour fermer la session d'un joueur sans
  identité vérifiée : relâcher la barrière seule le laisserait dans le bucket 0 sans personnage,
  pour toujours. Ce n'est pas un outil de modération.

Délibérément non demandées : `world.props`, `world.elevators`, `combat.config`,
`players.damage.read`. Rien à demander pour `Open77.routingBuckets`, qui
isole un joueur en train de choisir un personnage : l'API est installée pour toute resource
serveur et n'exige aucune permission.

## Contrats

La liste des exports, des événements et des commandes est dans le `README.md`. Ce qu'ils
garantissent au-delà de cette liste :

- **Tout nom `OPX.*` est une API documentée.** opx77_doc documente chaque membre de `OPX`
  (l'API des plug-ins serveur, `OPX.Events`, `OPX.Operations`, `OPX.Hooks.register`,
  `OPX.Storage.Players.*`) : aucun ne se renomme, même quand sa casse ne suit pas la règle
  PascalCase des autres ressources.
- **L'appelant est désigné par l'hôte.** Un export serveur lit `GetInvokingResource()` et
  `GetInvokingResourceGeneration()` à l'entrée, jamais un argument ; un événement réseau ne croit
  que `source`. Le compte derrière une session vient de `GetPlayerIdentifier`.
- **Une réponse a toujours la même forme.** Chaque export répond `{ ok = true, ... }` ou
  `{ ok = false, error = '<code>' }` et ne lève jamais. Côté client, un export n'est jamais un
  `OPX.Result`.
- **Un code de refus est une clé de locale.** `OPX.Refuse`, les exports et les réponses de
  commande passent par `OPX.RefusalKey` : un code que le catalogue ne porte pas part comme
  `error.unavailable`, et le vrai code reste dans le journal. `opx77_charcreator` et
  `opx77_charselector` rendent ces codes avec `Locale.exists(code)` : renommer une clé casserait
  leur affichage en silence.
- **Aucun nom d'événement n'apparaît sur deux canaux** (voir « L'espace de noms et les
  événements »).

## La contrainte qui décide de tout

ESX et qbx_core reposent entièrement sur un point : une ressource tierce peut
appeler le core. Sur Open2077 c'est impossible **côté serveur**, et la
documentation le dit sur quatre pages distinctes :

> The **server** runtime installs no `exports`, no `GetInvokingResource` and
> no cross-resource event bus.

> **Server resources cannot call each other.** […] So on the server, split by
> **file**, not by resource.

Ce n'est pas un manque à combler : « it is a platform fact, not an oversight
to be fixed later ». Open2077 avait planifié son propre `open77_gamemode` et
l'a abandonné pour cette raison exacte, distribuant les motifs communs par
génération de code plutôt que par liaison à l'exécution.

Le core en tire la conséquence : **une seule ressource serveur, découpée en
fichiers**. Ce qui serait une ressource-plugin ailleurs est ici un fichier
ajouté à `server/`, et `OPX.*` est l'API serveur — disponible parce que tout
ce qui la partage partage un état Lua.

La plateforme a depuis installé `exports` et `GetInvokingResource` dans le runtime serveur. Le
core publie donc aussi des exports serveur, bornés à ce qu'une autre ressource serveur ne peut pas
faire seule : l'identité d'une connexion, un curseur de changements et le stockage des inventaires
(voir « Les exports serveur »). Un plug-in qui a besoin de l'état du core reste un fichier de
`server/`.

## Côté client, c'est l'inverse

« The client runtime *does* have `exports` and `GetInvokingResource`. » C'est
là que le découpage en ressources redevient possible, et c'est ce qui permet
les satellites : `opx77_charselector` pour la sélection, `opx77_hud` pour l'overlay.

```lua
CreateThread(function()
  local promise, reason = Open77.exports.call("opx77_core", "GetPlayerData")
  if not promise then return print(reason) end   -- echec d'aiguillage
  local result, callError = promise:await()      -- echec de resolution
  if callError or not result.ok then return end
  print(result.data.citizenId)
end)
```

Trois pièges si vous arrivez de FiveM. Pas de proxy
`exports.<resource>:<name>()` — l'indexer lève *attempt to index a function
value*. Asynchrone, toujours : `await` n'est utilisable que dans un
`CreateThread`. Et l'erreur se lit à **deux** niveaux ; ne vérifier que le
premier transforme une erreur distante en `nil` silencieux.

Dernier point, qui est une faille si on l'ignore : un service exporté doit
prendre l'identité de l'appelant dans `GetInvokingResource()`, jamais dans un
argument — « would let any caller impersonate another resource ».

## L'ordre de chargement est le contrat

Il vit dans `open77.lua`, un fichier par ligne. Un fichier publie dans `OPX`,
et tous ceux d'après peuvent lire ce qui a été publié.

Deux règles, et elles ont chacune coûté quelque chose à quelqu'un :

**Aucun `require` sur nos propres fichiers.** Un fichier à la fois listé dans
le manifeste et chargé par `require` s'exécute **deux fois** — le chargeur de
manifeste ne remplit pas le cache de `require`. Et `require` est de toute
façon confiné à la ressource : il n'aurait jamais pu atteindre une
bibliothèque vivant ailleurs.

**Aucun glob.** `server/**/*.lua` ne matche rien contre des fichiers plats et
un glob vide empêche la ressource entière de démarrer. C'est un mode d'échec
qui n'apparaît qu'après un renommage.

## Un seul espace de noms

`OPX.Result`, `OPX.Table`, `OPX.Validate`, `OPX.AddMoney`, `OPX.PlayerData`.
Un fichier ajouté à cette ressource tape `OPX.` et trouve tout le framework.
Pas de seconde globale, rien à importer.

Depuis une ressource **cliente** satellite, il n'y a pas de `getSharedObject`
et il ne peut pas y en avoir : la plateforme fait passer chaque export par un
codec, « arguments and results must be serializable », et une fonction ne se
sérialise pas. Rendre `OPX` d'un bloc rendrait une table amputée de tout ce qui
la rend utile.

La moitié *données* est donc découpée en exports individuels, chacun rendant
une forme close : `GetVersion`, `GetSharedConfig`, `GetJobs`, `GetGangs`,
`GetOrigins`, `GetPlayerData`, `GetCharacters`. Les grades y sont réémis en
tableau 1-based portant un `level` explicite, jamais la table source indexée à
partir de `0` : aucune table à clé `0` n'a jamais traversé ce codec, et un
export n'est pas l'endroit où le découvrir.

Les changements d'état, eux, ne se demandent pas : ils arrivent, sur les deux
canaux de `OPX.Events` (`Client` sur le fil, `Local` sur le bus local du
client, décrits dans `README.md`).

Côté **serveur**, les exports ne rendent que des formes closes elles aussi (voir « Les exports
serveur ») ; le gameplay serveur qui a besoin d'`OPX` est un fichier ajouté à `server/`, où
`OPX` est simplement dans la portée.

## Les couches

| | |
|---|---|
| `config/` | les seuls fichiers qu'un opérateur édite. Clés `UPPER_SNAKE` |
| `data/` | métiers, gangs, parcours de vie. Des définitions, pas des réglages |
| `shared/` | `OPX` lui-même : result, table, string, math, validate, hooks, locales, identifiants citoyens |
| `server/storage/` | toutes les requêtes SQL, et le schéma |
| `server/` | roster, joueur, groupes, personnages, barrière, événements |
| `client/` | miroir d'état et surface d'exports |

## L'espace de noms et les événements

`OPX.IsServer` et `OPX.IsClient` sont lus sur une globale qu'un seul runtime possède
(`TriggerClientEvent` et `TriggerServerEvent`), toutes deux installées par l'amorce avant le
premier script. Pas sur `Open77.database` : elle n'est installée qu'avec `database.access`.

`OPX.Config` est rempli par les fichiers de `config/`. `SERVER` vaut nil sur un client et
`CLIENT` vaut nil sur le serveur, pour qu'une lecture du mauvais côté échoue bruyamment.

Les noms d'`OPX.Events` suivent `opx77:<côté>:<sujet>`, et aucun nom n'apparaît dans deux
tables : un `TriggerEvent` atteint aussi les gestionnaires `RegisterNetEvent` du même nom.

- `Platform` appartient à Open2077 ; ces noms sont listés pour n'avoir qu'un endroit à changer
  s'ils bougent.
- `Client` va du serveur au client : un auditeur tient `network.events` et utilise
  `RegisterNetEvent`.
- `Server` va du client au serveur : chaque charge utile est contrôlée par l'attaquant ; seul
  `source` ne peut pas être forgé.
- `Local` est levé par la moitié client du core après la mise à jour de son miroir, pour qu'un
  gestionnaire lise `OPX.GetPlayerData()` et voie le changement. `AddEventHandler` simple, aucune
  permission.
- `Internal` reste dans la resource, entre les fichiers du core, et ne traverse jamais le fil.

`OPX.Operations` dit à quelle requête répond un refus : sur `Events.Client.NOTIFY`, et en
troisième argument de `Events.Local.REFUSED`. Chaque valeur est nommée d'après la requête
`Events.Server` qui la déclenche.

## Session ≠ joueur

Une **session** est une machine connectée : elle existe dès
`onPlayerConnected` et porte le `userId` signé par le Master. Un **joueur** est
un personnage chargé, et n'existe qu'entre le choix et la déconnexion.

Quelqu'un dans l'écran de sélection a une session et pas de joueur. Chaque
appelant qui confond les deux finit soit par refuser une connexion légitime,
soit par faire confiance à un personnage jamais chargé.

`playerId` est recyclé, `userId` est durable. Le premier n'est donc qu'une clé
de recherche : chaque lecture revérifie le `userId` derrière l'emplacement.
Un départ manqué devient un non-événement au lieu d'une faille.

`OPX.Sessions` tient toutes les machines connectées, personnage ou non ; `OPX.Players`
seulement celles qui ont un personnage chargé. `OPX.PlayerRegistry` en est l'index inverse (par
identifiant citoyen et par compte), qui permet aux accesseurs de `server/functions.lua` de répondre
en O(1) ; seuls `OPX.RegisterPlayer` et `OPX.UnregisterPlayer` le modifient.

- **L'identité vient de l'hôte.** `userIdOf` résout `GetPlayerIdentifier` une fois et le garde,
  mais seulement quand il le trouve : pendant le démarrage la globale peut ne pas être encore
  installée, et un `nil` mis en cache ferait répondre « personne » à tous les appels suivants.
- **`OPX.EnsureSession` est le seul chemin vers une session.** Elle la crée si cette VM ne connaît
  pas encore le joueur, et l'évince si l'emplacement appartient désormais à un autre compte. Sans
  identité vérifiée, rien ne peut lui être attribué : la session est oubliée et la réponse est
  `nil`. `gateSession` est posé par `server/lifecycle.lua` tant que la barrière est tenue,
  `charactersSent` par `server/character.lua` pour qu'une seconde demande coûte peu.
- **`OPX.ForgetSession` déconnecte, elle ne jette pas.** C'est le filet pour un départ que personne
  n'a signalé : le personnage encore attaché est déconnecté et sauvegardé. Avant cela la session
  est marquée `departing` (l'emplacement appartient peut-être déjà à quelqu'un d'autre, qui ne doit
  pas être déplacé de bucket) et `MaySample` passe à `false` (la sauvegarde échantillonne la
  position par source).
- **`OPX.RegisterPlayer`** retire d'abord des deux index un autre occupant de l'emplacement : cela
  veut dire qu'une seconde connexion a couru avec celle-ci. **`OPX.UnregisterPlayer`** ne retire
  une entrée d'index que si elle pointe encore sur ce joueur : un compte qui se reconnecte a
  brièvement ses deux sessions dans le roster.

## L'identifiant citoyen

Un joueur tape ces codes de mémoire, à l'oral : virements, signalements,
recherches admin. Le format est fait pour survivre à une lecture approximative.

Alphabet de 23 symboles sans glyphe ambigu — ni `0`/`O`, ni `1`/`I`/`L`, ni
`5`/`S`. Six symboles utiles plus un symbole de contrôle, rendus `H7K-M4X3`.
Le contrôle est une somme pondérée modulo 23 ; le modulo est premier, ce qui
lui fait détecter **toutes** les substitutions d'un symbole et **toutes** les
inversions de deux symboles voisins.

Sans ce contrôle, une faute de frappe peut produire un code valide appartenant
à quelqu'un d'autre : l'argent part chez un inconnu, sans la moindre erreur
affichée.

Ce code est aussi la `character_key` d'`open77_appearance` et
d'`open77_playerstate`. Une seule identité au lieu de deux, donc pas de cas où
le visage d'un personnage et son argent sont en désaccord sur de qui il s'agit.

Dans le code, `OPX.CitizenId` : 23 symboles sans ambiguïté, six de
charge et un de contrôle. Le module premier est ce qui attrape chaque substitution et chaque
transposition : il ne se change pas. `OPX.CitizenId.generate` prend un générateur injectable,
pour rendre la génération déterministe. `OPX.CitizenId.parse` est indulgent sur la casse et les
séparateurs et strict sur le contenu : un symbole inconnu est refusé, jamais retiré, car le
retirer transforme un identifiant en celui de quelqu'un d'autre. La longueur est vérifiée avant
que `upper()` et `gsub()` copient deux fois la chaîne, pour qu'un refus ait un coût fixe.
`OPX.CitizenId.isValid` garde un site d'appel interne ; une entrée de joueur passe par `parse`,
pour que l'appelant sache pourquoi.

## Les aides partagées

`OPX.Result` fait du succès et de l'échec des valeurs, pour que `nil` ne veuille jamais dire à la
fois « échoué » et « rien trouvé ». `error` est un code stable sur lequel brancher ; `detail` est
réservé aux journaux et au staff : il peut porter une exception brute de la base.

`OPX.Table.deepCopy` tient une table `seen` (table déjà copiée vers sa copie), pour qu'un graphe
qui se référence lui-même termine. `OPX.Table.count` compte aussi les clés hors partie tableau :
`#` ne répond que pour un tableau.

Les motifs Lua travaillent en octets, donc tout ce qui mesure ou découpe du texte dit son unité.
`OPX.String.length` compte en caractères et répond nil pour des octets qui ne sont pas de l'UTF-8
valide. `OPX.String.trim` n'utilise pas `^%s*(.-)%s*$` : ce motif revient en arrière une fois par
position finale, ce qui est quadratique sur une longue suite d'espaces et ininterruptible au
niveau C. `OPX.String.interpolate` laisse un nom inconnu en place, pour qu'une faute de frappe se
voie. `OPX.String.random` suit un gabarit (`A` une lettre, `1` un chiffre, `.` l'un ou l'autre,
tout le reste recopié : `AA-1111` donne `KP-8302`) ; il repose sur `math.random`, qui n'est pas
sûr : jamais pour ce qu'un joueur ne doit pas deviner.

`OPX.Math.isFinite` n'accepte qu'un vrai nombre fini : NaN arrive d'un client par JSON, passe
toutes les comparaisons et empoisonne toute somme où il atterrit. `OPX.Math.distanceSquared` sert
à tout test « à moins de N » : même question, sans racine carrée. `OPX.Math.groupDigits` sépare
les milliers d'un montant affiché, par une espace par défaut.

## Les frontières de confiance

La plateforme authentifie qui envoie un message, jamais ce qu'il contient : `OPX.Validate`
vérifie ce qui la traverse. `OPX.Validate.text` rogne puis borne la longueur en caractères, pas en
octets, et refuse l'UTF-8 malformé plutôt que de le mesurer. Avant le rognage, la chaîne est
bornée en octets — le seul travail ici qui croît avec l'entrée — à quatre octets par caractère
permis plus 16, et à 1024 pour un appelant qui n'a pas donné de `max`. `OPX.Validate.oneOf` prend
un ensemble, pour que la vérification soit une seule lecture de hachage.

## Les hooks

`OPX.Hooks` garde additif un fichier de gameplay ajouté à la resource. Un hook tourne dans
l'opération qu'il garde : un hook qui cède la main bloque un transfert d'argent. La priorité la
plus basse passe d'abord, et les priorités égales dans l'ordre d'enregistrement (celui du
manifeste). La liste est triée à l'écriture et non à la lecture : elle est écrite au chargement et
lue à chaque appel. `OPX.Hooks.trigger` appelle chaque hook sous `pcall` : un hook appartient au
fichier de quelqu'un d'autre, et un hook cassé n'a pas d'avis ; seul un `false` explicite est un
veto. `OPX.Hooks.has` permet de ne pas construire une charge utile que personne ne lira.

## Les locales

Le texte vu par un joueur passe par `OPX.Locale` et la globale `locale(key, params)` ; les
journaux serveur restent en anglais quelle que soit la locale. `OPX.Locale.set` accepte un code
inconnu, qui retombe sur l'anglais : les catalogues s'enregistrent après le chargement de ce
fichier. `OPX.Locale.t` ne répond jamais nil : une traduction manquante retombe sur `en`, puis sur
la clé elle-même. La locale est appliquée au chargement du fichier, faute de quoi `LOCALE` dans
`config/shared.lua` resterait sans effet.

## Les définitions et l'affichage

`OPX.ResolveJob` et `OPX.ResolveGang` répondent un Result plutôt que nil, pour qu'un appelant
distingue « pas de tel métier » de « pas de tel grade dans ce métier ». `OPX.TopGrade` donne le
grade le plus haut d'une table contiguë depuis 0, pour qu'un appelant borne au lieu d'échouer.

`OPX.NAME_PATTERN` décrit une lettre par une plage d'octets plutôt que `%a`, qui est ASCII seul et
refuserait « Éloïse ». Les octets de tête sur quatre octets sont exclus : c'est là que vivent les
émojis.

`OPX.IsNotifyPosition` est indicatif : sur `false`, un appelant avertit plutôt que de laisser
tomber le toast. `OPX.FormatMoney` affiche `12 500 €$` pour EDDIES et le nom du type pour tout
autre.

`OPX.Now` donne des millisecondes monotones du processus. `GetGameTimer` est résolu au premier
usage et non au chargement : pendant l'amorce, la globale peut ne pas encore être installée. Le
repli remet `Open77.time.monotonic()` en millisecondes : une constante ferait comparer à chaque
délai deux nombres égaux, pour toujours.

## Les données statiques

`data/jobs.lua` et `data/gangs.lua` sont des définitions et non des réglages : la clé est stockée
sur la ligne du personnage, donc on en ajoute librement et on n'en renomme jamais. Les grades sont
indexés depuis 0 et contigus. `none` est l'absence de gang, gardée comme entrée pour que rien n'ait
à traiter nil. `unemployed` a `defaultDuty = true` : il n'y a rien où pointer, donc sa petite paie
n'exige pas de service. `data/origins.lua` liste les parcours de vie proposés à la création,
validés contre cette liste, stockés dans `PlayerData.charInfo.origin` et jamais relus par le core.

## La configuration

`config/shared.lua` part chez chaque client dans le jeu de resources signé : tout y est public.
Identifiants, webhooks et identifiants d'administrateurs vont dans `config/server.lua`, qui n'est
jamais distribué. Les nombres qu'un opérateur peut changer en cours de partie sont redéclarés comme
tunables dans `server/tunables.lua`, avec ces valeurs pour défaut. `config/vehicles.lua` reste au
serveur : un format de plaque et un plafond d'apparition ne regardent pas le client.
`config/client.lua` n'est pas autoritaire : un client modifié peut tout y changer, et le serveur
re-dérive ce qui compte.

## Le démarrage

Le démarrage (`server/main.lua`) tourne dans son propre thread : la création des tables attend des
allers-retours avec la base, et le chunk principal du fichier doit rendre la main tout de suite.
Il sonde la base, applique le schéma, cherche les ressources en conflit, avertit si
`DEFAULT_SPAWN.SET` est faux, puis pose `OPX.Booted`.

`OPX.Booted` est posé dans les deux cas : les exports serveur répondent `core.booting` tant que la
question du schéma n'est pas tranchée, puis répondent, en mode dégradé ou non. `OPX.BootError`
dit pourquoi le core ne peut pas charger de personnage (`no database`, `schema failed: <table>`).

`warnAboutPlacementConflicts` interroge `GetResourceState` pour chaque nom de
`CONFLICTING_PLACERS` : c'est le seul moyen de savoir, puisque les ressources serveur ne peuvent
pas s'appeler. Un état `starting` compte : une ressource qui démarre placera des joueurs dans un
instant. La vérification est protégée par un `pcall`, pour qu'une erreur n'arrête pas le démarrage.

## Le pont MySQL

`server/storage/main.lua` est le seul endroit qui parle au pont `MySQL`. Chaque appel cède la
main : il se fait depuis un `CreateThread`, jamais au niveau du fichier ni dans un gestionnaire
qui ne tourne pas dans un thread. Les requêtes utilisent des paramètres nommés (`@citizen`) :
le pont réécrit les `?` en parcourant le texte de la requête.

`MySQL.<méthode>.await` lève une erreur au lieu de répondre `valeur, raison`, et une erreur
levée dans un `CreateThread` tue ce thread en silence. `run` enveloppe donc chaque appel dans un
`pcall` et répond un `Result` : `no-database` quand le pont n'est pas installé, `query-failed`
avec l'exception brute en `detail` quand il lève. Une valeur `nil` est un résultat vide, pas un
échec : `single` répond `nil` pour « aucune ligne ».

`OPX.Storage.update` est aussi la bonne méthode pour le DDL ; `OPX.Storage.execute` en est un
alias pour les requêtes dont personne ne lit la réponse.

`OPX.Storage.transaction` est séparée de `run` parce que c'est la seule méthode du pont qui
résout `false, raison` au lieu de lever : passée par `run`, un rollback serait lu comme une
réussite. Elle distingue `transaction-raised` (le pont a levé) de `transaction-failed` (il a
annulé).

`OPX.Storage.ready` sonde la base une fois (`SELECT 1`) et garde la réponse pour toute la durée
de la ressource : `nil` tant que la sonde n'a pas eu lieu, puis `true` ou `false`. Sans base, le
core démarre quand même, dit en deux lignes que personne ne pourra se connecter tant que ce
n'est pas réparé, et `OPX.BootError` vaut `no database`.

### Une absence voyage comme une chaîne vide

Le pont abandonne un paramètre `nil` au lieu de le lier à `NULL`, et MySqlConnector refuse alors
la requête (`Parameter '@x' must be defined`). Une colonne nullable reçoit donc `''` pour « rien »
et la requête le retransforme en `NULL` avec `NULLIF(@x, '')` : un JSON encodé n'est jamais vide,
un nom d'apparence de véhicule non plus. `OPX.Storage.Nullable` le fait pour toute colonne JSON,
dans les trois fichiers de requêtes ; le nom d'apparence d'un véhicule, qui n'est pas du JSON, est
lié de la même façon directement dans `OPX.Storage.Vehicles.insert`.

À la lecture, `OPX.Storage.Decode` accepte une chaîne ou une table déjà décodée, parce qu'une
version du pont peut faire l'un ou l'autre. Une colonne qui ne se décode pas est absente plutôt que fatale : le
personnage se charge avec la valeur par défaut de la colonne, la pile d'objets se charge sans ses
métadonnées.

## Les requêtes sur un personnage

Toutes les requêtes du core sur un personnage sont dans `server/storage/players.lua`, et toutes
répondent un `Result` en cédant la main. Aucune ne décide de rien : la propriété et la
suppression sont vérifiées par l'appelant.

- **L'entité.** `toEntity` donne une valeur par défaut à chaque colonne JSON ; `appearance` vaut
  `nil` par défaut, ce qui veut dire « jamais capturée ». Elle est aussi publiée en
  `OPX.Storage.Players.toEntity` pour un plug-in qui ferait sa propre lecture.
- **Le compte.** `OPX.Storage.Players.upsertAccount` réécrit `display_name` sans condition et
  pose `last_seen_at` explicitement : `ON UPDATE CURRENT_TIMESTAMP` ne se déclenche que si une
  colonne change.
- **La liste.** `OPX.Storage.Players.fetchAll` trie les personnages jamais joués en tête, là où
  le joueur regarde, puis du plus récemment joué au plus ancien.
- **Le numéro d'emplacement.** `OPX.Storage.Players.nextCid` prend le plus petit numéro libre
  plutôt que le plus grand plus un : un emplacement supprimé est réutilisé au lieu de voir les
  numéros grimper au-delà de la limite configurée.
- **Les collisions sont tranchées par la clé.** `OPX.Storage.Players.insert` (et
  `OPX.Storage.Vehicles.insert` pour une plaque, `OPX.Storage.Inventories.ensure` pour un
  conteneur) laisse la clé unique décider, jamais un `SELECT` préalable : deux joueurs qui créent
  dans le même tick passeraient tous les deux ce contrôle.
- **L'identité ne se réécrit pas.** `OPX.Storage.Players.save` n'a ni `citizen_id` ni `user_id`
  dans sa liste `SET` : un `UPDATE` capable de déplacer un personnage vers un autre compte est
  exactement la façon dont on vole des personnages.
- **Visage et vêtements s'écrivent tout de suite.** `saveAppearance` et `saveClothing` écrivent au
  moment où le client valide, pas à la sauvegarde automatique suivante. Pour le visage, `nil`
  efface la colonne, ce qui signifie « ce personnage n'a pas de visage enregistré ».
  `fetchClothing` distingue « rien d'enregistré » (`nil`) d'une ligne dont le JSON ne se décode
  pas (`clothing-unreadable`), qui n'est pas « rien ».
- **La suppression est douce.** `OPX.Storage.Players.softDelete` garde la ligne : une erreur se
  rattrape, et un identifiant citoyen n'est jamais redonné à un inconnu.
  `OPX.Storage.Players.countRows` est la seule lecture du core qui ne filtre pas `deleted_at` :
  elle compte les lignes jamais écrites par un compte, et c'est elle qui borne le cycle
  créer-supprimer-créer.
- **Les appartenances.** `OPX.Storage.Players.upsertGroup` rejoint un groupe ou change de grade :
  lequel des deux découle de la clé primaire composite, pas du site d'appel qui aurait pensé à
  vérifier. `OPX.Storage.Players.membersOf` s'arrête à 200 lignes : un résultat non borné bloque
  le worker de la base.

## Les véhicules en base

`server/storage/vehicles.lua` lit et écrit `opx77_vehicles` sans aucune politique :
`server/vehicles.lua` décide. L'état (`OPX.Storage.Vehicles.STATE` : `OUT` 0, `STORED` 1,
`IMPOUNDED` 2) est un nombre et non une chaîne : la colonne est un `TINYINT`, et un mode de jeu
ajoute ses propres états sans changer la table. La colonne `body` porte toute la vue des dégâts : carrosserie,
vitres, phares, pneus et `detachedParts`. `OPX.Storage.Vehicles.setState` n'écrit qu'une colonne,
pour qu'un changement d'état ne réécrive pas une copie périmée de tout le reste ;
`OPX.Storage.Vehicles.countByOwner` sert au plafond par personnage.

## Le stockage des inventaires

`server/storage/inventories.lua` lit et écrit `opx77_inventories` et `opx77_inventory_items` sans
politique non plus : `server/exports.lua` valide, `opx77_inventory` décide de ce qui va dans un
conteneur.

- `OPX.Storage.Inventories.characterExists` ne reconnaît qu'un personnage vivant : le sac d'un
  personnage supprimé reste dans la table, et personne ne l'ouvre.
- `OPX.Storage.Inventories.ensure` laisse la clé unique `(kind, owner)` départager deux créateurs
  simultanés ; la taille donnée ne sert qu'à celui qui crée.
- `OPX.Storage.Inventories.contents` pagine par numéro d'emplacement et non par décalage : une
  sauvegarde qui tombe entre deux pages ne peut pas faire sortir une pile des deux. Sa limite (et
  celle de `holders`) est une constante de l'appelant, formatée dans la requête.
- `OPX.Storage.Inventories.save` réécrit chaque conteneur listé comme une seule unité : un
  `DELETE`, les `INSERT`, puis le tampon `updated_at`. Les lignes d'un conteneur partent en
  plusieurs requêtes de la même transaction au-delà de `ROWS_PER_INSERT` (50), ce qui garde courte
  la liste de paramètres de chaque requête. C'est le seul endroit en paramètres positionnels :
  une requête de transaction est liée comme les ressources de la plateforme la lient, et le
  nombre de `?` est comparé aux valeurs avant tout envoi.
- `OPX.Storage.Inventories.delete` supprime un conteneur ; ses piles partent par cascade.

## Le schéma

`OPX.Schema` (`server/storage/schema.lua`) est une seule liste ordonnée d'instructions
`CREATE TABLE IF NOT EXISTS`, une par table que possède le core, dans l'ordre de leurs clés
étrangères. `OPX.Storage.applySchema` les exécute toutes à chaque démarrage : une table qui existe
n'est pas touchée, une table absente est créée. `sql/schema.sql` porte les mêmes instructions,
commentées, pour un opérateur ; les deux se modifient ensemble. Aucun commentaire n'entre dans les
chaînes Lua (voir `docs/unknowns.md`, « paramètres nommés »).

Il n'y a pas de migrations, et c'est voulu tant que le projet est en développement : la base est
recréée à chaque changement de table plutôt que migrée, et une instruction `IF NOT EXISTS` ne
modifie jamais une table existante. Il n'y a donc ni table d'historique, ni migration optionnelle,
ni reprise au démarrage suivant.

`OPX.Storage.applySchema` s'arrête à la première instruction qui échoue plutôt que de continuer sur
un schéma incomplet : le démarrage pose `OPX.BootError = 'schema failed: <table>'` et le core
refuse les connexions, exactement comme sans base. Les vêtements n'ont plus de régime à part : si
leur table ne peut pas être créée, personne ne se connecte, au lieu d'un core qui démarre sans
restaurer ni sauvegarder ce que portent les personnages.

## Le journal d'audit

`OPX.Logger` (`server/logger.lua`) est le journal de ce dont un opérateur devra rendre compte plus
tard, par opposition à `Open77.log`, qui dit ce que fait le code. Le journal de la plateforme est
son seul support : chaque entrée est une ligne `[audit] event=... severity=... citizen=... user=...
player=... message="..." data=...`, toujours de la même forme pour qu'un `grep` la retrouve.

- **Tout peut venir d'un client.** Le message et les données sont bornés à `MAX_MESSAGE`
  (200 caractères) et débarrassés de leurs caractères de contrôle. `OPX.Logger.safe` est publiée
  pour cette raison : un saut de ligne dans un texte choisi par un client forge une ligne de
  journal entière, attribuée à la ressource que l'attaquant nomme.
- **Les répétitions sont regroupées.** Une entrée identique (même événement, même propriétaire)
  dans une fenêtre de `DEDUPE_MS` (10 s) n'est pas écrite mais comptée, pour qu'un client qui
  boucle sur un refus coûte une ligne et un nombre au lieu d'un écran. La première entrée après
  la fenêtre porte `[+N suppressed]` ; une fenêtre fermée est gardée `RETAIN_MS` (six fenêtres)
  pour pouvoir le dire. Le propriétaire est rangé à côté de la clé plutôt que relu dedans, parce
  qu'une clé se termine soit par la source, soit par l'identifiant citoyen.
- **Le grand livre n'est jamais regroupé.** Une entrée `info` ou `debug` sous `money.` ou
  `character.` (`LEDGER_PREFIXES`) est écrite à chaque fois : six achats en huit secondes sont
  six réponses, et les regrouper détruirait l'enregistrement. Un refus sous ces préfixes l'est
  quand même, par sa sévérité : `OPX.Logger.security` est le seul producteur de `warn`, et un refus
  n'est pas une ligne de grand livre.
- **Ce qui borne la table.** `sweep` parcourt les entrées récentes au plus une fois par fenêtre
  (`nextSweepAt`) — balayer à chaque entrée serait un parcours complet par ligne — et c'est lui,
  pas `OPX.Logger.forget`, qui borne la table. Il n'efface que des clés déjà rendues par `pairs`,
  ce que Lua définit ; en ajouter pendant le parcours ne l'est pas.
- **Au départ.** `OPX.Logger.forget` retire les fenêtres d'une source qui part, pour qu'une source
  qui ne revient jamais ne garde pas de clé. Un appelant qui connaît l'identifiant citoyen le
  passe : une entrée journalisée sans source est indexée par identifiant citoyen, qu'une source
  qui part ne nomme pas.
- **Toujours passer la source.** Sans elle, `OPX.Logger.security` indexe la fenêtre par événement
  seulement, et un joueur qui boucle sur un refus avale ceux de tous les autres.
  `OPX.Logger.player` couvre la forme la plus courante (source, citoyen et compte d'un `Player`).

## Les réglages à chaud

`server/tunables.lua` déclare à `Open77.tunables` les valeurs qu'un opérateur peut changer depuis
le panneau Warden pendant que des gens jouent. Elles se lisent dans `OPX.Tune.KEY` au moment de
s'en servir : copiée dans une locale au niveau du fichier, une valeur resterait figée pour toute la
durée de la ressource.

- Chaque valeur déclarée a pour défaut la clé de `config/server.lua` correspondante ; ensuite, le
  panneau et `tunables.json` de l'hôte en sont les propriétaires.
- `Open77.tunables.declare` lève en cas de déclaration refusée, et c'est voulu : mieux vaut ne pas
  démarrer que tourner sur une valeur que le panneau ne sait pas régler.
- `SELECTION_MS` a pour plafond `ENTRY.PIPELINE_MS`, lui-même sous `ENTRY.GATE_MS` : le core ne
  rafraîchit jamais sa prise sur la barrière, et une sélection plus longue ferait déclarer le core
  mort par l'hôte en plein écran de sélection.
- `OPX.TuneNumber` relit une valeur avec un plancher. Le panneau impose `min` et `max` ; le
  plancher est aussi la réponse pour une valeur qui ne serait pas un nombre fini, pour qu'aucun
  appelant ne compare un nombre à `nil`. Le test est
  `OPX.Math.isFinite` et non `value ~= value` : une infinité passe un test de NaN et figerait un
  intervalle.

## Les lectures ne cèdent jamais la main

Les accesseurs de `server/functions.lua` (`OPX.GetPlayer`, `OPX.GetPlayerByCitizenId`,
`OPX.GetPlayerByUserId`, `OPX.GetPlayers`, `OPX.GetPlayerCount`, `OPX.Notify`, `OPX.Refuse`,
`OPX.Cooling`...) ne font aucun aller-retour avec la base : ils s'appellent depuis un gestionnaire
d'événement sans thread. La seule exception est `OPX.GetCharacter`, qui lit la ligne quand le
personnage n'est pas en jeu (forme hors ligne : une entité nue, sans `Functions`), et ne
s'appelle donc que depuis une coroutine.

`OPX.GetPlayer` répond `nil` pour quelqu'un encore dans l'écran de sélection : ce n'est pas une
erreur, c'est une session sans joueur.

## Le parcours du roster évince après coup

`OPX.GetPlayers` est le parcours à utiliser, pas `pairs(OPX.Players)` : il revérifie le `userId`
derrière chaque emplacement et évince (déconnexion et sauvegarde, via `OPX.ForgetSession`) celui
dont le compte a changé. Les emplacements périmés sont collectés pendant le parcours et évincés
**après** : les gestionnaires de `OPX.Logout` modifieraient la table en cours d'itération.
`OPX.GetPlayerCount` fait la même vérification sans construire de table et sans évincer.

## Les réponses et les refus

- **`OPX.Notify`** passe par `Open77.notifications`, que l'hôte route vers le paquet client
  officiel `open77_notifications` : sans lui, le toast ne s'affiche nulle part, et le core ne
  déclare aucune dépendance sur lui.
- **`OPX.RefusalKey`** garantit qu'un code rendu à un joueur existe dans le catalogue. La couche
  de stockage répond `query-failed` ou `no-database`, un validateur `too-short` : ces codes sont
  pour le journal, pas pour un joueur, et deviennent `error.unavailable` (avec une ligne
  d'avertissement). `OPX.NotifyLocale` s'en sert : une clé absente est remplacée plutôt
  qu'affichée brute.
- **`OPX.CommandResult`** répond par une ligne de chat à une commande dont on a demandé à lire le
  résultat (une liste, un dump, un bloc de configuration). Pas sur `open77:command:result` :
  `opx77_chat` n'affiche aucun résultat accepté sur ce canal. Ce qu'une commande a **fait** passe
  par `OPX.CommandNotice`, un toast levé par la moitié client du core via `opx77_notify`, qui
  redevient la ligne de chat d'autrefois sur un client sans `opx77_notify`. `toasted` signale que
  l'action a déjà levé le même toast par `OPX.Notify` : le client n'écrit alors que la ligne de
  chat, et seulement s'il n'a pas de toast. Source `nil` ou `0` : la console, qui lit un `print`.
- **`OPX.Refuse`** dit au client quelle requête est refusée et avec quel code, et rien d'autre :
  un refus qui s'explique dit à un attaquant quelle moitié de sa supposition était juste. Le code
  passe par `OPX.RefusalKey`, donc ce canal n'envoie jamais un code que le client ne sait pas
  rendre. L'`operation` (une valeur de `OPX.Operations`) est indispensable : sans elle, un client
  qui attend la réponse à l'une de plusieurs requêtes ne sait pas quel `error.tooFast` est le sien.

## La suppression des réponses répétées

`OPX.Notify` tient une fenêtre par joueur (`repeated`, `lastAnswer`) : un toast identique
(même type, même texte) envoyé au même joueur dans les 2 000 ms (`ANSWER_DEDUPE_MS`) est avalé.
Seule une répétition exacte l'est : deux toasts différents sont deux choses que le joueur doit
apprendre.

`OPX.Refuse` n'y passe pas. Un refus est la réponse à une requête, et les clients
(`opx77_charselector`, `opx77_charcreator`, `opx77_appearance`) ne libèrent leur requête en
attente qu'à sa réception : un second refus identique avalé laissait le sélecteur verrouillé
jusqu'à son délai de 20 s. Chaque requête est déjà refroidie par opération à sa porte, donc un
refus coûte au plus un petit événement par requête admise.

La table d'un joueur est bornée à 32 textes, sans quoi un client qui provoque un texte nouveau à
chaque message la ferait grossir pour toute la session. À 32, les fenêtres déjà fermées sont
retirées ; s'il en reste 32, seule la plus ancienne l'est. Vider la table entière perdait les
fenêtres encore ouvertes, et un toast identique repartait avant ses 2 000 ms. Les clés retirées
pendant le parcours sont celles que `pairs` vient de rendre, ce que Lua permet.

## Les délais par joueur

`OPX.Cooling` tient un délai par joueur **et par opération**, pas par porte d'entrée : la même
opération atteinte par un événement réseau et par une commande partage sa fenêtre. Ce n'est pas
une frontière de sécurité, les vérifications de propriété de `server/character.lua` le sont.
`OPX.Cooling` enregistre la tentative qu'il laisse passer ; la console (source 0) n'est jamais
refroidie.

`OPX.ForgetCooldowns` vide, au départ d'un joueur, ses délais **et** sa fenêtre de toasts : un
identifiant de joueur est recyclé, et une fenêtre laissée derrière refuserait l'action suivante du
prochain joueur à porter cet identifiant, ou avalerait son premier toast.

## Les portes réseau

`server/events.lua` ne décide rien : chaque gestionnaire valide ce qui arrive et appelle
`server/character.lua` ou `server/player.lua`. Tout ce qu'un client envoie est contrôlé par
l'attaquant ; seul `source` ne se falsifie pas.

- **`onPlayerConnected`** est un événement diffusé par l'hôte : `source` n'y est pas renseigné,
  l'identifiant arrive donc en argument, et sous forme de chaîne. Il ne porte rien d'autre : le
  nom et le compte de la ligne de connexion sont lus dans la session, que
  `OPX.Lifecycle.beginEntry` vient de créer. Un identifiant inutilisable (non numérique, ou ≤ 0)
  est journalisé et ignoré.
- **Le départ** (`onPlayerDisconnected(playerId, reason)`) est au mieux : un départ que personne
  ne signale est couvert par la revérification du `userId` dans `OPX.EnsureSession`, et
  `OPX.Logout` est idempotent. La session est marquée `departing` **avant** la déconnexion du
  personnage : un joueur sur le départ n'est pas remis dans un bucket de sélection, et l'hôte
  supprime de lui-même le bucket d'un joueur parti. Une ligne d'audit `session.disconnect` porte
  `reason` (`connection_closed` pour un joueur parti ou un lien perdu, sinon le texte donné à
  `disconnect`, `kick` ou `ban`), pour distinguer un départ d'une expulsion. L'identifiant
  citoyen est lu **avant** `OPX.Logout`, qui le retire. Le gestionnaire vide ensuite les cooldowns
  (`OPX.ForgetCooldowns`) et la déduplication de l'audit (`OPX.Logger.forget`), indexées par
  source, alors qu'une source est recyclée ; l'identifiant citoyen lu plus tôt est passé à
  `OPX.Logger.forget` pour les entrées indexées par personnage.
- **`onPlayerReady`** : un `detail` de la forme `liveness_lost:<res>[,<res>...]` veut dire qu'une
  retenue a dépassé son échéance de vivacité et que la plateforme a conclu que son détenteur
  avait disparu. Si `opx77_core` figure dans la liste, la ligne d'avertissement dit que le joueur
  est peut-être dans le monde sans personnage.
- **Les cooldowns des portes.** Chaque gestionnaire vérifie un cooldown **avant** son
  `CreateThread`, sur une clé `.request` qui lui est propre (`select.request`, `create.request`,
  `delete.request`) : `OPX.Cooling` enregistre la tentative qu'il autorise, donc partager la clé
  de l'opération elle-même (`select`, `create`, `delete`, que les fonctions de
  `server/character.lua` consomment) ferait refuser l'opération par elle-même. Les commandes
  ouvertes équivalentes (`tooFast` dans `server/commands.lua`) prennent **la même** clé
  `.request` que la porte réseau, pour que les deux entrées partagent une seule fenêtre.
- **`opx77:server:ready`** est l'annonce du client, et c'est ce qui remplit le roster après un
  rechargement : `onPlayerConnected` ne se redéclenche pas pour les joueurs déjà là. Un joueur
  qui a déjà un personnage chargé reçoit `playerLoaded` (le roster rouvrirait l'écran de
  sélection). Sinon, le joueur est isolé dans son bucket de sélection **seulement** si sa
  barrière est encore fermée (`OPX.Lifecycle.isReady`) : c'est une arrivée dont le déplacement a
  été refusé à la connexion, ou un joueur encore derrière la barrière au rechargement de la VM.
  Quelqu'un qui a passé la barrière a été dans le monde pendant cette session et reste où il
  est : après un rechargement, c'est tout le monde qui jouait.
- **`opx77:server:selectCharacter`** : un refus n'est journalisé que s'il n'est pas
  `error.tooFast`. La branche du cooldown est justement celle que prend un attaquant ; la
  journaliser ferait de la limite un écrivain d'une ligne par message. Le refus part sur le fil
  seulement, sans toast : `opx77_charselector` le rend déjà dans sa ligne d'état, et le même
  texte en toast le disait deux fois. `opx77:server:createCharacter` garde son toast à côté du
  refus : `opx77_charcreator` s'en sert quand son formulaire est déjà fermé.
- **`opx77:server:reportPosition`** est un indice. Seul le cap est conservé : x, y et z sont
  re-dérivés de l'instantané serveur au moment de la sauvegarde, donc un client qui ment sur eux
  ne ment à personne. Le cooldown est un littéral (1000 ms) et non
  `CLIENT.POSITION_REPORT_MS` : la VM serveur ne charge jamais `config/client.lua`.

## Les commandes et leurs réponses

Le troisième argument de `RegisterCommand` rattache une commande à la permission ACL
`command.<nom>`, que l'hôte résout avant que le gestionnaire ne tourne ; chaque commande ouverte
passe d'abord par un cooldown de porte. `register` enregistre la commande **et** retient son nom
et son drapeau dans `registered`, que lisent les suggestions : une commande ne peut pas être
ajoutée sans que le chat apprenne si elle est restreinte.

- La console tourne en source 0, qui n'est pas un joueur et n'a pas de personnage
  (`requirePlayer`) ; `OPX.Cooling` répond toujours faux pour elle.
- `targetOf` résout un argument joueur ou citoyen par sa forme **analysée**, jamais la brute :
  un identifiant citoyen tapé sans son séparateur en reste un.
- `opx77` et `opx77.where` trient ce qu'ils listent (les joueurs par source, les types de
  monnaie par nom) pour que deux exécutions se comparent ligne à ligne. `opx77.where` ne montre
  que ce que croit le **serveur**. `opx77.here` imprime la position exactement dans la forme
  qu'attend `config/shared.lua` (`DEFAULT_SPAWN`).
- `opx77.create` ne renvoie que la ligne de locale : la commande est ouverte, et `detail` peut
  contenir une exception brute de la base.
- `opx77.job`, `opx77.gang` et `opx77.group` rendent un échec par `failureText` : un code du
  catalogue devient sa ligne de locale (avec `detail` pour les deux premières, le nom du métier
  ou du gang), et un code de stockage (`query-failed`, `no-database`) devient
  `error.unavailable` à l'écran, sa cause écrite dans le journal. Ce sont des commandes ACL, mais
  un message MySQL n'a rien à faire dans un toast.
- `opx77.duty` est ouverte, et chaque exécution coûte deux événements sortants portant tout
  `PlayerData` : d'où son cooldown de 2 s. Une réussite est déjà annoncée en toast par
  `OPX.SetJobDuty` ; le drapeau `toasted` de `OPX.CommandNotice` la limite à un seul toast, et à
  la seule ligne de chat sur un client qui n'a pas de toast à montrer.
- `opx77.money` utilise un vrai `if/else` : dans `a >= 0 and Add() or Remove()`, un `false`
  rendu par `Add` exécuterait aussi `Remove`. Une seule table de paramètres couvre tous les codes
  que renvoient les mutateurs : `money.insufficient` porte un `{type}`, les autres non, et un
  paramètre en trop est ignoré.
- `opx77.save` réécrit tout de suite chaque personnage chargé, pour la minute qui précède un
  redémarrage prévu.

## L'autocomplétion

Les suggestions partent sur `chat:ready` : envoyées au démarrage, elles n'arriveraient nulle
part. `HELP` porte, par commande, des clés de catalogue rendues au moment de l'envoi, et les
paramètres dans l'ordre où le gestionnaire lit `args` ; `helpValues` lit la configuration telle
qu'elle est au moment de l'envoi et trie les types de monnaie, sans quoi l'ordre de `pairs`
remanierait la liste d'une suggestion à l'autre. Une commande restreinte n'est proposée qu'à un
joueur que l'ACL laisserait l'exécuter (`permitted`, par `Open77.acl.isAllowed`) : une suggestion
est un indice dans une zone de texte, pas une autorisation, et la liste du staff ne regarde
personne d'autre. Une lecture de l'ACL qui lève compte comme un refus : la
commande est alors proposée à personne plutôt qu'à tout le monde. `chat:ready` est un événement réseau que n'importe qui peut
envoyer, et la réponse pèse quelques kilo-octets : il a son propre cooldown de 10 s.

## La barrière d'entrée

> do not teleport, spawn, kill or force a respawn on a player until their
> readiness gate has opened.

Le core déclare sa participation une fois au boot, ce qui pose un verrou sur
chaque joueur connecté ensuite — il ne court pas après un verrou avant qu'autre
chose déplace le joueur, il en a déjà un avant que le joueur existe.

Deux échéances, et la nôtre est la plus courte. L'`livenessIntervalMs` déclaré
au `participate` n'est pas une limite imposée au joueur : c'est un chien de
garde sur nous, et il ne se déclenche que sur la preuve que le détenteur du
verrou a disparu. L'hôte ouvre alors la barrière lui-même et émet
`liveness_lost:opx77_core` — pas `timeout:`, qui n'existe dans aucune assembly
livrée malgré ce qu'annonce le site — potentiellement avec le joueur encore
dans l'écran de sélection et **sans pantin du tout**. Le core se donne donc une
échéance en dessous : il abandonne le premier, relâche délibérément, et dit
pourquoi.

Le nôtre n'est d'ailleurs pas le seul verrou. Chaque joueur en porte un second,
nommé `__platform`, sans échéance et qu'aucun Lua ne peut relâcher : il ne
tombe que lorsque le client a annoncé `open77:session:gameplayReady`, ce
qu'émet `open77_appearance` une fois le pantin réellement attaché et vivant.
C'est ce qui donne son sens à une barrière ouverte — « ce joueur est incarné »,
et pas seulement « les autres ressources ont fini ». Sur un serveur sans
ressource qui émette cet événement, aucune barrière ne s'ouvre jamais.

Le placement se fait par **kill → respawn**, jamais par transform brut : la
transaction de respawn porte le fondu, le préchargement du streaming et la
fenêtre de grâce qu'un téléport direct saute. Et l'état de vie est lu avant,
parce que la barrière peut s'être ouverte sur un abandon de verrou plutôt que
sur une incarnation.

- `OPX.Lifecycle.participate` est appelé une fois, au chargement, pour que chaque connexion
  ultérieure arrive avec une prise au nom du core. Chaque joueur arrive en plus tenu par
  `__platform`, qui ne tombe que lorsqu'un client émet `open77:session:gameplayReady` ; si ni
  `opx77_appearance` ni `open77_appearance` ne tourne, une ligne l'annonce.
- `OPX.Lifecycle.hold` retient le numéro de session de la barrière : c'est ce qui garde une
  libération honnête, car libérer par un identifiant de joueur recyclé seul pourrait lever la
  prise de quelqu'un d'autre.
- `OPX.Lifecycle.release` est idempotent et sans danger pour un joueur qui n'a jamais eu de
  prise ; la note atteint chaque ressource comme `detail` de `onPlayerReady`. Sans session de
  barrière connue, le statut est **demandé** à l'hôte plutôt que la libération sautée : une prise
  que personne ne libère n'a pas d'échéance et bloque ce joueur aussi longtemps que la ressource
  répond.
- `OPX.Lifecycle.isReady` lit comme ouverte une barrière pour un identifiant sur lequel l'hôte
  lève.
- `OPX.Lifecycle.beginEntry` tourne sur son propre thread pour la lecture en base, et aucun
  chemin d'échec ne laisse le joueur tenu. Sans identité vérifiée, `refuseEntry` relâche la
  barrière puis ferme la session par `Open77.players.disconnect`, avec le texte
  `entry.noIdentity` que le joueur lit sur son écran ; chaque tentative du sélecteur retomberait
  sur la même absence d'identité. Si l'hôte refuse la déconnexion, une ligne d'erreur le dit et le
  refus part sur le fil (`OPX.Refuse`, opération `entry`). Le core ne teste pas la présence de
  l'API : elle est documentée. Un roster en échec et le délai de sélection ne déconnectent pas :
  le joueur est isolé, le sélecteur redemande le roster, et `SelectCharacter` marche encore après
  le délai (un opx77_charcreator encore ouvert serait sinon expulsé). Le déplacement dans le
  bucket de sélection se fait volontairement sous la barrière fermée : il n'écrit ni
  transformation ni état de vie, et pris à ce moment personne d'autre n'est jamais répliqué dans
  le monde que ce joueur s'apprête à charger. Un refus aussi tôt est retenté au `READY` du
  client.
- `OPX.Lifecycle.watch` abandonne un joueur qui ne choisit jamais : un thread par joueur entrant,
  sur un budget de 1 024, qui sort dès que la barrière est libérée ou que l'emplacement change de
  main. Le corps de la vérification est sous `pcall` : une levée laisserait ce joueur tenir la
  barrière pour toute la session.

## Le bucket de sélection

Un joueur sans personnage chargé attend dans un routing bucket à lui (`server/buckets.lua`),
pour que personne en train de choisir ne voie ni ne soit vu. Voir le README, « The selection
bucket ». Les identifiants de bucket de l'hôte sont des uint32 (`UINT32_MAX`) et les identifiants
de joueur de petits entiers recyclés : le bucket de sélection vaut `BASE + id`, donc toute la plage
va de `BASE + 1` à `BASE + ID_SPAN` (65 535).

La configuration de l'opérateur (`ENTRY.BUCKET`) est résolue une fois au chargement : une valeur
invalide est signalée une fois et la valeur livrée est utilisée. Un `WORLD` situé dans la plage de
sélection coupe l'isolation (ligne d'erreur). `ISOLATE = false` coupe toute la fonction : personne
n'est déplacé, et un bucket stocké est honoré comme avant. `LOCKDOWN = false` laisse le mode de
l'hôte tel quel.

Les fonctions de l'hôte sont celles d'`Open77.routingBuckets`, installé pour toute ressource
serveur et sans permission de manifeste ; chaque appel passe par un `pcall`, et une lecture qui
lève répond « bucket inconnu ».

La politique d'un bucket de sélection (pas de population ambiante, le lockdown configuré, comme
la plateforme prépare ses propres manches isolées) est posée par `prepare` une fois par bucket :
elle appartient au bucket et survit au joueur, et elle est reposée après un rechargement (la table
`prepared` est celle de la VM).

- `OPX.Buckets.isSelection` répond même isolation coupée, pour reconnaître une position stockée là
  par une configuration antérieure.
- `OPX.Buckets.placementOf` : un bucket stocké dans la plage de sélection, ou qui n'est pas un
  identifiant de bucket, se lit comme `WORLD` : un bucket de sélection appartient à qui porte
  l'identifiant de joueur maintenant, jamais à un personnage.
- `OPX.Buckets.move` journalise chaque déplacement en debug, et un refus aussi en warn : le joueur
  attend alors dans le mauvais monde, ou y entre.
- `OPX.Buckets.isolate` refuse un joueur qui a un personnage chargé (il est dans le monde) ou qui
  part (`session.departing` : son identifiant est peut-être déjà donné à quelqu'un d'autre).
- `OPX.Buckets.release` ne touche qu'un joueur qui est dans sa plage de sélection : un bucket
  choisi depuis par une autre ressource est laissé tel quel. Il répond `true` aussi quand il n'y
  avait rien à relâcher, et dit à part si un déplacement a eu lieu.
- À l'arrêt du core (`onResourceStop`), tout joueur encore dans un bucket de sélection est rendu à
  `WORLD` : personne n'est laissé dans un bucket qu'aucune ressource en marche ne connaît. Après
  un rechargement, c'est le `READY` du client qui réisole quiconque est encore derrière la
  barrière.

## Le déplacement de bucket sous la barrière fermée

Un déplacement de bucket n'est pas un placement : il change les corps, props et véhicules que
l'hôte réplique vers et depuis le joueur, sans écrire la transformation, l'état de vie ni le
pantin, qui sont ce dont la barrière de disponibilité protège un client pas encore incarné. Il se
fait donc barrière fermée, dès le premier instant où le core connaît le joueur.

## Multipersonnage

Tout ce qui touche au roster, à la création, à la suppression et à la sélection
(`server/character.lua`) lit la base : ces fonctions ne s'appellent que depuis un
`CreateThread`.

**Le roster.** `OPX.SendCharacters` enregistre le compte derrière la session puis envoie ses
personnages vivants. L'appeler deux fois est sans danger : un rechargement vide le roster de
cette VM et le client se réannonce. Le refroidissement (clé `roster`, 2 s) est posé ici et non
à une porte d'entrée, parce que la fonction est aussi atteinte par la commande libre
`/opx77.characters`. Un envoi déjà limité par son appelant (`pushed`) n'est ni refroidi ni
refroidissant : l'envoi du core à la connexion, le `READY` du client (clé `ready`) et le renvoi
qui suit une création ou une suppression (clés `create.request`, `delete.request`). L'envoi à la
connexion part avant que les ressources du client tournent et n'arrive donc généralement nulle
part ; s'il refroidissait, le `READY` du client une seconde plus tard serait écarté avec lui. Et
un renvoi après création écarté par le `READY` qui le précède laissait `opx77_charcreator`
attendre 20 s puis rouvrir le formulaire, dont un nouvel envoi créait un second personnage.

**Pas de roster sur un personnage chargé.** `OPX.SendCharacters` relit `OPX.Players` après ses
deux lectures en base et n'envoie rien si un personnage a été chargé entre-temps : il répond
quand même les résumés, que `/opx77.characters` affiche. Pendant un `/opx77.select`,
`opx77_charselector` redemande le roster dès le déchargement ; son `READY` ne voit alors aucun
joueur, et un roster arrivé après `playerLoaded` rouvrait l'écran de sélection, sa caméra et son
verrou de contrôles sur un personnage en jeu.

**Le résumé.** `toSummary` n'envoie volontairement pas l'entité entière : l'argent, les
métadonnées et la position stockée ne regardent personne tant qu'un personnage n'est pas
chargé, pas même le titulaire du compte.

**La création.** `validateRegistration` vérifie une inscription venue du réseau ; le compte est
pris dans la session et jamais dans la charge utile, car `source` est la seule valeur qu'un
client ne peut pas falsifier. La date de naissance n'est que vérifiée en forme, jamais
analysée : le bac à sable retire `os`, il n'y a pas d'horloge contre laquelle la vérifier.
Dans `OPX.CreateCharacter`, le refroidissement (clé `create`, 3 s) vient **après** la
validation : il protège l'écriture, pas un nom mal tapé. Le plafond compte des **lignes** et non
des personnages (`countRows`), parce que la suppression douce garde la ligne alors que
`nextCid` libère l'emplacement. Dans `OPX.TuneNumber('CHARACTER_ROWS', 5)`, 5 est le plancher,
pas une valeur par défaut : la valeur de repli est celle de la configuration.

Une collision d'identifiant citoyen est tranchée par la clé unique de la colonne, pas par un
`SELECT` préalable : deux joueurs créant au même tick passeraient tous deux ce contrôle. Seule
une collision (`duplicate` dans le détail) vaut un nouveau tirage, cinq au plus ; toute autre
erreur échouerait cinq fois de suite.

Les deux lignes d'appartenance (métier et gang par défaut) ne sont pas optionnelles :
`OPX.SetPlayerPrimaryJob` vérifie la ligne d'appartenance, et un personnage sans elle se verrait
refuser à jamais son propre métier par défaut. Si elles échouent, le personnage est supprimé
plutôt que rendu : la ligne a quelques secondes, ne contient rien, et la clé étrangère des
appartenances est `ON DELETE CASCADE`. Si même cette suppression échoue, une ligne d'erreur dit
qu'il faut la retirer à la main.

**La suppression.** `OPX.DeleteCharacter` est douce : la ligne est marquée plutôt que retirée,
donc l'identifiant citoyen n'est jamais réattribué. Les lignes des tables listées dans
`CHARACTERS.CASCADE_TABLES` partent réellement ; leur requête est construite par concaténation
parce qu'un paramètre ne peut pas tenir lieu d'identifiant. Le refroidissement (clé `delete`,
3 s) protège aussi le journal d'audit, puisque chaque suppression refusée écrit une ligne de
sécurité. Le personnage est sorti du monde d'abord, sinon l'autosave réécrit la ligne une
minute plus tard. L'événement interne `CHARACTER_DELETED` est ce que le curseur de changements
de `server/exports.lua` transmet aux autres ressources serveur.

## Pas d'oracle d'existence

Un personnage (ou un véhicule) qui appartient à quelqu'un d'autre reçoit exactement le même code
qu'un personnage inexistant (`character.notFound`, `vehicle.notFound`), dans
`OPX.DeleteCharacter`, `OPX.SelectCharacter` et `OPX.Vehicles.Spawn`. Répondre « pas à vous »
dirait à un attaquant que l'identifiant existe. La tentative est en revanche écrite en ligne de
sécurité (`character.deleteRefused`, `character.notYours`, `vehicle.notYours`).

## La sélection

`OPX.SelectCharacter` est toute la séquence « je choisis celui-ci », et son ordre est le
contrat : connexion, placement, puis libération de la barrière. Le refroidissement (clé
`select`, 1 s) est posé ici parce que la commande libre `/opx77.select` l'atteint aussi.

- Re-sélectionner le personnage déjà chargé répond tôt : sur la **même** ligne, la lecture
  ci-dessous devancerait l'écriture et rendrait les valeurs d'avant la sauvegarde.
- Lors d'un changement de personnage, la cible est vérifiée (existence, propriétaire, déjà en
  jeu ailleurs) **avant** de démonter le personnage courant ; sinon un changement refusé
  laisserait le joueur dans le monde sans rien de chargé ni rien pour le sauvegarder.
- Le démontage est **attendu** (`OPX.LogoutAndWait`) et non délégué à un thread : la lecture du
  personnage suivant devancerait une sauvegarde lancée en parallèle. Si cette sauvegarde échoue,
  le changement est refusé ; le personnage est déjà déchargé, le joueur choisit donc de nouveau
  et retourne dans son bucket de sélection.
- Une connexion refusée **ne libère pas** la barrière : ce serait mettre le joueur dans le
  monde sans personnage. Un changement qui a démonté le dernier personnage le laisse en train de
  choisir, donc hors du monde aussi (`OPX.Buckets.isolate`).
- Un personnage chargé mais non placé est tout de même sorti du bucket de sélection : il joue là
  où il se tient, dans le monde et non seul dans un bucket de sélection.

## Le placement

`OPX.PlaceCharacter` place un personnage chargé par **kill puis respawn**, jamais par écriture
directe de la transformation. Chaque sortie en échec laisse `MaySample` à faux.

- `allowSampling` est le seul endroit où `MaySample` passe à vrai, et il n'est jamais remis à
  faux ici : un personnage placé correctement puis échouant une seconde tentative se tient
  toujours là où il doit être.
- Sans position stockée et sans `DEFAULT_SPAWN.SET`, l'échantillonnage est permis sur **cet**
  échec précis : rien n'a été restauré, donc là où le joueur se trouve devient sa position.
- Le bucket de placement vient de `OPX.Buckets.placementOf` et n'est jamais un bucket de
  sélection, qui appartient à qui détient un identifiant de joueur et non à un personnage.
- L'état de vie est lu cinq fois sur une seconde (`isSettled` : `alive` ou `dead`). La barrière
  n'est pas encore ouverte, et ce sondage est tout ce qui sépare le placement d'un joueur en
  pleine transition ; placer quelqu'un en transition, c'est poser un respawn sur un autre.
- Le joueur est déplacé hors du bucket de sélection **avant** le kill, comme les modes de jeu de
  la plateforme déplacent un joueur avant de le placer : le respawn nomme le même bucket, et rien
  de répliqué depuis le bucket de sélection ne reste à emporter.
- Si le respawn échoue, un revive relève le corps là où il est tombé et non là où la ligne le
  dit : `MaySample` reste donc à faux et la position stockée survit pour la tentative suivante.
- L'armure est appliquée **après** la transaction : ce n'est pas une option du respawn, et le
  corps est sur le point d'être remplacé.

## L'objet Player

`OPX.CreatePlayer` construit un Player autour d'une entité stockée ; `normalise`
(`OPX.NormaliseEntity`) complète d'abord ce qui lui manque, pour qu'un personnage antérieur à un
champ se charge au lieu d'être refusé :

- une monnaie absente vaut **zéro**, pas le montant de départ configuré : un montant de départ est
  une dotation de nouveau personnage ;
- une clé de `STARTING_METADATA` absente est **copiée en profondeur** : une valeur par défaut
  prise par référence serait une seule table partagée par tous les personnages ;
- un `appearance` qui n'est pas une table devient `nil` ;
- un métier ou un gang supprimé de `data/` retombe sur `PLAYER.DEFAULT_JOB` /
  `PLAYER.DEFAULT_GANG` ; la ligne d'appartenance est laissée intacte, en cours d'édition ou non.

Champs du Player :

- `Revision` est le drapeau « sale » de la sauvegarde automatique : incrémenté à chaque
  changement, jamais remis à zéro, et il ne bouge que dans `Functions.UpdatePlayerData`. Il est
  compté **avant** le retour hors ligne : une promotion hors ligne est un changement aussi.
- `MaySample` reste faux tant que le monde n'est pas d'accord avec la ligne stockée.
  `OPX.PlaceCharacter` est le seul à le passer à vrai ; `OPX.ForgetSession` le remet à faux avant
  la sauvegarde d'une éviction.
- La `source` d'un Player hors ligne est forcée à `nil` par un `if`, pas par
  `offline and nil or entity.source`, qui donnerait `entity.source` dans les deux branches.

`Functions.UpdatePlayerData` pousse tout `PlayerData` au client propriétaire ; chaque mutateur
l'appelle lui-même au lieu de le laisser à l'appelant. `Functions.SetPlayerData` refuse (erreur
levée) d'écrire `citizenId`, `userId` ou `source` : c'est l'identité. Les `Functions` d'argent, de
groupe, `Save` (coroutine seulement : elle écrit) et `Logout` sont le même code que les mutateurs
`OPX.*` au niveau du module, donc une règle ajoutée à l'un est suivie par l'autre.

`OPX.ResolvePlayer` accepte les trois formes qu'un appelant peut tenir : un Player, un identifiant
de joueur ou un identifiant citoyen (en jeu seulement).

## L'argent

- Un montant passe par `amountOf` : positif, fini, arrondi à l'entier. NaN arrive par JSON depuis
  un client et passe toutes les comparaisons, y compris celle qui empêcherait le joueur de le
  dépenser. Un montant refusé écrit une ligne de sécurité `money.badAmount`.
- Un Player hors ligne est refusé (`money.offline`) par les trois mutateurs : aucune colonne
  `money` n'est écrite pour un Player hors du roster.
- `OPX.RemoveMoney` refuse au lieu de tronquer quand il n'y a pas assez (`money.insufficient`),
  sauf pour un type listé dans `MONEY.ALLOW_NEGATIVE` : un achat à moitié réussi est pire qu'un
  achat qui échoue.
- `OPX.SetMoney` accepte zéro, et c'est le seul : c'est la seule façon de vider un compte.
- Chaque mutateur passe par un hook (`money:beforeAdd`, `money:beforeRemove`,
  `money:beforeSet`) qui peut opposer un veto (`money.vetoed`).
- `announceMoney` annonce le changement à ses quatre publics : le client propriétaire
  (`MONEY_CHANGE`), les fichiers du core (`Events.Internal.MONEY_CHANGE`), le journal d'audit, et
  `PlayerData` lui-même. L'événement interne porte la `source` **et** l'identifiant citoyen. Comme les trois
  mutateurs refusent un Player hors ligne, le client propriétaire est toujours là pour recevoir
  `MONEY_CHANGE`.
- Les réponses `false, <code>` des mutateurs sont des clés de locale nommant le refus.

## La position

`OPX.SamplePosition` recalcule la position depuis `Open77.players.position` ; le cap (`heading`)
est le seul champ repris du rapport du client. Faux laisse la dernière position connue en place.
L'échantillon est refusé tant que `MaySample` est faux, et quand le `userId` derrière l'identifiant
de joueur a changé : l'identifiant peut avoir été recyclé, et les coordonnées d'un autre compte ne
doivent jamais atterrir dans cette ligne.

## Entrer et sortir du monde

`OPX.Login` (coroutine seulement) met un personnage en jeu. L'ordre est voulu : les groupes se
chargent avant que le Player soit enregistré, et l'entrée du roster existe avant que le client soit
prévenu.

- Un personnage d'un autre compte reçoit le **même** code qu'un personnage absent
  (`character.notFound`), avec une ligne de sécurité `character.notYours` : « celui de quelqu'un
  d'autre » serait un oracle d'existence.
- Un personnage déjà chargé ailleurs est refusé (`character.inUse`) : deux Players qui écrivent
  une même ligne, c'est la dernière sauvegarde qui gagne en silence.
- Les vêtements (`OPX.Clothing.load`) ne refusent jamais la connexion : une ligne illisible
  donne `nil`, et `nil` n'est ni habillé ni sauvegardé par personne.
- Après les trois lectures, la session est relue : si le joueur est parti pendant l'attente
  (`departing`, ou une autre session sur l'identifiant), la connexion est refusée
  (`entry.noIdentity`) avant tout enregistrement. Le `OPX.Logout` du départ a déjà tourné et ne
  repasserait pas : le fantôme resterait au roster jusqu'à l'éviction de l'autosave, son
  propriétaire reconnecté recevrait `character.inUse`, et un identifiant recyclé hériterait de
  son `PlayerData`.

`OPX.Save` échantillonne la position puis écrit la ligne (coroutine seulement).

`OPX.Logout` est idempotent : les deux événements de déconnexion peuvent arriver pour le même
départ. Le Player sort du roster **avant** la sauvegarde, qui cède la main : sinon une recherche
répondrait « toujours présent » pendant l'écriture. La position est échantillonnée tout de suite
et non dans la sauvegarde : le déplacement qui suit la ferait stocker dans le bucket de sélection.
Le joueur retourne ensuite à l'écran de sélection, donc hors du monde (`OPX.Buckets.isolate`,
refusé pour un joueur qui part), et la sauvegarde est dispatchée sur un thread.

`OPX.LogoutAndWait` fait la même chose mais **attend** la ligne : c'est ce qu'il faut à un
changement de personnage, car `OPX.Logout` dispatche, et la lecture du personnage suivant
battrait ce thread jusqu'à la base.

## Les groupes hors ligne

Métiers et gangs sont multi-appartenance, en jeu ou non (`server/groups.lua`) ; chaque fonction
cède la main quand le personnage n'est pas dans le monde.

`withCharacter` applique un changement au Player en jeu, ou charge un Player hors ligne temporaire
(ligne et groupes). Il **re-résout** le Player après chaque attente : une connexion peut arriver
au milieu du changement, et le changement est alors réappliqué au Player vivant (ligne de debug)
au lieu d'être écrit par-dessus lui. Hors ligne, seule la colonne concernée est réécrite
(`SAVE_PRIMARY`), jamais la ligne entière, par deux instructions distinctes plutôt qu'une seule
avec le nom de colonne interpolé. Une opération qui ne touche que `opx77_character_groups`
(`OPX.AddPlayerToJob`, `OPX.AddPlayerToGang`) n'écrit aucune colonne.

`joinGroup` / `leaveGroup` écrivent la ligne d'appartenance d'abord ; l'annonce est à la charge de
l'appelant, et aucun appelant ne peut la sauter, car c'est elle qui atteint la sauvegarde
automatique (`Revision`).

- `OPX.SetJob` rend primaire un métier à un grade, en le rejoignant au besoin ; le service vient du
  `defaultDuty` du métier au lieu d'être reporté.
- `OPX.SetJobDuty` refuse un métier dont `defaultDuty` est vrai (`job.noDuty`) : il n'y a pas de
  service à prendre.
- `OPX.RemovePlayerFromJob` fait retomber le métier primaire sur le métier par défaut quand c'est
  lui qu'on retire, sinon un employé renvoyé continuerait à toucher son salaire. L'annonce a lieu
  même pour un métier non primaire, parce que `leaveGroup` a changé `PlayerData.jobs`. Même chose
  pour `OPX.RemovePlayerFromGang` et `PlayerData.gangs`.
- `OPX.SetPlayerPrimaryJob` / `OPX.SetPlayerPrimaryGang` refusent un groupe dont le personnage
  n'est pas membre (`job.notMember`, `gang.notMember`) au lieu de le rejoindre.
- `OPX.GetPlayersByJob` et `OPX.GetPlayersByGang` lisent la mémoire et ne cèdent pas la main ;
  `OPX.GetGroupMembers` lit la base (coroutine seulement).

## La sauvegarde et la paie

`server/loops.lua` porte les deux travaux de fond.

- **L'échantillonnage de position** tourne à 1 Hz (`SAMPLE_MS`), parce qu'au moment où un
  gestionnaire de déconnexion s'exécute la session a en général disparu et
  `Open77.players.position` répond nil. La passe parcourt délibérément `pairs(OPX.Players)` et
  non `OPX.GetPlayers()` : ce parcours-là expulse, et une expulsion mettrait une écriture en base
  dans une boucle à 1 Hz.
- **L'autosave** (`autosave`) n'écrit que les personnages dont la ligne sortirait différente
  (`needsWriting`) ; une déconnexion, elle, sauvegarde toujours. Deux questions, parce que la
  position est hors du compteur de révision : un échantillon à 1 Hz passé par un mutateur
  salirait tout le monde à chaque tour. Une position n'est « déplacée » qu'au-delà de
  `MOVED_METRES` (1 m) : un joueur immobile oscille de quelques centimètres pendant que
  l'animation se pose, et zéro ferait de tout personnage inactif un personnage en mouvement. La
  révision est lue **avant** l'écriture (`remember` reçoit celle-là) : `OPX.Save` cède la main,
  et un paiement arrivé entre-temps serait sinon marqué comme écrit. `prune` oublie toutes les
  cinq minutes le suivi des personnages que plus personne ne joue.
- **Les intervalles** relisent `OPX.TuneNumber` à chaque échéance : un tunable capturé dans une
  locale se fige au chargement. Chaque travail est enveloppé dans son propre `pcall`, pour qu'un
  travail en échec n'empêche pas les autres, et la passe entière l'est encore par la boucle :
  `OPX.Now` et `OPX.TuneNumber` sont eux aussi des lectures de l'hôte, et une erreur de l'un
  d'eux mettrait fin à l'autosave pour la session. La boucle ne fait rien tant que
  `OPX.BootError` est posé.
- **La paie** (`paycheck`) : `PAYCHECK_TYPE` est résolu une fois au chargement, pour qu'un nom qui
  n'est pas un type de monnaie soit signalé au démarrage et non à chaque cycle (repli sur
  `SHARED.MONEY.DEFAULT`). `offDutyPay` est la dérogation propre au métier, et l'interrupteur
  global `PAYCHECK_REQUIRES_DUTY` ne la contredit pas. Le hook `paycheck:before` peut opposer un
  veto.
- **L'arrêt** (`onResourceStop`) est la dernière occasion d'écrire : un fil par personnage, pas
  une boucle, parce qu'une boucle unique enverrait le premier `UPDATE`, se suspendrait, et ne
  serait jamais reprise. C'est au mieux, et la ligne de journal le dit.

## Le visage

`server/appearance.lua` valide, écrit et diffuse le visage d'un personnage. `opx77_appearance`
est une ressource cliente qui capture un instantané et l'envoie ici ; rien d'autre ne l'écrit.

- `isInteger` refuse un nombre en chaîne (jamais `tonumber("3")`) : un index d'option arrivant
  en chaîne est un client qui ne parle plus le langage de ce fichier.
- `isHash` lit un identifiant moteur 64 bits tel que la plateforme le rend, `0x` et seize
  chiffres hexadécimaux, comparé en minuscules et **jamais** via `tonumber`, qu'un hachage 64 bits
  ne survit pas. Le hachage de famille de corps (`gender`) peut être nul ; un nom d'option non.
  Ce `gender` est le hachage opaque du moteur, pas la chaîne `female`/`male`, qui est
  `charInfo.gender` et vit sur la ligne du personnage.
- `digest` est l'empreinte SHA-256 du catalogue, en minuscules.
- `OPX.Appearance.canonical` rend la forme canonique : options denses, noms en minuscules,
  chaque champ du type que la colonne attend. `choices = 0` est une entrée de catalogue sans rien
  à choisir, que le moteur rapporte bien ; c'est le seul cas où l'index ne peut pas être borné
  par lui. `#value.options` s'arrête au premier trou, donc la boucle n'a prouvé que le
  **préfixe** : un dernier passage refuse toute clé numérique hors de `1..count`
  (`sparse_options`).
- Dans `OPX.SaveAppearance`, la comparaison `OPX.Appearance.same` vient avant l'encodage : deux
  instantanés canoniques identiques s'encodent aux mêmes octets, donc le contrôle de taille ne
  peut pas répondre différemment pour un visage déjà stocké.
- Le personnage écrit par `opx77:server:saveAppearance` vient de la connexion, résolu avant le
  thread, jamais de la charge utile. L'identifiant citoyen de la charge utile ne sert qu'à refuser
  (`appearance.stale`) un visage capturé pour le personnage d'avant ; il reste optionnel, pour
  qu'un `opx77_appearance` qui ne l'envoie pas encore continue d'enregistrer.
- `PlayerData.appearance` est posé **avant** l'écriture, et remis à l'ancien visage si elle
  échoue (sauf si un autre visage l'a remplacé entre-temps) : la sauvegarde de déconnexion
  réécrit la colonne depuis la mémoire, et, lancée pendant l'attente, elle écrasait sinon le
  visage qui venait d'être enregistré.
- L'écriture cède la main : la diffusion au client (`SET_PLAYER_DATA`, `APPEARANCE_UPDATE`)
  n'a lieu que si ce Player est toujours celui chargé sur la source
  (`OPX.Players[data.source] == player`), comme pour les vêtements.

## Les vêtements

`server/clothing.lua`. `opx77_appearance` lit l'équipement et la garde-robe du pantin et les
envoie ici ; rien d'autre ne les écrit. Un enregistrement par personnage dans
`opx77_character_clothing`, porté dans `PlayerData.clothing` : l'enregistrement, `false` quand
rien n'est stocké, ou nil quand le core ne peut pas le dire (lecture échouée),
ce que le client lit comme « n'habille rien, ne sauvegarde rien ». L'enregistrement a la forme de
la plateforme, celle que son service de présentation stocke : neuf emplacements, sept tenues
qui remplacent les sept emplacements visibles, et la tenue active. Les sous-vêtements se portent
mais ne sont jamais remplacés.

- Les tenues sont indexées de 0 à 6, comme `Open77.wardrobe` les indexe ; un nom
  d'enregistrement est borné à 160 octets comme `Open77.equipment.info` le borne. `recordOf`
  n'a pas de catalogue : le serveur n'en a pas, c'est donc la forme que la distribution des looks
  accepte aussi.
- `outfitIndex` accepte une clé numérique ou, après JSON, une chaîne d'un chiffre. Dans
  `OPX.Clothing.canonical`, `"0"` et `0` sont la même tenue : en recevoir deux, c'est un client
  qui veut dire deux choses différentes, et c'est refusé (`invalid_outfit`).
- `MAX_JSON_BYTES` (16 Kio) ne fait qu'attraper une forme que les contrôles auraient laissée
  passer par erreur : neuf emplacements et 49 remplacements de 160 octets restent sous 10 Kio.
- Le refroidissement est le même que pour un visage, 2 s, sur sa propre clé.
- `OPX.Clothing.load` ne refuse jamais une connexion : un échec donne nil, ce qui tient la ligne
  stockée à l'écart d'un client à qui on n'a pas pu la montrer. `OPX.SaveClothing` refuse donc
  une écriture tant que `PlayerData.clothing` est nil : écrire maintenant remplacerait ce que
  personne n'a vu.
- L'écriture cède la main : un joueur qui a changé de personnage entre-temps ne reçoit pas les
  vêtements de celui-ci (`OPX.Players[data.source] == player`).
- `opx77:server:saveClothing` écrit la ligne du personnage de la connexion ; l'identifiant
  citoyen de la charge utile ne sert qu'à refuser (`clothing.stale`) une sauvegarde capturée
  pour le personnage d'avant.

## Les véhicules

`server/vehicles.lua`. La plaque est l'identité, pas l'identifiant d'exécution, et la propriété
se prouve contre le personnage chargé par la connexion, jamais contre ce que le client affirme.

- `live` (plaque → identifiant d'exécution et propriétaire) est ce qui est sorti maintenant ; il
  est reconstruit à vide à chaque rechargement.
- La plaque suit `PLATE_FORMAT` en ASCII majuscule, parce que la colonne est `ascii_bin`. Une
  plaque en double est le seul échec d'insertion qui vaille un nouveau tirage ; tout autre échec
  vient de la base. Le détail est comparé en minuscules, comme pour un identifiant citoyen dans
  `OPX.CreateCharacter` : la casse du message dépend du pont et de la version du serveur. Après
  cinq tirages en double, la réponse est `vehicle.plateExhausted`, la dernière plaque tirée en
  détail. L'enregistrement est refusé au-delà de 256 caractères ici, pour une raison
  lisible, alors que l'hôte le plafonne aussi.
- `OPX.Vehicles.PlateOf` ne connaît que les véhicules que le core a fait apparaître : un
  véhicule créé par une autre ressource n'a pas de ligne, et rien de durable ne doit s'y
  rattacher.
- `OPX.Vehicles.Spawn` rend les dégâts et les drapeaux stockés au véhicule créé, sinon un cycle
  ranger-sortir répare gratuitement vitres, phares, pneus, bosses et le drapeau détruit. La
  connexion est relue après la lecture en base, qui a cédé la main : écrire `live` pour un
  personnage parti entre-temps laisserait un véhicule que rien ne rangera jamais, il est donc
  retiré.
- `OPX.Vehicles.Store` lit l'instantané **avant** le retrait, car il disparaît avec le véhicule.
  Si la ligne ne peut pas être lue, le retrait a quand même lieu et une ligne d'erreur dit que
  l'état est perdu, pas différé.
- `OPX.Vehicles.StoreAll` collecte les plaques **avant** que quoi que ce soit ne cède la main :
  une apparition survenant pendant le parcours insérerait une clé dans la table parcourue, le cas
  indéfini de `next` en Lua. Chaque plaque est relue ensuite, car elle a pu être rangée ou
  retirée pendant l'attente d'une précédente. Elle sert au départ d'un personnage (événement
  interne `PLAYER_UNLOADED`, pour que l'état soit écrit plutôt que perdu au prochain
  rechargement de l'hôte) et à l'arrêt de la ressource.
- `onVehicleRemoved` : l'hôte a retiré un véhicule, détruit ou pris par une autre ressource. Le
  véhicule est oublié tout de suite, et l'état `STORED` est écrit sur un thread : un gestionnaire
  d'événement n'est pas une coroutine, et une écriture en base y céderait la main hors thread.
- La boucle de sauvegarde (`SAVE_SECONDS`) est la garantie que les dégâts sont conservés, pas le
  gestionnaire d'arrêt. Elle photographie les clés et enveloppe chaque sauvegarde dans un
  `pcall` : une seule levée mettrait fin, en silence, à la persistance de l'état pour tout le
  processus.
- À l'arrêt de la ressource, qui retire tous ses véhicules, les lignes sont écrites d'abord, sans
  passer par un thread : un arrêt ne reprend pas de thread.
- `opx77:server:spawnVehicle` et `opx77:server:storeVehicle` rederivent tout : le personnage
  depuis la connexion, la propriété depuis la ligne. Pour ranger, la propriété est vérifiée avant
  de retirer quoi que ce soit du monde : `live` est indexé par plaque, un joueur pourrait sinon
  ranger la voiture d'un autre en la nommant. Un échec de l'une ou l'autre envoie le refus
  (`OPX.Refuse`) **et** un toast d'erreur du même code : aucune ressource OPX n'écoute ces deux
  opérations, et sans le toast le joueur ne saurait pas pourquoi rien ne s'est passé.

## Les exports serveur

`server/exports.lua` charge en dernier : publier la surface affirme que tout ce qu'elle lit
existe. Chaque export répond `{ ok = true, ... }` ou `{ ok = false, error = <clé de locale> }` et
ne lève jamais ; une erreur est journalisée et répond `error.unavailable`. `guard` construit la
fonction publiée, et chaque export est enregistré par sa propre ligne `exports('Nom', guard(...))`
pour que les contrôleurs voient chaque nom.

- **L'appelant** est lu dans l'hôte une seule fois, à l'entrée (`callerOf`), puis transmis au
  corps de l'export : les coroutines exportées s'entrelacent à chaque `yield`, et une copie au
  niveau du module nommerait la dernière reprise. Un nom vide, de plus de 64 octets ou hors de
  `[%w_%-%.]` est refusé (`export.callerDenied`).
- **Les portes**, dans l'ordre : l'appelant, puis `OPX.Booted` (`core.booting` tant que le fil de
  démarrage n'a pas tranché la question du schéma), puis la portée — une lecture passe par
  `EXPORTS.READ` (`mayRead`), toute autre par `EXPORTS.CALLERS[nom].scopes` (`mayWrite`). Un refus
  est une ligne de sécurité `export.denied` nommant l'appelant, sa génération, l'export et la
  portée.
- **Les arguments** sont tous vérifiés, ceux d'un appelant connu compris (`integer`, où un NaN
  échoue à `value == value` ; `token`).
- **La taille** : `sized` refuse une réponse encodée plus lourde que `EXPORTS.MAX_RESULT_BYTES`
  avec `export.tooLarge`, sans quoi l'appelant verrait un refus opaque du codec au lieu d'un code
  sur lequel brancher.
- **`CONTRACT`** (renvoyé par `GetVersion` sous `exports`) est incrémenté à tout changement
  cassant d'arguments ou de réponse ; un nom d'export n'est jamais réutilisé.
- **`GetIdentity`** : un identifiant joueur ne trouve qu'une connexion en ligne ; un identifiant
  citoyen trouve aussi un personnage hors ligne, et alors `online` et `loaded` sont faux et
  `source` absent.
- **`GetVehiclePlate`** : `plate` est absent pour un véhicule que le core n'a pas fait
  apparaître, qui n'a pas de ligne sur laquelle indexer quoi que ce soit de durable.

## Le curseur de changements

Les VM serveur ne s'entendent pas : une autre ressource serveur ne peut pas écouter
`OPX.Events.Internal`. `GetChanges` expose donc ce qui arrive aux personnages (`loaded`,
`unloaded`, `deleted`) comme un anneau borné (`JOURNAL_SIZE`, 512) lu depuis un curseur, pas
comme un bus de rappels, au plus `EVENTS_PER_READ` (16) événements par lecture, du plus ancien
au plus récent. `reset` dit que le curseur de l'appelant n'est pas celui de ce journal : le core
a rechargé, ou l'anneau l'a dépassé, et l'appelant doit relire ce qu'il garde au lieu de se fier
aux seuls événements.

## Le stockage d'inventaire par étapes

Portée `inventory`. Le core stocke ce qu'on lui remet ; ce qui peut aller dans un conteneur
relève d'`opx77_inventory`.

- `InventoryEnsure` trouve ou crée un conteneur ; la taille demandée ne sert qu'à la création, un
  conteneur existant répond la taille avec laquelle il a été créé. Un propriétaire lié
  (`LINKED_KINDS`) doit exister : un personnage vivant pour `citizen`, un véhicule possédé pour
  `plate`.
- `InventoryRead` rend une page de piles après l'emplacement `after`, rognée ligne par ligne
  contre **la moitié** du budget de réponse : le reste est la marge pour le surcoût du nœud.
  `nextAfter` est présent tant qu'il peut y en avoir d'autres.
- Une sauvegarde est **mise en attente sur plusieurs appels** (`staged`, par nom d'appelant puis
  par jeton), parce qu'un argument porte au plus 48 Kio, puis validée en une transaction par
  `InventoryCommit`. La première mise en attente d'un conteneur sous un jeton le vide : un
  conteneur mis en attente sans ligne est sauvegardé vide. Un jeton que personne ne valide est
  oublié après `STAGE_TTL_MS` (30 s) ; un appelant tient au plus `TOKENS_PER_CALLER` (8) jetons,
  un jeton au plus `CONTAINERS_PER_TOKEN` (64) conteneurs. Une pile invalide ou un emplacement
  répété abandonne le jeton entier. Un commit en échec n'écrit rien ; l'appelant remet en attente
  et réessaie.

## La moitié client

Le client ne porte que présentation et intention : tout ce qu'il signale est un indice que le
serveur re-dérive.

- **Le miroir** : `OPX.PlayerData` est la copie du serveur, vide avant qu'un personnage charge.
  Rien ne la capture dans une locale, parce qu'un gestionnaire remplace la table entière à la
  connexion. `OPX.GetPlayerData` ne rend jamais nil, pour qu'on puisse indexer sans garde ; la
  vraie question est `OPX.IsLoggedIn`, vrai entre `playerLoaded` et `playerUnloaded`.
- **L'ordre miroir puis événement** : chaque gestionnaire de `client/events.lua` met d'abord le
  miroir à jour, puis déclenche l'événement local, pour qu'un gestionnaire réveillé lise le
  changement et non la valeur remplacée.
- **Le roster** est typé avant d'être stocké : `#` sur une non-table et `%d` sur un non-entier
  lèvent tous deux, et une erreur entre l'écriture de l'état et la diffusion laisserait un roster
  à moitié appliqué. On remplace les **champs** de `OPX.Characters`, jamais la table : chaque
  export garde une référence sur elle.
- **`setPlayerData`** renvoie tout `PlayerData` après chaque changement, plutôt qu'un correctif :
  un protocole de fusion est une classe de bogues où les deux copies dérivent sans que l'une ou
  l'autre puisse s'en apercevoir.
- **Les refus** (`opx77:client:notify`) portent l'opération et un code, qui est toujours une clé
  de locale : une interface le rend avec `locale(code)` et obtient la langue du joueur.
- **L'annonce** (`OPX.Announce`, `opx77:server:ready`) est ce qui rend un rechargement du core
  survivable : le roster du serveur est vide et `onPlayerConnected` ne se redéclenche pas. Elle
  part au démarrage de la ressource, puis de nouveau sur `open77:worldReady`, car un client peut
  démarrer avant que le monde soit prêt ; le serveur la limite.
- **Le cap** (`client/loops.lua`) est la seule boucle cliente : le serveur lit la position de
  façon autoritaire, et `Open77.players.position` est la seule chose qui ne donne pas la
  direction. Un changement de moins de `HEADING_EPSILON` (2°) ne vaut pas un événement : le lacet
  d'un joueur immobile dérive pendant que l'animation se pose. Le dernier cap envoyé est oublié à
  la déconnexion, pour que le premier rapport du personnage suivant parte toujours ; le corps est
  sous `pcall`, sans quoi une erreur arrêterait le rapport pour la session.
- **La sélection** (`client/character.lua`) n'ouvre pas le créateur de personnage :
  `opx77_appearance` possède cette transaction. `OPX.CreateCharacter` vérifie l'inscription avec
  les mêmes règles que le serveur, qui les revérifie : le contrôle local épargne seulement un
  aller-retour et donne quelque chose à marquer à l'interface.

## Les réponses de commande côté client

`opx77:client:commandAnswer` porte ce qu'a fait une commande tapée par ce joueur, déjà dans la
locale configurée : un toast tant qu'`opx77_notify` tourne, la ligne de chat sinon (`answerLine`,
la ligne que la réponse était avant d'être un toast). `toasted` veut dire que l'action a déjà
levé le même toast elle-même, par les notifications du serveur : seul un client sans toast a
alors besoin de la ligne. Le toast occupe un seul emplacement remplacé
(`id = 'opx77_core.command'`, `replace = true`) : un joueur qui relance une commande voit une
réponse, pas une pile.

`toast` enveloppe l'appel `Open77.exports.call` dans un `pcall`, mais l'enveloppe s'arrête là :
`await` cède la main, et un `yield` n'est pas sûr sous un `pcall`. La promesse est testée par
présence, jamais par son type Lua : c'est un userdata, pas une table. L'échec d'un toast n'est
journalisé qu'une fois (`toastReported`), pas une fois par réponse.

## Les exports client

Chaque export répond une table simple `{ ok = boolean, ... }`, jamais un `OPX.Result`.

- `GetPlayerData`, `GetAppearance` et `GetClothing` répondent `ok = false` avant la connexion
  plutôt qu'une table vide : un appelant ne peut pas confondre « pas encore connecté » et
  « connecté sans rien ».
- `HasJob` est un export, et pas une simple lecture de champ, parce qu'il combine un contrôle de
  service et une comparaison de grade ; `minGrade` est lu par `tonumber`, donc un non-nombre
  est absent plutôt que le grade 0. `HasGang` n'a pas de drapeau de service — une gang n'a pas
  de postes — donc `minGrade` y est le deuxième paramètre et le troisième sur `HasJob`.
- `SelectCharacter`, `CreateCharacter`, `DeleteCharacter` et `RequestCharacters` sont des
  requêtes : la réponse dit seulement qu'elle est partie, le résultat arrive sur
  `OPX.Events.Local.PLAYER_LOADED` ou `.REFUSED`. Un argument du mauvais type répond
  `error.badRequest` sans rien envoyer, et les contrôles locaux de `CreateCharacter` les codes
  du serveur (`character.badName`, `character.badOrigin`) : chaque `error` est une clé du
  catalogue, qu'`opx77_charselector` et `opx77_charcreator` savent rendre.
- `GetSharedConfig` ne rend que la configuration dont une interface a légitimement besoin ; les
  définitions statiques passent par `GetJobs`, `GetGangs` et `GetOrigins`. `locale` y est la
  langue **en vigueur** (`OPX.Locale.current()`), pas celle configurée : elles diffèrent après
  `Locale.set`.
- `Locale` refuse une clé non textuelle avec `error.badRequest`, une vraie clé de catalogue et non
  `bad-key`, parce qu'`error` sert de clé partout où il est affiché.
- `GetJobs` et `GetGangs` réémettent les grades en tableau 1-based portant un `level` explicite,
  jamais la table source indexée à partir de 0 : lire `grade.level`, jamais l'indice. Une gang ne
  porte ni paie ni service : ce n'est pas un employeur.
- La validité de `NOTIFY_POSITION` est vérifiée une fois au chargement : c'est une valeur de
  configuration qui ne change pas sans redémarrage, et une interface qui la demande cent fois ne
  doit pas produire cent lignes.

## Clés résolues à l'exécution

Presque toutes les clés de `locales/` sont des codes de refus : elles arrivent à `locale()` par
une variable (`result.error`, `OPX.RefusalKey(code)`) et sont rendues par les satellites avec
`Locale.exists(code)`. Deux clés ne sont nommées littéralement par aucun fichier du core et sont
gardées, parce qu'opx77_doc les donne en exemple à un plug-in serveur : `job.updated` (le texte
envoyé avec `OPX.NotifyLocale` après un changement de métier, `core/server-api.md`) et
`error.noPermission` (le refus opposé avec `OPX.Refuse` à une action réservée,
`core/player.md`).

`character.notYours`, `character.deleteRefused` et `vehicle.notYours` sont des noms
d'événements du journal d'audit, pas des clés : un joueur ne lit jamais « pas à vous », il reçoit
`character.notFound` ou `vehicle.notFound` (voir « Pas d'oracle d'existence »).

## Limites connues

- Les bannissements et la file d'attente ne sont pas gérés.
- `OPX.Storage.ready` garde sa réponse pour toute la durée de la ressource : une base qui revient
  après le démarrage n'est prise en compte qu'au redémarrage du core.
- `OPX.Storage.Players.toEntity`, `OPX.GetPlayerCount`, `OPX.Hooks.has` et les champs de session
  `connectedAt`, `heldAt` et `charactersSent` ne sont lus par aucun fichier du core, ni par aucune
  autre ressource OPX. Ils restent : ils font partie de l'API des plug-ins serveur qu'opx77_doc
  documente.
- `OPX.GetPlayersByJob` / `OPX.GetPlayersByGang` passent par `OPX.GetPlayers`, qui peut évincer un
  emplacement périmé ; l'éviction ne cède pas la main (la sauvegarde part sur un thread), mais une
  lecture « en mémoire » peut ainsi déclencher une déconnexion.
