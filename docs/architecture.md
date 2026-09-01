# OPX//77 CORE — architecture

Un framework de jeu de rôle pour [OPEN//77](https://open2077.net), la
plateforme multijoueur de Cyberpunk 2077.

Statut : **squelette fonctionnel**. Personnages, argent, métiers, gangs,
persistance et barrière d'entrée tournent.
L'interface de sélection reste à faire.

Le code est commenté en anglais, cette documentation est en français.

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

## Côté client, c'est l'inverse

« The client runtime *does* have `exports` and `GetInvokingResource`. » C'est
là que le découpage en ressources redevient possible, et c'est ce qui permet
les satellites : `opx77_char` pour la sélection, `opx77_hud` pour l'overlay.

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

Il vit dans `open77.lua`, un fichier par ligne. Un fichier publie dans `OPX`
ou `OPX`, et tous ceux d'après peuvent lire ce qui a été publié.

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

Depuis une ressource **cliente** satellite, `getSharedObject` rend la moitié
*données* de cette table — version, config partagée, définitions des métiers
et des gangs, personnage courant. Il ne peut pas rendre les fonctions : la
plateforme fait passer chaque export par un codec, « arguments and results
must be serializable », et une fonction ne se sérialise pas. Les appels
restent donc des exports individuels.

Côté **serveur** il n'y a pas d'équivalent et il ne peut pas y en avoir : le
runtime serveur n'installe aucun `exports`. Le gameplay serveur est un fichier
ajouté à `server/`, où `OPX` est simplement dans la portée.

## Les couches

| | |
|---|---|
| `config/` | les seuls fichiers qu'un opérateur édite. Clés `UPPER_SNAKE` |
| `data/` | métiers, gangs, parcours de vie. Des définitions, pas des réglages |
| `shared/` | `OPX` lui-même : result, table, string, math, log, validate, hooks, locales, identifiants citoyens |
| `server/storage/` | toutes les requêtes SQL, et les migrations |
| `server/` | roster, joueur, groupes, personnages, barrière, événements |
| `client/` | miroir d'état et surface d'exports |

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

## La barrière d'entrée

> do not teleport, spawn, kill or force a respawn on a player until their
> readiness gate has opened.

Le core déclare sa participation une fois au boot, ce qui pose un verrou sur
chaque joueur connecté ensuite — il ne court pas après un verrou avant qu'autre
chose déplace le joueur, il en a déjà un avant que le joueur existe.

Deux échéances, et la nôtre est la plus courte. L'hôte ouvre la barrière
lui-même à `GATE_MS` et émet `timeout:opx77_core`, potentiellement avec le
joueur encore dans l'écran de sélection et **sans pantin du tout**. Le core se
donne donc une échéance en dessous : il abandonne le premier, relâche
délibérément, et dit pourquoi.

Le placement se fait par **kill → respawn**, jamais par transform brut : la
transaction de respawn porte le fondu, le préchargement du streaming et la
fenêtre de grâce qu'un téléport direct saute. Et l'état de vie est lu avant,
parce que le timeout de l'hôte peut encore gagner.

## Ce qui manque

- L'interface de sélection (`opx77_char`, ressource cliente).
- L'inventaire, et le lien avec `open77_clothing`.
- Les véhicules persistants.
- Les bannissements et la file d'attente.
