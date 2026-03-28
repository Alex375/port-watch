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
            projectName: "MyApp", roleLabel: nil, roleIcon: nil
        )
        let entry2 = PortEntry(
            id: "3001-2-0", port: 3001, pid: 2,
            processName: "python", processPath: "", commandLine: "", cwd: "",
            tcpState: .listen, processStartTime: Date(),
            residentMemoryBytes: 0, totalCPUTimeNs: 0,
            projectName: "MyApp", roleLabel: nil, roleIcon: nil
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
            dbProc: ["postgres"]
        )
        XCTAssertEqual(kw.front, ["front", "web"])
        XCTAssertEqual(kw.back, ["api", "server"])
        XCTAssertEqual(kw.db, ["db"])
        XCTAssertEqual(kw.dbProc, ["postgres"])
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
            dbProc: ["postgres"]
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
        // Use a cwd that doesn't match any git root, so we test the known-port fallback
        // only when Docker is not mapping this port.
        let name = ProjectDetector.detectProject(cwd: "", port: 5432)
        // Accept either the known-port name or a Docker container name
        let isExpected = name == "PostgreSQL" || name.hasPrefix("Docker:")
        XCTAssertTrue(isExpected, "Port 5432 should be 'PostgreSQL' or Docker, got: \(name)")
    }

    func testKnownPortMySQL() {
        let name = ProjectDetector.detectProject(cwd: "", port: 3306)
        XCTAssertEqual(name, "MySQL")
    }

    func testKnownPortRedis() {
        let name = ProjectDetector.detectProject(cwd: "", port: 6379)
        XCTAssertEqual(name, "Redis")
    }

    func testKnownPortMongoDB() {
        let name = ProjectDetector.detectProject(cwd: "", port: 27017)
        XCTAssertEqual(name, "MongoDB")
    }

    func testKnownPortElasticsearch() {
        let name = ProjectDetector.detectProject(cwd: "", port: 9200)
        XCTAssertEqual(name, "Elasticsearch")
    }

    func testUnknownPortAndEmptyCwd() {
        let name = ProjectDetector.detectProject(cwd: "", port: 12345)
        XCTAssertEqual(name, "Other")
    }

    func testUnknownPortWithNonGitCwd() {
        // Use a directory that exists but has no .git
        let name = ProjectDetector.detectProject(cwd: "/tmp", port: 55555)
        XCTAssertEqual(name, "Other")
    }

    func testDetectProjectWithGitDirectory() throws {
        // Create a temp directory with a .git folder
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortWatchTest-\(UUID().uuidString)")
        let gitDir = tempDir.appendingPathComponent(".git")

        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let name = ProjectDetector.detectProject(cwd: tempDir.path, port: 9999)
        // Should return the folder name containing .git
        XCTAssertEqual(name, tempDir.lastPathComponent)
    }

    func testDetectProjectWithGitInParentDirectory() throws {
        // Create a temp directory structure: root/.git and root/subdir
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortWatchTest-\(UUID().uuidString)")
        let gitDir = tempDir.appendingPathComponent(".git")
        let subDir = tempDir.appendingPathComponent("src").appendingPathComponent("backend")

        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let name = ProjectDetector.detectProject(cwd: subDir.path, port: 9999)
        // Should walk up and find the root directory name
        XCTAssertEqual(name, tempDir.lastPathComponent)
    }

    func testDetectProjectGitTakesPriorityOverKnownPort() throws {
        // Even for a known port, if there's a git root, it should use the git project name.
        // Use port 9200 (Elasticsearch) instead of 5432 to avoid Docker interference.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PortWatchTest-\(UUID().uuidString)")
        let gitDir = tempDir.appendingPathComponent(".git")

        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let name = ProjectDetector.detectProject(cwd: tempDir.path, port: 9200)
        // Git root should take priority over known port.
        // Docker could still claim this port, but that's very unlikely for 9200.
        let isGitName = name == tempDir.lastPathComponent
        let isDocker = name.hasPrefix("Docker:")
        XCTAssertTrue(isGitName || isDocker,
                       "Should detect git project or Docker, got: \(name)")
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
        let savedNotif = settings.notificationsEnabled
        let savedConflict = settings.notifyPortConflicts
        let savedFront = settings.frontKeywords
        let savedBack = settings.backKeywords
        let savedDB = settings.dbKeywords
        let savedDBProc = settings.dbProcessNames

        defer {
            // Restore original values
            settings.cpuThreshold = savedCPU
            settings.ramThresholdMB = savedRAM
            settings.refreshInterval = savedRefresh
            settings.notificationsEnabled = savedNotif
            settings.notifyPortConflicts = savedConflict
            settings.frontKeywords = savedFront
            settings.backKeywords = savedBack
            settings.dbKeywords = savedDB
            settings.dbProcessNames = savedDBProc
        }

        settings.resetToDefaults()

        XCTAssertEqual(settings.cpuThreshold, 50.0)
        XCTAssertEqual(settings.ramThresholdMB, 500.0)
        XCTAssertEqual(settings.refreshInterval, 10.0)
        XCTAssertEqual(settings.notificationsEnabled, false)
        XCTAssertEqual(settings.notifyPortConflicts, true)
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
        let savedNotif = settings.notificationsEnabled
        let savedConflict = settings.notifyPortConflicts
        let savedFront = settings.frontKeywords
        let savedBack = settings.backKeywords
        let savedDB = settings.dbKeywords
        let savedDBProc = settings.dbProcessNames

        defer {
            // Restore original values
            settings.cpuThreshold = savedCPU
            settings.ramThresholdMB = savedRAM
            settings.refreshInterval = savedRefresh
            settings.notificationsEnabled = savedNotif
            settings.notifyPortConflicts = savedConflict
            settings.frontKeywords = savedFront
            settings.backKeywords = savedBack
            settings.dbKeywords = savedDB
            settings.dbProcessNames = savedDBProc
        }

        // Modify all values
        settings.cpuThreshold = 90.0
        settings.ramThresholdMB = 2000.0
        settings.refreshInterval = 30.0
        settings.notificationsEnabled = true
        settings.notifyPortConflicts = false
        settings.frontKeywords = ["custom"]
        settings.backKeywords = ["custom"]
        settings.dbKeywords = ["custom"]
        settings.dbProcessNames = ["custom"]

        // Verify they changed
        XCTAssertEqual(settings.cpuThreshold, 90.0)
        XCTAssertEqual(settings.ramThresholdMB, 2000.0)
        XCTAssertEqual(settings.refreshInterval, 30.0)
        XCTAssertEqual(settings.notificationsEnabled, true)
        XCTAssertEqual(settings.notifyPortConflicts, false)

        // Reset
        settings.resetToDefaults()

        // Verify all back to defaults
        XCTAssertEqual(settings.cpuThreshold, 50.0)
        XCTAssertEqual(settings.ramThresholdMB, 500.0)
        XCTAssertEqual(settings.refreshInterval, 10.0)
        XCTAssertEqual(settings.notificationsEnabled, false)
        XCTAssertEqual(settings.notifyPortConflicts, true)
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
