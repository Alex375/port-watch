# Cahier des charges technique -- PortWatch

## Contexte et objectif

Developpeur travaillant sur plusieurs projets simultanement (frontend, backend, bases de donnees, Docker), l'utilisateur se retrouve regulierement avec des processus tournant en local sur des ports ouverts sans en avoir conscience. L'objectif est de creer une application macOS legere, logee dans la **menubar**, qui liste en temps reel tous les processus actifs sur les ports ouverts, les associe a leur projet, et permet de les gerer sans quitter son environnement de travail.

---

## Stack technique

| Composant | Technologie |
|---|---|
| Langage | Swift 6.0 |
| UI menubar | SwiftUI `MenuBarExtra` avec `.menuBarExtraStyle(.window)` (popover riche, pas un NSMenu) |
| Concurrence | Swift Concurrency (`@Observable`, `@MainActor`, `Task.detached`, `Sendable`) |
| Scan des ports / process | APIs systeme macOS natives (libproc via `import Darwin`) -- aucune dependance externe |
| Detection Docker | `docker ps --format json` via subprocess |
| Persistance reglages | `UserDefaults` avec `@Observable` |
| Notifications | `UNUserNotificationCenter` |
| Target macOS | macOS 26 (Tahoe) minimum |
| Distribution | `.app` standalone (pas d'App Store, pas de signature payante) |
| Prerequis licence | Aucun -- usage personnel, Xcode gratuit suffit |

---

## Fonctionnalites

### 1. Affichage dans la menubar

- Icone dans la menubar macOS affichant le nombre de ports ouverts en temps reel (SF Symbol `network` + compteur)
- Clic sur l'icone -> popover SwiftUI riche (style `.window`, largeur 420pt) avec la liste complete
- Rafraichissement automatique configurable (defaut **10 secondes**, reglable de 3 a 30s)
- Bouton de refresh manuel

---

### 2. Detection des processus et ports

Implementation via libproc (`import Darwin`), sans `lsof` ni dependance externe :

1. `proc_listallpids()` -- enumeration de tous les PIDs
2. `proc_pidinfo(PROC_PIDLISTFDS)` -- file descriptors par PID
3. `proc_pidfdinfo(PROC_PIDFDSOCKETINFO)` -- details socket (famille, protocole, port local, etat TCP)
4. `proc_name()` / `proc_pidpath()` -- nom et chemin de l'executable
5. `proc_pidinfo(PROC_PIDVNODEPATHINFO)` -- repertoire de travail (cwd)
6. `sysctl(KERN_PROCARGS2)` -- arguments en ligne de commande (resume lisible)
7. `proc_pidinfo(PROC_PIDTBSDINFO)` -- info BSD (heure de demarrage du process)
8. `proc_pidinfo(PROC_PIDTASKINFO)` -- info tache (memoire residente, temps CPU en ticks Mach)
9. `mach_timebase_info` -- conversion ticks Mach -> nanosecondes

Filtrage : seuls les sockets TCP en etat **LISTEN**, **CLOSE_WAIT** ou **TIME_WAIT** sont retenus. Deduplication par (port, PID) pour gerer les listeners dual IPv4/IPv6.

Pour chaque port ouvert, afficher :

- **Numero de port**
- **Nom du processus** (ex: `node`, `uvicorn`, `python`, `redis-server`)
- **PID**
- **Ligne de commande** resumee (ex: `node vite`, `python manage.py runserver`)
- **Nom du projet** associe (voir section Detection de projet)
- **Role** (Front, Back, DB, Cache) -- voir section Detection de role
- **Repertoire de travail** (cwd) avec substitution `~/`
- **Duree depuis le demarrage** du processus (ex: `2h03`, `42min`)
- **Statut** : actif, zombie, ou warning CPU/RAM

---

### 3. Detection du projet associe

La logique de detection suit cette priorite :

**1. Docker en premier**
Si le processus est un container Docker, appeler `docker ps --format json` (rafraichi une fois par cycle de scan) et croiser le port expose avec les donnees retournees. Afficher le nom du container et de l'image. Recherche du binaire Docker dans `/usr/local/bin/docker`, `/opt/homebrew/bin/docker`, puis fallback sur `/usr/bin/env docker`.

**2. Racine git**
Remonter l'arborescence depuis le `cwd` du processus jusqu'a trouver un repertoire `.git`. Le nom du dossier contenant `.git` est utilise comme nom de projet.

**3. Port connu (fallback)**
Si aucun marqueur trouve, identifier le service par son port standard :

| Port | Service |
|---|---|
| 5432 | PostgreSQL |
| 3306 | MySQL |
| 6379 | Redis |
| 27017 | MongoDB |
| 9200 | Elasticsearch |

**4. "Other"**
Si aucune methode ne trouve de projet, le processus est classe dans le groupe "Other".

---

### 4. Detection du role

Chaque processus est tague avec un role base sur des mots-cles configurables. La detection compare le nom du dossier cwd, le nom du processus et la ligne de commande aux listes de mots-cles suivantes (editables dans les reglages) :

| Role | Mots-cles par defaut | Icone |
|---|---|---|
| Front | front, web, client, ui, vite, webpack, next, nuxt | globe |
| Back | back, api, server, uvicorn, gunicorn, flask, django, express, fastify | server.rack |
| DB | postgres, mysqld, mysql, mongod, mongos, redis-server, redis-sentinel (noms de process) + db, database (mots-cles dossier) | externaldrive.fill |
| Cache | memcached, rabbitmq-server (hardcode par nom de process) | bolt.horizontal |

Priorite de detection : DB > Front > Back > Cache.

---

### 5. Groupement par projet

Les processus sont **groupes par projet** dans le popover, pas affiches en liste plate. "Other" est toujours trie en dernier. Chaque groupe affiche :

- Nom du projet avec indicateur colore (bleu pour les projets identifies, gris pour "Other")
- Nombre de ports
- Bouton "Kill all" pour le projet (absent pour "Other")
- Liste des ports avec leurs details

---

### 6. Actions disponibles

**Par processus :**
- **Kill** -- sequence stricte :
  1. Verifier que le process est vivant (`kill(pid, 0)`)
  2. Envoyer `SIGTERM`
  3. Polling toutes les 200ms pendant 4 secondes
  4. Si toujours vivant -> envoyer `SIGKILL`
  5. Polling toutes les 200ms pendant 2 secondes
  6. Si toujours vivant -> rapport d'erreur explicite avec PID, port, nom du process et message errno
  7. Re-scan immediat pour mettre a jour l'interface
- **Confirmation requise** pour les processus "Other" (non identifies) via un banner inline avec avertissement
- **Ouvrir dans le navigateur** -- ouvre `http://localhost:PORT` dans le navigateur par defaut

**Par projet :**
- **Kill all** -- kill tous les processus du groupe en sequence (dedupliques par PID), avec verification individuelle et rapport final (ex: "3 processes killed" ou "2/3 killed, 1 failed")

---

### 7. Detection des ports zombies

Un processus est considere zombie si son etat de connexion TCP est `CLOSE_WAIT` ou `TIME_WAIT`. Il est signale visuellement avec un badge rouge "ZOMBIE" dans le popover. Le point de statut passe au rouge. Il peut toujours etre kille manuellement.

---

### 8. Detection des conflits de port

Quand plusieurs PIDs ecoutent sur le meme port, un badge jaune "PORT CONFLICT" est affiche. Une notification macOS optionnelle est envoyee (si activee dans les reglages).

---

### 9. Alertes -- nouveau port ouvert

Les notifications sont **optionnelles** et activables/desactivables depuis les reglages (desactivees par defaut).

Quand activees, une notification macOS native (`UNUserNotificationCenter`) est declenchee a chaque nouveau port detecte, avec :
- Le numero de port
- Le nom du processus
- Le nom du projet si detecte

---

### 10. Indicateur CPU / RAM

- Surveiller en continu le CPU et la RAM de chaque processus via `proc_pidinfo(PROC_PIDTASKINFO)`
- **CPU %** calcule entre deux cycles de scan consecutifs : delta `(pti_total_user + pti_total_system)` converti de ticks Mach en nanosecondes, divise par le temps ecoule
- **Affichage conditionnel** : les badges s'affichent uniquement quand un seuil est depasse -- ex: badge orange "73% CPU" ou "612 MB"
- En dessous des seuils, rien n'est affiche pour ne pas surcharger le menu
- Seuil CPU par defaut : **50%** -- configurable dans les reglages (slider 10-100%)
- Seuil RAM par defaut : **500 MB** -- configurable dans les reglages (slider 100-2000 MB)
- Aucune permission supplementaire requise pour acceder a ces metriques

---

### 11. Reglages

Panneau de reglages inline (remplace le contenu principal du popover) accessible via l'icone engrenage :

- **Seuils d'alerte** : CPU (slider 10-100%), RAM (slider 100-2000 MB)
- **Intervalle de refresh** : slider 3-30 secondes
- **Notifications** : toggle nouveau port, toggle conflit de port
- **Mots-cles de detection** : editables par role (Front, Back, DB, DB processes) avec ajout/suppression de tags
- **Reset to defaults** : remet tous les reglages aux valeurs par defaut
- **Desinstallation** : avec confirmation explicite

Persistance via `UserDefaults` avec `@Observable` pour mise a jour reactive de l'UI.

---

## Environnement de developpement requis

- **Xcode** (gratuit, App Store) -- obligatoire pour compiler Swift sur macOS
- Claude Code utilise `xcodebuild` en ligne de commande pour builder le projet sans interaction manuelle avec l'IDE
- Le `.app` produit n'est pas signe avec un certificat Apple Developer -- au premier lancement, faire **clic droit -> Ouvrir -> Ouvrir quand meme** pour bypasser Gatekeeper (une seule fois)
- `LSUIElement = true` dans Info.plist : l'app n'apparait pas dans le Dock

---

## Desinstallation

La desinstallation doit etre **complete et sans residu** -- aucun fichier laisse, aucun process fantome continuant de tourner en arriere-plan.

Un desinstalleur est fourni sous deux formes complementaires :

**1. Depuis le menu de l'app**
Un item "Uninstall PortWatch..." dans les reglages, avec une confirmation explicite avant d'agir. Il execute la sequence complete puis quitte l'app.

**2. Script shell standalone**
Un fichier `uninstall.sh` livre a cote du `.app`, executable independamment meme si l'app ne demarre plus.

**Sequence de desinstallation complete :**

1. Killer proprement le process PortWatch (`SIGTERM` puis `SIGKILL` si pas de reponse sous 3s)
2. Supprimer le `.app`
3. Supprimer `~/Library/Application Support/PortWatch`
4. Supprimer `~/Library/Preferences/com.portwatch.app.plist`
5. Supprimer `~/Library/Caches/PortWatch`
6. Supprimer `~/Library/Logs/PortWatch`
7. Purger `UserDefaults` pour le bundle identifier
8. Purger les notifications en attente et delivrees dans le centre de notifications macOS
9. Verifier qu'aucun process residuel ne tourne (et le killer si c'est le cas)

Apres desinstallation, le systeme doit etre dans un etat strictement identique a avant l'installation.

---

## Public cible et philosophie de gestion des erreurs

PortWatch est une application **destinee aux developpeurs**. La gestion des erreurs doit suivre cette philosophie sans exception :

- **Zero erreur silencieuse** -- aucune erreur ne doit etre catchee et ignoree. Toute erreur doit remonter a l'utilisateur via le banner `KillReport`.
- **Messages d'erreur explicites** -- afficher le contexte complet : quelle operation a echoue, sur quel process/port/PID, et pourquoi (message d'erreur systeme inclus, errno).
- **Pas de faux positifs** -- ne jamais indiquer qu'une operation a reussi sans l'avoir verifiee. Une action "kill" n'est confirmee que si le process est effectivement mort (verification par `kill(pid, 0)`).
- **Toujours signaler** -- permissions insuffisantes, process introuvable, Docker non disponible, commande systeme en echec : tout doit etre visible dans l'interface, jamais masque.
- **Etat de l'UI toujours coherent avec la realite** -- si une operation echoue, l'interface doit refleter l'etat reel (re-scan immediat apres chaque kill), pas l'etat souhaite.

---

## Ce qui est explicitement hors scope

- Lancement automatique au demarrage de macOS (Login Item) -- **non souhaite**
- Distribution sur l'App Store
- Interface de preferences complexe (fenetre separee)
- Support Windows ou Linux
- Lecture de fichiers marqueurs (`package.json`, `pyproject.toml`, etc.) pour le nom de projet -- remplace par detection racine git

---

## Notes pour l'implementation

- L'acces a certains processus systeme peut necessiter des permissions elevees sur macOS -- gerer proprement les cas ou `cwd` ou les infos process ne sont pas accessibles sans `sudo` (retourner une chaine vide plutot que crasher)
- Le scan tourne sur un **`Task.detached(priority: .utility)`** pour ne pas bloquer le thread principal SwiftUI
- Les reglages sont editables directement depuis le popover (panneau inline, pas de fenetre separee)
- Le scan utilise un cache par PID (nom, path, cwd, cmd, BSD info, task info, projet) pour eviter les syscalls redondants dans un meme cycle de scan
