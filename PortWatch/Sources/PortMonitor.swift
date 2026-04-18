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
    var pendingKillConfirmation: PortEntry? = nil

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
        let rawEntries = await Task.detached(priority: .utility) {
            PortScanner.scanAllPorts(keywords: kw)
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

        // Detect port conflicts: multiple PIDs on the same port
        var portPIDs: [UInt16: Set<Int32>] = [:]
        for entry in rawEntries {
            portPIDs[entry.port, default: []].insert(entry.pid)
        }
        let newConflicts = Set(portPIDs.filter { $0.value.count > 1 }.keys)
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

    /// Set the kill report and schedule auto-dismiss after 15 seconds.
    private func setKillReport(_ report: KillReport?) {
        killReportDismissTask?.cancel()
        lastKillReport = report
        guard report != nil else { return }
        killReportDismissTask = Task {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            withAnimation { lastKillReport = nil }
        }
    }

    // MARK: - Kill

    /// Kill a single process and report the result.
    func killPort(_ entry: PortEntry) async {
        setKillReport(nil)
        killingPIDs.insert(entry.pid)

        let result = await Task.detached(priority: .userInitiated) {
            await PortScanner.killProcess(pid: entry.pid, port: entry.port, processName: entry.processName)
        }.value

        killingPIDs.remove(entry.pid)

        if result.success {
            // Final verification: double-check the process is actually dead
            if PortScanner.isAlive(pid: entry.pid) {
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
