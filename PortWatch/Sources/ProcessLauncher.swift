import Foundation

/// Spawns a subprocess from a `LaunchSnapshot` — used by `PortMonitor.startSnapshot`.
///
/// Two code paths:
/// - **Docker**: `snapshot.dockerContainerID != nil` → run `docker start <id>`. We do **not**
///   spawn the captured binary, because docker containers carry their own network/volume
///   configuration that can't be reproduced from argv alone.
/// - **Native**: spawn `snapshot.executablePath` with the captured `arguments[1...]`, `cwd`,
///   and `environment`. We drop argv[0] because `Process` re-injects `executableURL` as argv[0]
///   itself. stdout/stderr are redirected to `/dev/null` so the child doesn't block on a pipe
///   no one is reading, and so its logs don't bleed into PortWatch's own.
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

        // Detach stdio. We own the parent FDs explicitly so they're closed after `run()`
        // (posix_spawn dup'd them into the child). Leaking these FDs on every relaunch
        // was the pre-fix behaviour — open 3 per restart, exhaust the FD limit over time.
        let nullIn = FileHandle(forReadingAtPath: "/dev/null")
        let nullOut = FileHandle(forWritingAtPath: "/dev/null")
        let nullErr = FileHandle(forWritingAtPath: "/dev/null")
        task.standardInput = nullIn as Any
        task.standardOutput = nullOut as Any
        task.standardError = nullErr as Any

        defer {
            try? nullIn?.close()
            try? nullOut?.close()
            try? nullErr?.close()
        }

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

    /// Build the argv for `docker <verb> <id>`. Exposed for unit testing.
    static func dockerCommand(verb: String, containerID: String) -> (executable: URL, args: [String]) {
        let candidates = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker"]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return (URL(fileURLWithPath: path), [verb, containerID])
        }
        // Fallback: rely on PATH via /usr/bin/env
        return (URL(fileURLWithPath: "/usr/bin/env"), ["docker", verb, containerID])
    }

    /// Build the argv for `docker start <id>`. Kept as a thin wrapper for callers that
    /// only deal with one verb, and so existing tests keep compiling.
    static func dockerStartCommand(containerID: String) -> (executable: URL, args: [String])? {
        dockerCommand(verb: "start", containerID: containerID)
    }

    /// Build the argv for `docker stop <id>`.
    static func dockerStopCommand(containerID: String) -> (executable: URL, args: [String])? {
        dockerCommand(verb: "stop", containerID: containerID)
    }

    private static func startDockerContainer(id: String, processName: String) async -> LaunchResult {
        let cmd = dockerCommand(verb: "start", containerID: id)
        return await runDockerCommand(executable: cmd.executable, args: cmd.args, processName: processName)
    }

    /// Stop a docker container. Invoked from `PortMonitor.stopPort` as the kill step for
    /// container-backed entries (rather than SIGTERM on the daemon process).
    static func stopDockerContainer(id: String, processName: String) async -> LaunchResult {
        let cmd = dockerCommand(verb: "stop", containerID: id)
        return await runDockerCommand(executable: cmd.executable, args: cmd.args, processName: processName)
    }

    private static func runDockerCommand(
        executable: URL, args: [String], processName: String
    ) async -> LaunchResult {
        let task = Process()
        task.executableURL = executable
        task.arguments = args

        // stdout → /dev/null. Previously this was `Pipe()` never read, which would
        // deadlock `waitUntilExit()` if docker ever wrote more than the pipe buffer
        // (64 KB). docker start/stop only prints the container id so it never hit the
        // limit in practice, but the pattern was a latent bug.
        let nullOut = FileHandle(forWritingAtPath: "/dev/null")
        task.standardOutput = nullOut as Any

        // stderr → pipe so we can surface docker's error message in the banner. Drained
        // on a background task concurrent with `waitUntilExit`, so neither can block the
        // other even if docker wrote > 64 KB of stderr.
        let errPipe = Pipe()
        task.standardError = errPipe

        do {
            try task.run()
        } catch {
            try? nullOut?.close()
            return LaunchResult(pid: 0, success: false, error: error.localizedDescription)
        }

        let errReader = errPipe.fileHandleForReading
        async let errData: Data = Task.detached(priority: .userInitiated) {
            errReader.readDataToEndOfFile()
        }.value

        await Task.detached(priority: .userInitiated) {
            task.waitUntilExit()
        }.value

        let collectedErr = await errData
        try? nullOut?.close()

        if task.terminationStatus == 0 {
            return LaunchResult(pid: 0, success: true, error: nil)
        }
        let errMessage = String(data: collectedErr, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "docker exited with status \(task.terminationStatus)"
        return LaunchResult(
            pid: 0, success: false,
            error: "docker \(args.first ?? "") \(processName): \(errMessage)"
        )
    }
}
