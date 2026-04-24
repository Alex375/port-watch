import Foundation
import SwiftUI

@MainActor
@Observable
final class PortMonitor {
    var entries: [PortEntryDisplay] = []
    var lastScanDate: Date? = nil

    var portCount: Int { entries.count }

    /// Port count excluding "Other" — used for menubar icon state.
    var projectPortCount: Int {
        entries.filter { $0.entry.projectName != "Other" }.count
    }

    /// Whether any *project* entry is a confirmed zombie — used for menubar icon.
    /// "Other" is excluded to avoid alarms on system-level sockets the user cannot act on.
    var hasZombie: Bool {
        entries.contains { $0.isZombie && $0.entry.projectName != "Other" }
    }

    /// Number of consecutive scans a `(pid, port)` must remain in `CLOSE_WAIT` before being flagged as a zombie.
    nonisolated static let zombieConfirmationScans = 3

    /// Drop entries whose process name is in the user's ignore list (case-insensitive).
    /// Pure function — exposed for unit testing. `ignored` must be pre-lowercased.
    nonisolated static func filterIgnoredProcesses(_ entries: [PortEntry], ignored: Set<String>) -> [PortEntry] {
        guard !ignored.isEmpty else { return entries }
        return entries.filter { !ignored.contains($0.processName.lowercased()) }
    }

    var groupedEntries: [ProjectGroup] {
        let grouped = Dictionary(grouping: entries) { $0.entry.projectName }
        return grouped.map { ProjectGroup(projectName: $0.key, entries: $0.value) }
            .sorted { lhs, rhs in
                // "Other" always goes last
                if lhs.projectName == "Other" { return false }
                if rhs.projectName == "Other" { return true }
                return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
            }
    }

    /// Last kill result — shown to the user, never swallowed.
    var lastKillReport: KillReport? = nil

    /// Auto-dismiss task for the kill report banner.
    private var killReportDismissTask: Task<Void, Never>?

    /// Pending kill that requires confirmation (e.g. "Other" processes).
    var pendingKillConfirmation: PortEntryDisplay? = nil

    /// PIDs currently being killed — drives the loading spinner in UI.
    var killingPIDs: Set<Int32> = []

    /// Ports with multiple listeners — potential conflict.
    var conflictPorts: Set<UInt16> = []

    let settings = AppSettings.shared
    let snapshotStore = SnapshotStore.shared

    /// PIDs / snapshot ids currently being launched — drives the spinner in the
    /// "Recently stopped" section rows.
    var launchingSnapshotIDs: Set<String> = []

    /// Groups of recently-killed processes that can be relaunched, sorted most-recent-first.
    var stoppedGroups: [StoppedProjectGroup] {
        snapshotStore.groupedByProject()
    }

    private var previousSamples: [Int32: CPUSample] = [:]
    private var knownPorts: Set<UInt16> = []
    private var previousConflicts: Set<UInt16> = []
    private var scanTask: Task<Void, Never>? = nil

    /// Streak counter per `(pid, port)` for `CLOSE_WAIT` sockets.
    /// Reset to 0 when the socket leaves `CLOSE_WAIT` or disappears.
    private var closeWaitStreaks: [String: Int] = [:]

    nonisolated static func streakKey(pid: Int32, port: UInt16) -> String {
        "\(pid)-\(port)"
    }

    /// Advance the zombie streak for one scan.
    /// Returns the new streak value (0 if the socket isn't a zombie candidate) and whether it's a confirmed zombie.
    /// Exposed for unit testing.
    nonisolated static func advanceZombieStreak(
        tcpState: TCPState,
        previousStreak: Int,
        threshold: Int = zombieConfirmationScans
    ) -> (streak: Int, isZombie: Bool) {
        guard tcpState.isZombieCandidate else { return (0, false) }
        let streak = previousStreak + 1
        return (streak, streak >= threshold)
    }

    // MARK: - Worker fleet collapsing

    /// Collapse worker fleets: on each port, if multiple PIDs share an ancestry relationship
    /// (via `ppid`), they are merged into a single display representing the master, with
    /// `workerCount`, `workerPIDs`, aggregated CPU/RAM, and zombie propagation.
    ///
    /// Motivation: Python `multiprocessing.spawn`, gunicorn, uvicorn, Node cluster, nginx, etc.
    /// all fork a master that opens the listening socket; children inherit the FD. Prior to this
    /// fix these were misreported as port conflicts (issue #17).
    nonisolated static func collapseFleets(_ displays: [PortEntryDisplay]) -> [PortEntryDisplay] {
        let byPort = Dictionary(grouping: displays) { $0.entry.port }
        var result: [PortEntryDisplay] = []
        for (_, entries) in byPort {
            if entries.count == 1 {
                result.append(entries[0])
                continue
            }
            let fleets = partitionIntoFleets(entries)
            for fleet in fleets {
                if fleet.count == 1 {
                    result.append(fleet[0])
                } else {
                    result.append(mergeFleet(fleet))
                }
            }
        }
        return result.sorted { $0.entry.port < $1.entry.port }
    }

    /// Partition entries on the same port into connected components based on `ppid` links.
    /// Uses union-find: two entries are in the same fleet if one's `ppid` matches another's `pid`
    /// (direct parent/child), transitively covering multi-level ancestry within the same port set.
    nonisolated static func partitionIntoFleets(_ entries: [PortEntryDisplay]) -> [[PortEntryDisplay]] {
        guard !entries.isEmpty else { return [] }
        var parent: [Int32: Int32] = [:]
        for e in entries { parent[e.entry.pid] = e.entry.pid }

        func find(_ x: Int32) -> Int32 {
            var node = x
            while let p = parent[node], p != node { node = p }
            var cur = x
            while let p = parent[cur], p != node {
                parent[cur] = node
                cur = p
            }
            return node
        }
        func union(_ a: Int32, _ b: Int32) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }

        let pidSet = Set(entries.map { $0.entry.pid })
        for e in entries where pidSet.contains(e.entry.ppid) && e.entry.ppid != 0 {
            union(e.entry.pid, e.entry.ppid)
        }

        let groups = Dictionary(grouping: entries) { find($0.entry.pid) }
        return Array(groups.values)
    }

    /// Merge a fleet into a single display. Master = the entry whose `ppid` is NOT in the fleet
    /// (i.e. whose parent lives outside this group, or is 0). Ties are broken by lowest PID so
    /// the same master is picked across consecutive scans, keeping the row's `id` stable
    /// (otherwise `PortRowView.isExpanded` state would reset each refresh).
    nonisolated static func mergeFleet(_ fleet: [PortEntryDisplay]) -> PortEntryDisplay {
        precondition(!fleet.isEmpty)
        let pidSet = Set(fleet.map { $0.entry.pid })
        let sortedByPid = fleet.sorted { $0.entry.pid < $1.entry.pid }
        let master = sortedByPid.first { !pidSet.contains($0.entry.ppid) }
            ?? sortedByPid[0]
        let workers = fleet.filter { $0.entry.pid != master.entry.pid }

        let cpuSamples = fleet.compactMap(\.cpuPercent)
        let cpuPercent: Double? = cpuSamples.isEmpty ? nil : cpuSamples.reduce(0, +)
        let totalRAM = fleet.reduce(UInt64(0)) { $0 + $1.entry.residentMemoryBytes }
        let anyZombie = fleet.contains { $0.isZombie }

        return PortEntryDisplay(
            entry: master.entry,
            cpuPercent: cpuPercent,
            isZombie: anyZombie,
            workerCount: workers.count,
            workerPIDs: workers.map { $0.entry.pid },
            aggregatedMemoryBytes: totalRAM
        )
    }

    init() {
        startScanning()
    }

    func startScanning() {
        guard scanTask == nil else { return }
        scanTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.performScan()
                let interval = await AppSettings.shared.refreshInterval
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopScanning() {
        scanTask?.cancel()
        scanTask = nil
    }

    func performScan() async {
        let kw = PortScanner.RoleKeywords(
            front: settings.frontKeywords,
            back: settings.backKeywords,
            db: settings.dbKeywords,
            dbProc: settings.dbProcessNames,
            mcp: settings.mcpKeywords,
            claude: settings.claudeKeywords
        )
        let ignoredLowercased = Set(settings.ignoredProcesses.map { $0.lowercased() })
        let rawEntries = await Task.detached(priority: .utility) {
            let all = PortScanner.scanAllPorts(keywords: kw)
            return Self.filterIgnoredProcesses(all, ignored: ignoredLowercased)
        }.value

        let now = Date()
        var displayEntries: [PortEntryDisplay] = []
        var newSamples: [Int32: CPUSample] = [:]
        var newStreaks: [String: Int] = [:]

        for entry in rawEntries {
            var cpuPercent: Double? = nil
            if let prev = previousSamples[entry.pid] {
                let deltaCPU = entry.totalCPUTimeNs.subtractingReportingOverflow(prev.totalCPUTimeNs)
                if !deltaCPU.overflow {
                    let deltaWall = now.timeIntervalSince(prev.wallTime)
                    if deltaWall > 0 {
                        cpuPercent = (Double(deltaCPU.partialValue) / (deltaWall * 1_000_000_000)) * 100.0
                    }
                }
            }
            newSamples[entry.pid] = CPUSample(
                pid: entry.pid,
                totalCPUTimeNs: entry.totalCPUTimeNs,
                wallTime: now
            )

            let key = Self.streakKey(pid: entry.pid, port: entry.port)
            let result = Self.advanceZombieStreak(
                tcpState: entry.tcpState,
                previousStreak: closeWaitStreaks[key] ?? 0
            )
            if result.streak > 0 { newStreaks[key] = result.streak }

            displayEntries.append(PortEntryDisplay(entry: entry, cpuPercent: cpuPercent, isZombie: result.isZombie))
        }

        // Collapse worker fleets (Python multiprocessing, gunicorn workers, nginx workers, …)
        // into a single display row per family. Rows with unrelated PIDs on the same port
        // survive as separate entries and are flagged as real conflicts below.
        displayEntries = Self.collapseFleets(displayEntries)

        // Detect port conflicts *after* collapse: a real conflict is multiple unrelated families
        // on the same port (not a master + its workers).
        var portCounts: [UInt16: Int] = [:]
        for d in displayEntries {
            portCounts[d.entry.port, default: 0] += 1
        }
        let newConflicts = Set(portCounts.filter { $0.value > 1 }.keys)
        self.conflictPorts = newConflicts

        // Notifications
        do {
            let currentPorts = Set(rawEntries.map(\.port))

            // New ports
            if !knownPorts.isEmpty {
                let newPorts = currentPorts.subtracting(knownPorts)
                for port in newPorts {
                    if let entry = rawEntries.first(where: { $0.port == port }) {
                        let isProject = entry.projectName != "Other"
                        if settings.shouldNotifyNewPort(isProject: isProject) {
                            NotificationManager.shared.notifyNewPort(
                                port: port, processName: entry.processName, projectName: entry.projectName)
                        }
                    }
                }
            }

            // New conflicts
            let freshConflicts = newConflicts.subtracting(previousConflicts)
            for port in freshConflicts {
                let conflictEntries = rawEntries.filter { $0.port == port }
                let hasProject = conflictEntries.contains { $0.projectName != "Other" }
                if settings.shouldNotifyConflict(hasProject: hasProject) {
                    let names = conflictEntries.map(\.processName)
                    NotificationManager.shared.notifyPortConflict(port: port, processNames: names)
                }
            }

            self.previousConflicts = newConflicts
            self.knownPorts = currentPorts
        }

        self.entries = displayEntries
        self.previousSamples = newSamples
        self.closeWaitStreaks = newStreaks
        self.lastScanDate = now
    }

    /// Set the kill report and schedule auto-dismiss after 4 seconds.
    private func setKillReport(_ report: KillReport?) {
        killReportDismissTask?.cancel()
        lastKillReport = report
        guard report != nil else { return }
        killReportDismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation { lastKillReport = nil }
        }
    }

    // MARK: - Stop (kill + snapshot)

    /// Route a shutdown through `docker stop` if a container id is provided, otherwise
    /// fall through to the SIGTERM → SIGKILL sequence. `nonisolated` so it can run in a
    /// detached task. Preserves the `KillResult` shape so the existing report-building
    /// code downstream stays untouched.
    nonisolated static func shutdownOne(
        pid: Int32, port: UInt16, processName: String, dockerContainerID: String?
    ) async -> PortScanner.KillResult {
        if let id = dockerContainerID, !id.isEmpty {
            let r = await ProcessLauncher.stopDockerContainer(id: id, processName: processName)
            return PortScanner.KillResult(
                pid: pid, port: port, processName: processName,
                success: r.success, error: r.error
            )
        }
        return await PortScanner.killProcess(pid: pid, port: port, processName: processName)
    }

    /// Stop the process behind a port row — kills, verifies the process is gone, and only
    /// then saves a restart snapshot. If the kill fails or the process is still alive, no
    /// snapshot is recorded (the row will still appear in the live list on the next scan).
    /// If the row is a worker fleet, master + workers are killed in parallel and aggregated
    /// in a single banner message. Docker-backed rows route through `docker stop` instead.
    func stopPort(_ display: PortEntryDisplay) async {
        setKillReport(nil)

        let master = display.entry
        // Capture the snapshot in memory BEFORE the kill (argv / env / cwd need to be read
        // off the live process) but only persist it below once the kill is confirmed.
        let pendingSnapshot = master.toSnapshot()

        // Worker PIDs are only relevant for native fleets — for docker, the daemon process
        // owns the port and `docker stop` is a single operation.
        let containerID = master.dockerContainerID
        let workerPIDs = (containerID?.isEmpty == false) ? [] : display.workerPIDs
        let allPIDs = [master.pid] + workerPIDs
        for pid in allPIDs { killingPIDs.insert(pid) }

        let masterPid = master.pid
        let masterPort = master.port
        let masterName = master.processName

        let results = await Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: PortScanner.KillResult.self) { group in
                group.addTask {
                    await Self.shutdownOne(
                        pid: masterPid, port: masterPort,
                        processName: masterName, dockerContainerID: containerID
                    )
                }
                for wpid in workerPIDs {
                    group.addTask {
                        await Self.shutdownOne(
                            pid: wpid, port: masterPort,
                            processName: masterName, dockerContainerID: nil
                        )
                    }
                }
                var collected: [PortScanner.KillResult] = []
                for await r in group { collected.append(r) }
                return collected
            }
        }.value

        for pid in allPIDs { killingPIDs.remove(pid) }

        // Single-process / single-container fast path. Docker stops skip the `isAlive` check
        // because the daemon process stays up even after the container stops — the port
        // going away is what confirms success (picked up on the next scan).
        let isDocker = containerID?.isEmpty == false
        if workerPIDs.isEmpty, let result = results.first {
            let verb = isDocker ? "Stopped container" : "Killed"
            let subject = "\(result.processName) on :\(result.port)"
            if result.success {
                if !isDocker && PortScanner.isAlive(pid: master.pid) {
                    setKillReport(KillReport(
                        message: "Kill of \(subject) (PID \(result.pid)) reported success but process is still alive",
                        isError: true
                    ))
                } else {
                    // Kill verified — now it's safe to commit the snapshot to the history.
                    snapshotStore.save(pendingSnapshot)
                    let suffix = isDocker ? "" : " (PID \(result.pid))"
                    setKillReport(KillReport(message: "\(verb) \(subject)\(suffix)", isError: false))
                }
            } else {
                let action = isDocker ? "stop container" : "kill"
                setKillReport(KillReport(
                    message: "Failed to \(action) \(subject) (PID \(result.pid)): \(result.error ?? "unknown error")",
                    isError: true
                ))
            }
            await performScan()
            return
        }

        // Fleet kill — aggregate report. Snapshot is saved only if at least one PID
        // (master or worker) was verified dead; otherwise nothing reached the history.
        var successes = 0
        var failures: [String] = []
        for r in results {
            if r.success {
                if PortScanner.isAlive(pid: r.pid) {
                    failures.append("PID \(r.pid) still alive after kill reported success")
                } else {
                    successes += 1
                }
            } else {
                failures.append("PID \(r.pid) — \(r.error ?? "unknown error")")
            }
        }
        let total = successes + failures.count
        let label = "\(master.processName) on :\(master.port) (\(total) processes)"
        if successes > 0 {
            snapshotStore.save(pendingSnapshot)
        }
        if failures.isEmpty {
            setKillReport(KillReport(message: "Killed \(label)", isError: false))
        } else {
            let msg = "Killed \(successes)/\(total) of \(label)\n" + failures.joined(separator: "\n")
            setKillReport(KillReport(message: msg, isError: true))
        }

        await performScan()
    }

    /// Stop all processes in a project group — snapshots are captured in memory first but
    /// only persisted to the history for rows whose kill was verified (process dead, or
    /// `docker stop` returned 0). Failed or still-alive PIDs produce no snapshot.
    func stopProject(_ group: ProjectGroup) async {
        setKillReport(nil)

        // Capture snapshots in memory — one per row. Multiple ports on the same PID produce
        // multiple snapshots, which is what we want (each port is independently relaunchable).
        // Key them by pid so we can commit only the ones whose kill succeeds.
        var pendingSnapshotsByPid: [Int32: [LaunchSnapshot]] = [:]
        for display in group.entries {
            pendingSnapshotsByPid[display.entry.pid, default: []].append(display.entry.toSnapshot())
        }

        // Deduplicate by (pid, containerID) — a single PID listening on multiple ports
        // only needs one shutdown. A docker-backed row is tracked separately so we route
        // through `docker stop` for each unique container.
        struct ShutdownTarget {
            let pid: Int32
            let port: UInt16
            let processName: String
            let containerID: String?
        }
        var targets: [ShutdownTarget] = []
        var seenPIDs = Set<Int32>()
        var seenContainerIDs = Set<String>()
        for display in group.entries {
            let entry = display.entry
            if let cid = entry.dockerContainerID, !cid.isEmpty {
                guard seenContainerIDs.insert(cid).inserted else { continue }
                targets.append(ShutdownTarget(pid: entry.pid, port: entry.port, processName: entry.processName, containerID: cid))
            } else {
                guard seenPIDs.insert(entry.pid).inserted else { continue }
                targets.append(ShutdownTarget(pid: entry.pid, port: entry.port, processName: entry.processName, containerID: nil))
            }
            killingPIDs.insert(entry.pid)
        }

        let results = await withTaskGroup(of: PortScanner.KillResult.self) { taskGroup in
            for target in targets {
                taskGroup.addTask {
                    await Self.shutdownOne(
                        pid: target.pid, port: target.port,
                        processName: target.processName,
                        dockerContainerID: target.containerID
                    )
                }
            }
            var collected: [PortScanner.KillResult] = []
            for await result in taskGroup { collected.append(result) }
            return collected
        }

        for target in targets { killingPIDs.remove(target.pid) }

        var successes = 0
        var failures: [String] = []
        for result in results {
            if result.success {
                successes += 1
            } else {
                failures.append(":\(result.port) \(result.processName) — \(result.error ?? "unknown error")")
            }
        }

        // Final verification for native kills — `docker stop` already blocks until done,
        // so we only re-check PIDs that went through the kill() path. Only now do we commit
        // snapshots for rows whose kill was verified.
        var zombieWarnings: [String] = []
        for (target, result) in zip(targets, results) {
            guard result.success else { continue }
            let verified: Bool
            if target.containerID == nil {
                if PortScanner.isAlive(pid: result.pid) {
                    zombieWarnings.append(":\(result.port) \(result.processName) (PID \(result.pid)) still alive after kill reported success")
                    verified = false
                } else {
                    verified = true
                }
            } else {
                verified = true
            }
            if verified, let snaps = pendingSnapshotsByPid[target.pid] {
                for snap in snaps { snapshotStore.save(snap) }
            }
        }

        let total = successes + failures.count
        if failures.isEmpty && zombieWarnings.isEmpty {
            setKillReport(KillReport(
                message: "\(group.projectName): \(successes) process\(successes == 1 ? "" : "es") stopped",
                isError: false
            ))
        } else if !failures.isEmpty {
            let msg = "\(group.projectName): \(successes)/\(total) stopped, \(failures.count) failed\n" + failures.joined(separator: "\n")
            setKillReport(KillReport(message: msg, isError: true))
        } else {
            let msg = "\(group.projectName): stops reported success but verification failed\n" + zombieWarnings.joined(separator: "\n")
            setKillReport(KillReport(message: msg, isError: true))
        }

        await performScan()
    }

    // MARK: - Start (relaunch from snapshot)

    /// How long `startSnapshot`/`startProject` poll for the port to reappear before giving
    /// up. Mirrors the symmetry with the kill path: SIGTERM waits 4 s for the process to
    /// exit, so we give the relaunch the same budget to bind its port.
    static let relaunchVerificationBudget: Duration = .seconds(6)
    /// Interval between port rescans during relaunch verification. Short enough to feel
    /// snappy for fast binders (Go/Rust), long enough to avoid hammering libproc for a
    /// slow starter (JVM, Python import chain).
    static let relaunchPollInterval: Duration = .milliseconds(200)

    /// Poll up to `budget` for the given port to be bound by a process matching
    /// `projectKey`. Returns `true` as soon as it's observed, `false` on timeout.
    /// The caller owns the rescan loop — we keep triggering `performScan()` so the
    /// live `entries` stay up to date both in the UI and for this check.
    private func waitForPortReappearance(
        port: UInt16,
        projectKey: String,
        budget: Duration = relaunchVerificationBudget,
        interval: Duration = relaunchPollInterval
    ) async -> Bool {
        let start = ContinuousClock.now
        while ContinuousClock.now - start < budget {
            await performScan()
            if entries.contains(where: { $0.entry.port == port && $0.entry.projectKey == projectKey }) {
                return true
            }
            try? await Task.sleep(for: interval)
        }
        // One last scan after the budget — the final sleep may have pushed us just past
        // the deadline while the port came up.
        await performScan()
        return entries.contains { $0.entry.port == port && $0.entry.projectKey == projectKey }
    }

    /// Relaunch a single snapshot. Spawns (or `docker start`s) the process, then polls
    /// up to `relaunchVerificationBudget` for the port to actually become LISTEN before
    /// declaring success. If the port never reappears within the budget we surface an
    /// error — the snapshot stays in the history so the user can retry.
    func startSnapshot(_ snapshot: LaunchSnapshot) async {
        guard !launchingSnapshotIDs.contains(snapshot.id) else { return }
        launchingSnapshotIDs.insert(snapshot.id)
        setKillReport(nil)

        let result = await ProcessLauncher.relaunch(snapshot)

        if !result.success {
            launchingSnapshotIDs.remove(snapshot.id)
            setKillReport(KillReport(
                message: "Failed to launch \(snapshot.processName) on :\(snapshot.port): \(result.error ?? "unknown error")",
                isError: true
            ))
            return
        }

        // Spawn succeeded — now verify the port is actually bound. A successful spawn
        // only means we got a PID back; the process could still fail on startup (missing
        // config, port already taken, DB connection refused, etc.).
        let reappeared = await waitForPortReappearance(
            port: snapshot.port,
            projectKey: snapshot.projectKey
        )
        launchingSnapshotIDs.remove(snapshot.id)

        if reappeared {
            snapshotStore.remove(id: snapshot.id)
            setKillReport(KillReport(
                message: "Launched \(snapshot.processName) on :\(snapshot.port)",
                isError: false
            ))
        } else {
            setKillReport(KillReport(
                message: "Launched \(snapshot.processName) but :\(snapshot.port) did not come up within \(Int(Self.relaunchVerificationBudget.components.seconds))s — check the process logs",
                isError: true
            ))
        }
    }

    /// Relaunch every snapshot for a project, sequentially by role (DB → Cache → Back →
    /// MCP → Front → Other) so that downstream services see their dependencies already
    /// bound. Processes within the same role bucket run in parallel.
    func startProject(projectKey: String) async {
        let allSnapshots = snapshotStore.all(for: projectKey)
        guard !allSnapshots.isEmpty else { return }
        setKillReport(nil)
        let projectName = allSnapshots.first?.projectName ?? projectKey

        let buckets = Dictionary(grouping: allSnapshots) { RelaunchRole.from(roleLabel: $0.roleLabel) }
        let sortedRoles = buckets.keys.sorted { $0.rawValue < $1.rawValue }

        var successes = 0
        var failures: [String] = []

        // Mark every snapshot as "launching" up front — the per-row spinner must stay
        // lit during both the spawn and the port-bind verification. IDs are cleared
        // one-by-one below as each port comes up (or after the budget expires).
        for snap in allSnapshots { launchingSnapshotIDs.insert(snap.id) }

        for (index, role) in sortedRoles.enumerated() {
            guard let bucket = buckets[role], !bucket.isEmpty else { continue }

            let results = await withTaskGroup(of: (LaunchSnapshot, ProcessLauncher.LaunchResult).self) { taskGroup in
                for snap in bucket {
                    taskGroup.addTask { (snap, await ProcessLauncher.relaunch(snap)) }
                }
                var out: [(LaunchSnapshot, ProcessLauncher.LaunchResult)] = []
                for await r in taskGroup { out.append(r) }
                return out
            }

            for (snap, r) in results {
                if r.success {
                    successes += 1
                } else {
                    // Spawn itself failed — stop showing the spinner for this row now.
                    launchingSnapshotIDs.remove(snap.id)
                    failures.append(":\(snap.port) \(snap.processName) — \(r.error ?? "unknown error")")
                }
            }

            // Only pause between role buckets, not after the last one.
            if index < sortedRoles.count - 1 {
                try? await Task.sleep(for: .milliseconds(500))
            }
        }

        // Verify each spawn actually bound its port. Poll up to the same budget as the
        // single-snapshot path, with one rescan loop shared across all snapshots in this
        // project. Snapshots whose ports come up get removed from the history; the rest
        // are kept (failed launches or slow starters). Spinner stays lit per row until
        // the port is verified up or the budget expires.
        let start = ContinuousClock.now
        var pendingPorts = Set(allSnapshots.map { $0.port })
        while !pendingPorts.isEmpty && ContinuousClock.now - start < Self.relaunchVerificationBudget {
            await performScan()
            let runningNow = Set(entries.filter { $0.entry.projectKey == projectKey }.map { $0.entry.port })
            let justCameUp = pendingPorts.intersection(runningNow)
            if !justCameUp.isEmpty {
                for snap in allSnapshots where justCameUp.contains(snap.port) {
                    snapshotStore.remove(id: snap.id)
                    launchingSnapshotIDs.remove(snap.id)
                }
                pendingPorts.subtract(justCameUp)
            }
            if pendingPorts.isEmpty { break }
            try? await Task.sleep(for: Self.relaunchPollInterval)
        }

        // Clear any remaining spinners — the budget expired without these ports coming up.
        for snap in allSnapshots where pendingPorts.contains(snap.port) {
            launchingSnapshotIDs.remove(snap.id)
        }

        let verified = allSnapshots.count - pendingPorts.count
        let total = successes + failures.count
        if failures.isEmpty && pendingPorts.isEmpty {
            setKillReport(KillReport(
                message: "\(projectName): launched \(verified) process\(verified == 1 ? "" : "es")",
                isError: false
            ))
        } else if failures.isEmpty {
            let budget = Int(Self.relaunchVerificationBudget.components.seconds)
            let missing = pendingPorts.sorted().map(String.init).joined(separator: ", ")
            setKillReport(KillReport(
                message: "\(projectName): launched \(total), but :\(missing) did not come up within \(budget)s",
                isError: true
            ))
        } else {
            let msg = "\(projectName): launched \(successes)/\(total), \(failures.count) failed\n" + failures.joined(separator: "\n")
            setKillReport(KillReport(message: msg, isError: true))
        }
    }
}
