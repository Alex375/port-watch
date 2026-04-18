import XCTest
@testable import PortWatch

// MARK: - TCPState Tests

final class TCPStateTests: XCTestCase {

    func testDisplayNameForAllCases() {
        XCTAssertEqual(TCPState.closed.displayName, "CLOSED")
        XCTAssertEqual(TCPState.listen.displayName, "LISTEN")
        XCTAssertEqual(TCPState.synSent.displayName, "SYN_SENT")
        XCTAssertEqual(TCPState.synReceived.displayName, "SYN_RECV")
        XCTAssertEqual(TCPState.established.displayName, "ESTABLISHED")
        XCTAssertEqual(TCPState.closeWait.displayName, "CLOSE_WAIT")
        XCTAssertEqual(TCPState.finWait1.displayName, "FIN_WAIT_1")
        XCTAssertEqual(TCPState.closing.displayName, "CLOSING")
        XCTAssertEqual(TCPState.lastAck.displayName, "LAST_ACK")
        XCTAssertEqual(TCPState.finWait2.displayName, "FIN_WAIT_2")
        XCTAssertEqual(TCPState.timeWait.displayName, "TIME_WAIT")
    }

    func testIsZombieTrueForCloseWait() {
        XCTAssertTrue(TCPState.closeWait.isZombie)
    }

    func testIsZombieTrueForTimeWait() {
        XCTAssertTrue(TCPState.timeWait.isZombie)
    }

    func testIsZombieFalseForNonZombieStates() {
        let nonZombie: [TCPState] = [
            .closed, .listen, .synSent, .synReceived,
            .established, .finWait1, .closing, .lastAck, .finWait2
        ]
        for state in nonZombie {
            XCTAssertFalse(state.isZombie, "\(state.displayName) should not be zombie")
        }
    }

    func testRawValues() {
        XCTAssertEqual(TCPState.closed.rawValue, 0)
        XCTAssertEqual(TCPState.listen.rawValue, 1)
        XCTAssertEqual(TCPState.synSent.rawValue, 2)
        XCTAssertEqual(TCPState.synReceived.rawValue, 3)
        XCTAssertEqual(TCPState.established.rawValue, 4)
        XCTAssertEqual(TCPState.closeWait.rawValue, 5)
        XCTAssertEqual(TCPState.finWait1.rawValue, 6)
        XCTAssertEqual(TCPState.closing.rawValue, 7)
        XCTAssertEqual(TCPState.lastAck.rawValue, 8)
        XCTAssertEqual(TCPState.finWait2.rawValue, 9)
        XCTAssertEqual(TCPState.timeWait.rawValue, 10)
    }

    func testInitFromRawValue() {
        XCTAssertEqual(TCPState(rawValue: 1), .listen)
        XCTAssertEqual(TCPState(rawValue: 4), .established)
        XCTAssertNil(TCPState(rawValue: 99))
    }
}

// MARK: - PortEntry Tests

final class PortEntryTests: XCTestCase {

    private func makeEntry(
        port: UInt16 = 8080,
        pid: Int32 = 1234,
        processName: String = "node",
        processPath: String = "/usr/bin/node",
        commandLine: String = "node server.js",
        cwd: String = "/Users/test/project",
        tcpState: TCPState = .listen,
        processStartTime: Date = Date(),
        residentMemoryBytes: UInt64 = 0,
        totalCPUTimeNs: UInt64 = 0,
        projectName: String = "TestProject",
        worktreeName: String? = nil,
        roleLabel: String? = nil,
        roleIcon: String? = nil
    ) -> PortEntry {
        PortEntry(
            id: "\(port)-\(pid)-0",
            port: port,
            pid: pid,
            processName: processName,
            processPath: processPath,
            commandLine: commandLine,
            cwd: cwd,
            tcpState: tcpState,
            processStartTime: processStartTime,
            residentMemoryBytes: residentMemoryBytes,
            totalCPUTimeNs: totalCPUTimeNs,
            projectName: projectName,
            worktreeName: worktreeName,
            roleLabel: roleLabel,
            roleIcon: roleIcon
        )
    }

    // MARK: uptimeFormatted

    func testUptimeFormattedSeconds() {
        let entry = makeEntry(processStartTime: Date().addingTimeInterval(-30))
        let formatted = entry.uptimeFormatted
        // Should be around "30s" (could be 29s or 30s depending on timing)
        XCTAssertTrue(formatted.hasSuffix("s"), "Expected seconds format, got: \(formatted)")
        XCTAssertFalse(formatted.contains("min"), "Should not contain 'min' for <60s")
        XCTAssertFalse(formatted.contains("h"), "Should not contain 'h' for <60s")
    }

    func testUptimeFormattedMinutes() {
        let entry = makeEntry(processStartTime: Date().addingTimeInterval(-300)) // 5 min
        let formatted = entry.uptimeFormatted
        XCTAssertTrue(formatted.hasSuffix("min"), "Expected minutes format, got: \(formatted)")
        // Should be "5min"
        XCTAssertTrue(formatted.contains("5"), "Expected ~5 minutes, got: \(formatted)")
    }

    func testUptimeFormattedHours() {
        let entry = makeEntry(processStartTime: Date().addingTimeInterval(-7500)) // 2h05
        let formatted = entry.uptimeFormatted
        XCTAssertTrue(formatted.contains("h"), "Expected hours format, got: \(formatted)")
        XCTAssertEqual(formatted, "2h05")
    }

    func testUptimeFormattedExactlyOneHour() {
        let entry = makeEntry(processStartTime: Date().addingTimeInterval(-3600)) // 1h00
        let formatted = entry.uptimeFormatted
        XCTAssertEqual(formatted, "1h00")
    }

    func testUptimeFormattedHoursWithMinutes() {
        let entry = makeEntry(processStartTime: Date().addingTimeInterval(-5400)) // 1h30
        let formatted = entry.uptimeFormatted
        XCTAssertEqual(formatted, "1h30")
    }

    // MARK: memoryMB

    func testMemoryMBZero() {
        let entry = makeEntry(residentMemoryBytes: 0)
        XCTAssertEqual(entry.memoryMB, 0.0, accuracy: 0.001)
    }

    func testMemoryMBExactlyOneMB() {
        let entry = makeEntry(residentMemoryBytes: 1024 * 1024)
        XCTAssertEqual(entry.memoryMB, 1.0, accuracy: 0.001)
    }

    func testMemoryMB500MB() {
        let entry = makeEntry(residentMemoryBytes: 500 * 1024 * 1024)
        XCTAssertEqual(entry.memoryMB, 500.0, accuracy: 0.001)
    }

    func testMemoryMBFractional() {
        let entry = makeEntry(residentMemoryBytes: 1536 * 1024) // 1.5 MB
        XCTAssertEqual(entry.memoryMB, 1.5, accuracy: 0.001)
    }

    // MARK: shortCwd

    func testShortCwdWithHomePrefix() {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/test"
        let entry = makeEntry(cwd: "\(home)/Projects/myapp")
        XCTAssertEqual(entry.shortCwd, "~/Projects/myapp")
    }

    func testShortCwdWithoutHomePrefix() {
        let entry = makeEntry(cwd: "/opt/homebrew/bin")
        XCTAssertEqual(entry.shortCwd, "/opt/homebrew/bin")
    }

    func testShortCwdEmpty() {
        let entry = makeEntry(cwd: "")
        XCTAssertEqual(entry.shortCwd, "")
    }

    func testShortCwdHomeItself() {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/test"
        let entry = makeEntry(cwd: home)
        XCTAssertEqual(entry.shortCwd, "~")
    }

    // MARK: cwdFolder

    func testCwdFolder() {
        let entry = makeEntry(cwd: "/Users/test/Projects/backend")
        XCTAssertEqual(entry.cwdFolder, "backend")
    }

    func testCwdFolderEmpty() {
        let entry = makeEntry(cwd: "")
        XCTAssertEqual(entry.cwdFolder, "")
    }

    func testCwdFolderRoot() {
        let entry = makeEntry(cwd: "/")
        XCTAssertEqual(entry.cwdFolder, "/")
    }

    // MARK: detectRole

    func testDetectRoleFrontByFolder() {
        let result = PortEntry.detectRole(
            folder: "frontend", process: "node", cmd: "node server.js",
            frontKeywords: ["front"], backKeywords: ["back"],
            dbKeywords: ["db"], dbProcessNames: ["postgres"]
        )
        XCTAssertEqual(result.label, "Front")
        XCTAssertEqual(result.icon, "globe")
    }

    func testDetectRoleFrontByCmd() {
        let result = PortEntry.detectRole(
            folder: "myproject", process: "node", cmd: "vite serve",
            frontKeywords: ["front", "vite"], backKeywords: ["back"],
            dbKeywords: ["db"], dbProcessNames: ["postgres"]
        )
        XCTAssertEqual(result.label, "Front")
        XCTAssertEqual(result.icon, "globe")
    }

    func testDetectRoleBackByFolder() {
        let result = PortEntry.detectRole(
            folder: "backend", process: "python", cmd: "python manage.py",
            frontKeywords: ["front"], backKeywords: ["back"],
            dbKeywords: ["db"], dbProcessNames: ["postgres"]
        )
        XCTAssertEqual(result.label, "Back")
        XCTAssertEqual(result.icon, "server.rack")
    }

    func testDetectRoleBackByCmd() {
        let result = PortEntry.detectRole(
            folder: "myproject", process: "python", cmd: "uvicorn main:app",
            frontKeywords: ["front"], backKeywords: ["back", "uvicorn"],
            dbKeywords: ["db"], dbProcessNames: ["postgres"]
        )
        XCTAssertEqual(result.label, "Back")
        XCTAssertEqual(result.icon, "server.rack")
    }

    func testDetectRoleDBByProcessName() {
        let result = PortEntry.detectRole(
            folder: "data", process: "postgres", cmd: "postgres -D /var",
            frontKeywords: ["front"], backKeywords: ["back"],
            dbKeywords: ["db"], dbProcessNames: ["postgres"]
        )
        XCTAssertEqual(result.label, "DB")
        XCTAssertEqual(result.icon, "externaldrive.fill")
    }

    func testDetectRoleDBByFolderKeyword() {
        let result = PortEntry.detectRole(
            folder: "database", process: "node", cmd: "node migrate.js",
            frontKeywords: ["front"], backKeywords: ["back"],
            dbKeywords: ["db", "database"], dbProcessNames: ["postgres"]
        )
        XCTAssertEqual(result.label, "DB")
        XCTAssertEqual(result.icon, "externaldrive.fill")
    }

    func testDetectRoleCacheMemcached() {
        let result = PortEntry.detectRole(
            folder: "cache", process: "memcached", cmd: "memcached -p 11211",
            frontKeywords: ["front"], backKeywords: ["back"],
            dbKeywords: ["db"], dbProcessNames: ["postgres"]
        )
        XCTAssertEqual(result.label, "Cache")
        XCTAssertEqual(result.icon, "bolt.horizontal")
    }

    func testDetectRoleCacheRabbitmq() {
        let result = PortEntry.detectRole(
            folder: "mq", process: "rabbitmq-server", cmd: "rabbitmq-server",
            frontKeywords: ["front"], backKeywords: ["back"],
            dbKeywords: ["db"], dbProcessNames: ["postgres"]
        )
        XCTAssertEqual(result.label, "Cache")
        XCTAssertEqual(result.icon, "bolt.horizontal")
    }

    func testDetectRoleNilForUnknown() {
        let result = PortEntry.detectRole(
            folder: "randomthing", process: "someprocess", cmd: "someprocess --arg",
            frontKeywords: ["front"], backKeywords: ["back"],
            dbKeywords: ["db"], dbProcessNames: ["postgres"]
        )
        XCTAssertNil(result.label)
        XCTAssertNil(result.icon)
    }

    func testDetectRoleCaseInsensitive() {
        let result = PortEntry.detectRole(
            folder: "FRONTEND", process: "NODE", cmd: "NODE server.js",
            frontKeywords: ["front"], backKeywords: ["back"],
            dbKeywords: ["db"], dbProcessNames: ["postgres"]
        )
        XCTAssertEqual(result.label, "Front")
    }

    func testDetectRoleDBTakesPriorityOverFront() {
        // If a process name matches DB, it should be DB even if folder matches front
        let result = PortEntry.detectRole(
            folder: "frontend", process: "postgres", cmd: "postgres",
            frontKeywords: ["front"], backKeywords: ["back"],
            dbKeywords: ["db"], dbProcessNames: ["postgres"]
        )
        XCTAssertEqual(result.label, "DB")
    }

    func testDetectRoleMCPByProcessName() {
        let result = PortEntry.detectRole(
            folder: "project", process: "mcp-server-github", cmd: "mcp-server-github",
            frontKeywords: ["front"], backKeywords: ["back"],
            dbKeywords: ["db"], dbProcessNames: ["postgres"],
            mcpKeywords: ["mcp-server", "mcp_server", "fastmcp", "modelcontextprotocol"]
        )
        XCTAssertEqual(result.label, "MCP")
        XCTAssertEqual(result.icon, "cpu")
    }

    func testDetectRoleMCPByCmd() {
        let result = PortEntry.detectRole(
            folder: "project", process: "node", cmd: "node /path/to/@modelcontextprotocol/server",
            frontKeywords: ["front"], backKeywords: ["back"],
            dbKeywords: ["db"], dbProcessNames: ["postgres"],
            mcpKeywords: ["mcp-server", "mcp_server", "fastmcp", "modelcontextprotocol"]
        )
        XCTAssertEqual(result.label, "MCP")
        XCTAssertEqual(result.icon, "cpu")
    }

    func testDetectRoleMCPFastmcp() {
        let result = PortEntry.detectRole(
            folder: "tools", process: "python", cmd: "python -m fastmcp run server.py",
            frontKeywords: ["front"], backKeywords: ["back"],
            dbKeywords: ["db"], dbProcessNames: ["postgres"],
            mcpKeywords: ["mcp-server", "mcp_server", "fastmcp", "modelcontextprotocol"]
        )
        XCTAssertEqual(result.label, "MCP")
    }

    func testDetectRoleDBTakesPriorityOverMCP() {
        // DB process names should still win over MCP keywords
        let result = PortEntry.detectRole(
            folder: "mcp-server", process: "postgres", cmd: "postgres",
            frontKeywords: ["front"], backKeywords: ["back"],
            dbKeywords: ["db"], dbProcessNames: ["postgres"],
            mcpKeywords: ["mcp-server"]
        )
        XCTAssertEqual(result.label, "DB")
    }

    func testDetectRoleMCPByFolder() {
        // MCP keyword in folder should match, even if cmd contains "server" (back keyword)
        let result = PortEntry.detectRole(
            folder: "mcp-server-github", process: "node", cmd: "node index.js",
            frontKeywords: ["front"], backKeywords: ["server"],
            dbKeywords: ["db"], dbProcessNames: ["postgres"],
            mcpKeywords: ["mcp-server"]
        )
        XCTAssertEqual(result.label, "MCP")
        XCTAssertEqual(result.icon, "cpu")
    }

    func testDetectRoleMCPFolderWinsOverBack() {
        // Folder contains "mcp_server" and cmd contains "server" — MCP should win
        let result = PortEntry.detectRole(
            folder: "mcp_server_tools", process: "python", cmd: "python server.py",
            frontKeywords: ["front"], backKeywords: ["server"],
            dbKeywords: ["db"], dbProcessNames: ["postgres"],
            mcpKeywords: ["mcp_server"]
        )
        XCTAssertEqual(result.label, "MCP")
    }

    func testDetectRoleMCPTakesPriorityOverBack() {
        // MCP keyword in cmd should win over back keyword in cmd
        let result = PortEntry.detectRole(
            folder: "project", process: "node", cmd: "node mcp-server --api",
            frontKeywords: ["front"], backKeywords: ["api"],
            dbKeywords: ["db"], dbProcessNames: ["postgres"],
            mcpKeywords: ["mcp-server"]
        )
        XCTAssertEqual(result.label, "MCP")
    }

    // MARK: worktreeName

    func testWorktreeNameNilByDefault() {
        let entry = makeEntry()
        XCTAssertNil(entry.worktreeName)
    }

    func testWorktreeNameStored() {
        let entry = makeEntry(worktreeName: "agent-abc123")
        XCTAssertEqual(entry.worktreeName, "agent-abc123")
    }

    // MARK: id and identity

    func testEntryId() {
        let entry = makeEntry(port: 3000, pid: 42)
        XCTAssertEqual(entry.id, "3000-42-0")
    }
}

// MARK: - PortEntryDisplay Tests

final class PortEntryDisplayTests: XCTestCase {

    private func makeEntry(
        commandLine: String = "",
        processName: String = "node"
    ) -> PortEntry {
        PortEntry(
            id: "8080-1-0",
            port: 8080,
            pid: 1,
            processName: processName,
            processPath: "/usr/bin/node",
            commandLine: commandLine,
            cwd: "/tmp",
            tcpState: .listen,
            processStartTime: Date(),
            residentMemoryBytes: 0,
            totalCPUTimeNs: 0,
            projectName: "Test",
            worktreeName: nil,
            roleLabel: nil,
            roleIcon: nil
        )
    }

    func testCommandSummaryWithCommandLine() {
        let entry = makeEntry(commandLine: "node server.js --port 3000", processName: "node")
        let display = PortEntryDisplay(entry: entry, cpuPercent: nil)
        XCTAssertEqual(display.commandSummary, "node server.js --port 3000")
    }

    func testCommandSummaryFallsBackToProcessName() {
        let entry = makeEntry(commandLine: "", processName: "nginx")
        let display = PortEntryDisplay(entry: entry, cpuPercent: nil)
        XCTAssertEqual(display.commandSummary, "nginx")
    }

    func testDisplayIdMatchesEntryId() {
        let entry = makeEntry()
        let display = PortEntryDisplay(entry: entry, cpuPercent: 12.5)
        XCTAssertEqual(display.id, entry.id)
    }

    func testCpuPercentIsStored() {
        let entry = makeEntry()
        let display = PortEntryDisplay(entry: entry, cpuPercent: 42.5)
        XCTAssertEqual(display.cpuPercent, 42.5)
    }

    func testCpuPercentNil() {
        let entry = makeEntry()
        let display = PortEntryDisplay(entry: entry, cpuPercent: nil)
        XCTAssertNil(display.cpuPercent)
    }
}

// MARK: - ProjectGroup Tests

final class ProjectGroupTests: XCTestCase {

    func testProjectGroupProperties() {
        let entry = PortEntry(
            id: "3000-1-0",
            port: 3000,
            pid: 1,
            processName: "node",
            processPath: "/usr/bin/node",
            commandLine: "node index.js",
            cwd: "/tmp",
            tcpState: .listen,
            processStartTime: Date(),
            residentMemoryBytes: 0,
            totalCPUTimeNs: 0,
            projectName: "MyApp",
            worktreeName: nil,
            roleLabel: nil,
            roleIcon: nil
        )
        let display = PortEntryDisplay(entry: entry, cpuPercent: nil)
        let group = ProjectGroup(projectName: "MyApp", entries: [display])

        XCTAssertEqual(group.projectName, "MyApp")
        XCTAssertEqual(group.entries.count, 1)
        XCTAssertEqual(group.entries.first?.entry.port, 3000)
    }

    func testProjectGroupMultipleEntries() {
        let entry1 = PortEntry(
            id: "3000-1-0", port: 3000, pid: 1,
            processName: "node", processPath: "", commandLine: "", cwd: "",
            tcpState: .listen, processStartTime: Date(),
            residentMemoryBytes: 0, totalCPUTimeNs: 0,
            projectName: "MyApp", worktreeName: nil, roleLabel: nil, roleIcon: nil
        )
        let entry2 = PortEntry(
            id: "3001-2-0", port: 3001, pid: 2,
            processName: "python", processPath: "", commandLine: "", cwd: "",
            tcpState: .listen, processStartTime: Date(),
            residentMemoryBytes: 0, totalCPUTimeNs: 0,
            projectName: "MyApp", worktreeName: nil, roleLabel: nil, roleIcon: nil
        )
        let displays = [
            PortEntryDisplay(entry: entry1, cpuPercent: nil),
            PortEntryDisplay(entry: entry2, cpuPercent: nil),
        ]
        let group = ProjectGroup(projectName: "MyApp", entries: displays)
        XCTAssertEqual(group.entries.count, 2)
    }
}

// MARK: - KillReport Tests

final class KillReportTests: XCTestCase {

    func testKillReportSuccess() {
        let report = KillReport(message: "Killed node on :3000 (PID 42)", isError: false)
        XCTAssertEqual(report.message, "Killed node on :3000 (PID 42)")
        XCTAssertFalse(report.isError)
    }

    func testKillReportError() {
        let report = KillReport(message: "Failed to kill node on :3000 (PID 42): Operation not permitted", isError: true)
        XCTAssertTrue(report.isError)
        XCTAssertTrue(report.message.contains("Failed"))
    }
}

// MARK: - CPUSample Tests

final class CPUSampleTests: XCTestCase {

    func testCPUSampleProperties() {
        let now = Date()
        let sample = CPUSample(pid: 100, totalCPUTimeNs: 5_000_000_000, wallTime: now)
        XCTAssertEqual(sample.pid, 100)
        XCTAssertEqual(sample.totalCPUTimeNs, 5_000_000_000)
        XCTAssertEqual(sample.wallTime, now)
    }
}

// MARK: - PortScanner Tests

final class PortScannerTests: XCTestCase {

    func testAllPIDsReturnsNonEmptyList() {
        let pids = PortScanner.allPIDs()
        XCTAssertFalse(pids.isEmpty, "allPIDs should return at least one PID")
    }

    func testAllPIDsContainsCurrentProcess() {
        let pids = PortScanner.allPIDs()
        let myPID = getpid()
        XCTAssertTrue(pids.contains(myPID), "allPIDs should contain the current process PID \(myPID)")
    }

    func testAllPIDsContainsPID1() {
        let pids = PortScanner.allPIDs()
        XCTAssertTrue(pids.contains(1), "allPIDs should contain PID 1 (launchd)")
    }

    func testProcessNameForLaunchd() {
        let name = PortScanner.processName(pid: 1)
        // proc_name for PID 1 may return "<unknown>" if the process lacks permission,
        // but processPath should still work. Accept either.
        let isLaunchd = name == "launchd"
        let isUnknown = name == "<unknown>"
        XCTAssertTrue(isLaunchd || isUnknown,
                       "PID 1 name should be 'launchd' or '<unknown>' (got: \(name))")
    }

    func testProcessNameForCurrentProcess() {
        let name = PortScanner.processName(pid: getpid())
        XCTAssertFalse(name.isEmpty, "Current process should have a name")
        XCTAssertNotEqual(name, "<unknown>", "Current process name should not be <unknown>")
    }

    func testProcessPathForPID1() {
        let path = PortScanner.processPath(pid: 1)
        // launchd is at /sbin/launchd
        XCTAssertTrue(path.contains("launchd"), "PID 1 path should contain 'launchd', got: \(path)")
    }

    func testProcessPathForCurrentProcess() {
        let path = PortScanner.processPath(pid: getpid())
        XCTAssertFalse(path.isEmpty, "Current process should have a path")
    }

    func testIsAliveForCurrentProcess() {
        XCTAssertTrue(PortScanner.isAlive(pid: getpid()), "Current process should be alive")
    }

    func testIsAliveForPID1() {
        XCTAssertTrue(PortScanner.isAlive(pid: 1), "launchd (PID 1) should be alive")
    }

    func testIsAliveForInvalidPID() {
        // PID 99999 is very unlikely to exist
        XCTAssertFalse(PortScanner.isAlive(pid: 99999), "PID 99999 should not be alive")
    }

    func testMachTicksToNanosecondsZero() {
        XCTAssertEqual(PortScanner.machTicksToNanoseconds(0), 0)
    }

    func testMachTicksToNanosecondsNonZero() {
        // The conversion depends on the machine's timebase, but output should be >= input
        // (on most Macs numer/denom is 1/1, but on some Apple Silicon it differs)
        let result = PortScanner.machTicksToNanoseconds(1_000_000)
        XCTAssertGreaterThan(result, 0, "Converting 1M ticks should produce a non-zero result")
    }

    func testMachTicksToNanosecondsMonotonic() {
        let small = PortScanner.machTicksToNanoseconds(100)
        let large = PortScanner.machTicksToNanoseconds(1000)
        XCTAssertLessThanOrEqual(small, large, "More ticks should produce more (or equal) nanoseconds")
    }

    func testRoleKeywordsCreation() {
        let kw = PortScanner.RoleKeywords(
            front: ["front", "web"],
            back: ["api", "server"],
            db: ["db"],
            dbProc: ["postgres"],
            mcp: ["mcp-server"]
        )
        XCTAssertEqual(kw.front, ["front", "web"])
        XCTAssertEqual(kw.back, ["api", "server"])
        XCTAssertEqual(kw.db, ["db"])
        XCTAssertEqual(kw.dbProc, ["postgres"])
        XCTAssertEqual(kw.mcp, ["mcp-server"])
    }

    func testProcessCwdForCurrentProcess() {
        let cwd = PortScanner.processCwd(pid: getpid())
        // The test runner should have a working directory
        XCTAssertFalse(cwd.isEmpty, "Current process should have a cwd")
    }

    func testBsdInfoForCurrentProcess() {
        let info = PortScanner.bsdInfo(pid: getpid())
        XCTAssertNotNil(info, "Should be able to get BSD info for current process")
    }

    func testTaskInfoForCurrentProcess() {
        let info = PortScanner.taskInfo(pid: getpid())
        XCTAssertNotNil(info, "Should be able to get task info for current process")
        if let info {
            XCTAssertGreaterThan(info.pti_resident_size, 0, "Resident memory should be > 0")
        }
    }

    func testFileDescriptorsForCurrentProcess() {
        let fds = PortScanner.fileDescriptors(for: getpid())
        XCTAssertFalse(fds.isEmpty, "Current process should have file descriptors")
    }

    func testFileDescriptorsForInvalidPID() {
        let fds = PortScanner.fileDescriptors(for: 99999)
        XCTAssertTrue(fds.isEmpty, "Invalid PID should return empty file descriptors")
    }

    func testScanAllPortsReturnsArray() {
        // Integration test: scan all ports. Result may be empty if nothing is listening,
        // but the call should not crash.
        let entries = PortScanner.scanAllPorts()
        // Verify all entries have valid ports
        for entry in entries {
            XCTAssertGreaterThan(entry.port, 0, "Port should be > 0")
            XCTAssertGreaterThan(entry.pid, 0, "PID should be > 0")
            XCTAssertFalse(entry.processName.isEmpty, "Process name should not be empty")
        }
    }

    func testScanAllPortsEntriesAreSortedByPort() {
        let entries = PortScanner.scanAllPorts()
        guard entries.count >= 2 else { return } // Skip if fewer than 2 entries
        for i in 0..<(entries.count - 1) {
            XCTAssertLessThanOrEqual(entries[i].port, entries[i + 1].port,
                                     "Entries should be sorted by port")
        }
    }

    func testScanAllPortsWithKeywords() {
        let kw = PortScanner.RoleKeywords(
            front: ["front", "vite"],
            back: ["api", "server"],
            db: ["db"],
            dbProc: ["postgres"],
            mcp: ["mcp-server", "fastmcp"]
        )
        let entries = PortScanner.scanAllPorts(keywords: kw)
        // Should not crash; entries may or may not have roles
        _ = entries
    }

    func testKillResultProperties() {
        let result = PortScanner.KillResult(
            pid: 42,
            port: 3000,
            processName: "node",
            success: true,
            error: nil
        )
        XCTAssertEqual(result.pid, 42)
        XCTAssertEqual(result.port, 3000)
        XCTAssertEqual(result.processName, "node")
        XCTAssertTrue(result.success)
        XCTAssertNil(result.error)
    }

    func testKillResultWithError() {
        let result = PortScanner.KillResult(
            pid: 42,
            port: 3000,
            processName: "node",
            success: false,
            error: "Operation not permitted"
        )
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.error, "Operation not permitted")
    }
}

// MARK: - ProjectDetector Tests

final class ProjectDetectorTests: XCTestCase {

    func testKnownPortPostgreSQL() {
        // Docker detection runs first and may claim port 5432 if Docker is running.
        let result = ProjectDetector.detectProject(cwd: "", port: 5432)
        let isExpected = result.name == "PostgreSQL" || result.name.hasPrefix("Docker:")
        XCTAssertTrue(isExpected, "Port 5432 should be 'PostgreSQL' or Docker, got: \(result.name)")
        XCTAssertNil(result.worktreeName)
    }

    func testKnownPortMySQL() {
        let result = ProjectDetector.detectProject(cwd: "", port: 3306)
        XCTAssertEqual(result.name, "MySQL")
        XCTAssertNil(result.worktreeName)
    }

    func testKnownPortRedis() {
        let result = ProjectDetector.detectProject(cwd: "", port: 6379)
        XCTAssertEqual(result.name, "Redis")
        XCTAssertNil(result.worktreeName)
    }

    func testKnownPortMongoDB() {
        let result = ProjectDetector.detectProject(cwd: "", port: 27017)
        XCTAssertEqual(result.name, "MongoDB")
        XCTAssertNil(result.worktreeName)
    }

    func testKnownPortElasticsearch() {
        let result = ProjectDetector.detectProject(cwd: "", port: 9200)
        XCTAssertEqual(result.name, "Elasticsearch")
        XCTAssertNil(result.worktreeName)
    }

    func testUnknownPortAndEmptyCwd() {
        let result = ProjectDetector.detectProject(cwd: "", port: 12345)
        XCTAssertEqual(result.name, "Other")
        XCTAssertNil(result.worktreeName)
    }

    func testUnknownPortWithNonGitCwd() {
        let result = ProjectDetector.detectProject(cwd: "/tmp", port: 55555)
        XCTAssertEqual(result.name, "Other")
        XCTAssertNil(result.worktreeName)
    }

    func testDetectProjectWithGitDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortWatchTest-\(UUID().uuidString)")
        let gitDir = tempDir.appendingPathComponent(".git")

        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let result = ProjectDetector.detectProject(cwd: tempDir.path, port: 9999)
        XCTAssertEqual(result.name, tempDir.lastPathComponent)
        XCTAssertNil(result.worktreeName)
    }

    func testDetectProjectWithGitInParentDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortWatchTest-\(UUID().uuidString)")
        let gitDir = tempDir.appendingPathComponent(".git")
        let subDir = tempDir.appendingPathComponent("src").appendingPathComponent("backend")

        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let result = ProjectDetector.detectProject(cwd: subDir.path, port: 9999)
        XCTAssertEqual(result.name, tempDir.lastPathComponent)
        XCTAssertNil(result.worktreeName)
    }

    func testDetectProjectGitTakesPriorityOverKnownPort() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortWatchTest-\(UUID().uuidString)")
        let gitDir = tempDir.appendingPathComponent(".git")

        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let result = ProjectDetector.detectProject(cwd: tempDir.path, port: 9200)
        let isGitName = result.name == tempDir.lastPathComponent
        let isDocker = result.name.hasPrefix("Docker:")
        XCTAssertTrue(isGitName || isDocker,
                       "Should detect git project or Docker, got: \(result.name)")
        XCTAssertNil(result.worktreeName)
    }

    // MARK: - Worktree detection

    func testDetectProjectWithGitWorktree() throws {
        let mainRepo = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortWatchTest-main-\(UUID().uuidString)")
        let mainGitDir = mainRepo.appendingPathComponent(".git")
        let worktreesDir = mainGitDir.appendingPathComponent("worktrees").appendingPathComponent("my-worktree")

        try FileManager.default.createDirectory(at: worktreesDir, withIntermediateDirectories: true)

        let worktreeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortWatchTest-wt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: worktreeDir, withIntermediateDirectories: true)

        let gitFile = worktreeDir.appendingPathComponent(".git")
        try "gitdir: \(worktreesDir.path)".write(to: gitFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: mainRepo)
            try? FileManager.default.removeItem(at: worktreeDir)
        }

        let result = ProjectDetector.detectProject(cwd: worktreeDir.path, port: 9999)
        XCTAssertEqual(result.name, mainRepo.lastPathComponent)
        // worktreeName should be the worktree folder name
        XCTAssertEqual(result.worktreeName, worktreeDir.lastPathComponent)
    }

    func testDetectProjectWithGitWorktreeFromSubdirectory() throws {
        let mainRepo = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortWatchTest-main-\(UUID().uuidString)")
        let mainGitDir = mainRepo.appendingPathComponent(".git")
        let worktreesDir = mainGitDir.appendingPathComponent("worktrees").appendingPathComponent("wt")

        try FileManager.default.createDirectory(at: worktreesDir, withIntermediateDirectories: true)

        let worktreeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortWatchTest-wt-\(UUID().uuidString)")
        let subDir = worktreeDir.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let gitFile = worktreeDir.appendingPathComponent(".git")
        try "gitdir: \(worktreesDir.path)".write(to: gitFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: mainRepo)
            try? FileManager.default.removeItem(at: worktreeDir)
        }

        // Process cwd is in a subdirectory of the worktree
        let result = ProjectDetector.detectProject(cwd: subDir.path, port: 9999)
        XCTAssertEqual(result.name, mainRepo.lastPathComponent)
        // worktreeName is the folder containing .git file, not the subdirectory
        XCTAssertEqual(result.worktreeName, worktreeDir.lastPathComponent)
    }

    func testDetectProjectWithGitWorktreeRelativePath() throws {
        let mainRepo = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortWatchTest-main-\(UUID().uuidString)")
        let mainGitDir = mainRepo.appendingPathComponent(".git")
        let worktreesDir = mainGitDir.appendingPathComponent("worktrees").appendingPathComponent("wt")

        try FileManager.default.createDirectory(at: worktreesDir, withIntermediateDirectories: true)

        // Create worktree inside main repo's .claude/worktrees/
        let worktreeDir = mainRepo.appendingPathComponent(".claude").appendingPathComponent("worktrees").appendingPathComponent("wt")
        try FileManager.default.createDirectory(at: worktreeDir, withIntermediateDirectories: true)

        let gitFile = worktreeDir.appendingPathComponent(".git")
        try "gitdir: ../../../.git/worktrees/wt".write(to: gitFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: mainRepo)
        }

        let result = ProjectDetector.detectProject(cwd: worktreeDir.path, port: 9999)
        XCTAssertEqual(result.name, mainRepo.lastPathComponent)
        XCTAssertEqual(result.worktreeName, "wt")
    }

    func testDetectProjectWorktreeGroupsUnderMainProject() throws {
        // Worktree and main repo should return the same project name
        let mainRepo = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortWatchTest-main-\(UUID().uuidString)")
        let mainGitDir = mainRepo.appendingPathComponent(".git")
        let worktreesDir = mainGitDir.appendingPathComponent("worktrees").appendingPathComponent("wt")

        try FileManager.default.createDirectory(at: worktreesDir, withIntermediateDirectories: true)

        let worktreeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortWatchTest-wt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: worktreeDir, withIntermediateDirectories: true)

        let gitFile = worktreeDir.appendingPathComponent(".git")
        try "gitdir: \(worktreesDir.path)".write(to: gitFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: mainRepo)
            try? FileManager.default.removeItem(at: worktreeDir)
        }

        let mainResult = ProjectDetector.detectProject(cwd: mainRepo.path, port: 3000)
        let wtResult = ProjectDetector.detectProject(cwd: worktreeDir.path, port: 3001)

        // Both should resolve to the same project name
        XCTAssertEqual(mainResult.name, wtResult.name)
        // Main repo is not a worktree
        XCTAssertNil(mainResult.worktreeName)
        // Worktree has a name
        XCTAssertNotNil(wtResult.worktreeName)
    }

    func testDetectProjectWorktreeInvalidGitFileContent() throws {
        // .git file exists but has garbage content
        let worktreeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortWatchTest-wt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: worktreeDir, withIntermediateDirectories: true)

        let gitFile = worktreeDir.appendingPathComponent(".git")
        try "this is not a valid gitdir reference".write(to: gitFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: worktreeDir)
        }

        let result = ProjectDetector.detectProject(cwd: worktreeDir.path, port: 9999)
        // Should fallback to folder name since resolution fails
        XCTAssertEqual(result.name, worktreeDir.lastPathComponent)
        // Still recognized as a worktree (it's a .git file, not directory)
        XCTAssertNotNil(result.worktreeName)
    }

    func testDetectProjectWorktreeEmptyGitFile() throws {
        let worktreeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortWatchTest-wt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: worktreeDir, withIntermediateDirectories: true)

        let gitFile = worktreeDir.appendingPathComponent(".git")
        try "".write(to: gitFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: worktreeDir)
        }

        let result = ProjectDetector.detectProject(cwd: worktreeDir.path, port: 9999)
        XCTAssertEqual(result.name, worktreeDir.lastPathComponent)
        XCTAssertNotNil(result.worktreeName)
    }

    func testDetectProjectWorktreeGitdirPointsToNonexistentPath() throws {
        let worktreeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortWatchTest-wt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: worktreeDir, withIntermediateDirectories: true)

        let gitFile = worktreeDir.appendingPathComponent(".git")
        try "gitdir: /nonexistent/path/.git/worktrees/foo".write(to: gitFile, atomically: true, encoding: .utf8)

        defer {
            try? FileManager.default.removeItem(at: worktreeDir)
        }

        let result = ProjectDetector.detectProject(cwd: worktreeDir.path, port: 9999)
        // Resolution fails because the .git dir doesn't exist, falls back to folder name
        XCTAssertEqual(result.name, worktreeDir.lastPathComponent)
        XCTAssertNotNil(result.worktreeName)
    }

    func testDetectProjectNormalRepoHasNilWorktreeName() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortWatchTest-\(UUID().uuidString)")
        let gitDir = tempDir.appendingPathComponent(".git")

        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let result = ProjectDetector.detectProject(cwd: tempDir.path, port: 9999)
        XCTAssertEqual(result.name, tempDir.lastPathComponent)
        XCTAssertNil(result.worktreeName)
    }
}

// MARK: - AppSettings Tests

@MainActor
final class AppSettingsTests: XCTestCase {

    func testDefaultValues() {
        let settings = AppSettings.shared
        // Store current values, reset, check defaults, then restore
        let savedCPU = settings.cpuThreshold
        let savedRAM = settings.ramThresholdMB
        let savedRefresh = settings.refreshInterval
        let savedNotif = settings.notifyNewPorts
        let savedConflict = settings.notifyConflicts
        let savedFront = settings.frontKeywords
        let savedBack = settings.backKeywords
        let savedDB = settings.dbKeywords
        let savedDBProc = settings.dbProcessNames

        defer {
            // Restore original values
            settings.cpuThreshold = savedCPU
            settings.ramThresholdMB = savedRAM
            settings.refreshInterval = savedRefresh
            settings.notifyNewPorts = savedNotif
            settings.notifyConflicts = savedConflict
            settings.frontKeywords = savedFront
            settings.backKeywords = savedBack
            settings.dbKeywords = savedDB
            settings.dbProcessNames = savedDBProc
        }

        settings.resetToDefaults()

        XCTAssertEqual(settings.cpuThreshold, 50.0)
        XCTAssertEqual(settings.ramThresholdMB, 500.0)
        XCTAssertEqual(settings.refreshInterval, 10.0)
        XCTAssertEqual(settings.notifyNewPorts, 0)
        XCTAssertEqual(settings.notifyConflicts, 1)
        XCTAssertEqual(settings.frontKeywords, ["front", "web", "client", "ui", "vite", "webpack", "next", "nuxt"])
        XCTAssertEqual(settings.backKeywords, ["back", "api", "server", "uvicorn", "gunicorn", "flask", "django", "express", "fastify"])
        XCTAssertEqual(settings.dbKeywords, ["db", "database"])
        XCTAssertEqual(settings.dbProcessNames, ["postgres", "mysqld", "mysql", "mongod", "mongos", "redis-server", "redis-sentinel"])
    }

    func testResetToDefaultsRestoresModifiedValues() {
        let settings = AppSettings.shared
        // Save originals
        let savedCPU = settings.cpuThreshold
        let savedRAM = settings.ramThresholdMB
        let savedRefresh = settings.refreshInterval
        let savedNotif = settings.notifyNewPorts
        let savedConflict = settings.notifyConflicts
        let savedFront = settings.frontKeywords
        let savedBack = settings.backKeywords
        let savedDB = settings.dbKeywords
        let savedDBProc = settings.dbProcessNames

        defer {
            // Restore original values
            settings.cpuThreshold = savedCPU
            settings.ramThresholdMB = savedRAM
            settings.refreshInterval = savedRefresh
            settings.notifyNewPorts = savedNotif
            settings.notifyConflicts = savedConflict
            settings.frontKeywords = savedFront
            settings.backKeywords = savedBack
            settings.dbKeywords = savedDB
            settings.dbProcessNames = savedDBProc
        }

        // Modify all values
        settings.cpuThreshold = 90.0
        settings.ramThresholdMB = 2000.0
        settings.refreshInterval = 30.0
        settings.notifyNewPorts = 2
        settings.notifyConflicts = 0
        settings.frontKeywords = ["custom"]
        settings.backKeywords = ["custom"]
        settings.dbKeywords = ["custom"]
        settings.dbProcessNames = ["custom"]

        // Verify they changed
        XCTAssertEqual(settings.cpuThreshold, 90.0)
        XCTAssertEqual(settings.ramThresholdMB, 2000.0)
        XCTAssertEqual(settings.refreshInterval, 30.0)
        XCTAssertEqual(settings.notifyNewPorts, 2)
        XCTAssertEqual(settings.notifyConflicts, 0)

        // Reset
        settings.resetToDefaults()

        // Verify all back to defaults
        XCTAssertEqual(settings.cpuThreshold, 50.0)
        XCTAssertEqual(settings.ramThresholdMB, 500.0)
        XCTAssertEqual(settings.refreshInterval, 10.0)
        XCTAssertEqual(settings.notifyNewPorts, 0)
        XCTAssertEqual(settings.notifyConflicts, 1)
        XCTAssertEqual(settings.frontKeywords, ["front", "web", "client", "ui", "vite", "webpack", "next", "nuxt"])
        XCTAssertEqual(settings.backKeywords, ["back", "api", "server", "uvicorn", "gunicorn", "flask", "django", "express", "fastify"])
        XCTAssertEqual(settings.dbKeywords, ["db", "database"])
        XCTAssertEqual(settings.dbProcessNames, ["postgres", "mysqld", "mysql", "mongod", "mongos", "redis-server", "redis-sentinel"])
    }

    func testSettingsPersistToUserDefaults() {
        let settings = AppSettings.shared
        let savedCPU = settings.cpuThreshold

        defer {
            settings.cpuThreshold = savedCPU
        }

        settings.cpuThreshold = 75.0
        // The didSet should write to UserDefaults
        let stored = UserDefaults.standard.double(forKey: "cpuThreshold")
        XCTAssertEqual(stored, 75.0)
    }
}

// MARK: - filterIgnoredProcesses Tests

final class FilterIgnoredProcessesTests: XCTestCase {

    private func make(pid: Int32 = 100, port: UInt16 = 3000, name: String) -> PortEntry {
        PortEntry(
            id: "\(port)-\(pid)",
            port: port, pid: pid,
            processName: name, processPath: "", commandLine: "", cwd: "",
            tcpState: .listen,
            processStartTime: Date(),
            residentMemoryBytes: 0, totalCPUTimeNs: 0,
            projectName: "Test", worktreeName: nil,
            roleLabel: nil, roleIcon: nil
        )
    }

    func testEmptyIgnoreListReturnsAll() {
        let entries = [make(name: "node"), make(name: "postgres")]
        let result = PortMonitor.filterIgnoredProcesses(entries, ignored: [])
        XCTAssertEqual(result.count, 2)
    }

    func testFiltersByExactName() {
        let entries = [
            make(name: "claude"),
            make(name: "node"),
            make(name: "discord"),
        ]
        let result = PortMonitor.filterIgnoredProcesses(entries, ignored: ["claude", "discord"])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.processName, "node")
    }

    func testCaseInsensitiveMatch() {
        // `ignored` is expected to be pre-lowercased by the caller; process names may vary.
        let entries = [make(name: "Claude"), make(name: "CLAUDE"), make(name: "CLAUDEX")]
        let result = PortMonitor.filterIgnoredProcesses(entries, ignored: ["claude"])
        XCTAssertEqual(result.count, 1) // only CLAUDEX (different name) survives
        XCTAssertEqual(result.first?.processName, "CLAUDEX")
    }

    func testExactMatchOnly_NoSubstring() {
        // "claude" in ignore list should NOT filter out "claude-helper" or "myclaude".
        let entries = [
            make(name: "claude"),
            make(name: "claude-helper"),
            make(name: "myclaude"),
        ]
        let result = PortMonitor.filterIgnoredProcesses(entries, ignored: ["claude"])
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains { $0.processName == "claude-helper" })
        XCTAssertTrue(result.contains { $0.processName == "myclaude" })
    }

    func testPreservesOrderOfRemaining() {
        let entries = [
            make(port: 3000, name: "node"),
            make(port: 5432, name: "postgres"),
            make(port: 64975, name: "claude"),
            make(port: 8080, name: "redis-server"),
        ]
        let result = PortMonitor.filterIgnoredProcesses(entries, ignored: ["claude"])
        XCTAssertEqual(result.map(\.port), [3000, 5432, 8080])
    }
}
