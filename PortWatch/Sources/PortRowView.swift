import AppKit
import SwiftUI

/// Single port row — redesigned card layout.
///
/// Layout philosophy:
///   ┃ 3000      [Back]      15min
///   ┃ node · PID 2345
///   ┃ node server.js  ~/repo
///   ↑
///   accent bar (role color, full height)
///
/// - Port number is the visual hero (large, monospace).
/// - Role is conveyed by a colored accent strip on the left, plus a compact badge.
/// - Actions (kill, open in browser) fade in on hover to reduce permanent noise.
/// - Warning state tints the whole card background.
struct PortRowView: View {
    let display: PortEntryDisplay
    let isKilling: Bool
    let isConflict: Bool
    let isPendingConfirmation: Bool
    /// True when this row is only being shown because the user toggled
    /// "Show ignored". Renders dimmed with an "ignored" pill and suppresses
    /// the hover kill/open actions (issue #26).
    var isIgnored: Bool = false
    let settings: AppSettings
    let onKill: () -> Void
    let onOpen: () -> Void
    let onConfirmKill: () -> Void
    let onCancelKill: () -> Void
    /// Right-click → "Ignore" — adds this process name to the ignored list.
    var onIgnore: () -> Void = {}
    /// Right-click → "Stop ignoring" — only meaningful for rows already shown via
    /// the "Show ignored" toggle (`isIgnored == true`).
    var onUnignore: () -> Void = {}

    @State private var isHovered = false
    @State private var isExpanded = false

    /// For fleets, scale the CPU threshold by the number of processes so the warning
    /// reflects abnormal per-process load rather than the raw sum (N workers × 100% each
    /// would otherwise always trip a 50% threshold). Honest total is still shown in the pill.
    private var cpuThresholdForRow: Double {
        isFleet ? settings.cpuThreshold * Double(display.workerCount + 1) : settings.cpuThreshold
    }
    private var cpuOver: Bool { (display.cpuPercent ?? 0) > cpuThresholdForRow }
    private var ramOver: Bool { display.memoryMB > settings.ramThresholdMB }
    private var isFleet: Bool { display.workerCount > 0 }
    /// Persistent zombie flag from `PortMonitor` — only true after N consecutive CLOSE_WAIT scans (PR #11).
    private var isZombie: Bool { display.isZombie }
    private var hasWarning: Bool { isZombie || cpuOver || ramOver || isConflict }

    /// Primary color that drives the accent strip and role-related tints.
    private var accentColor: Color {
        if isPendingConfirmation { return .orange }
        if isZombie { return .red }
        if cpuOver || ramOver { return .orange }
        if let label = display.entry.roleLabel { return roleColor(label) }
        return .secondary
    }

    /// Subtle background tint — stronger when the row is in a warning state.
    private var backgroundTint: Color {
        if isPendingConfirmation { return .orange.opacity(0.12) }
        if isZombie { return .red.opacity(0.07) }
        if cpuOver || ramOver { return .orange.opacity(0.05) }
        if isHovered { return .primary.opacity(0.06) }
        return .primary.opacity(0.035)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left accent strip — role color, full height
            Rectangle()
                .fill(accentColor.opacity(0.7))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 5) {
                topRow
                subtitleRow
                if isExpanded && !display.commandSummary.isEmpty {
                    commandLine
                        .transition(.opacity)
                }
                if hasWarning {
                    warningRow
                }
                if isPendingConfirmation {
                    confirmationRow
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical, 10)
            .padding(.leading, 12)
            .padding(.trailing, 10)
        }
        .background(backgroundTint, in: RoundedRectangle(cornerRadius: 8))
        .opacity(isIgnored ? 0.55 : 1.0)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            guard !display.commandSummary.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        }
        .contextMenu { rowContextMenu }
    }

    // MARK: - Right-click context menu

    /// Character budget per wrapped detail line. A macOS context menu is NSMenu-backed and
    /// each item renders on a single, truncating line, so we pre-wrap long values into short
    /// lines that comfortably fit the menu's width in the system font (proportional, so this
    /// is deliberately conservative). See `wrappedLines(_:width:)`.
    private static let detailWrapWidth = 56
    /// Hard ceiling on wrapped lines per detail section so a pathological multi-kilobyte
    /// command line can't produce an absurdly tall menu; the remainder is summarised.
    private static let maxDetailLines = 60

    /// Right-click menu. Actions first (open/copy/reveal/terminal), then the ignore/unignore
    /// toggle, and finally the *untruncated* detail sections (full command, working directory,
    /// executable) at the bottom. The detail sections deliberately spell things out in full:
    /// the in-row layout truncates the command and cwd for density, but a context menu can
    /// afford to be verbose, so this is where the user reads the complete values.
    @ViewBuilder
    private var rowContextMenu: some View {
        Button(action: onOpen) {
            Label("Open \(display.entry.localhostURLString)", systemImage: "globe")
        }
        Button(action: copyURL) {
            Label("Copy URL", systemImage: "doc.on.doc")
        }

        // Filesystem actions only make sense when we captured a working directory.
        if !display.entry.cwd.isEmpty {
            Divider()
            Button(action: revealInFinder) {
                Label("Reveal in Finder", systemImage: "folder")
            }
            Button(action: openInTerminal) {
                Label("Open in Terminal", systemImage: "terminal")
            }
        }

        Divider()

        if isIgnored {
            Button(action: onUnignore) {
                Label("Stop ignoring “\(display.entry.processName)”", systemImage: "eye")
            }
        } else {
            Button(action: onIgnore) {
                Label("Ignore “\(display.entry.processName)”", systemImage: "eye.slash")
            }
        }

        Divider()

        detailSection("Command", fullCommand)
        if !display.entry.cwd.isEmpty {
            detailSection("Working directory", display.entry.cwd)
        }
        if !display.entry.processPath.isEmpty {
            detailSection("Executable", display.entry.processPath)
        }
    }

    /// The complete invocation: the raw argv joined with spaces (so the full executable path
    /// and every flag are present), falling back to the single-line summary when argv wasn't
    /// captured. Wrapped by `detailSection` so it never truncates in the menu.
    private var fullCommand: String {
        let argv = display.entry.arguments
        return argv.isEmpty ? display.commandSummary : argv.joined(separator: " ")
    }

    /// A "detail" section whose value is shown in full as a stack of non-interactive,
    /// pre-wrapped label rows — the menu can't wrap a single item, so we wrap ourselves.
    @ViewBuilder
    private func detailSection(_ title: String, _ value: String) -> some View {
        Section(title) {
            let capped = Self.cappedDetailLines(
                Self.wrappedLines(value, width: Self.detailWrapWidth),
                max: Self.maxDetailLines
            )
            ForEach(Array(capped.shown.enumerated()), id: \.offset) { _, line in
                Text(line)
            }
            if capped.overflow > 0 {
                Text("… +\(capped.overflow) more lines")
            }
        }
    }

    /// Cap a list of wrapped detail lines at `max`, returning the visible prefix plus the
    /// number of overflow lines dropped. Pure + `nonisolated` so the `maxDetailLines`
    /// guard-rail arithmetic is unit-testable without constructing a live view.
    nonisolated static func cappedDetailLines(_ lines: [String], max: Int) -> (shown: [String], overflow: Int) {
        guard lines.count > max else { return (lines, 0) }
        return (Array(lines.prefix(max)), lines.count - max)
    }

    /// Greedily wrap `text` into lines no longer than `width` characters for display inside an
    /// NSMenu-backed context menu (each item renders on a single, truncating line — so we
    /// pre-wrap rather than rely on the OS). Breaks after the last "/" or space within the
    /// window so paths/commands stay readable, hard-splitting any run longer than `width`.
    /// The concatenation of the returned lines always equals `text` (no characters lost or
    /// added). `nonisolated` + pure so the unit suite can exercise it directly.
    nonisolated static func wrappedLines(_ text: String, width: Int) -> [String] {
        guard width > 0, text.count > width else { return [text] }
        let chars = Array(text)
        let n = chars.count
        var lines: [String] = []
        var start = 0
        while start < n {
            if n - start <= width {
                lines.append(String(chars[start..<n]))
                break
            }
            let windowEnd = start + width
            var brk = windowEnd // hard break at the width budget by default
            var i = windowEnd - 1
            while i > start {
                if chars[i] == "/" || chars[i] == " " {
                    brk = i + 1 // break right after the separator to keep it readable
                    break
                }
                i -= 1
            }
            lines.append(String(chars[start..<brk]))
            start = brk
        }
        return lines
    }

    // MARK: - Context menu actions

    /// Copy `http://localhost:<port>` to the system pasteboard.
    private func copyURL() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(display.entry.localhostURLString, forType: .string)
    }

    /// Reveal the process's working directory in Finder (selected in its parent).
    private func revealInFinder() {
        let path = display.entry.cwd
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Bundle identifiers of terminals that open a folder in a new window rooted there,
    /// in preference order — iTerm2 first (the common developer choice), Apple Terminal as
    /// the always-present fallback. Both reliably accept a directory URL as the open item.
    private static let preferredTerminals = ["com.googlecode.iterm2", "com.apple.Terminal"]

    /// Open a new terminal window rooted at the process's working directory, preferring
    /// iTerm2 then Apple Terminal. If neither resolves (extremely rare — Terminal.app is a
    /// core macOS component), reveal the directory in Finder instead so the action is never
    /// a silent no-op (CLAUDE.md: "zero silent errors").
    private func openInTerminal() {
        let path = display.entry.cwd
        guard !path.isEmpty else { return }
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        let workspace = NSWorkspace.shared
        guard let terminal = Self.preferredTerminals.lazy
            .compactMap({ workspace.urlForApplication(withBundleIdentifier: $0) })
            .first
        else {
            workspace.activateFileViewerSelecting([dir])
            return
        }
        workspace.open([dir], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Top row: hero port + role + uptime + actions

    private var topRow: some View {
        HStack(alignment: .center, spacing: 10) {
            // Hero port number — monospaced, prominent
            Text(String(display.entry.port))
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)

            // Role badge (compact, centered with port)
            if let label = display.entry.roleLabel, let icon = display.entry.roleIcon {
                roleBadge(icon: icon, label: label)
            }

            // Ignored pill — only visible when the row is being shown via the
            // "Show ignored" toggle. Signals the user this would normally be hidden.
            if isIgnored {
                ignoredBadge
            }

            // Fleet pill — discrete, neutral. Means the row aggregates a master + N workers.
            if isFleet {
                fleetPill
            }

            // Worktree tag — discrete, neutral color
            if let wtName = display.entry.worktreeName {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange.opacity(0.7))
                    Text(wtName)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.10), in: Capsule())
                .help("Git worktree: \(wtName)")
            }

            Spacer(minLength: 6)

            // Expand/collapse indicator — the whole card is tappable to toggle.
            if !display.commandSummary.isEmpty {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .frame(width: 14, height: 14)
            }

            // Actions (hover) or uptime (idle). Ignored rows never reveal the
            // kill/open cluster — killing a process you've explicitly silenced
            // is almost always a mistake; remove it from the list first.
            if isHovered && !isIgnored {
                actionsCluster
                    .transition(.opacity)
            } else {
                uptimePill
                    .transition(.opacity)
            }
        }
    }

    private var uptimePill: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 9))
            Text(display.entry.uptimeFormatted)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(.tertiary)
    }

    private var actionsCluster: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                Image(systemName: "globe")
                    .font(.system(size: 13))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.borderless)
            .help("Open \(display.entry.localhostURLString)")

            if isKilling {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 14, height: 14)
            } else {
                Button(action: onKill) {
                    Image(systemName: "power.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Stop \(display.entry.processName) (PID \(display.entry.pid)) — snapshot saved for restart")
            }
        }
    }

    // MARK: - Subtitle row: process · PID · command · cwd

    private var subtitleRow: some View {
        HStack(spacing: 6) {
            // Process name + PID inline
            HStack(spacing: 6) {
                Text(display.entry.processName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("PID \(display.entry.pid)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 6)

            // cwd on the right
            if !display.entry.cwd.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "folder")
                        .font(.system(size: 9))
                    Text(display.entry.shortCwd)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .foregroundStyle(.tertiary)
                .help(display.entry.cwd)
            }
        }
    }

    // MARK: - Inline kill confirmation

    private var confirmationRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text("Unidentified process — killing it may affect your system.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: onCancelKill)
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Button(action: onConfirmKill) {
                    Text("Kill process")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Command line (tertiary info)

    private var commandLine: some View {
        HStack(spacing: 5) {
            Image(systemName: "terminal")
                .font(.system(size: 9))
            Text(display.commandSummary)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(.tertiary)
        .help(display.commandSummary)
    }

    // MARK: - Warning row

    private var warningRow: some View {
        HStack(spacing: 6) {
            if isConflict {
                warningPill(icon: "arrow.triangle.branch", text: "conflict", color: .secondary)
            }
            if isZombie {
                warningPill(icon: "xmark.seal.fill", text: "ZOMBIE", color: .red)
            }
            if let cpu = display.cpuPercent, cpu > cpuThresholdForRow {
                warningPill(icon: "cpu", text: String(format: "%.0f%% CPU", cpu), color: .orange)
                    .help(isFleet
                          ? "Total CPU across master + \(display.workerCount) workers"
                          : "CPU usage")
            }
            if ramOver {
                warningPill(icon: "memorychip", text: String(format: "%.0f MB", display.memoryMB), color: .orange)
                    .help(isFleet
                          ? "Total RAM across master + \(display.workerCount) workers"
                          : "Resident memory")
            }
            Spacer()
        }
    }

    // MARK: - Fleet pill

    private var fleetPill: some View {
        HStack(spacing: 3) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 8))
            Text("×\(display.workerCount + 1)")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.12), in: Capsule())
        .help("Master + \(display.workerCount) worker process\(display.workerCount == 1 ? "" : "es") sharing this socket")
    }

    // MARK: - Ignored pill

    private var ignoredBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "eye.slash")
                .font(.system(size: 8))
            Text("ignored")
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.12), in: Capsule())
        .help("This process is in the ignored list. It would normally be hidden, and CPU/zombie sampling is skipped for it.")
    }

    // MARK: - Reusable bits

    private func roleBadge(icon: String, label: String) -> some View {
        HStack(spacing: 3) {
            roleIconView(icon: icon, size: 9)
            if label != "Claude" {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.3)
            }
        }
        .foregroundStyle(roleColor(label))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(roleColor(label).opacity(0.14), in: Capsule())
        .overlay(
            Capsule().strokeBorder(roleColor(label).opacity(0.25), lineWidth: 0.5)
        )
    }

    /// Render a role icon. Asset catalog names (e.g. "ClaudeLogo") render with their
    /// native colors; anything else is treated as an SF Symbol and inherits the parent
    /// `foregroundStyle`.
    @ViewBuilder
    private func roleIconView(icon: String, size: CGFloat) -> some View {
        if NSImage(named: icon) != nil {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: size + 2, height: size + 2)
        } else {
            Image(systemName: icon)
                .font(.system(size: size))
        }
    }

    private func warningPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.14), in: Capsule())
    }

    private func roleColor(_ label: String) -> Color {
        switch label {
        case "Front": return Color(nsColor: .systemBlue)
        case "Back":  return Color(nsColor: .systemIndigo)
        case "DB":    return Color(nsColor: .systemBrown)
        case "Cache": return Color(nsColor: .systemGray)
        case "MCP":   return Color(nsColor: .systemPurple)
        case "Claude": return Color(red: 204/255, green: 124/255, blue: 94/255)
        default:      return Color.secondary
        }
    }
}
