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
    var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }
    var notifyPortConflicts: Bool {
        didSet { UserDefaults.standard.set(notifyPortConflicts, forKey: "notifyPortConflicts") }
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

    private init() {
        let defaults = UserDefaults.standard

        let defaultFront = ["front", "web", "client", "ui", "vite", "webpack", "next", "nuxt"]
        let defaultBack = ["back", "api", "server", "uvicorn", "gunicorn", "flask", "django", "express", "fastify"]
        let defaultDB = ["db", "database"]
        let defaultDBProc = ["postgres", "mysqld", "mysql", "mongod", "mongos", "redis-server", "redis-sentinel"]

        // Register defaults
        defaults.register(defaults: [
            "cpuThreshold": 50.0,
            "ramThresholdMB": 500.0,
            "refreshInterval": 10.0,
            "notificationsEnabled": false,
            "notifyPortConflicts": true,
            "frontKeywords": defaultFront,
            "backKeywords": defaultBack,
            "dbKeywords": defaultDB,
            "dbProcessNames": defaultDBProc,
        ])

        self.cpuThreshold = defaults.double(forKey: "cpuThreshold")
        self.ramThresholdMB = defaults.double(forKey: "ramThresholdMB")
        self.refreshInterval = defaults.double(forKey: "refreshInterval")
        self.notificationsEnabled = defaults.bool(forKey: "notificationsEnabled")
        self.notifyPortConflicts = defaults.bool(forKey: "notifyPortConflicts")
        self.frontKeywords = defaults.stringArray(forKey: "frontKeywords") ?? defaultFront
        self.backKeywords = defaults.stringArray(forKey: "backKeywords") ?? defaultBack
        self.dbKeywords = defaults.stringArray(forKey: "dbKeywords") ?? defaultDB
        self.dbProcessNames = defaults.stringArray(forKey: "dbProcessNames") ?? defaultDBProc
    }

    func resetToDefaults() {
        cpuThreshold = 50.0
        ramThresholdMB = 500.0
        refreshInterval = 10.0
        notificationsEnabled = false
        notifyPortConflicts = true
        frontKeywords = ["front", "web", "client", "ui", "vite", "webpack", "next", "nuxt"]
        backKeywords = ["back", "api", "server", "uvicorn", "gunicorn", "flask", "django", "express", "fastify"]
        dbKeywords = ["db", "database"]
        dbProcessNames = ["postgres", "mysqld", "mysql", "mongod", "mongos", "redis-server", "redis-sentinel"]
    }
}
