# PortWatch

Application macOS menubar qui surveille en temps reel les ports TCP ouverts sur votre machine, identifie les processus et projets associes, et permet de les gerer directement depuis la barre de menus.

## Fonctionnalites

- **Monitoring temps reel** -- affiche tous les ports ouverts (LISTEN, CLOSE_WAIT, TIME_WAIT) avec le processus, PID, ligne de commande, projet associe et duree d'execution
- **Detection de projet** -- identifie automatiquement le projet via Docker (`docker ps`), racine git (`.git`), ou ports standards connus (PostgreSQL, MySQL, Redis, MongoDB, Elasticsearch)
- **Groupement par projet** -- les processus sont regroupes par projet dans un popover riche SwiftUI, pas en liste plate. "Other" toujours en dernier
- **Detection de role** -- chaque processus est tague Front/Back/DB/Cache selon des mots-cles configurables (dossier cwd, nom du process, ligne de commande)
- **Kill de processus** -- kill individuel ou par projet, avec sequence SIGTERM (4s polling) puis SIGKILL (2s polling) et verification. Confirmation requise pour les processus non identifies ("Other")
- **Detection zombies** -- signale les processus en `CLOSE_WAIT` / `TIME_WAIT` avec un badge rouge
- **Detection de conflits** -- signale quand plusieurs PIDs ecoutent sur le meme port (badge jaune)
- **Alertes CPU/RAM** -- badges conditionnels quand les seuils sont depasses (defaut : 50% CPU, 500 MB RAM)
- **Notifications macOS** -- optionnelles (desactivees par defaut) : nouveau port detecte, conflit de port
- **Ouvrir dans le navigateur** -- bouton pour ouvrir `http://localhost:PORT` directement
- **Reglages en ligne** -- seuils CPU/RAM, intervalle de refresh (3-30s), notifications, mots-cles de detection editables
- **Desinstallation complete** -- depuis le menu Reglages ou via `./uninstall.sh`

## Stack

| Composant | Technologie |
|---|---|
| Langage | Swift 6.0 |
| UI | SwiftUI `MenuBarExtra` (`.window` style) |
| Concurrence | Swift Concurrency (`@Observable`, `@MainActor`, `Task.detached`) |
| Scan ports/process | APIs systeme macOS natives (libproc via `import Darwin`) |
| Detection Docker | `docker ps --format json` via subprocess |
| Persistance | `UserDefaults` |
| Notifications | `UNUserNotificationCenter` |
| Target | macOS 26 (Tahoe) minimum |
| Distribution | `.app` standalone (pas de signature, pas d'App Store) |

## Prerequis

- macOS 26 (Tahoe) ou plus recent
- Xcode (gratuit, App Store)

## Build

```bash
# Build debug
xcodebuild -scheme PortWatch -configuration Debug build

# Build release
xcodebuild -scheme PortWatch -configuration Release build

# Tests
xcodebuild -scheme PortWatch test
```

## Installation

L'app n'est pas signee avec un certificat Apple Developer. Au premier lancement :
**Clic droit -> Ouvrir -> Ouvrir quand meme** pour bypasser Gatekeeper (une seule fois).

## Utilisation

L'app vit dans la menubar. L'icone affiche le nombre de ports ouverts. Un clic ouvre un popover avec :

- Les ports groupes par projet, avec pour chacun : numero de port, nom du processus, PID, ligne de commande, role (Front/Back/DB/Cache), duree, dossier cwd
- Des badges d'alerte : zombie (rouge), conflit de port (jaune), CPU/RAM excessifs (orange)
- Un bouton kill par processus (avec confirmation pour les processus "Other") et par projet
- Un bouton pour ouvrir le port dans le navigateur
- Un panneau de reglages inline (seuils, interval, notifications, mots-cles de detection)
- Un bouton de refresh manuel et un bouton Quit

## Desinstallation

Deux options :
1. **Depuis l'app** -- menu Reglages -> "Uninstall PortWatch..." avec confirmation
2. **Script standalone** -- `./uninstall.sh`

Les deux suppriment l'app, les preferences (`UserDefaults`), caches, logs et processus residuels.

## Structure du projet

```
PortWatch/
  Sources/
    PortWatchApp.swift       # Entry point, MenuBarExtra, UI complete
    PortEntry.swift          # Modeles de donnees (TCPState, PortEntry, PortEntryDisplay, ProjectGroup, KillReport)
    PortScanner.swift        # Scan libproc bas niveau + kill sequence
    PortMonitor.swift        # Boucle de scan, CPU %, conflits, notifications
    ProjectDetector.swift    # Detection projet (Docker, git, ports connus)
    NotificationManager.swift # Notifications macOS
    AppSettings.swift        # Reglages persistants (UserDefaults)
    SettingsView.swift       # Vue reglages + desinstallation + FlowLayout
  Info.plist                 # LSUIElement=true (pas d'icone dock)
PortWatchTests/
  PortWatchTests.swift       # Tests
uninstall.sh                 # Desinstalleur standalone
```

## Licence

Usage personnel.
