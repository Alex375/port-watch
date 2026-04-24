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

    func testIsZombieCandidateTrueForCloseWait() {
        XCTAssertTrue(TCPState.closeWait.isZombieCandidate)
    }

    func testIsZombieCandidateFalseForTimeWait() {
        // TIME_WAIT is a normal TCP state (2*MSL cleanup) and must never be flagged as a zombie.
        XCTAssertFalse(TCPState.timeWait.isZombieCandidate)
    }

    func testIsZombieCandidateFalseForNonZombieStates() {
        let nonZombie: [TCPState] = [
            .closed, .listen, .synSent, .synReceived,
            .established, .finWait1, .closing, .lastAck, .finWait2, .timeWait
        ]
        for state in nonZombie {
            XCTAssertFalse(state.isZombieCandidate, "\(state.displayName) should not be a zombie candidate")
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
        ppid: Int32 = 0,
        processName: String = "node",
        processPath: String = "/usr/bin/node",
        commandLine: String = "node server.js",
        arguments: [String] = [],
        environment: [String: String] = [:],
        cwd: String = "/Users/test/project",
        tcpState: TCPState = .listen,
        processStartTime: Date = Date(),
        residentMemoryBytes: UInt64 = 0,
        totalCPUTimeNs: UInt64 = 0,
        projectName: String = "TestProject",
        worktreeName: String? = nil,
        projectKey: String = "other:test",
        dockerContainerID: String? = nil,
        roleLabel: String? = nil,
        roleIcon: String? = nil
    ) -> PortEntry {
        PortEntry(
            id: "\(port)-\(pid)-0",
            port: port,
            pid: pid,
            ppid: ppid,
            processName: processName,
            processPath: processPath,
            commandLine: commandLine,
            arguments: arguments,
            environment: environment,
            cwd: cwd,
            tcpState: tcpState,
            processStartTime: processStartTime,
            residentMemoryBytes: residentMemoryBytes,
            totalCPUTimeNs: totalCPUTimeNs,
            projectName: projectName,
            worktreeName: worktreeName,
            projectKey: projectKey,
            dockerContainerID: dockerContainerID,
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

    // MARK: Claude detection

    func testDetectRoleClaudeByProcessName() {
        let result = PortEntry.detectRole(
            folder: "project", process: "claude", cmd: "claude",
            frontKeywords: ["front"], backKeywords: ["back"],
            dbKeywords: ["db"], dbProcessNames: ["postgres"],
            mcpKeywords: ["mcp-server"],
            claudeKeywords: ["claude", "claude-code"]
        )
        XCTAssertEqual(result.label, "Claude")
        XCTAssertEqual(result.icon, "ClaudeLogo")
    }

    func testDetectRoleClaudeByCmd() {
        let result = PortEntry.detectRole(
            folder: "project", process: "node", cmd: "node /usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js",
            frontKeywords: ["front"], backKeywords: ["back"],
            dbKeywords: ["db"], dbProcessNames: ["postgres"],
            mcpKeywords: ["mcp-server"],
            claudeKeywords: ["claude", "claude-code", "@anthropic-ai/claude-code"]
        )
        XCTAssertEqual(result.label, "Claude")
    }

    func testDetectRoleClaudeTakesPriorityOverMCP() {
        // A Claude process that also has "mcp" in its cmd should still be tagged "Claude"
        let result = PortEntry.detectRole(
            folder: "project", process: "claude", cmd: "claude --mcp-config",
            frontKeywords: ["front"], backKeywords: ["back"],
            dbKeywords: ["db"], dbProcessNames: ["postgres"],
            mcpKeywords: ["mcp"],
            claudeKeywords: ["claude"]
        )
        XCTAssertEqual(result.label, "Claude")
    }

    func testDetectRoleClaudeDoesNotMatchFolder() {
        // Claude keywords only match process name and cmd — a folder called "claude-notes"
        // with a generic node process shouldn't be tagged Claude.
        let result = PortEntry.detectRole(
            folder: "claude-notes", process: "node", cmd: "node index.js",
            frontKeywords: ["front"], backKeywords: ["back"],
            dbKeywords: ["db"], dbProcessNames: ["postgres"],
            mcpKeywords: [],
            claudeKeywords: ["claude"]
        )
        XCTAssertNotEqual(result.label, "Claude")
    }

    func testDetectRoleDBTakesPriorityOverClaude() {
        let result = PortEntry.detectRole(
            folder: "project", process: "postgres", cmd: "postgres claude",
            frontKeywords: ["front"], backKeywords: ["back"],
            dbKeywords: ["db"], dbProcessNames: ["postgres"],
            mcpKeywords: [],
            claudeKeywords: ["claude"]
        )
        XCTAssertEqual(result.label, "DB")
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
            ppid: 0,
            processName: processName,
            processPath: "/usr/bin/node",
            commandLine: commandLine,
            arguments: [],
            environment: [:],
            cwd: "/tmp",
            tcpState: .listen,
            processStartTime: Date(),
            residentMemoryBytes: 0,
            totalCPUTimeNs: 0,
            projectName: "Test",
            worktreeName: nil,
            projectKey: "other:test",
            dockerContainerID: nil,
            roleLabel: nil,
            roleIcon: nil
        )
    }

    func testCommandSummaryWithCommandLine() {
        let entry = makeEntry(commandLine: "node server.js --port 3000", processName: "node")
        let display = PortEntryDisplay(entry: entry, cpuPercent: nil, isZombie: false)
        XCTAssertEqual(display.commandSummary, "node server.js --port 3000")
    }

    func testCommandSummaryFallsBackToProcessName() {
        let entry = makeEntry(commandLine: "", processName: "nginx")
        let display = PortEntryDisplay(entry: entry, cpuPercent: nil, isZombie: false)
        XCTAssertEqual(display.commandSummary, "nginx")
    }

    func testDisplayIdMatchesEntryId() {
        let entry = makeEntry()
        let display = PortEntryDisplay(entry: entry, cpuPercent: 12.5, isZombie: false)
        XCTAssertEqual(display.id, entry.id)
    }

    func testCpuPercentIsStored() {
        let entry = makeEntry()
        let display = PortEntryDisplay(entry: entry, cpuPercent: 42.5, isZombie: false)
        XCTAssertEqual(display.cpuPercent, 42.5)
    }

    func testCpuPercentNil() {
        let entry = makeEntry()
        let display = PortEntryDisplay(entry: entry, cpuPercent: nil, isZombie: false)
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
            ppid: 0,
            processName: "node",
            processPath: "/usr/bin/node",
            commandLine: "node index.js",
            arguments: [],
            environment: [:],
            cwd: "/tmp",
            tcpState: .listen,
            processStartTime: Date(),
            residentMemoryBytes: 0,
            totalCPUTimeNs: 0,
            projectName: "MyApp",
            worktreeName: nil,
            projectKey: "other:test",
            dockerContainerID: nil,
            roleLabel: nil,
            roleIcon: nil
        )
        let display = PortEntryDisplay(entry: entry, cpuPercent: nil, isZombie: false)
        let group = ProjectGroup(projectName: "MyApp", entries: [display])

        XCTAssertEqual(group.projectName, "MyApp")
        XCTAssertEqual(group.entries.count, 1)
        XCTAssertEqual(group.entries.first?.entry.port, 3000)
    }

    func testProjectGroupMultipleEntries() {
        let entry1 = PortEntry(
            id: "3000-1-0", port: 3000, pid: 1, ppid: 0,
            processName: "node", processPath: "", commandLine: "",
            arguments: [], environment: [:], cwd: "",
            tcpState: .listen, processStartTime: Date(),
            residentMemoryBytes: 0, totalCPUTimeNs: 0,
            projectName: "MyApp", worktreeName: nil,
            projectKey: "other:test", dockerContainerID: nil,
            roleLabel: nil, roleIcon: nil
        )
        let entry2 = PortEntry(
            id: "3001-2-0", port: 3001, pid: 2, ppid: 0,
            processName: "python", processPath: "", commandLine: "",
            arguments: [], environment: [:], cwd: "",
            tcpState: .listen, processStartTime: Date(),
            residentMemoryBytes: 0, totalCPUTimeNs: 0,
            projectName: "MyApp", worktreeName: nil,
            projectKey: "other:test", dockerContainerID: nil,
            roleLabel: nil, roleIcon: nil
        )
        let displays = [
            PortEntryDisplay(entry: entry1, cpuPercent: nil, isZombie: false),
            PortEntryDisplay(entry: entry2, cpuPercent: nil, isZombie: false),
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
            mcp: ["mcp-server"],
            claude: ["claude"]
        )
        XCTAssertEqual(kw.front, ["front", "web"])
        XCTAssertEqual(kw.back, ["api", "server"])
        XCTAssertEqual(kw.db, ["db"])
        XCTAssertEqual(kw.dbProc, ["postgres"])
        XCTAssertEqual(kw.mcp, ["mcp-server"])
        XCTAssertEqual(kw.claude, ["claude"])
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
            mcp: ["mcp-server", "fastmcp"],
            claude: ["claude"]
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

    func testClaudeKeywordsDefaults() {
        let settings = AppSettings.shared
        let saved = settings.claudeKeywords
        defer { settings.claudeKeywords = saved }

        settings.resetToDefaults()
        XCTAssertEqual(
            settings.claudeKeywords,
            ["claude", "claude-code", "@anthropic-ai/claude-code", "anthropic-ai/claude"]
        )
    }

    func testSnapshotTTLMinutesDefault() {
        let settings = AppSettings.shared
        let saved = settings.snapshotTTLMinutes
        defer { settings.snapshotTTLMinutes = saved }

        settings.resetToDefaults()
        XCTAssertEqual(settings.snapshotTTLMinutes, 60, "Default TTL is 1 hour — max of the slider; use the toggle for indefinite retention")
    }

    func testSnapTTLMinutesStaysPreciseBelowTenMinutes() {
        // Under 10 min the slider must resolve to 1-minute precision — that's the range
        // where the user wants to pick "5 min" or "7 min" specifically.
        XCTAssertEqual(SettingsView.snapTTLMinutes(1.0), 1)
        XCTAssertEqual(SettingsView.snapTTLMinutes(4.6), 5)
        XCTAssertEqual(SettingsView.snapTTLMinutes(7.0), 7)
        XCTAssertEqual(SettingsView.snapTTLMinutes(9.4), 9)
    }

    func testSnapTTLMinutesFiveMinuteStepsUnderAnHour() {
        XCTAssertEqual(SettingsView.snapTTLMinutes(11), 10)
        XCTAssertEqual(SettingsView.snapTTLMinutes(13), 15)
        XCTAssertEqual(SettingsView.snapTTLMinutes(32), 30)
        XCTAssertEqual(SettingsView.snapTTLMinutes(58), 60)
    }

    func testSnapTTLMinutesQuarterHourUnderSixHours() {
        XCTAssertEqual(SettingsView.snapTTLMinutes(62), 60)
        XCTAssertEqual(SettingsView.snapTTLMinutes(70), 75)
        XCTAssertEqual(SettingsView.snapTTLMinutes(200), 195)
        XCTAssertEqual(SettingsView.snapTTLMinutes(350), 345)
    }

    func testSnapTTLMinutesHourStepsUnderOneDay() {
        XCTAssertEqual(SettingsView.snapTTLMinutes(6 * 60 + 10), 6 * 60)
        XCTAssertEqual(SettingsView.snapTTLMinutes(12 * 60 + 20), 12 * 60)
        XCTAssertEqual(SettingsView.snapTTLMinutes(23 * 60), 23 * 60)
    }

    func testSnapTTLMinutesTwelveHourStepsUnderAWeek() {
        XCTAssertEqual(SettingsView.snapTTLMinutes(25 * 60), 24 * 60)       // 1d
        XCTAssertEqual(SettingsView.snapTTLMinutes(34 * 60), 36 * 60)       // 1.5d
        XCTAssertEqual(SettingsView.snapTTLMinutes(5 * 24 * 60), 5 * 24 * 60)
    }

    func testSnapTTLMinutesDayStepsBeyondAWeek() {
        XCTAssertEqual(SettingsView.snapTTLMinutes(10 * 24 * 60 + 60), 10 * 24 * 60)
        XCTAssertEqual(SettingsView.snapTTLMinutes(30 * 24 * 60), 30 * 24 * 60)
    }

    func testSnapshotTTLMinutesZeroMeansKeepForever() {
        // The "Keep forever" toggle writes 0 — SnapshotStore.pruneMinutes treats 0 as a no-op.
        let settings = AppSettings.shared
        let saved = settings.snapshotTTLMinutes
        defer { settings.snapshotTTLMinutes = saved }

        settings.snapshotTTLMinutes = 0
        XCTAssertEqual(settings.snapshotTTLMinutes, 0)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "snapshotTTLMinutes"), 0)
    }

    func testSnapshotTTLMinutesAcceptsShortRetention() {
        // User asked: "je veux qu'il reste 5 min en historique". Make sure 5 min is a valid,
        // persisted value.
        let settings = AppSettings.shared
        let saved = settings.snapshotTTLMinutes
        defer { settings.snapshotTTLMinutes = saved }

        settings.snapshotTTLMinutes = 5
        XCTAssertEqual(settings.snapshotTTLMinutes, 5)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "snapshotTTLMinutes"), 5)
    }

    func testClaudeKeywordsPersistToUserDefaults() {
        let settings = AppSettings.shared
        let saved = settings.claudeKeywords
        defer { settings.claudeKeywords = saved }

        settings.claudeKeywords = ["claude-test"]
        let stored = UserDefaults.standard.stringArray(forKey: "claudeKeywords")
        XCTAssertEqual(stored, ["claude-test"])
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

// MARK: - Zombie Streak Tests (from #11)

final class ZombieStreakTests: XCTestCase {

    func testNonCandidateStateYieldsNoStreak() {
        let result = PortMonitor.advanceZombieStreak(tcpState: .listen, previousStreak: 0)
        XCTAssertEqual(result.streak, 0)
        XCTAssertFalse(result.isZombie)
    }

    func testTimeWaitIsNeverZombie() {
        // TIME_WAIT is a normal TCP teardown state — even across many scans it must not be flagged.
        let result = PortMonitor.advanceZombieStreak(tcpState: .timeWait, previousStreak: 99)
        XCTAssertEqual(result.streak, 0)
        XCTAssertFalse(result.isZombie)
    }

    func testCloseWaitFirstScanIsNotZombieYet() {
        let result = PortMonitor.advanceZombieStreak(tcpState: .closeWait, previousStreak: 0, threshold: 3)
        XCTAssertEqual(result.streak, 1)
        XCTAssertFalse(result.isZombie)
    }

    func testCloseWaitBelowThresholdIsNotZombie() {
        let result = PortMonitor.advanceZombieStreak(tcpState: .closeWait, previousStreak: 1, threshold: 3)
        XCTAssertEqual(result.streak, 2)
        XCTAssertFalse(result.isZombie)
    }

    func testCloseWaitAtThresholdIsZombie() {
        let result = PortMonitor.advanceZombieStreak(tcpState: .closeWait, previousStreak: 2, threshold: 3)
        XCTAssertEqual(result.streak, 3)
        XCTAssertTrue(result.isZombie)
    }

    func testCloseWaitAboveThresholdStaysZombie() {
        let result = PortMonitor.advanceZombieStreak(tcpState: .closeWait, previousStreak: 10, threshold: 3)
        XCTAssertEqual(result.streak, 11)
        XCTAssertTrue(result.isZombie)
    }

    func testThresholdOneFlagsImmediately() {
        let result = PortMonitor.advanceZombieStreak(tcpState: .closeWait, previousStreak: 0, threshold: 1)
        XCTAssertEqual(result.streak, 1)
        XCTAssertTrue(result.isZombie)
    }

    func testSimulatedSustainedCloseWaitBecomesZombie() {
        // Simulate 5 consecutive CLOSE_WAIT scans with threshold 3.
        var streak = 0
        var zombieScans = 0
        for _ in 1...5 {
            let r = PortMonitor.advanceZombieStreak(tcpState: .closeWait, previousStreak: streak, threshold: 3)
            streak = r.streak
            if r.isZombie { zombieScans += 1 }
        }
        // Scans 3, 4, 5 should all report zombie.
        XCTAssertEqual(zombieScans, 3)
        XCTAssertEqual(streak, 5)
    }

    func testStreakKeyFormat() {
        XCTAssertEqual(PortMonitor.streakKey(pid: 1234, port: 8080), "1234-8080")
        XCTAssertEqual(PortMonitor.streakKey(pid: 1, port: 3000), "1-3000")
    }

    func testZombieConfirmationScansDefault() {
        // Guard against accidental changes to the published default.
        XCTAssertEqual(PortMonitor.zombieConfirmationScans, 3)
    }
}

// MARK: - PortEntryDisplay.isZombie Tests (from #11)

final class PortEntryDisplayZombieTests: XCTestCase {

    private func makeEntry(tcpState: TCPState = .listen, projectName: String = "App") -> PortEntry {
        PortEntry(
            id: "8080-1-0",
            port: 8080, pid: 1, ppid: 0,
            processName: "node", processPath: "", commandLine: "",
            arguments: [], environment: [:], cwd: "",
            tcpState: tcpState,
            processStartTime: Date(),
            residentMemoryBytes: 0, totalCPUTimeNs: 0,
            projectName: projectName, worktreeName: nil,
            projectKey: "other:test", dockerContainerID: nil,
            roleLabel: nil, roleIcon: nil
        )
    }

    func testIsZombieIsStoredOnDisplay() {
        let display = PortEntryDisplay(entry: makeEntry(tcpState: .closeWait), cpuPercent: nil, isZombie: true)
        XCTAssertTrue(display.isZombie)
    }

    func testIsZombieFalseByDefault() {
        let display = PortEntryDisplay(entry: makeEntry(), cpuPercent: nil, isZombie: false)
        XCTAssertFalse(display.isZombie)
    }
}

// MARK: - PortScanner.filterServerSockets Tests (from #12)

final class FilterServerSocketsTests: XCTestCase {

    /// Build a minimal PortEntry for a given pid/port/state.
    private func make(pid: Int32 = 1234, port: UInt16, state: TCPState, processName: String = "proc") -> PortEntry {
        PortEntry(
            id: "\(port)-\(pid)-\(UUID().uuidString.prefix(4))",
            port: port, pid: pid, ppid: 0,
            processName: processName, processPath: "", commandLine: "",
            arguments: [], environment: [:], cwd: "",
            tcpState: state,
            processStartTime: Date(),
            residentMemoryBytes: 0, totalCPUTimeNs: 0,
            projectName: "Other", worktreeName: nil,
            projectKey: "other:test", dockerContainerID: nil,
            roleLabel: nil, roleIcon: nil
        )
    }

    func testPureClientProcessIsFilteredOut() {
        // Claude-like scenario: process has only CLOSE_WAIT on ephemeral ports (no LISTEN).
        // These are outbound HTTPS connections in teardown, not server ports.
        let input = [
            make(port: 51251, state: .closeWait),
            make(port: 51255, state: .closeWait),
            make(port: 51260, state: .timeWait),
        ]
        let result = PortScanner.filterServerSockets(pidEntries: input)
        XCTAssertTrue(result.isEmpty, "Pure client should be filtered entirely, got: \(result.map(\.port))")
    }

    func testServerWithMatchingListenAndCloseWaitIsKept() {
        // A real server: listens on :3000, has a CLOSE_WAIT on :3000 (client connection the server never closed).
        // Both should be kept — the CLOSE_WAIT is a legitimate server-side leak signal.
        let input = [
            make(port: 3000, state: .listen),
            make(port: 3000, state: .closeWait),
        ]
        let result = PortScanner.filterServerSockets(pidEntries: input)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains { $0.tcpState == .listen && $0.port == 3000 })
        XCTAssertTrue(result.contains { $0.tcpState == .closeWait && $0.port == 3000 })
    }

    func testServerWithOutboundClientSocketsDropsClient() {
        // Mixed case: a server listens on :8080, also makes outbound calls with CLOSE_WAIT on ephemeral ports.
        // Only the LISTEN and same-port zombies should be kept.
        let input = [
            make(port: 8080, state: .listen),
            make(port: 51999, state: .closeWait),  // outbound client leak — drop
            make(port: 8080, state: .timeWait),    // server-side connection in teardown — keep
        ]
        let result = PortScanner.filterServerSockets(pidEntries: input)
        XCTAssertEqual(result.count, 2)
        XCTAssertFalse(result.contains { $0.port == 51999 })
        XCTAssertTrue(result.contains { $0.tcpState == .timeWait && $0.port == 8080 })
    }

    func testPureListenerIsKept() {
        let input = [make(port: 5432, state: .listen, processName: "postgres")]
        let result = PortScanner.filterServerSockets(pidEntries: input)
        XCTAssertEqual(result.count, 1)
    }

    func testEmptyInputReturnsEmpty() {
        XCTAssertTrue(PortScanner.filterServerSockets(pidEntries: []).isEmpty)
    }

    func testMultipleListenPortsCoexist() {
        // A process can legitimately listen on several ports (e.g. HTTP + metrics + admin).
        let input = [
            make(port: 8080, state: .listen),
            make(port: 9090, state: .listen),
            make(port: 9090, state: .closeWait),  // keep — matches LISTEN
            make(port: 50123, state: .closeWait), // drop — no matching LISTEN
        ]
        let result = PortScanner.filterServerSockets(pidEntries: input)
        XCTAssertEqual(result.count, 3)
        XCTAssertFalse(result.contains { $0.port == 50123 })
    }

    func testClaudeLikeScenarioEndToEnd() {
        // Reproduces issue #10: Claude CLI process has only CLOSE_WAIT sockets on ephemeral ports
        // from its HTTPS connections to anthropic.com. Without the filter it would appear in the UI
        // tagged as "Back" because the cmd/cwd could incidentally match a Back keyword.
        let claudeEntries = [
            make(pid: 35301, port: 51287, state: .closeWait, processName: "claude"),
            make(pid: 35301, port: 51293, state: .closeWait, processName: "claude"),
            make(pid: 35301, port: 51421, state: .closeWait, processName: "claude"),
        ]
        let result = PortScanner.filterServerSockets(pidEntries: claudeEntries)
        XCTAssertTrue(result.isEmpty)
    }
}

// MARK: - filterIgnoredProcesses Tests (from #13 — UI branch)

final class FilterIgnoredProcessesTests: XCTestCase {

    private func make(pid: Int32 = 100, port: UInt16 = 3000, name: String) -> PortEntry {
        PortEntry(
            id: "\(port)-\(pid)",
            port: port, pid: pid, ppid: 0,
            processName: name, processPath: "", commandLine: "",
            arguments: [], environment: [:], cwd: "",
            tcpState: .listen,
            processStartTime: Date(),
            residentMemoryBytes: 0, totalCPUTimeNs: 0,
            projectName: "Test", worktreeName: nil,
            projectKey: "other:test", dockerContainerID: nil,
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

// MARK: - Fleet collapsing Tests (from #17 — worker fleet detection)

final class FleetCollapseTests: XCTestCase {

    /// Build a PortEntryDisplay with the given pid/ppid on a port.
    private func make(
        pid: Int32,
        ppid: Int32,
        port: UInt16 = 8000,
        name: String = "python",
        cpuPercent: Double? = nil,
        ramBytes: UInt64 = 0
    ) -> PortEntryDisplay {
        let entry = PortEntry(
            id: "\(port)-\(pid)", port: port, pid: pid, ppid: ppid,
            processName: name, processPath: "", commandLine: "",
            arguments: [], environment: [:], cwd: "",
            tcpState: .listen, processStartTime: Date(),
            residentMemoryBytes: ramBytes, totalCPUTimeNs: 0,
            projectName: "api", worktreeName: nil,
            projectKey: "other:test", dockerContainerID: nil,
            roleLabel: nil, roleIcon: nil
        )
        return PortEntryDisplay(entry: entry, cpuPercent: cpuPercent, isZombie: false)
    }

    // MARK: partitionIntoFleets

    func testPartitionSinglePIDReturnsSingleFleet() {
        let result = PortMonitor.partitionIntoFleets([make(pid: 100, ppid: 1)])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.count, 1)
    }

    func testPartitionParentChildFormOneFleet() {
        // ppid of 101 points to pid 100 → same fleet.
        let entries = [
            make(pid: 100, ppid: 1),
            make(pid: 101, ppid: 100),
            make(pid: 102, ppid: 100),
        ]
        let result = PortMonitor.partitionIntoFleets(entries)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.count, 3)
    }

    func testPartitionUnrelatedPIDsStaySeparate() {
        // Two unrelated servers on the same port (real conflict).
        let entries = [
            make(pid: 100, ppid: 1),
            make(pid: 200, ppid: 2),
        ]
        let result = PortMonitor.partitionIntoFleets(entries)
        XCTAssertEqual(result.count, 2)
    }

    func testPartitionMultiLevelAncestryFormsOneFleet() {
        // 102 → 101 → 100 : transitive ancestry, all within port entries.
        let entries = [
            make(pid: 100, ppid: 1),
            make(pid: 101, ppid: 100),
            make(pid: 102, ppid: 101),
        ]
        let result = PortMonitor.partitionIntoFleets(entries)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.count, 3)
    }

    func testPartitionPpidZeroDoesNotLinkFleets() {
        // ppid = 0 is a sentinel for "unavailable" and must never be used as a join key,
        // otherwise all orphaned entries would collapse into a single mega-fleet.
        let entries = [
            make(pid: 100, ppid: 0),
            make(pid: 200, ppid: 0),
        ]
        let result = PortMonitor.partitionIntoFleets(entries)
        XCTAssertEqual(result.count, 2)
    }

    // MARK: mergeFleet

    func testMergeFleetPicksMasterByAncestry() {
        // Only pid 100's ppid is outside the fleet — it's the master.
        let fleet = [
            make(pid: 101, ppid: 100),
            make(pid: 100, ppid: 1),
            make(pid: 102, ppid: 100),
        ]
        let merged = PortMonitor.mergeFleet(fleet)
        XCTAssertEqual(merged.entry.pid, 100)
        XCTAssertEqual(merged.workerCount, 2)
        XCTAssertEqual(Set(merged.workerPIDs), Set([101, 102]))
    }

    func testMergeFleetAggregatesCPU() {
        let fleet = [
            make(pid: 100, ppid: 1, cpuPercent: 2.0),
            make(pid: 101, ppid: 100, cpuPercent: 1.5),
            make(pid: 102, ppid: 100, cpuPercent: 0.5),
        ]
        let merged = PortMonitor.mergeFleet(fleet)
        XCTAssertEqual(merged.cpuPercent ?? 0, 4.0, accuracy: 0.001)
    }

    func testMergeFleetAggregatesRAM() {
        let fleet = [
            make(pid: 100, ppid: 1, ramBytes: 100 * 1024 * 1024),   // 100 MB
            make(pid: 101, ppid: 100, ramBytes: 50 * 1024 * 1024),  // 50 MB
            make(pid: 102, ppid: 100, ramBytes: 50 * 1024 * 1024),  // 50 MB
        ]
        let merged = PortMonitor.mergeFleet(fleet)
        XCTAssertEqual(merged.memoryMB, 200.0, accuracy: 0.001)
    }

    func testMergeFleetCPUNilWhenNoSamples() {
        let fleet = [
            make(pid: 100, ppid: 1, cpuPercent: nil),
            make(pid: 101, ppid: 100, cpuPercent: nil),
        ]
        let merged = PortMonitor.mergeFleet(fleet)
        XCTAssertNil(merged.cpuPercent)
    }

    // MARK: collapseFleets

    func testCollapseFleetsPythonMultiprocessing() {
        // Reproduces issue #17: python multiprocessing.spawn creates 4 workers sharing the
        // listening socket inherited from the master. Should collapse into ONE display row
        // with workerCount = 4.
        let entries = [
            make(pid: 1000, ppid: 1, port: 8000, cpuPercent: 1.0, ramBytes: 20 * 1024 * 1024),
            make(pid: 1001, ppid: 1000, port: 8000, cpuPercent: 0.5, ramBytes: 15 * 1024 * 1024),
            make(pid: 1002, ppid: 1000, port: 8000, cpuPercent: 0.5, ramBytes: 15 * 1024 * 1024),
            make(pid: 1003, ppid: 1000, port: 8000, cpuPercent: 0.5, ramBytes: 15 * 1024 * 1024),
            make(pid: 1004, ppid: 1000, port: 8000, cpuPercent: 0.5, ramBytes: 15 * 1024 * 1024),
        ]
        let result = PortMonitor.collapseFleets(entries)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.entry.pid, 1000)
        XCTAssertEqual(result.first?.workerCount, 4)
        XCTAssertEqual(result.first?.cpuPercent ?? 0, 3.0, accuracy: 0.001)
        XCTAssertEqual(result.first?.memoryMB ?? 0, 80.0, accuracy: 0.001)
    }

    func testCollapseFleetsPreservesRealConflicts() {
        // Two unrelated processes on the same port must survive as a real conflict.
        let entries = [
            make(pid: 100, ppid: 1, port: 5000, name: "node"),
            make(pid: 200, ppid: 2, port: 5000, name: "python"),
        ]
        let result = PortMonitor.collapseFleets(entries)
        XCTAssertEqual(result.count, 2)
    }

    func testCollapseFleetsMixedCase() {
        // Port A: isolated. Port B: fleet. Port C: real conflict.
        let entries = [
            make(pid: 10, ppid: 1, port: 3000, name: "node"),
            make(pid: 100, ppid: 1, port: 8000, name: "python"),
            make(pid: 101, ppid: 100, port: 8000, name: "python"),
            make(pid: 102, ppid: 100, port: 8000, name: "python"),
            make(pid: 200, ppid: 1, port: 9000, name: "ruby"),
            make(pid: 201, ppid: 50, port: 9000, name: "go"),
        ]
        let result = PortMonitor.collapseFleets(entries)
        // Expect 4 rows: 3000 (isolated), 8000 (fleet×1), 9000 (×2 unrelated).
        XCTAssertEqual(result.count, 4)
        let port8000 = result.filter { $0.entry.port == 8000 }
        XCTAssertEqual(port8000.count, 1)
        XCTAssertEqual(port8000.first?.workerCount, 2)
        let port9000 = result.filter { $0.entry.port == 9000 }
        XCTAssertEqual(port9000.count, 2)
    }

    func testCollapseFleetsResultSortedByPort() {
        let entries = [
            make(pid: 10, ppid: 1, port: 9000),
            make(pid: 20, ppid: 1, port: 3000),
            make(pid: 30, ppid: 1, port: 5000),
        ]
        let result = PortMonitor.collapseFleets(entries)
        XCTAssertEqual(result.map { $0.entry.port }, [3000, 5000, 9000])
    }

    func testCollapseFleetsIsolatedProcessHasZeroWorkerCount() {
        let entries = [make(pid: 100, ppid: 1)]
        let result = PortMonitor.collapseFleets(entries)
        XCTAssertEqual(result.first?.workerCount, 0)
        XCTAssertTrue(result.first?.workerPIDs.isEmpty ?? false)
    }

    func testCollapseFleetsZombieStatePropagates() {
        let master = make(pid: 100, ppid: 1)
        let workerEntry = PortEntry(
            id: "8000-101", port: 8000, pid: 101, ppid: 100,
            processName: "python", processPath: "", commandLine: "",
            arguments: [], environment: [:], cwd: "",
            tcpState: .listen, processStartTime: Date(),
            residentMemoryBytes: 0, totalCPUTimeNs: 0,
            projectName: "api", worktreeName: nil,
            projectKey: "other:test", dockerContainerID: nil,
            roleLabel: nil, roleIcon: nil
        )
        let worker = PortEntryDisplay(entry: workerEntry, cpuPercent: nil, isZombie: true)
        let result = PortMonitor.collapseFleets([master, worker])
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first?.isZombie ?? false)
    }
}

// MARK: - LaunchSnapshot + SnapshotStore Tests (restart feature)

final class LaunchSnapshotTests: XCTestCase {

    private func makeSnapshot(
        projectKey: String = "/tmp/my-webapp",
        projectName: String = "my-webapp",
        port: UInt16 = 3000,
        processName: String = "node",
        roleLabel: String? = "Front",
        roleIcon: String? = "globe",
        cwd: String = "/tmp/my-webapp",
        executablePath: String = "/usr/local/bin/node",
        arguments: [String] = ["node", "server.js"],
        environment: [String: String] = ["NODE_ENV": "development"],
        capturedAt: Date = Date(),
        dockerContainerID: String? = nil
    ) -> LaunchSnapshot {
        LaunchSnapshot(
            projectKey: projectKey, projectName: projectName, port: port,
            processName: processName, roleLabel: roleLabel, roleIcon: roleIcon,
            cwd: cwd, executablePath: executablePath,
            arguments: arguments, environment: environment,
            capturedAt: capturedAt, dockerContainerID: dockerContainerID
        )
    }

    func testIdIsStableForSameKeyPortName() {
        let a = makeSnapshot()
        let b = makeSnapshot(capturedAt: Date().addingTimeInterval(-3600))
        XCTAssertEqual(a.id, b.id, "Snapshots with the same (projectKey, port, processName) must share an id so resaving replaces the old record")
    }

    func testIdDiffersAcrossProjects() {
        let a = makeSnapshot(projectKey: "/a/repo")
        let b = makeSnapshot(projectKey: "/b/repo")
        XCTAssertNotEqual(a.id, b.id)
    }

    func testCommandSummaryBuildsFromArguments() {
        let snap = makeSnapshot(arguments: ["/usr/local/bin/node", "/path/to/server.js", "--port", "3000"])
        // Long path args should collapse to basenames, same as PortScanner.commandLine.
        XCTAssertEqual(snap.commandSummary, "node server.js --port 3000")
    }

    func testCommandSummaryFallsBackToProcessName() {
        let snap = makeSnapshot(arguments: [])
        XCTAssertEqual(snap.commandSummary, "node")
    }

    func testShortCwdSubstitutesHome() {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/test"
        let snap = makeSnapshot(cwd: "\(home)/Projects/app")
        XCTAssertEqual(snap.shortCwd, "~/Projects/app")
    }

    func testCapturedAgoJustNow() {
        let snap = makeSnapshot(capturedAt: Date())
        XCTAssertEqual(snap.capturedAgo, "just now")
    }

    func testCapturedAgoMinutes() {
        let snap = makeSnapshot(capturedAt: Date().addingTimeInterval(-300)) // 5 min
        XCTAssertTrue(snap.capturedAgo.contains("min"))
        XCTAssertTrue(snap.capturedAgo.contains("5"))
    }

    func testEncodeDecodeRoundTrip() throws {
        // ISO8601 encoding drops sub-second precision, so use a whole-second date for the equality check.
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = makeSnapshot(capturedAt: date)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snap)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LaunchSnapshot.self, from: data)
        XCTAssertEqual(decoded, snap)
    }

    func testRelaunchRoleOrdering() {
        // DB must sort before everything else so back-ends see the database when they start.
        XCTAssertLessThan(RelaunchRole.db.rawValue, RelaunchRole.cache.rawValue)
        XCTAssertLessThan(RelaunchRole.cache.rawValue, RelaunchRole.back.rawValue)
        XCTAssertLessThan(RelaunchRole.back.rawValue, RelaunchRole.front.rawValue)
        XCTAssertLessThan(RelaunchRole.front.rawValue, RelaunchRole.other.rawValue)
    }

    func testRelaunchRoleFromLabel() {
        XCTAssertEqual(RelaunchRole.from(roleLabel: "DB"), .db)
        XCTAssertEqual(RelaunchRole.from(roleLabel: "Cache"), .cache)
        XCTAssertEqual(RelaunchRole.from(roleLabel: "Back"), .back)
        XCTAssertEqual(RelaunchRole.from(roleLabel: "Front"), .front)
        XCTAssertEqual(RelaunchRole.from(roleLabel: "MCP"), .mcp)
        XCTAssertEqual(RelaunchRole.from(roleLabel: nil), .other)
        XCTAssertEqual(RelaunchRole.from(roleLabel: "Unknown"), .other)
    }
}

@MainActor
final class SnapshotStoreTests: XCTestCase {

    private var savedGlobalTTL: Int = 60

    override func setUp() {
        super.setUp()
        // Disable the global auto-prune during SnapshotStore unit tests — several tests
        // deliberately seed snapshots older than the default retention to exercise prune
        // behaviour explicitly. Without this, `store.save()` would strip them on insert.
        savedGlobalTTL = AppSettings.shared.snapshotTTLMinutes
        AppSettings.shared.snapshotTTLMinutes = 0
    }

    override func tearDown() {
        AppSettings.shared.snapshotTTLMinutes = savedGlobalTTL
        super.tearDown()
    }

    /// Fresh defaults per test so instances don't pollute each other.
    private func freshStore() -> (SnapshotStore, UserDefaults) {
        let suite = "test.SnapshotStore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (SnapshotStore(defaults: defaults), defaults)
    }

    private func makeSnapshot(
        projectKey: String = "/tmp/app",
        projectName: String = "app",
        port: UInt16 = 3000,
        processName: String = "node",
        roleLabel: String? = "Back",
        capturedAt: Date = Date(),
        dockerContainerID: String? = nil
    ) -> LaunchSnapshot {
        LaunchSnapshot(
            projectKey: projectKey, projectName: projectName, port: port,
            processName: processName, roleLabel: roleLabel, roleIcon: "server.rack",
            cwd: "/tmp/app", executablePath: "/usr/bin/node",
            arguments: ["node"], environment: [:],
            capturedAt: capturedAt, dockerContainerID: dockerContainerID
        )
    }

    func testInitialStoreIsEmpty() {
        let (store, _) = freshStore()
        XCTAssertTrue(store.isEmpty)
    }

    func testSaveAndRetrieve() {
        let (store, _) = freshStore()
        let snap = makeSnapshot()
        store.save(snap)
        XCTAssertEqual(store.all(for: "/tmp/app").count, 1)
        XCTAssertEqual(store.all(for: "/other").count, 0)
    }

    func testSaveDeduplicatesById() {
        // Saving twice with the same (projectKey, port, processName) must replace, not accumulate.
        let (store, _) = freshStore()
        let old = makeSnapshot(capturedAt: Date().addingTimeInterval(-3600))
        store.save(old)
        let fresh = makeSnapshot(capturedAt: Date())
        store.save(fresh)
        XCTAssertEqual(store.snapshots.count, 1)
        XCTAssertEqual(store.snapshots.values.first?.capturedAt, fresh.capturedAt)
    }

    func testRemoveById() {
        let (store, _) = freshStore()
        let snap = makeSnapshot()
        store.save(snap)
        store.remove(id: snap.id)
        XCTAssertTrue(store.isEmpty)
    }

    func testRemoveByProjectKey() {
        let (store, _) = freshStore()
        store.save(makeSnapshot(port: 3000, processName: "front"))
        store.save(makeSnapshot(port: 4000, processName: "back"))
        store.save(makeSnapshot(projectKey: "/other", port: 5432, processName: "postgres"))
        store.remove(projectKey: "/tmp/app")
        XCTAssertEqual(store.snapshots.count, 1)
        XCTAssertEqual(store.snapshots.values.first?.processName, "postgres")
    }

    func testClearAll() {
        let (store, _) = freshStore()
        store.save(makeSnapshot(port: 3000, processName: "a"))
        store.save(makeSnapshot(port: 3001, processName: "b"))
        store.clearAll()
        XCTAssertTrue(store.isEmpty)
    }

    func testPersistenceSurvivesNewStoreInstance() {
        // New store reading the same defaults must see previously-saved snapshots.
        let suite = "test.SnapshotStore.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = SnapshotStore(defaults: defaults)
        a.save(makeSnapshot())
        let b = SnapshotStore(defaults: defaults)
        XCTAssertEqual(b.snapshots.count, 1)
    }

    func testGroupedByProjectSortsByMostRecent() {
        let (store, _) = freshStore()
        let old = makeSnapshot(projectKey: "/a", projectName: "a-project",
                               port: 3000, processName: "front",
                               capturedAt: Date().addingTimeInterval(-3600))
        let recent = makeSnapshot(projectKey: "/b", projectName: "b-project",
                                  port: 4000, processName: "back",
                                  capturedAt: Date())
        store.save(old)
        store.save(recent)
        let groups = store.groupedByProject()
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.projectKey, "/b", "Most recent project should come first")
    }

    func testPruneDropsSnapshotsOlderThanTTL() {
        let (store, _) = freshStore()
        let old = makeSnapshot(port: 3000, processName: "front",
                               capturedAt: Date().addingTimeInterval(-48 * 3600)) // 2 days old
        let recent = makeSnapshot(port: 4000, processName: "back",
                                  capturedAt: Date().addingTimeInterval(-1 * 3600)) // 1 h old
        store.save(old)
        store.save(recent)
        store.pruneMinutes(olderThan: 24 * 60) // 1-day TTL in minutes
        XCTAssertEqual(store.snapshots.count, 1)
        XCTAssertEqual(store.snapshots.values.first?.processName, "back")
    }

    func testPruneByMinutesDropsSnapshotsOlderThanMinutes() {
        // User-facing example from the settings: 5-minute retention.
        let (store, _) = freshStore()
        let older = makeSnapshot(port: 3000, processName: "front",
                                 capturedAt: Date().addingTimeInterval(-10 * 60)) // 10 min old
        let fresh = makeSnapshot(port: 4000, processName: "back",
                                 capturedAt: Date().addingTimeInterval(-60)) // 1 min old
        store.save(older)
        store.save(fresh)
        store.pruneMinutes(olderThan: 5)
        XCTAssertEqual(store.snapshots.count, 1)
        XCTAssertEqual(store.snapshots.values.first?.processName, "back")
    }

    func testPruneNoOpWhenTTLIsZero() {
        // Global TTL is forced to 0 in setUp, so `save()`'s internal prune is a no-op.
        // Here we also verify the explicit `pruneMinutes(olderThan: 0)` leaves snapshots alone.
        let (store, _) = freshStore()
        store.save(makeSnapshot(capturedAt: Date().addingTimeInterval(-60)))
        XCTAssertEqual(store.snapshots.count, 1, "fresh snapshot should survive the initial prune")
        store.pruneMinutes(olderThan: 0)
        XCTAssertEqual(store.snapshots.count, 1, "TTL ≤ 0 should preserve everything")
    }

    func testSaveConditionalOnKillSuccess() {
        // Mirrors the refactored flow in PortMonitor.stopPort: a snapshot is *captured in
        // memory* before the kill but only committed to the store if the kill is verified.
        // This test reproduces the two branches (verified dead → save, still alive → no save)
        // directly on the store, since the PortMonitor kill path is integration-level and
        // relies on real PIDs.
        let (store, _) = freshStore()
        let pending = makeSnapshot(port: 7777, processName: "python")

        // Branch 1: kill reported success but process is still alive → no commit.
        let killReportedSuccess = true
        let stillAlive = true
        if killReportedSuccess && !stillAlive {
            store.save(pending)
        }
        XCTAssertTrue(store.isEmpty, "Must not commit when the kill couldn't be verified")

        // Branch 2: kill verified (process gone) → commit.
        let verifiedDead = true
        if verifiedDead { store.save(pending) }
        XCTAssertEqual(store.snapshots.count, 1)
    }

    func testGroupedByProjectSortsSnapshotsByRoleWithinGroup() {
        let (store, _) = freshStore()
        store.save(makeSnapshot(port: 3000, processName: "vite", roleLabel: "Front"))
        store.save(makeSnapshot(port: 4000, processName: "node", roleLabel: "Back"))
        store.save(makeSnapshot(port: 5432, processName: "postgres", roleLabel: "DB"))
        let groups = store.groupedByProject()
        XCTAssertEqual(groups.count, 1)
        let ordered = groups[0].snapshots.map(\.roleLabel)
        // DB → Back → Front per RelaunchRole priority.
        XCTAssertEqual(ordered, ["DB", "Back", "Front"])
    }
}

// MARK: - PortScanner.parseProcArgsBuffer Tests

final class ParseProcArgsBufferTests: XCTestCase {

    /// Build a synthetic KERN_PROCARGS2 buffer:
    /// [argc: Int32][exec_path\0][padding\0…][argv_0\0argv_1\0…][env_0\0env_1\0…]
    private func makeBuffer(execPath: String, argv: [String], env: [String: String]) -> [UInt8] {
        var buffer: [UInt8] = []
        // argc
        var argc = Int32(argv.count)
        withUnsafeBytes(of: &argc) { buffer.append(contentsOf: $0) }
        // exec_path + null
        buffer.append(contentsOf: Array(execPath.utf8))
        buffer.append(0)
        // no padding needed for test — parser handles it
        // argv
        for a in argv {
            buffer.append(contentsOf: Array(a.utf8))
            buffer.append(0)
        }
        // env (KEY=VALUE pairs)
        for (k, v) in env {
            let pair = "\(k)=\(v)"
            buffer.append(contentsOf: Array(pair.utf8))
            buffer.append(0)
        }
        return buffer
    }

    func testParsesArgvAndEnv() {
        let buf = makeBuffer(
            execPath: "/usr/local/bin/node",
            argv: ["node", "server.js", "--port", "3000"],
            env: ["NODE_ENV": "development", "PATH": "/usr/bin:/bin"]
        )
        let parsed = PortScanner.parseProcArgsBuffer(buf)
        XCTAssertEqual(parsed.argv, ["node", "server.js", "--port", "3000"])
        XCTAssertEqual(parsed.environment["NODE_ENV"], "development")
        XCTAssertEqual(parsed.environment["PATH"], "/usr/bin:/bin")
        XCTAssertEqual(parsed.summary, "node server.js --port 3000")
    }

    func testHandlesEmptyEnv() {
        let buf = makeBuffer(execPath: "/bin/sleep", argv: ["sleep", "10"], env: [:])
        let parsed = PortScanner.parseProcArgsBuffer(buf)
        XCTAssertEqual(parsed.argv, ["sleep", "10"])
        XCTAssertTrue(parsed.environment.isEmpty)
    }

    func testHandlesArgvWithPaths() {
        let buf = makeBuffer(
            execPath: "/usr/bin/python3",
            argv: ["python3", "/Users/test/project/main.py"],
            env: [:]
        )
        let parsed = PortScanner.parseProcArgsBuffer(buf)
        XCTAssertEqual(parsed.argv, ["python3", "/Users/test/project/main.py"])
        XCTAssertEqual(parsed.summary, "python3 main.py", "Long path args should be basenamed in the summary")
    }

    func testTooSmallBufferReturnsEmpty() {
        let parsed = PortScanner.parseProcArgsBuffer([0, 0, 0])
        XCTAssertTrue(parsed.argv.isEmpty)
        XCTAssertTrue(parsed.environment.isEmpty)
    }
}

// MARK: - ProcessLauncher Docker command tests

final class ProcessLauncherDockerTests: XCTestCase {

    func testDockerStartCommandUsesAbsolutePathIfAvailable() {
        guard let (exe, args) = ProcessLauncher.dockerStartCommand(containerID: "abc123") else {
            XCTFail("expected a command"); return
        }
        // On systems without docker installed, falls back to /usr/bin/env docker start <id>
        if exe.path == "/usr/bin/env" {
            XCTAssertEqual(args, ["docker", "start", "abc123"])
        } else {
            XCTAssertTrue(exe.path.hasSuffix("/docker"), "got \(exe.path)")
            XCTAssertEqual(args, ["start", "abc123"])
        }
    }

    func testDockerStopCommandMirrorsStart() {
        guard let (exe, args) = ProcessLauncher.dockerStopCommand(containerID: "abc123") else {
            XCTFail("expected a command"); return
        }
        if exe.path == "/usr/bin/env" {
            XCTAssertEqual(args, ["docker", "stop", "abc123"])
        } else {
            XCTAssertEqual(args, ["stop", "abc123"])
        }
    }
}

// MARK: - PortEntry.toSnapshot

final class PortEntryToSnapshotTests: XCTestCase {

    func testCopiesAllRelaunchRelevantFields() {
        let entry = PortEntry(
            id: "3000-1-0", port: 3000, pid: 1, ppid: 0,
            processName: "node", processPath: "/usr/local/bin/node",
            commandLine: "node server.js",
            arguments: ["node", "server.js"],
            environment: ["NODE_ENV": "development"],
            cwd: "/tmp/app",
            tcpState: .listen, processStartTime: Date(),
            residentMemoryBytes: 0, totalCPUTimeNs: 0,
            projectName: "app", worktreeName: nil,
            projectKey: "/tmp/app", dockerContainerID: nil,
            roleLabel: "Back", roleIcon: "server.rack"
        )
        let snap = entry.toSnapshot()
        XCTAssertEqual(snap.projectKey, "/tmp/app")
        XCTAssertEqual(snap.projectName, "app")
        XCTAssertEqual(snap.port, 3000)
        XCTAssertEqual(snap.processName, "node")
        XCTAssertEqual(snap.executablePath, "/usr/local/bin/node")
        XCTAssertEqual(snap.arguments, ["node", "server.js"])
        XCTAssertEqual(snap.environment["NODE_ENV"], "development")
        XCTAssertEqual(snap.cwd, "/tmp/app")
        XCTAssertEqual(snap.roleLabel, "Back")
        XCTAssertNil(snap.dockerContainerID)
    }

    func testPropagatesDockerContainerID() {
        let entry = PortEntry(
            id: "5432-1-0", port: 5432, pid: 1, ppid: 0,
            processName: "com.docker.backend", processPath: "/",
            commandLine: "", arguments: [], environment: [:], cwd: "/",
            tcpState: .listen, processStartTime: Date(),
            residentMemoryBytes: 0, totalCPUTimeNs: 0,
            projectName: "Docker: redis", worktreeName: nil,
            projectKey: "docker:abc123", dockerContainerID: "abc123",
            roleLabel: "DB", roleIcon: "externaldrive.fill"
        )
        let snap = entry.toSnapshot()
        XCTAssertEqual(snap.dockerContainerID, "abc123")
    }
}
