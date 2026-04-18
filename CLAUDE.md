# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PortWatch is a macOS menubar app (Swift 6 + SwiftUI) that monitors open TCP ports, identifies associated processes and projects, and lets developers kill them. It uses `MenuBarExtra` with `.window` style for a rich popover UI in the system tray.

## Build & Run

```bash
# Build
xcodebuild -scheme PortWatch -configuration Debug build

# Build release .app
xcodebuild -scheme PortWatch -configuration Release build

# Run tests
xcodebuild -scheme PortWatch test

# Run a single test
xcodebuild -scheme PortWatch -only-testing:PortWatchTests/TestClassName/testMethodName test
```

The app is unsigned (no Apple Developer certificate). First launch requires: right-click > Open > Open Anyway to bypass Gatekeeper.

## Source Files

| File | Role |
|---|---|
| `PortWatch/Sources/PortWatchApp.swift` | App entry point (`@main`), `MenuBarExtra` scene with `.window` style, `MenuContentView` (full UI: header, grouped port list, kill confirmation banner, kill report banner, settings toggle, footer) |
| `PortWatch/Sources/PortEntry.swift` | Data models: `TCPState` enum (maps TSI_S_* constants), `PortEntry` struct (one open port), `CPUSample`, `PortEntryDisplay` (enriched with cross-scan CPU %), `ProjectGroup`, `KillReport`. Also contains `PortEntry.detectRole()` static method for role classification. |
| `PortWatch/Sources/PortScanner.swift` | Low-level stateless scanner (`enum PortScanner`). Wraps libproc APIs for PID enumeration, FD listing, socket info extraction, process name/path/cwd/cmdline retrieval, BSD info, task info. Contains `scanAllPorts()` (full scan with per-PID caching and dedup) and `killProcess()` (SIGTERM/SIGKILL sequence). |
| `PortWatch/Sources/PortMonitor.swift` | `@MainActor @Observable` class driving the UI. Owns the scan loop (configurable interval), computes CPU % from consecutive samples, detects port conflicts, triggers notifications, and exposes `killPort()`/`killProject()` with full result reporting. |
| `PortWatch/Sources/ProjectDetector.swift` | Stateless `enum ProjectDetector`. Priority: Docker containers (via `docker ps --format json`) > git root (walk up to `.git`, use folder name) > known port fallback (PostgreSQL, MySQL, Redis, MongoDB, Elasticsearch) > "Other". |
| `PortWatch/Sources/NotificationManager.swift` | `@MainActor` singleton wrapping `UNUserNotificationCenter`. Sends notifications for new port detection and port conflicts. |
| `PortWatch/Sources/AppSettings.swift` | `@MainActor @Observable` singleton persisted via `UserDefaults`. Stores thresholds (CPU, RAM), refresh interval, notification toggles, and configurable role detection keywords. |
| `PortWatch/Sources/SettingsView.swift` | SwiftUI settings panel (inline, replaces main content). Sliders for thresholds/refresh, notification toggles, editable keyword tags (with `FlowLayout`), reset to defaults, and uninstall with confirmation. |
| `PortWatchTests/PortWatchTests.swift` | 81 unit tests (TCPState, PortEntry, PortScanner, ProjectDetector, AppSettings, models). |
| `PortWatch/Sources/UpdateChecker.swift` | `@MainActor @Observable` singleton. Checks GitHub Releases API for new versions, downloads and replaces .app via helper shell script. |
| `uninstall.sh` | Standalone shell uninstaller (kills process, removes .app, prefs, caches, logs). |
| `PortWatch/Info.plist` | Bundle config. `LSUIElement = true` (no dock icon). |

## Architecture

### Key Patterns

- **`@Observable` (Observation framework)** — `PortMonitor` and `AppSettings` use `@Observable` (not `ObservableObject`). Views use `@Bindable` for two-way bindings.
- **`@MainActor`** — `PortMonitor`, `AppSettings`, `NotificationManager` are all `@MainActor`-isolated. Background work uses `Task.detached(priority: .utility)`.
- **`MenuBarExtra` with `.menuBarExtraStyle(.window)`** — gives a rich SwiftUI popover (not an `NSMenu`). The label shows port count with an SF Symbol.
- **`Sendable` everywhere** — all data models (`PortEntry`, `PortEntryDisplay`, `ProjectGroup`, `KillReport`, `TCPState`, `CPUSample`) are `Sendable`. `PortScanner` is a stateless `enum` marked `Sendable`.
- **Swift 6 strict concurrency** — the project compiles with Swift 6.0 and macOS 26 (Tahoe) deployment target.

### Port Scanning (libproc)

All port/process detection uses macOS native C APIs via `import Darwin` -- no `lsof`, no Python, no external dependencies:

1. `proc_listallpids()` — enumerate all PIDs
2. `proc_pidinfo(PROC_PIDLISTFDS)` — get file descriptors for a PID
3. `proc_pidfdinfo(PROC_PIDFDSOCKETINFO)` — get socket details (family, protocol, local port, TCP state)
4. `proc_name()` / `proc_pidpath()` — process name and executable path
5. `proc_pidinfo(PROC_PIDVNODEPATHINFO)` — process current working directory
6. `sysctl(KERN_PROCARGS2)` — command line arguments (parsed into human-readable summary)
7. `proc_pidinfo(PROC_PIDTBSDINFO)` — BSD info (process start time)
8. `proc_pidinfo(PROC_PIDTASKINFO)` — task info (resident memory, CPU time in Mach ticks)
9. `mach_timebase_info` — convert Mach ticks to nanoseconds for CPU % calculation

The scan filters for TCP sockets in LISTEN, CLOSE_WAIT, or TIME_WAIT states. Results are deduplicated by (port, pid) to handle dual IPv4/IPv6 listeners.

### Project Detection (`ProjectDetector`)

Priority order:
1. **Docker** — `docker ps --format json` subprocess, mapping exposed host ports to container names. Refreshed once per scan cycle.
2. **Git root** — walks up from process `cwd` looking for `.git` directory, returns the containing folder name as project name.
3. **Known ports** — fallback map: 5432=PostgreSQL, 3306=MySQL, 6379=Redis, 27017=MongoDB, 9200=Elasticsearch.
4. **"Other"** — if nothing matches.

### Role Detection

Each port entry is tagged with a role (Front, Back, DB, Cache) based on configurable keyword matching against the process cwd folder name, process name, and command line. Keywords are user-editable in Settings and persisted via UserDefaults.

Default keywords:
- **Front:** front, web, client, ui, vite, webpack, next, nuxt
- **Back:** back, api, server, uvicorn, gunicorn, flask, django, express, fastify
- **DB keywords:** db, database
- **DB process names:** postgres, mysqld, mysql, mongod, mongos, redis-server, redis-sentinel
- **Cache:** hardcoded for memcached, rabbitmq-server
- **MCP:** mcp-server, mcp_server, fastmcp, modelcontextprotocol (matches process name and command line)

### Kill Sequence

Strict verification at every step (via `PortScanner.killProcess()`):
1. Check process is alive (`kill(pid, 0)`)
2. Send `SIGTERM`
3. Poll every 200ms for up to 4 seconds
4. If still alive, send `SIGKILL`
5. Poll every 200ms for up to 2 seconds
6. If still alive, return error with full context (PID, port, process name, errno message)

Kills for "Other" (unidentified project) processes require explicit user confirmation via an inline banner.

### CPU % Calculation

CPU usage is computed across two consecutive scan cycles by comparing `pti_total_user + pti_total_system` (converted from Mach ticks to nanoseconds) against wall-clock elapsed time.

### Notifications

Optional (off by default), via `UNUserNotificationCenter`:
- New port detected
- Port conflict (multiple PIDs on same port)

## README Maintenance

The `README.md` does **not** need to be updated on every push to `main`. Badges (version, CI status) update automatically via shields.io.

**Update the README when:**
- A new user-visible feature is added (new role, new setting, new detection method, etc.)
- Prerequisites change (macOS version, Swift version, etc.)
- The contribution workflow changes

When a feature is added, update the relevant section in the README (Features, Role Tagging table, etc.) as part of the same feature branch, before merging to `dev`.

## Key Design Rules

- Processes are **grouped by project** in the menu, not a flat list. "Other" always sorted last.
- **Zero silent errors** — every failure surfaces to the user via `KillReport` with full context (operation, port, PID, system error message).
- **UI state must match reality** — never mark a process as killed before confirming it's dead. The scan re-runs after every kill.
- **Port conflict detection** — multiple PIDs on the same port are flagged with a yellow warning badge.
- Zombie detection: only sockets in `CLOSE_WAIT` sustained across 3 consecutive scans are flagged (`PortMonitor.zombieConfirmationScans`). `TIME_WAIT` is a normal TCP state and is never a zombie. The "Other" project is excluded from the menubar zombie badge to avoid noise from system-level sockets.
- CPU/RAM warnings are conditional — only shown when exceeding configurable thresholds (default: 50% CPU, 500 MB RAM).

## Git Workflow

### Branches
- **`main`** — production, protégée. Chaque merge déclenche un build Release + création automatique d'une GitHub Release avec le .app zippé.
- **`dev`** — intégration. Les feature branches mergent ici. Tests CI obligatoires.
- **`feature/xxx`** ou **`fix/xxx`** — branches de travail, créées depuis `dev`.

### Flow
```
feature/xxx ──merge──> dev ──PR──> main ──auto──> GitHub Release
                        │           │
                     Tests CI    Tests CI + Review @Alex375
```

### Protections
- **`main`** : push direct interdit, PR obligatoire, tests CI requis, review CODEOWNER (@Alex375) requise pour les contributeurs externes, admin peut bypass review.
- **`dev`** : tests CI requis.

### Versioning
La version est lue depuis `Info.plist` (`CFBundleShortVersionString`). Pour bumper la version, modifier ce champ dans la PR vers `main`. Le workflow Release crée automatiquement le tag `vX.Y.Z` et la GitHub Release.

### CI/CD (GitHub Actions)
- **`.github/workflows/ci.yml`** — build debug + tests sur chaque push vers `dev` et chaque PR vers `dev`/`main`.
- **`.github/workflows/release.yml`** — build Release + zip .app + création GitHub Release sur chaque push vers `main`. Skip si la version existe déjà.

## Skills

- **`/deploy`** (`.claude/skills/deploy/SKILL.md`) — Merge la branche feature courante dans `dev`, attend le CI, puis crée une PR de `dev` vers `main`.

## Out of Scope

- No Login Items / launch-at-startup
- No App Store distribution
- macOS only (no Windows/Linux)
