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
| `PortWatch/Sources/PortWatchApp.swift` | App entry point (`@main`), `MenuBarExtra` scene with `.window` style, `MenuContentView` (full UI: header, grouped port list, **Recently stopped section**, kill confirmation banner, kill/launch report banner, settings toggle, footer). Also defines `StoppedRowStyle` and `HoverButton`/`FooterButton` helpers. |
| `PortWatch/Sources/PortRowView.swift` | SwiftUI card for a single running port row — hero port number, role badge, fleet pill, hover-revealed actions (globe + power toggle), expandable command line, warning pills. The red power icon (`power.circle.fill`) is the stop toggle. A **right-click context menu** (`rowContextMenu`) offers actions (Open URL via `onOpen`, Copy URL, Reveal in Finder, Open in Terminal — the last three handled inline via `NSPasteboard`/`NSWorkspace`), *untruncated* detail sections (full Command, Working directory, Executable path — each pre-wrapped by the pure `PortRowView.wrappedLines(_:width:)` into short label rows because an NSMenu item is single-line and can't wrap; the in-row layout truncates these for density), and "Ignore/Stop ignoring `<process>`" (wired to `PortMonitor.ignoreProcess`/`unignoreProcess` via the `onIgnore`/`onUnignore` closures). |
| `PortWatch/Sources/PortEntry.swift` | Data models: `TCPState` enum (maps TSI_S_* constants), `PortEntry` struct (one open port, now including `arguments`, `environment`, `projectKey`, `dockerContainerID`), `CPUSample`, `PortEntryDisplay` (enriched with cross-scan CPU %), `ProjectGroup`, `KillReport`. Also contains `PortEntry.detectRole()` and `PortEntry.toSnapshot()`. |
| `PortWatch/Sources/LaunchSnapshot.swift` | `LaunchSnapshot` struct (`Codable, Sendable`) capturing everything needed to relaunch a killed process: cwd, executable path, full argv, scrubbed environment, role, port, and optional docker container id. Also defines `RelaunchRole` (DB < Cache < Back < MCP < Front < Other), `StoppedProjectGroup`, and `EnvScrubber` (deny-list that redacts secret-looking env vars before persistence — prevents tokens/keys from landing in plaintext UserDefaults). |
| `PortWatch/Sources/SnapshotStore.swift` | `@MainActor @Observable` singleton that persists `[id: LaunchSnapshot]` in UserDefaults (JSON, ISO8601 dates). Prunes snapshots older than `AppSettings.snapshotTTLMinutes` on init and after every save. `save()` prunes in-memory then persists once (one write per call). On decode failure, preserves the corrupt blob under `launchSnapshots.corruptBackup` instead of wiping silently. Exposes `save`, `remove(id:)`, `remove(projectKey:)`, `all(for:)`, `groupedByProject()`, `prune()`, `pruneMinutes(olderThan:)`, `clearAll()`. |
| `PortWatch/Sources/ProcessLauncher.swift` | Stateless `enum ProcessLauncher`. `relaunch(_ snapshot)` dispatches to `docker start <id>` when `dockerContainerID != nil`, otherwise spawns `Process(executable, args.dropFirst(), cwd, environment)` with stdio redirected to `/dev/null` (FDs explicitly closed after `run()` to avoid leaks) and a new process group (`setpgid`) so the child survives PortWatch quitting. Docker path drains stderr concurrently with `waitUntilExit()` to avoid the 64 KB pipe-buffer deadlock. `dockerCommand(verb:containerID:)` centralizes the `docker start`/`docker stop` argv builder. Also exposes `stopDockerContainer` used by `PortMonitor.stopPort` for container-backed rows. |
| `PortWatch/Sources/PortScanner.swift` | Low-level stateless scanner (`enum PortScanner`). Wraps libproc APIs. `processArgs(pid:)` parses `KERN_PROCARGS2` into `ProcessArgs(argv, environment, summary)`. `scanAllPorts()` fills `PortEntry.arguments`/`environment`/`projectKey`/`dockerContainerID`. `isPortListening(_:)` is a lightweight "any process LISTENing on this port?" check used by `PortMonitor` during relaunch verification — skips argv/cwd/project enrichment for a ~10× speedup. Still exposes `killProcess()` (SIGTERM/SIGKILL) for native kills; docker kills go through `ProcessLauncher`. |
| `PortWatch/Sources/PortMonitor.swift` | `@MainActor @Observable` class driving the UI. Owns the scan loop, computes CPU %, detects conflicts, triggers notifications. Stop flow: `stopPort()` / `stopProject()` save snapshots *before* killing, route Docker rows through `docker stop`, aggregate results via `shutdownOne()` (nonisolated static helper). `stopProject` keys pending snapshots by *target* (`docker:<id>` / `pid:<pid>`) rather than raw PID, so Docker Desktop's shared daemon PID doesn't cause collisions across containers. Start flow: `startSnapshot()` relaunches one snapshot and polls via `PortScanner.isPortListening` until the port binds; `startProject(projectKey:)` walks roles in priority order, parallel within a role, with a 500 ms pause between roles. Exposes `stoppedGroups` derived from `SnapshotStore`. |
| `PortWatch/Sources/ProjectDetector.swift` | Stateless `enum ProjectDetector`. Priority: Docker containers > git root > known port > "Other". Returns `ProjectInfo(name, worktreeName, key)` — `key` is a stable identifier (`docker:<id>` / absolute git-root path / `known:<name>` / `other:<processName>`) used by `SnapshotStore` so snapshots survive across app restarts and disambiguate same-named projects. Also exposes `dockerContainerID(forPort:)`. |
| `PortWatch/Sources/NotificationManager.swift` | `@MainActor` singleton wrapping `UNUserNotificationCenter`. Sends notifications for new port detection and port conflicts. |
| `PortWatch/Sources/AppSettings.swift` | `@MainActor @Observable` singleton persisted via `UserDefaults`. Stores thresholds (CPU, RAM), refresh interval, notification toggles, role detection keywords, ignored processes, and `snapshotTTLMinutes` (default 60 = 1 h; 0 = Keep forever). Also exposes `relaunchVerificationBudget` / `relaunchPollInterval` used by `PortMonitor` during restart verification. One-shot migration from legacy `snapshotTTLHours` runs *before* `register(defaults:)` so the pre-v2.2 value isn't shadowed by the new registered default. |
| `PortWatch/Sources/SettingsView.swift` | SwiftUI settings panel. Sections: Monitoring, Notifications, Role detection, Ignored processes, **Restart history** (TTL slider + snapshot count + Clear all), About, Danger zone. |
| `PortWatchTests/PortWatchTests.swift` | Unit tests (TCPState, PortEntry, PortScanner, ProjectDetector, AppSettings, models, fleet collapsing, `LaunchSnapshot` round-trip, `SnapshotStore` save/prune/grouping, `PortScanner.parseProcArgsBuffer`, `ProcessLauncher` docker command builder, `PortEntry.toSnapshot`). |
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

The scan filters for TCP sockets in LISTEN, CLOSE_WAIT, or TIME_WAIT states. A second filter (`PortScanner.filterServerSockets`) keeps each CLOSE_WAIT/TIME_WAIT only if the same PID is also LISTENing on that port — this drops client-side outbound connection remnants (e.g. a browser or AI tool's HTTPS connections sitting in CLOSE_WAIT on ephemeral ports) so only genuine server state reaches the UI. Results are deduplicated by (port, pid) to handle dual IPv4/IPv6 listeners.

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
- **Claude:** claude, claude-code, @anthropic-ai/claude-code, anthropic-ai/claude (matches process name and command line only — not folder, to avoid false positives on project folders named "claude-notes" etc.). Checked before MCP so the Claude CLI itself is tagged "Claude" even when it spawns MCP child processes.

### Stop / Start Sequence

Every stop is routed through `PortMonitor.shutdownOne(pid:port:processName:dockerContainerID:)`:
- **Native kill** (no container id) — strict SIGTERM → 4 s poll → SIGKILL → 2 s poll → verified dead (`PortScanner.killProcess`).
- **Docker stop** — `docker stop <id>` via `ProcessLauncher`. The daemon process stays alive, so `isAlive(pid:)` is not used to verify; the port going away on the next scan is the confirmation signal.

Before any stop, `PortMonitor` saves a `LaunchSnapshot` via `SnapshotStore.save()`. This is what makes the "Recently stopped" entries restartable.

A restart (`PortMonitor.startSnapshot`) calls `ProcessLauncher.relaunch`:
- **Docker** — `docker start <id>`. Preserves volumes and network.
- **Native** — spawns `Process` with `executableURL = snapshot.executablePath`, `arguments = snapshot.arguments.dropFirst()` (Swift re-injects argv[0]), `currentDirectoryURL = snapshot.cwd`, `environment = snapshot.environment`. stdio → `/dev/null`. After `run()`, calls `setpgid(pid, pid)` so the child becomes its own session leader and survives PortWatch quitting.

After each relaunch, PortMonitor sleeps 1 s, rescans, and removes the snapshot from `SnapshotStore` if the port reappeared under the same `projectKey`. If not, the snapshot stays so the user can retry.

Project-level restart (`PortMonitor.startProject(projectKey:)`) walks role buckets in priority order (**DB → Cache → Back → MCP → Front → Other**), with a 500 ms pause between buckets. Processes inside the same bucket launch in parallel.

Kills for "Other" (unidentified project) processes still require explicit user confirmation via an inline banner.

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
