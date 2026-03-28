import Foundation

/// Detects the project name associated with a process based on its cwd, or falls back to known port names.
enum ProjectDetector: Sendable {

    /// Well-known ports mapped to their service name.
    private static let knownPorts: [UInt16: String] = [
        5432:  "PostgreSQL",
        3306:  "MySQL",
        6379:  "Redis",
        27017: "MongoDB",
        9200:  "Elasticsearch",
    ]

    // MARK: - Docker

    private nonisolated(unsafe) static var dockerPortMap: [UInt16: String] = [:]

    /// Call once per scan cycle before calling detectProject.
    static func refreshDockerContainers() {
        dockerPortMap = fetchDockerPortMap()
    }

    private static func fetchDockerPortMap() -> [UInt16: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/docker")
        if !FileManager.default.fileExists(atPath: process.executableURL!.path) {
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/docker")
        }
        if !FileManager.default.fileExists(atPath: process.executableURL!.path) {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["docker", "ps", "--format", "json"]
        } else {
            process.arguments = ["ps", "--format", "json"]
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return [:]
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0, !data.isEmpty else { return [:] }

        var portMap: [UInt16: String] = [:]
        let lines = String(data: data, encoding: .utf8)?.components(separatedBy: .newlines) ?? []
        for line in lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            let names = json["Names"] as? String ?? ""
            let image = json["Image"] as? String ?? ""
            let label = names.isEmpty ? image : names
            guard !label.isEmpty else { continue }

            if let ports = json["Ports"] as? String {
                for portSpec in ports.components(separatedBy: ", ") {
                    if let arrowRange = portSpec.range(of: "->") {
                        let hostPart = portSpec[..<arrowRange.lowerBound]
                        if let colonRange = hostPart.range(of: ":", options: .backwards) {
                            let portStr = hostPart[hostPart.index(after: colonRange.lowerBound)...]
                            if let port = UInt16(portStr) {
                                portMap[port] = "Docker: \(label)"
                            }
                        }
                    }
                }
            }
        }

        return portMap
    }

    // MARK: - Public API

    static func detectProject(cwd: String, port: UInt16) -> String {
        // 1. Docker first
        if let dockerName = dockerPortMap[port] {
            return dockerName
        }

        // 2. Git root = project name (primary strategy)
        if !cwd.isEmpty {
            if let name = findGitRootName(from: cwd) {
                return name
            }
        }

        // 3. Known port fallback
        if let known = knownPorts[port] {
            return known
        }

        return "Other"
    }

    // MARK: - Git root detection

    /// Walk up from path to find the nearest .git directory. Returns the folder name containing .git.
    private static func findGitRootName(from path: String) -> String? {
        var current = URL(fileURLWithPath: path)
        let root = URL(fileURLWithPath: "/")

        while current.path != root.path {
            let gitURL = current.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitURL.path) {
                return current.lastPathComponent
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }

        return nil
    }
}
