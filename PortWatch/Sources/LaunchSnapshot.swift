import Foundation

/// A captured invocation of a process — everything needed to relaunch it faithfully.
///
/// Captured at kill-time (see `PortMonitor.stopPort`) and persisted via `SnapshotStore`.
/// A snapshot is identified by `(projectKey, port, processName)` so that relaunching the
/// same service replaces the old record instead of piling up duplicates.
struct LaunchSnapshot: Codable, Sendable, Identifiable, Equatable {
    /// Stable project identity across app restarts: the git root path, or `docker:<id>`,
    /// or `known:<serviceName>`, or `other:<processName>`.
    let projectKey: String
    /// User-facing project name ("my-webapp", "Docker: redis", "PostgreSQL", "Other").
    let projectName: String
    let port: UInt16
    let processName: String
    let roleLabel: String?
    let roleIcon: String?
    let cwd: String
    let executablePath: String
    /// argv captured from the running process. `arguments[0]` is the executable name as
    /// the process saw it (often just the basename); `arguments.dropFirst()` is what we
    /// feed to `Process.arguments` (Swift re-injects `executableURL` as argv[0] itself).
    let arguments: [String]
    let environment: [String: String]
    let capturedAt: Date
    /// When non-nil, the process is a docker container and relaunch must go through
    /// `docker start <id>` instead of spawning a binary.
    let dockerContainerID: String?

    /// Stable identifier used as the key in `SnapshotStore` — guarantees that re-killing
    /// the same service overwrites rather than accumulates.
    var id: String { "\(projectKey)::\(port)::\(processName)" }

    /// Short command summary matching the style of `PortEntryDisplay.commandSummary`.
    var commandSummary: String {
        guard !arguments.isEmpty else { return processName }
        let exe = URL(fileURLWithPath: arguments[0]).lastPathComponent
        let rest = arguments.dropFirst().map { arg -> String in
            if arg.hasPrefix("/") && arg.contains("/") {
                return URL(fileURLWithPath: arg).lastPathComponent
            }
            return arg
        }
        return ([exe] + rest).joined(separator: " ")
    }

    /// cwd with ~ substitution, mirroring `PortEntry.shortCwd`.
    var shortCwd: String {
        guard !cwd.isEmpty else { return "" }
        if let home = ProcessInfo.processInfo.environment["HOME"], cwd.hasPrefix(home) {
            return "~" + cwd.dropFirst(home.count)
        }
        return cwd
    }

    /// Human-friendly "5 min ago" / "2 h ago" / "just now".
    var capturedAgo: String {
        let seconds = Int(Date().timeIntervalSince(capturedAt))
        if seconds < 10 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) h ago" }
        let days = hours / 24
        return "\(days) d ago"
    }
}

/// Priority order used when relaunching an entire project: DB first so back-ends can
/// connect on startup, then cache, then back, then front, then anything else.
/// Processes within the same bucket are launched in parallel.
enum RelaunchRole: Int, CaseIterable {
    case db = 0
    case cache = 1
    case back = 2
    case mcp = 3
    case front = 4
    case other = 5

    static func from(roleLabel: String?) -> RelaunchRole {
        switch roleLabel {
        case "DB":    return .db
        case "Cache": return .cache
        case "Back":  return .back
        case "MCP":   return .mcp
        case "Front": return .front
        default:      return .other
        }
    }
}

/// A set of snapshots belonging to the same project, used by the "Recently stopped" section.
struct StoppedProjectGroup: Identifiable, Sendable {
    let projectKey: String
    let projectName: String
    let snapshots: [LaunchSnapshot]

    var id: String { projectKey }
    /// Most recent capture in the group — drives sort order.
    var mostRecentCapture: Date {
        snapshots.map(\.capturedAt).max() ?? .distantPast
    }
}
