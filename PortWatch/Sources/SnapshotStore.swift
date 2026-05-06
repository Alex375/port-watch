import Foundation
import OSLog
import SwiftUI

/// Persists `LaunchSnapshot` records across app restarts so a killed process can be
/// relaunched days later. Backed by `UserDefaults` (JSON-encoded), keyed by snapshot id.
///
/// Snapshots older than `ttlMinutes` are pruned automatically at init and after each save.
@MainActor
@Observable
final class SnapshotStore {
    static let shared = SnapshotStore()

    /// UserDefaults key for the encoded dictionary `[id: LaunchSnapshot]`.
    private static let storageKey = "launchSnapshots"
    /// Key under which a corrupted payload is preserved before being wiped. Gives us
    /// (and/or the user) a fighting chance to recover the data after a shape change.
    private static let corruptBackupKey = "launchSnapshots.corruptBackup"

    private static let log = Logger(subsystem: "com.portwatch", category: "SnapshotStore")

    private(set) var snapshots: [String: LaunchSnapshot] = [:]

    /// Exposed for testability — injected when a test wants an isolated defaults suite.
    private let defaults: UserDefaults

    /// TTL in minutes — snapshots older than this are pruned. Read from `AppSettings`.
    private var ttlMinutes: Int {
        AppSettings.shared.snapshotTTLMinutes
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.snapshots = Self.load(from: defaults)
        // Initial prune — persist only if we actually dropped anything.
        let before = snapshots.count
        removeExpired(minutes: ttlMinutes)
        if snapshots.count != before { persist() }
    }

    var isEmpty: Bool { snapshots.isEmpty }

    /// All snapshots for a given project key.
    func all(for projectKey: String) -> [LaunchSnapshot] {
        snapshots.values.filter { $0.projectKey == projectKey }
    }

    /// Grouped by project, sorted by most recent capture first. Within a group, entries
    /// are sorted by role (DB first) then port, so the UI presents a predictable order.
    func groupedByProject() -> [StoppedProjectGroup] {
        let byProject = Dictionary(grouping: snapshots.values) { $0.projectKey }
        return byProject.map { (key, snaps) in
            let sorted = snaps.sorted { lhs, rhs in
                let lr = RelaunchRole.from(roleLabel: lhs.roleLabel).rawValue
                let rr = RelaunchRole.from(roleLabel: rhs.roleLabel).rawValue
                if lr != rr { return lr < rr }
                return lhs.port < rhs.port
            }
            let projectName = sorted.first?.projectName ?? key
            return StoppedProjectGroup(projectKey: key, projectName: projectName, snapshots: sorted)
        }
        .sorted { $0.mostRecentCapture > $1.mostRecentCapture }
    }

    /// Save a snapshot, prune expired entries, persist once.
    ///
    /// Previously `save` called `persist()` then `prune()` which could `persist()` a
    /// second time — two JSON encodes + two UserDefaults writes per save. A `stopProject`
    /// stopping 10 rows rewrote the whole dictionary 20 times. Now it writes once.
    ///
    /// When `AppSettings.historyEnabled` is `false`, this becomes a no-op: nothing is
    /// kept in memory and nothing transits via UserDefaults. The other mutators
    /// (`remove`, `clearAll`, `prune`) stay live so an ON → OFF transition can still
    /// drain whatever was saved while history was on.
    func save(_ snapshot: LaunchSnapshot) {
        guard AppSettings.shared.historyEnabled else { return }
        snapshots[snapshot.id] = snapshot
        removeExpired(minutes: ttlMinutes)
        persist()
    }

    func remove(id: String) {
        guard snapshots.removeValue(forKey: id) != nil else { return }
        persist()
    }

    func remove(projectKey: String) {
        let before = snapshots.count
        snapshots = snapshots.filter { $0.value.projectKey != projectKey }
        if snapshots.count != before { persist() }
    }

    func clearAll() {
        guard !snapshots.isEmpty else { return }
        snapshots = [:]
        persist()
    }

    /// Drop snapshots older than the current TTL. No-op if TTL ≤ 0.
    func prune() {
        let before = snapshots.count
        removeExpired(minutes: ttlMinutes)
        if snapshots.count != before { persist() }
    }

    /// Drop snapshots older than `minutes`. No-op if `minutes` ≤ 0. Exposed separately so
    /// tests can prune with an explicit TTL without mutating global settings.
    func pruneMinutes(olderThan minutes: Int) {
        let before = snapshots.count
        removeExpired(minutes: minutes)
        if snapshots.count != before { persist() }
    }

    /// In-memory prune only. Caller is responsible for `persist()`.
    private func removeExpired(minutes: Int) {
        guard minutes > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(minutes) * 60)
        snapshots = snapshots.filter { $0.value.capturedAt >= cutoff }
    }

    // MARK: - Persistence

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(snapshots)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            // Encoding failure is improbable (LaunchSnapshot is a plain struct of
            // Codable primitives) but not impossible — e.g. invalid UTF-8 that slipped
            // through KERN_PROCARGS2 parsing. Surfacing via os_log keeps us aligned
            // with "zero silent errors" without a disruptive UI banner on a write path
            // the user didn't directly trigger.
            Self.log.error("Failed to encode snapshots: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from defaults: UserDefaults) -> [String: LaunchSnapshot] {
        guard let data = defaults.data(forKey: storageKey) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([String: LaunchSnapshot].self, from: data)
        } catch {
            // Shape drift or corruption. Preserve the original blob under a backup key
            // so it isn't silently wiped on the next `persist()` — the user can check
            // prefs or we can recover manually. Then start fresh.
            Self.log.error("Failed to decode snapshots (\(error.localizedDescription, privacy: .public)); backing up corrupt payload")
            defaults.set(data, forKey: corruptBackupKey)
            defaults.removeObject(forKey: storageKey)
            return [:]
        }
    }
}
