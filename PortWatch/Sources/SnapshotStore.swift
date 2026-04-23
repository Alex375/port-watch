import Foundation
import SwiftUI

/// Persists `LaunchSnapshot` records across app restarts so a killed process can be
/// relaunched days later. Backed by `UserDefaults` (JSON-encoded), keyed by snapshot id.
///
/// Snapshots older than `ttlHours` are pruned automatically at init and after each save.
@MainActor
@Observable
final class SnapshotStore {
    static let shared = SnapshotStore()

    /// UserDefaults key for the encoded dictionary `[id: LaunchSnapshot]`.
    private static let storageKey = "launchSnapshots"

    private(set) var snapshots: [String: LaunchSnapshot] = [:]

    /// Exposed for testability — injected when a test wants an isolated defaults suite.
    private let defaults: UserDefaults

    /// TTL in hours — snapshots older than this are pruned. Read from `AppSettings`.
    private var ttlHours: Int {
        AppSettings.shared.snapshotTTLHours
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.snapshots = Self.load(from: defaults)
        prune()
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

    func save(_ snapshot: LaunchSnapshot) {
        snapshots[snapshot.id] = snapshot
        persist()
        prune()
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
        prune(olderThan: ttlHours)
    }

    /// Drop snapshots older than `hours`. No-op if `hours` ≤ 0. Exposed separately so tests
    /// can prune with an explicit TTL without mutating global settings.
    func prune(olderThan hours: Int) {
        guard hours > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        let before = snapshots.count
        snapshots = snapshots.filter { $0.value.capturedAt >= cutoff }
        if snapshots.count != before { persist() }
    }

    // MARK: - Persistence

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshots) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func load(from defaults: UserDefaults) -> [String: LaunchSnapshot] {
        guard let data = defaults.data(forKey: storageKey) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: LaunchSnapshot].self, from: data)) ?? [:]
    }
}
