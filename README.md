<p align="center">
  <img src="screenshots/app_icon.png" width="128" alt="PortWatch icon" />
</p>

<h1 align="center">PortWatch</h1>

<p align="center">
  <strong>A lightweight macOS menubar app that monitors open TCP ports, identifies projects & processes, and lets you kill them — without leaving your workflow.</strong>
</p>

<p align="center">
  <a href="https://github.com/Alex375/port-watch/releases/latest"><img src="https://img.shields.io/github/v/release/Alex375/port-watch?label=Latest%20Release&color=blue" alt="Latest Release"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey?logo=apple" alt="macOS 26+">
  <img src="https://img.shields.io/badge/Swift-6.0-orange?logo=swift" alt="Swift 6.0">
  <a href="https://github.com/Alex375/port-watch/actions"><img src="https://img.shields.io/github/actions/workflow/status/Alex375/port-watch/ci.yml?branch=dev&label=CI" alt="CI"></a>
</p>

---

## Why PortWatch?

Ever run `lsof -i -P | grep LISTEN` to figure out what's hogging port 3000? PortWatch does that for you — continuously, visually, and with one-click kill.

- **Zero dependencies** — uses native macOS `libproc` APIs, no `lsof`, no Python, no external tools
- **Project-aware** — groups ports by Docker container, Git repo, or known service
- **Role tagging** — instantly see which port is your frontend, backend, database, cache, or MCP server
- **Non-intrusive** — lives in your menubar, no Dock icon

<p align="center">
  <img src="screenshots/menubar.png" alt="PortWatch in the macOS menubar" />
  <br />
  <em>PortWatch lives in your menubar — always visible, never in the way.</em>
</p>

## Features

### Port Detection

- Real-time scanning of all open TCP ports via native macOS APIs (`libproc`)
- Displays port number, process name, PID, full command line, and uptime
- Auto-refresh every 10s (configurable: 3s – 30s) + manual refresh

### Smart Project Grouping

Ports are automatically grouped by project using this priority:

| Priority | Method | Example |
|:---:|---|---|
| 1 | **Docker** — matches exposed ports with running containers | `my-api` container on :8080 |
| 2 | **Git repo** — walks up from process cwd to find `.git` | `port-watch` project |
| 3 | **Known ports** — PostgreSQL, MySQL, Redis, MongoDB, Elasticsearch | PostgreSQL on :5432 |
| 4 | **Other** — unidentified processes (shown last) | System services |

<p align="center">
  <img src="screenshots/main_screen.png" width="420" alt="Port list grouped by project" />
  <br />
  <em>Ports grouped by project with role tags, uptime, and one-click actions.</em>
</p>

### Role Tagging

Each process is tagged with a role based on configurable keyword matching against folder name, process name, and command line:

| Role | Default keywords | Icon |
|---|---|---|
| **Front** | front, web, client, ui, vite, webpack, next, nuxt | 🌐 Globe |
| **Back** | back, api, server, uvicorn, gunicorn, flask, django, express, fastify | 🖥 Server |
| **DB** | postgres, mysqld, mysql, mongod, redis-server + db, database (folders) | 💾 Drive |
| **Cache** | memcached, rabbitmq-server | ⚡ Bolt |
| **MCP** | mcp-server, mcp_server, fastmcp, modelcontextprotocol | 🤖 MCP |

All keywords are editable in Settings.

### Process Management

- **Kill individual process** — `SIGTERM` → 4s polling → `SIGKILL` → 2s polling → verified dead
- **Kill entire project** — kills all processes in a group in parallel, with per-process verification and detailed report
- **Safety confirmation** required for "Other" (unidentified) processes
- **Open in browser** — opens `http://localhost:PORT` for any port

### Monitoring & Alerts

| Indicator | Meaning | Badge |
|---|---|---|
| Zombie process | `CLOSE_WAIT` or `TIME_WAIT` state | 🔴 Red |
| Port conflict | Multiple PIDs on the same port | 🟡 Yellow |
| High CPU | Exceeds threshold (default: 50%) | 🟠 Orange |
| High RAM | Exceeds threshold (default: 500 MB) | 🟠 Orange |

### Dynamic Menubar Icon

| State | Icon |
|---|---|
| No project ports | Eye closed |
| 1–3 ports | Eye open |
| 4–8 ports | Eye filled |
| 9+ ports or zombie detected | Eye with warning |

### Notifications

Optional macOS notifications (off by default), configurable per category:

- **New ports** — Off / Projects only / All
- **Port conflicts** — Off / Projects only / All

### Settings

Inline settings panel with:
- CPU & RAM alert thresholds (sliders)
- Refresh interval (3–30 seconds)
- Notification preferences
- Detection keywords (editable tags)
- Version info + update checker
- Reset to defaults / Uninstall

<p align="center">
  <img src="screenshots/settings.png" width="420" alt="Settings panel" />
  <br />
  <em>Configurable thresholds, notification preferences, and editable detection keywords.</em>
</p>

### Auto-Update

Checks GitHub Releases at launch for new versions. One-click update: downloads, replaces, and relaunches.

---

## Installation

### Download

1. Go to [**Releases**](https://github.com/Alex375/port-watch/releases/latest)
2. Download `PortWatch.zip`
3. Unzip and move `PortWatch.app` to `/Applications`

### First Launch (unsigned app)

The app is not signed with an Apple Developer certificate. macOS will block the first launch:

1. Double-click `PortWatch.app` — macOS shows *"cannot be opened"*
2. Open **System Settings → Privacy & Security**
3. Scroll down — you'll see *"PortWatch was blocked"*
4. Click **Open Anyway**

This is only needed once.

---

## Uninstall

Two options:

| Method | How |
|---|---|
| **From the app** | Settings → *Uninstall PortWatch…* (with confirmation) |
| **Standalone script** | `./uninstall.sh` |

Both remove the .app, UserDefaults preferences, caches, logs, and any residual process.

---

## Build from Source

Requires **Xcode** (free from the App Store) on **macOS 26+**.

```bash
# Debug build
xcodebuild -scheme PortWatch -configuration Debug build

# Release build (.app)
xcodebuild -scheme PortWatch -configuration Release build

# Run tests
xcodebuild -scheme PortWatch test
```

---

## Tech Stack

| Component | Technology |
|---|---|
| Language | Swift 6.0 (strict concurrency) |
| UI | SwiftUI `MenuBarExtra` (`.window` style) |
| Concurrency | `@Observable`, `@MainActor`, `Task.detached`, `TaskGroup` |
| Port scanning | Native macOS `libproc` APIs (`import Darwin`) |
| Docker detection | `docker ps --format json` |
| Persistence | `UserDefaults` |
| Notifications | `UNUserNotificationCenter` |
| CI/CD | GitHub Actions (`macos-26` runner) |
| Min. macOS | 26.0 (Tahoe) |

---

## Contributing

### Git Workflow

```
feature/xxx ──merge──▸ dev ──PR──▸ main ──auto──▸ GitHub Release
                        │           │
                     CI tests    CI tests + review @Alex375
```

1. Create a branch from `dev`: `git checkout dev && git checkout -b feature/my-feature`
2. Code, commit, push
3. Merge into `dev` (CI tests must pass)
4. Create a PR `dev` → `main`
5. PR requires CI + review from @Alex375
6. On merge to `main`: GitHub Actions builds a Release `.app` and publishes a GitHub Release

### Versioning

Version is read from `Info.plist` (`CFBundleShortVersionString`). Bump it before each PR to `main` — otherwise the release is skipped.

| Change type | Version bump | Example |
|---|---|---|
| Bug fix / tweak | Patch | 1.1.0 → 1.1.1 |
| New feature | Minor | 1.1.0 → 1.2.0 |
| Breaking change | Major | 1.1.0 → 2.0.0 |

---

## License

Personal use.
