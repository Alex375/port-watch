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

    /// Map from exposed host port → container display label ("Docker: <name>").
    private nonisolated(unsafe) static var dockerPortMap: [UInt16: String] = [:]
    /// Map from exposed host port → container id (truncated 12-char form from `docker ps`).
    /// Used to route stop/restart through `docker stop/start <id>` instead of signalling the daemon.
    private nonisolated(unsafe) static var dockerContainerIDMap: [UInt16: String] = [:]

    /// Call once per scan cycle before calling detectProject.
    static func refreshDockerContainers() {
        let result = fetchDockerPortMap()
        dockerPortMap = result.labels
        dockerContainerIDMap = result.ids
    }

    /// Look up the container id for a host port. Returns nil if the port isn't
    /// mapped to a running container.
    static func dockerContainerID(forPort port: UInt16) -> String? {
        dockerContainerIDMap[port]
    }

    private static func fetchDockerPortMap() -> (labels: [UInt16: String], ids: [UInt16: String]) {
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
            return (labels: [:], ids: [:])
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0, !data.isEmpty else { return (labels: [:], ids: [:]) }

        var labels: [UInt16: String] = [:]
        var ids: [UInt16: String] = [:]
        let lines = String(data: data, encoding: .utf8)?.components(separatedBy: .newlines) ?? []
        for line in lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            let names = json["Names"] as? String ?? ""
            let image = json["Image"] as? String ?? ""
            let label = names.isEmpty ? image : names
            let containerID = (json["ID"] as? String) ?? ""
            guard !label.isEmpty else { continue }

            if let ports = json["Ports"] as? String {
                for portSpec in ports.components(separatedBy: ", ") {
                    if let arrowRange = portSpec.range(of: "->") {
                        let hostPart = portSpec[..<arrowRange.lowerBound]
                        if let colonRange = hostPart.range(of: ":", options: .backwards) {
                            let portStr = hostPart[hostPart.index(after: colonRange.lowerBound)...]
                            if let port = UInt16(portStr) {
                                labels[port] = "Docker: \(label)"
                                if !containerID.isEmpty {
                                    ids[port] = containerID
                                }
                            }
                        }
                    }
                }
            }
        }

        return (labels: labels, ids: ids)
    }

    // MARK: - Public API

    /// Detection result — includes a stable `projectKey` that survives app restarts and
    /// disambiguates projects with the same display name (e.g. two "backend" folders).
    struct ProjectInfo: Sendable {
        let name: String
        let worktreeName: String?
        /// Stable identifier. Format: `docker:<id>` / `<git-root-absolute-path>` /
        /// `known:<serviceName>` / `other:<processName>`.
        let key: String
    }

    static func detectProject(cwd: String, port: UInt16, processName: String = "") -> ProjectInfo {
        // 1. Docker first
        if let dockerName = dockerPortMap[port] {
            let id = dockerContainerIDMap[port] ?? dockerName
            return ProjectInfo(name: dockerName, worktreeName: nil, key: "docker:\(id)")
        }

        // 2. Git root = project name (primary strategy)
        if !cwd.isEmpty {
            if let result = findGitRoot(from: cwd) {
                return ProjectInfo(name: result.name, worktreeName: result.worktreeName, key: result.rootPath)
            }
        }

        // 3. Known port fallback
        if let known = knownPorts[port] {
            return ProjectInfo(name: known, worktreeName: nil, key: "known:\(known)")
        }

        let suffix = processName.isEmpty ? "unknown" : processName
        return ProjectInfo(name: "Other", worktreeName: nil, key: "other:\(suffix)")
    }

    // MARK: - Git root detection

    /// Walk up from path to find the nearest .git entry. Returns the repository name, an
    /// optional worktree name, and the absolute root path used as a stable `projectKey`.
    private static func findGitRoot(from path: String) -> (name: String, worktreeName: String?, rootPath: String)? {
        var current = URL(fileURLWithPath: path)
        let root = URL(fileURLWithPath: "/")
        let fm = FileManager.default

        while current.path != root.path {
            let gitURL = current.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: gitURL.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // Normal git repo — project key is the repo's absolute path.
                    return (current.lastPathComponent, nil, current.path)
                } else {
                    // Git worktree: .git is a file containing "gitdir: <path>". We key
                    // each worktree separately so restarting one doesn't collide with
                    // another, but keep the main repo name for display.
                    let wtName = current.lastPathComponent
                    if let mainRepoName = resolveWorktreeMainRepo(gitFile: gitURL) {
                        return (mainRepoName, wtName, current.path)
                    }
                    return (current.lastPathComponent, wtName, current.path)
                }
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }

        return nil
    }

    /// Read a .git file (worktree) and resolve the main repository name.
    /// The file contains something like: `gitdir: /path/to/main-repo/.git/worktrees/worktree-name`
    /// We navigate up from that path to find the main repo's .git directory.
    private static func resolveWorktreeMainRepo(gitFile: URL) -> String? {
        guard let contents = try? String(contentsOf: gitFile, encoding: .utf8) else { return nil }

        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("gitdir:") else { return nil }

        let gitdirPath = trimmed.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard !gitdirPath.isEmpty else { return nil }

        // Resolve the path (it may be relative to the worktree directory)
        let resolvedURL: URL
        if gitdirPath.hasPrefix("/") {
            resolvedURL = URL(fileURLWithPath: gitdirPath)
        } else {
            resolvedURL = gitFile.deletingLastPathComponent()
                .appendingPathComponent(gitdirPath)
                .standardized
        }

        // Walk up from the gitdir path looking for a directory that IS a .git directory.
        // Typical structure: /path/to/main-repo/.git/worktrees/worktree-name
        // We need to find /path/to/main-repo/.git, then return "main-repo".
        var candidate = resolvedURL
        let rootURL = URL(fileURLWithPath: "/")
        while candidate.path != rootURL.path {
            if candidate.lastPathComponent == ".git" {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                    return candidate.deletingLastPathComponent().lastPathComponent
                }
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path { break }
            candidate = parent
        }

        return nil
    }
}
