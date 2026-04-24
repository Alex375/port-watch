import Foundation
import SwiftUI

/// Persisted app settings via UserDefaults.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var cpuThreshold: Double {
        didSet { UserDefaults.standard.set(cpuThreshold, forKey: "cpuThreshold") }
    }
    var ramThresholdMB: Double {
        didSet { UserDefaults.standard.set(ramThresholdMB, forKey: "ramThresholdMB") }
    }
    var refreshInterval: TimeInterval {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval") }
    }
    /// 0 = Off, 1 = Projects only, 2 = All (projects + other)
    var notifyNewPorts: Int {
        didSet { UserDefaults.standard.set(notifyNewPorts, forKey: "notifyNewPorts") }
    }
    var notifyConflicts: Int {
        didSet { UserDefaults.standard.set(notifyConflicts, forKey: "notifyConflicts") }
    }

    /// Whether any notification is enabled.
    var notificationsEnabled: Bool {
        notifyNewPorts > 0 || notifyConflicts > 0
    }

    /// Should notify for a new port given its project status.
    func shouldNotifyNewPort(isProject: Bool) -> Bool {
        if notifyNewPorts == 2 { return true }
        if notifyNewPorts == 1 && isProject { return true }
        return false
    }

    /// Should notify for a conflict given its project status.
    func shouldNotifyConflict(hasProject: Bool) -> Bool {
        if notifyConflicts == 2 { return true }
        if notifyConflicts == 1 && hasProject { return true }
        return false
    }

    // MARK: - Role detection keywords

    var frontKeywords: [String] {
        didSet { UserDefaults.standard.set(frontKeywords, forKey: "frontKeywords") }
    }
    var backKeywords: [String] {
        didSet { UserDefaults.standard.set(backKeywords, forKey: "backKeywords") }
    }
    var dbKeywords: [String] {
        didSet { UserDefaults.standard.set(dbKeywords, forKey: "dbKeywords") }
    }
    var dbProcessNames: [String] {
        didSet { UserDefaults.standard.set(dbProcessNames, forKey: "dbProcessNames") }
    }
    var mcpKeywords: [String] {
        didSet { UserDefaults.standard.set(mcpKeywords, forKey: "mcpKeywords") }
    }
    var claudeKeywords: [String] {
        didSet { UserDefaults.standard.set(claudeKeywords, forKey: "claudeKeywords") }
    }
    /// Process names (case-insensitive exact match) whose LISTEN ports should be
    /// hidden from the UI. Used for tool/IDE internals (Claude, Discord, PyCharm…)
    /// that open loopback servers for IPC but aren't user-facing services.
    var ignoredProcesses: [String] {
        didSet { UserDefaults.standard.set(ignoredProcesses, forKey: "ignoredProcesses") }
    }

    /// How long a "recently stopped" snapshot is kept before being pruned, in minutes.
    /// 0 disables auto-prune (snapshots stay forever until cleared manually).
    var snapshotTTLMinutes: Int {
        didSet { UserDefaults.standard.set(snapshotTTLMinutes, forKey: "snapshotTTLMinutes") }
    }

    // MARK: - Relaunch tuning

    /// How long `PortMonitor.startSnapshot`/`startProject` poll for a restarted port
    /// to reappear before giving up. Mirrors the SIGTERM grace period on the stop path.
    nonisolated static let relaunchVerificationBudget: Duration = .seconds(6)
    /// Interval between port checks during relaunch verification. Short enough to feel
    /// snappy for fast binders (Go/Rust), long enough to avoid hammering libproc for a
    /// slow starter (JVM, Python import chain).
    nonisolated static let relaunchPollInterval: Duration = .milliseconds(200)

    private init() {
        let defaults = UserDefaults.standard

        let defaultFront = ["front", "web", "client", "ui", "vite", "webpack", "next", "nuxt"]
        let defaultBack = ["back", "api", "server", "uvicorn", "gunicorn", "flask", "django", "express", "fastify"]
        let defaultDB = ["db", "database"]
        let defaultDBProc = ["postgres", "mysqld", "mysql", "mongod", "mongos", "redis-server", "redis-sentinel"]
        let defaultMCP = ["mcp-server", "mcp_server", "fastmcp", "modelcontextprotocol"]
        let defaultClaude = ["claude", "claude-code", "@anthropic-ai/claude-code", "anthropic-ai/claude"]
        let defaultIgnored: [String] = []

        // Run the legacy TTL migration BEFORE `register(defaults:)` — the registration
        // domain sits on top of the user domain, so once `snapshotTTLMinutes` has a
        // registered default, `defaults.object(forKey: "snapshotTTLMinutes")` returns
        // the registered value, not nil, and the "never persisted" check below would
        // otherwise be dead (silently losing any legacy `snapshotTTLHours` value).
        Self.migrateLegacyTTLIfNeeded(defaults: defaults)

        defaults.register(defaults: [
            "cpuThreshold": 50.0,
            "ramThresholdMB": 500.0,
            "refreshInterval": 10.0,
            "notifyProjects": false,
            "notifyOther": false,
            "notifyNewPorts": 0,
            "notifyConflicts": 1,
            "frontKeywords": defaultFront,
            "backKeywords": defaultBack,
            "dbKeywords": defaultDB,
            "dbProcessNames": defaultDBProc,
            "mcpKeywords": defaultMCP,
            "claudeKeywords": defaultClaude,
            "ignoredProcesses": defaultIgnored,
            "snapshotTTLMinutes": 60, // 1 hour — use the "Keep forever" toggle for indefinite retention
        ])

        self.cpuThreshold = defaults.double(forKey: "cpuThreshold")
        self.ramThresholdMB = defaults.double(forKey: "ramThresholdMB")
        self.refreshInterval = defaults.double(forKey: "refreshInterval")
        self.notifyNewPorts = defaults.integer(forKey: "notifyNewPorts")
        self.notifyConflicts = defaults.integer(forKey: "notifyConflicts")
        self.frontKeywords = defaults.stringArray(forKey: "frontKeywords") ?? defaultFront
        self.backKeywords = defaults.stringArray(forKey: "backKeywords") ?? defaultBack
        self.dbKeywords = defaults.stringArray(forKey: "dbKeywords") ?? defaultDB
        self.dbProcessNames = defaults.stringArray(forKey: "dbProcessNames") ?? defaultDBProc
        self.mcpKeywords = defaults.stringArray(forKey: "mcpKeywords") ?? defaultMCP
        self.claudeKeywords = defaults.stringArray(forKey: "claudeKeywords") ?? defaultClaude
        self.ignoredProcesses = defaults.stringArray(forKey: "ignoredProcesses") ?? defaultIgnored
        self.snapshotTTLMinutes = defaults.integer(forKey: "snapshotTTLMinutes")
    }

    /// UserDefaults flag set once the legacy TTL migration has run (successfully or not).
    /// A dedicated key is used — rather than "is `snapshotTTLMinutes` persisted?" —
    /// because `register(defaults:)` populates the process-wide *registration domain*
    /// that `object(forKey:)` reads through, so "not persisted" becomes indistinguishable
    /// from "registered default" after any `AppSettings` has been instantiated. The flag
    /// is orthogonal to the registration domain.
    nonisolated static let legacyTTLMigratedKey = "snapshotTTL.migratedFromHours"

    /// One-shot migration from the pre-v2.2 `snapshotTTLHours` key to `snapshotTTLMinutes`.
    /// Idempotent via `legacyTTLMigratedKey`. `nonisolated` because it only touches the
    /// `UserDefaults` passed in — no actor state. Exposed `internal` (not private) so the
    /// unit test suite can exercise it directly.
    nonisolated static func migrateLegacyTTLIfNeeded(defaults: UserDefaults) {
        if defaults.bool(forKey: legacyTTLMigratedKey) { return }
        defaults.set(true, forKey: legacyTTLMigratedKey)

        guard let legacyHours = defaults.object(forKey: "snapshotTTLHours") as? Int else {
            return
        }
        defaults.set(legacyHours * 60, forKey: "snapshotTTLMinutes")
        defaults.removeObject(forKey: "snapshotTTLHours")
    }

    func resetToDefaults() {
        cpuThreshold = 50.0
        ramThresholdMB = 500.0
        refreshInterval = 10.0
        notifyNewPorts = 0
        notifyConflicts = 1
        frontKeywords = ["front", "web", "client", "ui", "vite", "webpack", "next", "nuxt"]
        backKeywords = ["back", "api", "server", "uvicorn", "gunicorn", "flask", "django", "express", "fastify"]
        dbKeywords = ["db", "database"]
        dbProcessNames = ["postgres", "mysqld", "mysql", "mongod", "mongos", "redis-server", "redis-sentinel"]
        mcpKeywords = ["mcp-server", "mcp_server", "fastmcp", "modelcontextprotocol"]
        claudeKeywords = ["claude", "claude-code", "@anthropic-ai/claude-code", "anthropic-ai/claude"]
        ignoredProcesses = []
        snapshotTTLMinutes = 60 // 1 hour — use the "Keep forever" toggle for indefinite retention
    }
}
