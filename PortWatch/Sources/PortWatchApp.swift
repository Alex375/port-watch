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
    @State private var isOtherCollapsed = true
    @State private var isStoppedCollapsed = false
    /// Measured height of the port list content. Drives the ScrollView's frame height explicitly,
    /// so that expanding a row animates the container smoothly instead of oscillating between
    /// "fits" and "scrolls" states (would trigger scroll-bar flicker — issue #20).
    @State private var portsContentHeight: CGFloat = 0

    /// Scan indicator color: green when healthy, orange while scanning.
    private var scanDotColor: Color {
        isRefreshing ? .orange : .green
    }

    /// App version from Info.plist (CFBundleShortVersionString).
    private var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

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
            // Header — hero count + live scan indicator
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(monitor.portCount)")
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                            .animation(.easeInOut(duration: 0.2), value: monitor.portCount)
                        Text(monitor.portCount == 1 ? "open port" : "open ports")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 5) {
                        // Pulsing dot — green when recently scanned
                        Circle()
                            .fill(scanDotColor)
                            .frame(width: 5, height: 5)
                            .overlay(
                                Circle()
                                    .stroke(scanDotColor.opacity(0.4), lineWidth: 4)
                                    .scaleEffect(isRefreshing ? 1.8 : 1.0)
                                    .opacity(isRefreshing ? 0 : 0.6)
                                    .animation(
                                        isRefreshing
                                            ? .easeOut(duration: 1.0).repeatForever(autoreverses: false)
                                            : .default,
                                        value: isRefreshing
                                    )
                            )
                        if let date = monitor.lastScanDate {
                            Text(isRefreshing ? "Scanning…" : "Updated \(date.formatted(.dateTime.hour().minute().second()))")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
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
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                        .frame(width: 22, height: 22)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
                .help("Refresh now")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Update banner — persistent (stays until user clicks Update), same card style as kill banner
            if updater.updateAvailable, let version = updater.latestVersion {
                updateBanner(version: version)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()

            Group {
                if monitor.entries.isEmpty && monitor.stoppedGroups.isEmpty {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.10))
                                .frame(width: 56, height: 56)
                            Image(systemName: "checkmark")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.green)
                        }
                        VStack(spacing: 3) {
                            Text("All clear")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("No TCP ports currently open.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .transition(.opacity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(monitor.groupedEntries, id: \.projectName) { group in
                                projectSection(group)
                            }
                            if !monitor.stoppedGroups.isEmpty {
                                if !monitor.entries.isEmpty {
                                    Divider().opacity(0.4)
                                }
                                recentlyStoppedSection
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { h in
                            portsContentHeight = h
                        }
                    }
                    // `.fixedSize(vertical:)` lets the ScrollView take the content's intrinsic
                    // height so the MenuBarExtra window grows/shrinks smoothly as rows expand.
                    // Hiding the indicator when content fits inside 600pt prevents the scroll
                    // bar from flashing briefly during the collapse animation (#20).
                    .frame(maxHeight: 600)
                    .fixedSize(horizontal: false, vertical: true)
                    .scrollIndicators(portsContentHeight > 600 ? .automatic : .never)
                }
            }
            // Kill report banner sits on TOP of the ports area as a floating overlay.
            // It does not shift the ports list or the footer.
            .overlay(alignment: .top) {
                if let report = monitor.lastKillReport {
                    killReportBanner(report)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            Divider().opacity(0.6)

            // Footer — Settings / version / Quit
            HStack(spacing: 0) {
                FooterButton(icon: "gearshape", label: "Settings") {
                    showSettings.toggle()
                }
                Spacer()
                if let version = appVersion {
                    Text("v\(version)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                FooterButton(icon: "power", label: "Quit", tint: .red.opacity(0.85)) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .animation(.easeInOut(duration: 0.25), value: monitor.lastKillReport?.message)
        .animation(.easeInOut(duration: 0.25), value: monitor.pendingKillConfirmation?.entry.pid)
    }

    // MARK: - Update banner

    @ViewBuilder
    private func updateBanner(version: String) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.blue)
                .frame(width: 3)
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 13))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Update available")
                        .font(.system(size: 11, weight: .semibold))
                    Text("v\(version)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if updater.isDownloading {
                    ProgressView(value: updater.downloadProgress)
                        .frame(width: 70)
                        .controlSize(.mini)
                } else {
                    Button {
                        Task { await updater.performUpdate() }
                    } label: {
                        Text("Update")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.08))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.blue.opacity(0.25), lineWidth: 0.5)
        )
    }

    // MARK: - Kill report banner (overlay)

    @ViewBuilder
    private func killReportBanner(_ report: KillReport) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(report.isError ? Color.red : Color.green)
                .frame(width: 3)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: report.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(report.isError ? .red : .green)
                    .font(.system(size: 12))
                    .padding(.top, 1)
                Text(report.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Button {
                    withAnimation { monitor.lastKillReport = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
        }
        // Solid base + subtle colored tint on top — fully opaque so ports below don't bleed through.
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 8).fill((report.isError ? Color.red : Color.green).opacity(0.10))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder((report.isError ? Color.red : Color.green).opacity(0.25), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
    }

    // MARK: - Project section

    @ViewBuilder
    private func projectSection(_ group: ProjectGroup) -> some View {
        let isOther = group.projectName == "Other"
        let isKilling = group.entries.contains { monitor.killingPIDs.contains($0.entry.pid) }

        VStack(alignment: .leading, spacing: 6) {
            // Project header — cleaner, more breathing room
            HStack(spacing: 8) {
                if isOther {
                    Image(systemName: isOtherCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                        .animation(.easeInOut(duration: 0.15), value: isOtherCollapsed)
                }

                Text(group.projectName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOther ? .secondary : .primary)

                Text("\(group.entries.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.10), in: Capsule())

                Spacer()

                if !isOther {
                    if isKilling {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        HoverButton(
                            icon: "power.circle.fill",
                            color: .red.opacity(0.85),
                            size: .system(size: 16),
                            help: "Stop all processes in \(group.projectName) (snapshots saved for restart)"
                        ) {
                            Task { await monitor.stopProject(group) }
                        }
                    }
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onTapGesture {
                if isOther {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isOtherCollapsed.toggle()
                    }
                }
            }

            // Port entries
            if !isOther || !isOtherCollapsed {
                VStack(spacing: 6) {
                    ForEach(group.entries) { display in
                        portRow(display)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }
                }
            }
        }
    }

    // MARK: - Recently stopped section

    @ViewBuilder
    private var recentlyStoppedSection: some View {
        let groups = monitor.stoppedGroups

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: isStoppedCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)
                    .animation(.easeInOut(duration: 0.15), value: isStoppedCollapsed)

                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    withAnimation { monitor.snapshotStore.clearAll() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                        Text("Clear")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("Forget all recently stopped snapshots")
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { isStoppedCollapsed.toggle() }
            }

            if !isStoppedCollapsed {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(groups) { group in
                        stoppedProjectSection(group)
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private func stoppedProjectSection(_ group: StoppedProjectGroup) -> some View {
        let projectLaunching = group.snapshots.contains { monitor.launchingSnapshotIDs.contains($0.id) }

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(group.projectName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("\(group.snapshots.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.10), in: Capsule())

                Spacer()

                if projectLaunching {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    HoverButton(
                        icon: "play.circle.fill",
                        color: .green.opacity(0.95),
                        size: .system(size: 16),
                        help: "Restart all \(group.snapshots.count) process\(group.snapshots.count == 1 ? "" : "es") in \(group.projectName)"
                    ) {
                        let key = group.projectKey
                        Task { await monitor.startProject(projectKey: key) }
                    }
                }
            }
            .padding(.vertical, 2)

            VStack(spacing: 6) {
                ForEach(group.snapshots) { snap in
                    stoppedRow(snap)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
    }

    @ViewBuilder
    private func stoppedRow(_ snap: LaunchSnapshot) -> some View {
        StoppedRowView(
            snap: snap,
            isLaunching: monitor.launchingSnapshotIDs.contains(snap.id),
            onStart: { Task { await monitor.startSnapshot(snap) } },
            onForget: { withAnimation { monitor.snapshotStore.remove(id: snap.id) } }
        )
    }

    // MARK: - Port row

    @ViewBuilder
    private func portRow(_ display: PortEntryDisplay) -> some View {
        let isPending = monitor.pendingKillConfirmation?.entry.pid == display.entry.pid
            && monitor.pendingKillConfirmation?.entry.port == display.entry.port
        PortRowView(
            display: display,
            isKilling: monitor.killingPIDs.contains(display.entry.pid),
            isConflict: monitor.conflictPorts.contains(display.entry.port),
            isPendingConfirmation: isPending,
            settings: monitor.settings,
            onKill: {
                if display.entry.projectName == "Other" {
                    monitor.pendingKillConfirmation = display
                } else {
                    Task { await monitor.stopPort(display) }
                }
            },
            onOpen: {
                if let url = URL(string: "http://localhost:\(display.entry.port)") {
                    NSWorkspace.shared.open(url)
                }
            },
            onConfirmKill: {
                let d = display
                monitor.pendingKillConfirmation = nil
                Task { await monitor.stopPort(d) }
            },
            onCancelKill: {
                monitor.pendingKillConfirmation = nil
            }
        )
    }

}

// MARK: - Footer Button

/// Footer button with icon + label and a subtle hover background.
/// Note: the old `warningBadges`/`iconBadge`/`roleColor`/`statusColor` helpers were
/// intentionally removed in this branch — they now live inside `PortRowView`.
struct FooterButton: View {
    let icon: String
    let label: String
    var tint: Color = .secondary
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(tint.opacity(isHovered ? 0.12 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Hover Button

// MARK: - Stopped row view

/// Single "Recently stopped" card. Mirrors `PortRowView`'s hover pattern: the launch /
/// forget buttons reveal themselves only when the row is hovered, while the captured-ago
/// timestamp takes that slot at rest. Keeps the visual density low so dozens of snapshots
/// remain scannable.
struct StoppedRowView: View {
    let snap: LaunchSnapshot
    let isLaunching: Bool
    let onStart: () -> Void
    let onForget: () -> Void

    @State private var isHovered = false

    var body: some View {
        let accent = StoppedRowStyle.roleColor(snap.roleLabel)

        HStack(spacing: 0) {
            Rectangle()
                .fill(accent.opacity(0.35))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 10) {
                    // Port number in tertiary so it reads as "dormant" at a glance and
                    // can't be mistaken for an actively listening port.
                    Text(String(snap.port))
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)

                    if let label = snap.roleLabel, let icon = snap.roleIcon {
                        StoppedRowStyle.roleBadge(icon: icon, label: label)
                    }

                    Spacer(minLength: 6)

                    if isLaunching {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 14, height: 14)
                    } else if isHovered {
                        actionsCluster
                            .transition(.opacity)
                    } else {
                        capturedPill
                            .transition(.opacity)
                    }
                }

                HStack(spacing: 6) {
                    Text(snap.processName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                    if !snap.commandSummary.isEmpty && snap.commandSummary != snap.processName {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(snap.commandSummary)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(snap.commandSummary)
                    }
                    Spacer(minLength: 6)
                    if !snap.shortCwd.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "folder")
                                .font(.system(size: 9))
                            Text(snap.shortCwd)
                                .font(.system(size: 10))
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                        .foregroundStyle(.tertiary)
                        .help(snap.cwd)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.leading, 12)
            .padding(.trailing, 10)
        }
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.18), style: StrokeStyle(lineWidth: 0.5, dash: [3, 2]))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var capturedPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 9))
            Text(snap.capturedAgo)
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(.tertiary)
    }

    private var actionsCluster: some View {
        HStack(spacing: 8) {
            Button(action: onStart) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
            }
            .buttonStyle(.borderless)
            .help("Launch: \(snap.commandSummary)\nin \(snap.shortCwd)")

            Button(action: onForget) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.borderless)
            .help("Forget this snapshot")
        }
    }
}

// MARK: - Stopped row styling

/// Role badges/colors for the "Recently stopped" section — mirrors the styling inside
/// `PortRowView` so running and stopped rows feel like siblings, just dimmed. Extracted
/// as a namespaced helper so it can be reused across the top-level views without leaking
/// into public API.
enum StoppedRowStyle {
    static func roleColor(_ label: String?) -> Color {
        switch label {
        case "Front": return Color(nsColor: .systemBlue)
        case "Back":  return Color(nsColor: .systemIndigo)
        case "DB":    return Color(nsColor: .systemBrown)
        case "Cache": return Color(nsColor: .systemGray)
        case "MCP":   return Color(nsColor: .systemPurple)
        default:      return Color.secondary
        }
    }

    @ViewBuilder
    static func roleBadge(icon: String, label: String) -> some View {
        let color = roleColor(label)
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.3)
        }
        .foregroundStyle(color.opacity(0.75))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.10), in: Capsule())
        .overlay(
            Capsule().strokeBorder(color.opacity(0.18), lineWidth: 0.5)
        )
    }
}

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
