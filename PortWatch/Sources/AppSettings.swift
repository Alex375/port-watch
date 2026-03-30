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

    private init() {
        let defaults = UserDefaults.standard

        let defaultFront = ["front", "web", "client", "ui", "vite", "webpack", "next", "nuxt"]
        let defaultBack = ["back", "api", "server", "uvicorn", "gunicorn", "flask", "django", "express", "fastify"]
        let defaultDB = ["db", "database"]
        let defaultDBProc = ["postgres", "mysqld", "mysql", "mongod", "mongos", "redis-server", "redis-sentinel"]
        let defaultMCP = ["mcp-server", "mcp_server", "fastmcp", "modelcontextprotocol"]

        // Register defaults
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
    }
}
