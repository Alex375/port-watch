import SwiftUI

@main
struct PortWatchApp: App {
    @State private var monitor = PortMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(monitor: monitor)
                .frame(width: 420)
        } label: {
            Label("\(monitor.portCount)", systemImage: menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        if monitor.hasZombie {
            return "eye.trianglebadge.exclamationmark"
        }
        let count = monitor.projectPortCount
        switch count {
        case 0:     return "eye.slash"
        case 1...3: return "eye"
        case 4...8: return "eye.fill"
        default:    return "eye.trianglebadge.exclamationmark"
        }
    }
}

struct MenuContentView: View {
    @Bindable var monitor: PortMonitor
    @State private var showSettings = false
    @State private var isRefreshing = false
    @State private var updater = UpdateChecker.shared
    @State private var hasCheckedUpdate = false

    var body: some View {
        Group {
            if showSettings {
                SettingsView(settings: monitor.settings) {
                    showSettings = false
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                mainContent
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showSettings)
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(monitor.portCount) open port\(monitor.portCount == 1 ? "" : "s")")
                        .font(.headline)
                    if let date = monitor.lastScanDate {
                        Text("Scanned at \(date.formatted(.dateTime.hour().minute().second()))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    Task {
                        isRefreshing = true
                        await monitor.performScan()
                        isRefreshing = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Kill report banner
            if let report = monitor.lastKillReport {
                HStack(spacing: 6) {
                    Image(systemName: report.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(report.isError ? .red : .green)
                        .font(.caption)
                    Text(report.message)
                        .font(.caption2)
                        .lineLimit(3)
                    Spacer()
                    Button {
                        monitor.lastKillReport = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(report.isError ? Color.red.opacity(0.08) : Color.green.opacity(0.08))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Update banner
            if updater.updateAvailable, let version = updater.latestVersion {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                    Text("v\(version) available")
                        .font(.caption2)
                        .fontWeight(.medium)
                    Spacer()
                    if updater.isDownloading {
                        ProgressView(value: updater.downloadProgress)
                            .frame(width: 60)
                            .controlSize(.mini)
                    } else {
                        Button("Update") {
                            Task { await updater.performUpdate() }
                        }
                        .font(.caption2)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.08))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider()

            if monitor.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "eye.slash")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No open ports detected")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(monitor.groupedEntries, id: \.projectName) { group in
                            projectSection(group)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 600)
                .fixedSize(horizontal: false, vertical: true)
            }

            // Kill confirmation banner
            if let entry = monitor.pendingKillConfirmation {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text("Kill unidentified process?")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    Text("\(entry.processName) on :\(entry.port) (PID \(entry.pid)) is not part of an identified project. Killing it could affect your system.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Spacer()
                        Button("Cancel") {
                            monitor.pendingKillConfirmation = nil
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        Button("Kill") {
                            let e = entry
                            monitor.pendingKillConfirmation = nil
                            Task { await monitor.killPort(e) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .font(.caption)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.06))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Divider()

            // Footer
            HStack {
                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gear")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .animation(.easeInOut(duration: 0.25), value: monitor.lastKillReport?.message)
        .animation(.easeInOut(duration: 0.25), value: monitor.pendingKillConfirmation?.pid)
        .task {
            if !hasCheckedUpdate {
                hasCheckedUpdate = true
                await updater.checkForUpdate()
            }
        }
    }

    // MARK: - Project section

    @ViewBuilder
    private func projectSection(_ group: ProjectGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Project header
            HStack(spacing: 8) {
                Circle()
                    .fill(group.projectName == "Other" ? Color.gray : Color.blue)
                    .frame(width: 10, height: 10)
                Text(group.projectName)
                    .font(.headline)
                Spacer()
                Text("\(group.entries.count) port\(group.entries.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                // Kill all button for project
                if group.projectName != "Other" {
                    let isKilling = group.entries.contains { monitor.killingPIDs.contains($0.entry.pid) }
                    if isKilling {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 14, height: 14)
                    } else {
                        HoverButton(icon: "xmark.circle", color: .red, size: .caption, help: "Kill all processes in \(group.projectName)") {
                            Task { await monitor.killProject(group) }
                        }
                    }
                }
            }

            // Port entries
            ForEach(group.entries) { display in
                portRow(display)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }

    // MARK: - Port row

    @ViewBuilder
    private func portRow(_ display: PortEntryDisplay) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Status indicator
            Circle()
                .fill(statusColor(for: display))
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(":" + String(display.entry.port))
                        .font(.system(.callout, design: .monospaced))
                        .fontWeight(.semibold)
                    Text(display.entry.processName)
                        .font(.callout)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("PID " + String(display.entry.pid))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(display.entry.uptimeFormatted)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    // Open in browser
                    HoverButton(icon: "globe", color: .blue, help: "Open in browser") {
                        if let url = URL(string: "http://localhost:\(display.entry.port)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    // Kill
                    if monitor.killingPIDs.contains(display.entry.pid) {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 12, height: 12)
                    } else {
                        HoverButton(icon: "xmark.circle.fill", color: .red, help: "Kill process") {
                            if display.entry.projectName == "Other" {
                                monitor.pendingKillConfirmation = display.entry
                            } else {
                                Task { await monitor.killPort(display.entry) }
                            }
                        }
                    }
                }
                if !display.commandSummary.isEmpty {
                    Text(display.commandSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                HStack(spacing: 4) {
                    if let icon = display.entry.roleIcon, let label = display.entry.roleLabel {
                        HStack(spacing: 3) {
                            Image(systemName: icon)
                                .font(.system(size: 8))
                            Text(label)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(roleColor(label))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(roleColor(label).opacity(0.12), in: Capsule())
                    }
                    if !display.entry.cwd.isEmpty {
                        Image(systemName: "folder")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                        Text(display.entry.shortCwd)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                warningBadges(display)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Warning badges

    @ViewBuilder
    private func warningBadges(_ display: PortEntryDisplay) -> some View {
        let s = monitor.settings
        let isConflict = monitor.conflictPorts.contains(display.entry.port)
        let cpuOver = (display.cpuPercent ?? 0) > s.cpuThreshold
        let ramOver = display.entry.memoryMB > s.ramThresholdMB
        let hasWarning = display.entry.tcpState.isZombie || cpuOver || ramOver || isConflict
        if hasWarning {
            HStack(spacing: 4) {
                if isConflict {
                    iconBadge("arrow.triangle.branch", "conflict", color: .secondary)
                }
                if display.entry.tcpState.isZombie {
                    iconBadge("xmark.seal.fill", "ZOMBIE", color: .red)
                }
                if let cpu = display.cpuPercent, cpu > s.cpuThreshold {
                    iconBadge("exclamationmark.triangle.fill", String(format: "%.0f%% CPU", cpu), color: .orange)
                }
                if ramOver {
                    iconBadge("exclamationmark.triangle.fill", String(format: "%.0f MB", display.entry.memoryMB), color: .orange)
                }
            }
        }
    }

    private func iconBadge(_ icon: String, _ text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 7))
            Text(text)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Helpers

    private func roleColor(_ label: String) -> Color {
        switch label {
        case "Front": return Color(nsColor: .systemBlue)
        case "Back":  return Color(nsColor: .systemIndigo)
        case "DB":    return Color(nsColor: .systemBrown)
        case "Cache": return Color(nsColor: .systemGray)
        default:      return Color.secondary
        }
    }

    private func statusColor(for display: PortEntryDisplay) -> Color {
        if display.entry.tcpState.isZombie { return .red }
        if let cpu = display.cpuPercent, cpu > monitor.settings.cpuThreshold { return .orange }
        return .green
    }
}

// MARK: - Hover Button

struct HoverButton: View {
    let icon: String
    let color: Color
    var size: Font = .caption2
    var help: String = ""
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(size)
                .foregroundStyle(color.opacity(isHovered ? 1.0 : 0.5))
                .scaleEffect(isHovered ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.borderless)
        .help(help)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
