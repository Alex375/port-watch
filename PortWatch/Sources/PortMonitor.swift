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
            mcp: settings.mcpKeywords
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

    // MARK: - Kill

    /// Kill the process behind a port row. If the row is a worker fleet, master and all
    /// workers are killed in parallel and the result is reported as a single aggregated message.
    func killPort(_ display: PortEntryDisplay) async {
        setKillReport(nil)

        let master = display.entry
        let workerPIDs = display.workerPIDs
        let allPIDs = [master.pid] + workerPIDs
        for pid in allPIDs { killingPIDs.insert(pid) }

        // Kill master + workers in parallel.
        let results = await Task.detached(priority: .userInitiated) {
            await withTaskGroup(of: PortScanner.KillResult.self) { group in
                group.addTask {
                    await PortScanner.killProcess(pid: master.pid, port: master.port, processName: master.processName)
                }
                for wpid in workerPIDs {
                    group.addTask {
                        await PortScanner.killProcess(pid: wpid, port: master.port, processName: master.processName)
                    }
                }
                var collected: [PortScanner.KillResult] = []
                for await r in group { collected.append(r) }
                return collected
            }
        }.value

        for pid in allPIDs { killingPIDs.remove(pid) }

        // Single-process fast path — keep the original message format.
        if workerPIDs.isEmpty, let result = results.first {
            if result.success {
                if PortScanner.isAlive(pid: master.pid) {
                    setKillReport(KillReport(
                        message: "Kill of \(result.processName) on :\(result.port) (PID \(result.pid)) reported success but process is still alive",
                        isError: true
                    ))
                } else {
                    setKillReport(KillReport(
                        message: "Killed \(result.processName) on :\(result.port) (PID \(result.pid))",
                        isError: false
                    ))
                }
            } else {
                setKillReport(KillReport(
                    message: "Failed to kill \(result.processName) on :\(result.port) (PID \(result.pid)): \(result.error ?? "unknown error")",
                    isError: true
                ))
            }
            await performScan()
            return
        }

        // Fleet kill — aggregate report.
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
        if failures.isEmpty {
            setKillReport(KillReport(message: "Killed \(label)", isError: false))
        } else {
            let msg = "Killed \(successes)/\(total) of \(label)\n" + failures.joined(separator: "\n")
            setKillReport(KillReport(message: msg, isError: true))
        }

        await performScan()
    }

    /// Kill all processes in a project group in parallel and report results.
    func killProject(_ group: ProjectGroup) async {
        setKillReport(nil)

        // Deduplicate by PID (multiple ports can belong to same process)
        var uniqueEntries: [PortEntry] = []
        var seenPIDs = Set<Int32>()
        for display in group.entries {
            guard seenPIDs.insert(display.entry.pid).inserted else { continue }
            uniqueEntries.append(display.entry)
            killingPIDs.insert(display.entry.pid)
        }

        // Kill all in parallel
        let results = await withTaskGroup(of: PortScanner.KillResult.self) { taskGroup in
            for entry in uniqueEntries {
                taskGroup.addTask {
                    await PortScanner.killProcess(pid: entry.pid, port: entry.port, processName: entry.processName)
                }
            }
            var collected: [PortScanner.KillResult] = []
            for await result in taskGroup {
                collected.append(result)
            }
            return collected
        }

        // Clear all killing indicators
        for entry in uniqueEntries {
            killingPIDs.remove(entry.pid)
        }

        // Tally results
        var successes = 0
        var failures: [String] = []
        for result in results {
            if result.success {
                successes += 1
            } else {
                failures.append(":\(result.port) \(result.processName) — \(result.error ?? "unknown error")")
            }
        }

        // Final verification: re-check each PID that was reported as killed
        var zombieWarnings: [String] = []
        for result in results where result.success {
            if PortScanner.isAlive(pid: result.pid) {
                zombieWarnings.append(":\(result.port) \(result.processName) (PID \(result.pid)) still alive after kill reported success")
            }
        }

        let total = successes + failures.count
        if failures.isEmpty && zombieWarnings.isEmpty {
            setKillReport(KillReport(
                message: "\(group.projectName): \(successes) process\(successes == 1 ? "" : "es") killed",
                isError: false
            ))
        } else if !failures.isEmpty {
            let msg = "\(group.projectName): \(successes)/\(total) killed, \(failures.count) failed\n" + failures.joined(separator: "\n")
            setKillReport(KillReport(message: msg, isError: true))
        } else {
            let msg = "\(group.projectName): kills reported success but verification failed\n" + zombieWarnings.joined(separator: "\n")
            setKillReport(KillReport(message: msg, isError: true))
        }

        await performScan()
    }
}
