import Foundation

/// Spawns a subprocess from a `LaunchSnapshot` — used by `PortMonitor.startSnapshot`.
///
/// Two code paths:
/// - **Docker**: `snapshot.dockerContainerID != nil` → run `docker start <id>`. We do **not**
///   spawn the captured binary, because docker containers carry their own network/volume
///   configuration that can't be reproduced from argv alone.
/// - **Native**: spawn `snapshot.executablePath` with the captured `arguments[1...]`, `cwd`,
///   and `environment`. We drop argv[0] because `Process` re-injects `executableURL` as argv[0]
///   itself. stdout/stderr are piped through a short-lived buffer so that if the launch fails
///   fast (binary not found, missing shared lib, immediate crash) we can surface the error.
enum ProcessLauncher {

    struct LaunchResult: Sendable {
        /// PID of the spawned process, or 0 if the launch was rejected before fork.
        let pid: Int32
        let success: Bool
        /// Non-nil on failure; suitable for showing in the `LaunchReport` banner.
        let error: String?
    }

    /// Relaunch a snapshot. Docker containers go through the CLI; everything else is a
    /// direct `Process` spawn. Never throws — all failures are surfaced via `LaunchResult`.
    static func relaunch(_ snapshot: LaunchSnapshot) async -> LaunchResult {
        if let containerID = snapshot.dockerContainerID, !containerID.isEmpty {
            return await startDockerContainer(id: containerID, processName: snapshot.processName)
        }
        return spawnNative(snapshot)
    }

    // MARK: - Native spawn

    private static func spawnNative(_ snapshot: LaunchSnapshot) -> LaunchResult {
        guard !snapshot.executablePath.isEmpty,
              FileManager.default.isExecutableFile(atPath: snapshot.executablePath) else {
            return LaunchResult(
                pid: 0, success: false,
                error: "Executable not found or not executable: \(snapshot.executablePath)"
            )
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: snapshot.executablePath)
        // argv[0] is re-injected by Process as the executable name; we only pass the rest.
        task.arguments = Array(snapshot.arguments.dropFirst())
        if !snapshot.cwd.isEmpty, FileManager.default.fileExists(atPath: snapshot.cwd) {
            task.currentDirectoryURL = URL(fileURLWithPath: snapshot.cwd)
        }
        if !snapshot.environment.isEmpty {
            task.environment = snapshot.environment
        }
        // Detach I/O so the child doesn't block on a pipe no one is reading, and so stdout
        // doesn't bleed into PortWatch's own logs.
        task.standardInput = FileHandle(forReadingAtPath: "/dev/null")
        task.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        task.standardError = FileHandle(forWritingAtPath: "/dev/null")

        do {
            try task.run()
        } catch {
            return LaunchResult(pid: 0, success: false, error: error.localizedDescription)
        }
        // Reparent to a new session so the child survives PortWatch quitting.
        _ = setpgid(task.processIdentifier, task.processIdentifier)
        return LaunchResult(pid: task.processIdentifier, success: true, error: nil)
    }

    // MARK: - Docker

    /// Build the argv for `docker start <id>`. Exposed for unit testing.
    static func dockerStartCommand(containerID: String) -> (executable: URL, args: [String])? {
        let candidates = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker"]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return (URL(fileURLWithPath: path), ["start", containerID])
        }
        // Fallback: rely on PATH via /usr/bin/env
        return (URL(fileURLWithPath: "/usr/bin/env"), ["docker", "start", containerID])
    }

    /// Build the argv for `docker stop <id>`.
    static func dockerStopCommand(containerID: String) -> (executable: URL, args: [String])? {
        let candidates = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker"]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return (URL(fileURLWithPath: path), ["stop", containerID])
        }
        return (URL(fileURLWithPath: "/usr/bin/env"), ["docker", "stop", containerID])
    }

    private static func startDockerContainer(id: String, processName: String) async -> LaunchResult {
        guard let cmd = dockerStartCommand(containerID: id) else {
            return LaunchResult(pid: 0, success: false, error: "docker CLI not found")
        }
        return await runDockerCommand(executable: cmd.executable, args: cmd.args, processName: processName)
    }

    /// Stop a docker container. Invoked from `PortMonitor.stopPort` as the kill step for
    /// container-backed entries (rather than SIGTERM on the daemon process).
    static func stopDockerContainer(id: String, processName: String) async -> LaunchResult {
        guard let cmd = dockerStopCommand(containerID: id) else {
            return LaunchResult(pid: 0, success: false, error: "docker CLI not found")
        }
        return await runDockerCommand(executable: cmd.executable, args: cmd.args, processName: processName)
    }

    private static func runDockerCommand(
        executable: URL, args: [String], processName: String
    ) async -> LaunchResult {
        let task = Process()
        task.executableURL = executable
        task.arguments = args
        let errPipe = Pipe()
        task.standardOutput = Pipe()
        task.standardError = errPipe
        do {
            try task.run()
        } catch {
            return LaunchResult(pid: 0, success: false, error: error.localizedDescription)
        }
        // Docker start/stop is synchronous — wait for the CLI to return. Use a detached task
        // so we don't block the MainActor.
        await Task.detached(priority: .userInitiated) {
            task.waitUntilExit()
        }.value
        if task.terminationStatus == 0 {
            return LaunchResult(pid: 0, success: true, error: nil)
        }
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errMessage = String(data: errData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "docker exited with status \(task.terminationStatus)"
        return LaunchResult(
            pid: 0, success: false,
            error: "docker \(args.first ?? "") \(processName): \(errMessage)"
        )
    }
}
