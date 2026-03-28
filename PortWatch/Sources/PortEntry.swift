import Foundation

/// TCP connection state, mapped from TSI_S_* constants in sys/proc_info.h
enum TCPState: Int32, Sendable {
    case closed      = 0
    case listen      = 1
    case synSent     = 2
    case synReceived = 3
    case established = 4
    case closeWait   = 5
    case finWait1    = 6
    case closing     = 7
    case lastAck     = 8
    case finWait2    = 9
    case timeWait    = 10

    var displayName: String {
        switch self {
        case .closed:      "CLOSED"
        case .listen:      "LISTEN"
        case .synSent:     "SYN_SENT"
        case .synReceived: "SYN_RECV"
        case .established: "ESTABLISHED"
        case .closeWait:   "CLOSE_WAIT"
        case .finWait1:    "FIN_WAIT_1"
        case .closing:     "CLOSING"
        case .lastAck:     "LAST_ACK"
        case .finWait2:    "FIN_WAIT_2"
        case .timeWait:    "TIME_WAIT"
        }
    }

    var isZombie: Bool {
        self == .closeWait || self == .timeWait
    }
}

/// One open TCP port with its owning process info.
struct PortEntry: Identifiable, Sendable {
    let id: String
    let port: UInt16
    let pid: Int32
    let processName: String
    let processPath: String
    let commandLine: String
    let cwd: String
    let tcpState: TCPState
    let processStartTime: Date
    let residentMemoryBytes: UInt64
    let totalCPUTimeNs: UInt64
    let projectName: String

    var uptime: TimeInterval {
        Date().timeIntervalSince(processStartTime)
    }

    var uptimeFormatted: String {
        let seconds = Int(uptime)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)min" }
        let hours = minutes / 60
        let remainingMin = minutes % 60
        return "\(hours)h\(String(format: "%02d", remainingMin))"
    }

    var memoryMB: Double {
        Double(residentMemoryBytes) / (1024 * 1024)
    }

    /// Cwd with ~ substitution.
    var shortCwd: String {
        guard !cwd.isEmpty else { return "" }
        var path = cwd
        if let home = ProcessInfo.processInfo.environment["HOME"], path.hasPrefix(home) {
            path = "~" + path.dropFirst(home.count)
        }
        return path
    }

    /// Last folder name from cwd (e.g. "backend", "frontend").
    var cwdFolder: String {
        guard !cwd.isEmpty else { return "" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// Role label computed at scan time from configurable keywords.
    let roleLabel: String?

    /// SF Symbol for the role.
    let roleIcon: String?

    /// Compute role from keywords. Called at scan time with settings values.
    static func detectRole(
        folder: String, process: String, cmd: String,
        frontKeywords: [String], backKeywords: [String],
        dbKeywords: [String], dbProcessNames: [String]
    ) -> (label: String?, icon: String?) {
        let f = folder.lowercased()
        let p = process.lowercased()
        let c = cmd.lowercased()

        // DB
        if dbProcessNames.contains(p) || dbKeywords.contains(where: { f.contains($0) }) {
            return ("DB", "externaldrive.fill")
        }
        // Front
        if frontKeywords.contains(where: { f.contains($0) || c.contains($0) }) {
            return ("Front", "globe")
        }
        // Back
        if backKeywords.contains(where: { f.contains($0) || c.contains($0) }) {
            return ("Back", "server.rack")
        }
        // Cache
        if ["memcached", "rabbitmq-server"].contains(p) {
            return ("Cache", "bolt.horizontal")
        }
        return (nil, nil)
    }
}

/// CPU usage computed from two scan samples.
struct CPUSample: Sendable {
    let pid: Int32
    let totalCPUTimeNs: UInt64
    let wallTime: Date
}

/// A PortEntry enriched with cross-scan computed data.
struct PortEntryDisplay: Identifiable, Sendable {
    let entry: PortEntry
    let cpuPercent: Double?

    var id: String { entry.id }

    /// Human-readable command summary. Shows the command line if available, otherwise process name.
    var commandSummary: String {
        if !entry.commandLine.isEmpty {
            return entry.commandLine
        }
        return entry.processName
    }
}

/// A group of port entries belonging to the same project.
struct ProjectGroup: Sendable {
    let projectName: String
    let entries: [PortEntryDisplay]
}

/// Result of a kill operation shown to the user.
struct KillReport: Sendable {
    let message: String
    let isError: Bool
}
