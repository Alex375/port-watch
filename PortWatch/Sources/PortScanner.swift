import Darwin
import Foundation

/// Low-level wrapper around libproc APIs. Stateless — all methods are static and safe to call from any thread.
enum PortScanner: Sendable {

    // MARK: - PID enumeration

    static func allPIDs() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }

        var pids = [Int32](repeating: 0, count: Int(count) + 64) // small safety margin
        let actualSize = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard actualSize > 0 else { return [] }

        return Array(pids.prefix(Int(actualSize)))
    }

    // MARK: - File descriptors

    static func fileDescriptors(for pid: Int32) -> [proc_fdinfo] {
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return [] }

        let fdInfoSize = MemoryLayout<proc_fdinfo>.stride
        let count = Int(bufferSize) / fdInfoSize
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: count + 16)

        let actualSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * fdInfoSize))
        guard actualSize > 0 else { return [] }

        return Array(fds.prefix(Int(actualSize) / fdInfoSize))
    }

    // MARK: - Socket info

    static func socketInfo(pid: Int32, fd: Int32) -> socket_fdinfo? {
        var info = socket_fdinfo()
        let expectedSize = Int32(MemoryLayout<socket_fdinfo>.size)
        let result = proc_pidfdinfo(pid, fd, PROC_PIDFDSOCKETINFO, &info, expectedSize)
        guard result == expectedSize else { return nil }
        return info
    }

    // MARK: - Process info

    static func processName(pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: Int(4 * MAXCOMLEN))
        let result = proc_name(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else { return "<unknown>" }
        return String(cString: buffer)
    }

    static func processPath(pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let result = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard result > 0 else { return "" }
        return String(cString: buffer)
    }

    static func processCwd(pid: Int32) -> String {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size)
        guard result == size else { return "" }
        return withUnsafePointer(to: info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
    }

    /// Full argv + environment captured from a running process via `KERN_PROCARGS2`.
    /// `summary` is the short human-readable form previously returned by `commandLine()`.
    struct ProcessArgs: Sendable {
        let argv: [String]
        let environment: [String: String]
        let summary: String
    }

    /// Parse the raw buffer returned by `sysctl(KERN_PROCARGS2, …)` into argv + env.
    /// Layout: `[argc: Int32][exec_path\0][null padding][argv[0]\0argv[1]\0…][env[0]\0env[1]\0…]`.
    /// Exposed for unit testing with synthetic buffers.
    static func parseProcArgsBuffer(_ buffer: [UInt8]) -> ProcessArgs {
        let size = buffer.count
        guard size > MemoryLayout<Int32>.size else {
            return ProcessArgs(argv: [], environment: [:], summary: "")
        }
        let argc = buffer.withUnsafeBufferPointer {
            $0.baseAddress!.withMemoryRebound(to: Int32.self, capacity: 1) { $0.pointee }
        }

        var offset = MemoryLayout<Int32>.size
        // Skip exec_path (null-terminated) and any null padding that follows.
        while offset < size && buffer[offset] != 0 { offset += 1 }
        while offset < size && buffer[offset] == 0 { offset += 1 }

        // Read argc argv strings (first token may be whitespace-empty in rare cases — we count
        // every null-delimited token until argc is reached, including empty ones).
        var argv: [String] = []
        var argCount: Int32 = 0
        while offset < size && argCount < argc {
            let start = offset
            while offset < size && buffer[offset] != 0 { offset += 1 }
            let arg = String(bytes: buffer[start..<offset], encoding: .utf8) ?? ""
            argv.append(arg)
            argCount += 1
            offset += 1 // skip null terminator
        }

        // Everything remaining up to the end is the environment block — each entry is
        // "KEY=VALUE" null-terminated. A trailing empty token marks the end.
        var environment: [String: String] = [:]
        while offset < size {
            let start = offset
            while offset < size && buffer[offset] != 0 { offset += 1 }
            if offset == start { offset += 1; continue }
            if let pair = String(bytes: buffer[start..<offset], encoding: .utf8),
               let eq = pair.firstIndex(of: "=") {
                let key = String(pair[..<eq])
                let value = String(pair[pair.index(after: eq)...])
                if !key.isEmpty { environment[key] = value }
            }
            offset += 1
        }

        let summary = Self.buildSummary(argv: argv)
        return ProcessArgs(argv: argv, environment: environment, summary: summary)
    }

    /// Short, human-readable command summary (basename of executable + args, long paths
    /// shortened to basenames). Used by `PortEntry.commandLine` and the UI tooltip.
    private static func buildSummary(argv: [String]) -> String {
        guard !argv.isEmpty else { return "" }
        let exe = URL(fileURLWithPath: argv[0]).lastPathComponent
        let rest = argv.dropFirst().map { arg -> String in
            if arg.hasPrefix("/") && arg.contains("/") {
                return URL(fileURLWithPath: arg).lastPathComponent
            }
            return arg
        }
        return ([exe] + rest).joined(separator: " ")
    }

    /// Fetch argv + env + summary for a live process.
    /// Returns empty `ProcessArgs` if the sysctl call fails (process gone, permissions).
    static func processArgs(pid: Int32) -> ProcessArgs {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else {
            return ProcessArgs(argv: [], environment: [:], summary: "")
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else {
            return ProcessArgs(argv: [], environment: [:], summary: "")
        }
        // sysctl may have written fewer bytes than the initial allocation.
        if size < buffer.count { buffer.removeSubrange(size..<buffer.count) }
        return parseProcArgsBuffer(buffer)
    }

    /// Legacy one-shot accessor — kept so existing callers that only need the summary
    /// string don't have to destructure `ProcessArgs`.
    static func commandLine(pid: Int32) -> String {
        processArgs(pid: pid).summary
    }

    // MARK: - Process lifecycle

    /// Check if a PID is still alive. Returns true if process exists (even if we lack permission to signal it).
    static func isAlive(pid: Int32) -> Bool {
        let result = kill(pid, 0)
        if result == 0 { return true }
        // kill returned -1: check errno immediately
        let savedErrno = errno
        // EPERM = process exists but we don't have permission to signal it
        // ESRCH = no such process
        return savedErrno == EPERM
    }

    /// Result of a kill operation — always reports what happened.
    struct KillResult: Sendable {
        let pid: Int32
        let port: UInt16
        let processName: String
        let success: Bool
        let error: String?
    }

    /// Wait and poll for process death, checking multiple times.
    private static func waitForDeath(pid: Int32, timeout: Duration) async -> Bool {
        let start = ContinuousClock.now
        while ContinuousClock.now - start < timeout {
            if !isAlive(pid: pid) { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return !isAlive(pid: pid)
    }

    /// Kill a process with the strict sequence: SIGTERM → 3s → verify → SIGKILL → verify → error.
    static func killProcess(pid: Int32, port: UInt16, processName: String) async -> KillResult {
        // 1. Check process exists
        guard isAlive(pid: pid) else {
            return KillResult(pid: pid, port: port, processName: processName, success: true, error: nil)
        }

        // 2. SIGTERM
        let termResult = kill(pid, SIGTERM)
        if termResult != 0 {
            let savedErrno = errno
            let err = String(cString: strerror(savedErrno))
            return KillResult(pid: pid, port: port, processName: processName, success: false,
                              error: "SIGTERM failed: \(err) (errno \(savedErrno))")
        }

        // 3. Wait up to 4 seconds, polling every 200ms
        if await waitForDeath(pid: pid, timeout: .seconds(4)) {
            return KillResult(pid: pid, port: port, processName: processName, success: true, error: nil)
        }

        // 4. SIGKILL
        let killResult = kill(pid, SIGKILL)
        if killResult != 0 {
            // Process may have died between check and SIGKILL
            if !isAlive(pid: pid) {
                return KillResult(pid: pid, port: port, processName: processName, success: true, error: nil)
            }
            let savedErrno = errno
            let err = String(cString: strerror(savedErrno))
            return KillResult(pid: pid, port: port, processName: processName, success: false,
                              error: "SIGKILL failed: \(err) (errno \(savedErrno))")
        }

        // 5. Wait up to 2 seconds for SIGKILL
        if await waitForDeath(pid: pid, timeout: .seconds(2)) {
            return KillResult(pid: pid, port: port, processName: processName, success: true, error: nil)
        }

        return KillResult(pid: pid, port: port, processName: processName, success: false,
                          error: "Process still alive after SIGTERM + SIGKILL")
    }

    static func bsdInfo(pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard result == size else { return nil }
        return info
    }

    static func taskInfo(pid: Int32) -> proc_taskinfo? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        guard result == size else { return nil }
        return info
    }

    // MARK: - Mach time conversion

    private static let timebaseInfo: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// Convert Mach absolute time ticks to nanoseconds.
    static func machTicksToNanoseconds(_ ticks: UInt64) -> UInt64 {
        return ticks * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
    }

    // MARK: - Full scan

    struct RoleKeywords: Sendable {
        let front: [String]
        let back: [String]
        let db: [String]
        let dbProc: [String]
        let mcp: [String]
        let claude: [String]
    }

    /// Keep only server-side sockets: every LISTEN entry, plus any CLOSE_WAIT/TIME_WAIT
    /// whose local port is *also* being LISTENed on by the same PID.
    ///
    /// Client-side connection sockets (outbound HTTP, etc.) end up in CLOSE_WAIT/TIME_WAIT
    /// on an ephemeral local port — they are not a server port the user can act on and
    /// would otherwise clutter the UI (e.g. Claude Code's HTTPS connections to anthropic.com
    /// appearing as `:51251` with a spurious "Back" role).
    ///
    /// Assumes `pidEntries` all share the same `pid`. Pure function for unit testing.
    static func filterServerSockets(pidEntries: [PortEntry]) -> [PortEntry] {
        let listenPorts = Set(pidEntries.filter { $0.tcpState == .listen }.map { $0.port })
        return pidEntries.filter { entry in
            if entry.tcpState == .listen { return true }
            return listenPorts.contains(entry.port)
        }
    }

    static func scanAllPorts(keywords: RoleKeywords? = nil) -> [PortEntry] {
        ProjectDetector.refreshDockerContainers()
        let pids = allPIDs()
        var entries: [PortEntry] = []

        // Per-PID cache to avoid redundant syscalls
        var nameCache: [Int32: String] = [:]
        var pathCache: [Int32: String] = [:]
        var argsCache: [Int32: ProcessArgs] = [:]
        var cwdCache: [Int32: String] = [:]
        var projectCache: [UInt64: ProjectDetector.ProjectInfo] = [:]
        var bsdCache: [Int32: proc_bsdinfo?] = [:]
        var taskCache: [Int32: proc_taskinfo?] = [:]

        for pid in pids {
            guard pid > 0 else { continue }

            let fds = fileDescriptors(for: pid)
            if fds.isEmpty { continue }

            // Check if this PID has any TCP sockets before fetching process info
            var hasTCPSocket = false
            for fd in fds {
                if fd.proc_fdtype == PROX_FDTYPE_SOCKET {
                    hasTCPSocket = true
                    break
                }
            }
            guard hasTCPSocket else { continue }

            // Per-PID buffer: we'll filter out orphan CLOSE_WAIT/TIME_WAIT sockets
            // (client-side connection remnants) after scanning all FDs for this PID.
            var pidEntries: [PortEntry] = []

            // Lazy-load process info only for PIDs with sockets
            func getName() -> String {
                if let cached = nameCache[pid] { return cached }
                let name = processName(pid: pid)
                nameCache[pid] = name
                return name
            }

            func getPath() -> String {
                if let cached = pathCache[pid] { return cached }
                let path = processPath(pid: pid)
                pathCache[pid] = path
                return path
            }

            func getArgs() -> ProcessArgs {
                if let cached = argsCache[pid] { return cached }
                let args = processArgs(pid: pid)
                argsCache[pid] = args
                return args
            }

            func getBSD() -> proc_bsdinfo? {
                if let cached = bsdCache[pid] { return cached }
                let info = bsdInfo(pid: pid)
                bsdCache[pid] = info
                return info
            }

            func getCwd() -> String {
                if let cached = cwdCache[pid] { return cached }
                let cwd = processCwd(pid: pid)
                cwdCache[pid] = cwd
                return cwd
            }

            // Cache key combines pid + port because docker containers resolve by port
            // (two ports on the same PID can belong to different containers in theory,
            // though unusual). For git/known/other, the key is pid-dependent only via cwd.
            func getProject(cwd: String, port: UInt16, processName: String) -> ProjectDetector.ProjectInfo {
                let cacheKey = (UInt64(UInt32(bitPattern: pid)) << 16) | UInt64(port)
                if let cached = projectCache[cacheKey] { return cached }
                let result = ProjectDetector.detectProject(cwd: cwd, port: port, processName: processName)
                projectCache[cacheKey] = result
                return result
            }

            func getTask() -> proc_taskinfo? {
                if let cached = taskCache[pid] { return cached }
                let info = taskInfo(pid: pid)
                taskCache[pid] = info
                return info
            }

            for fd in fds {
                guard fd.proc_fdtype == PROX_FDTYPE_SOCKET else { continue }

                guard let sockInfo = socketInfo(pid: pid, fd: fd.proc_fd) else { continue }

                let psi = sockInfo.psi

                // Only TCP sockets
                guard psi.soi_kind == 2 else { continue } // SOCKINFO_TCP

                // Only IPv4 or IPv6
                guard psi.soi_family == AF_INET || psi.soi_family == AF_INET6 else { continue }

                let tcpInfo = psi.soi_proto.pri_tcp
                let localPort = UInt16(bigEndian: UInt16(truncatingIfNeeded: tcpInfo.tcpsi_ini.insi_lport))

                guard localPort > 0 else { continue }

                let stateRaw = tcpInfo.tcpsi_state
                let tcpState = TCPState(rawValue: stateRaw) ?? .closed

                // Only keep LISTEN ports (servers) + zombie states
                guard tcpState == .listen || tcpState == .closeWait || tcpState == .timeWait else { continue }

                let bsd = getBSD()
                let startTime: Date
                if let bsd, bsd.pbi_start_tvsec > 0 {
                    startTime = Date(timeIntervalSince1970: TimeInterval(bsd.pbi_start_tvsec))
                } else {
                    startTime = Date()
                }
                let ppid = bsd.map { Int32($0.pbi_ppid) } ?? 0

                let task = getTask()
                let residentMem = task.map { UInt64($0.pti_resident_size) } ?? 0
                let cpuTimeNs: UInt64
                if let task {
                    let userNs = machTicksToNanoseconds(task.pti_total_user)
                    let sysNs = machTicksToNanoseconds(task.pti_total_system)
                    cpuTimeNs = userNs + sysNs
                } else {
                    cpuTimeNs = 0
                }

                let cwd = getCwd()
                let name = getName()
                let project = getProject(cwd: cwd, port: localPort, processName: name)
                let args = getArgs()

                let folder = cwd.isEmpty ? "" : URL(fileURLWithPath: cwd).lastPathComponent
                let role: (label: String?, icon: String?)
                if let kw = keywords {
                    role = PortEntry.detectRole(
                        folder: folder, process: name, cmd: args.summary,
                        frontKeywords: kw.front, backKeywords: kw.back,
                        dbKeywords: kw.db, dbProcessNames: kw.dbProc,
                        mcpKeywords: kw.mcp,
                        claudeKeywords: kw.claude)
                } else {
                    role = (nil, nil)
                }

                let entry = PortEntry(
                    id: "\(localPort)-\(pid)-\(fd.proc_fd)",
                    port: localPort,
                    pid: pid,
                    ppid: ppid,
                    processName: name,
                    processPath: getPath(),
                    commandLine: args.summary,
                    arguments: args.argv,
                    environment: args.environment,
                    cwd: cwd,
                    tcpState: tcpState,
                    processStartTime: startTime,
                    residentMemoryBytes: residentMem,
                    totalCPUTimeNs: cpuTimeNs,
                    projectName: project.name,
                    worktreeName: project.worktreeName,
                    projectKey: project.key,
                    dockerContainerID: ProjectDetector.dockerContainerID(forPort: localPort),
                    roleLabel: role.label,
                    roleIcon: role.icon
                )
                pidEntries.append(entry)
            }

            // Filter: keep LISTEN entries + CLOSE_WAIT/TIME_WAIT whose port matches a LISTEN
            // on this same PID. Orphan zombie sockets (client-side outbound connections) are dropped.
            entries.append(contentsOf: filterServerSockets(pidEntries: pidEntries))
        }

        // Deduplicate by (port, pid) — same process can listen on IPv4 + IPv6
        var seen = Set<String>()
        let unique = entries.filter { entry in
            let key = "\(entry.port)-\(entry.pid)"
            return seen.insert(key).inserted
        }

        return unique.sorted { $0.port < $1.port }
    }
}
