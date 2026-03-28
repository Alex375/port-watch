import Foundation
import SwiftUI

@MainActor
@Observable
final class PortMonitor {
    var entries: [PortEntryDisplay] = []
    var lastScanDate: Date? = nil

    var portCount: Int { entries.count }

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
            dbProc: settings.dbProcessNames
        )
        let rawEntries = await Task.detached(priority: .utility) {
            PortScanner.scanAllPorts(keywords: kw)
        }.value

        let now = Date()
        var displayEntries: [PortEntryDisplay] = []
        var newSamples: [Int32: CPUSample] = [:]

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
            displayEntries.append(PortEntryDisplay(entry: entry, cpuPercent: cpuPercent))
        }

        // Detect port conflicts: multiple PIDs on the same port
        var portPIDs: [UInt16: Set<Int32>] = [:]
        for entry in rawEntries {
            portPIDs[entry.port, default: []].insert(entry.pid)
        }
        let newConflicts = Set(portPIDs.filter { $0.value.count > 1 }.keys)
        self.conflictPorts = newConflicts

        // Notifications
        if settings.notificationsEnabled {
            let currentPorts = Set(rawEntries.map(\.port))

            // New ports
            if !knownPorts.isEmpty {
                let newPorts = currentPorts.subtracting(knownPorts)
                for port in newPorts {
                    if let entry = rawEntries.first(where: { $0.port == port }) {
                        NotificationManager.shared.notifyNewPort(
                            port: port, processName: entry.processName, projectName: entry.projectName)
                    }
                }
            }

            // New conflicts
            if settings.notifyPortConflicts {
                let freshConflicts = newConflicts.subtracting(previousConflicts)
                for port in freshConflicts {
                    let names = rawEntries.filter { $0.port == port }.map(\.processName)
                    NotificationManager.shared.notifyPortConflict(port: port, processNames: names)
                }
            }

            self.previousConflicts = newConflicts
            self.knownPorts = currentPorts
        }

        self.entries = displayEntries
        self.previousSamples = newSamples
        self.lastScanDate = now
    }

    // MARK: - Kill

    /// Kill a single process and report the result.
    func killPort(_ entry: PortEntry) async {
        lastKillReport = nil
        killingPIDs.insert(entry.pid)

        let result = await Task.detached(priority: .userInitiated) {
            await PortScanner.killProcess(pid: entry.pid, port: entry.port, processName: entry.processName)
        }.value

        killingPIDs.remove(entry.pid)

        if result.success {
            lastKillReport = KillReport(
                message: "Killed \(result.processName) on :\(result.port) (PID \(result.pid))",
                isError: false
            )
        } else {
            lastKillReport = KillReport(
                message: "Failed to kill \(result.processName) on :\(result.port) (PID \(result.pid)): \(result.error ?? "unknown error")",
                isError: true
            )
        }

        await performScan()
    }

    /// Kill all processes in a project group and report results.
    func killProject(_ group: ProjectGroup) async {
        lastKillReport = nil
        var successes = 0
        var failures: [String] = []

        // Deduplicate by PID (multiple ports can belong to same process)
        var seenPIDs = Set<Int32>()
        for display in group.entries {
            guard !seenPIDs.contains(display.entry.pid) else { continue }
            seenPIDs.insert(display.entry.pid)
            killingPIDs.insert(display.entry.pid)

            let result = await Task.detached(priority: .userInitiated) {
                await PortScanner.killProcess(pid: display.entry.pid, port: display.entry.port, processName: display.entry.processName)
            }.value

            killingPIDs.remove(display.entry.pid)

            if result.success {
                successes += 1
            } else {
                failures.append(":\(result.port) \(result.processName) — \(result.error ?? "unknown error")")
            }
        }

        let total = successes + failures.count
        if failures.isEmpty {
            lastKillReport = KillReport(
                message: "\(group.projectName): \(successes) process\(successes == 1 ? "" : "es") killed",
                isError: false
            )
        } else {
            let msg = "\(group.projectName): \(successes)/\(total) killed, \(failures.count) failed\n" + failures.joined(separator: "\n")
            lastKillReport = KillReport(message: msg, isError: true)
        }

        await performScan()
    }
}
