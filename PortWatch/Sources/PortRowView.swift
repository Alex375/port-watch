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
    let settings: AppSettings
    let onKill: () -> Void
    let onOpen: () -> Void
    let onConfirmKill: () -> Void
    let onCancelKill: () -> Void

    @State private var isHovered = false
    @State private var isExpanded = false

    private var cpuOver: Bool { (display.cpuPercent ?? 0) > settings.cpuThreshold }
    private var ramOver: Bool { display.entry.memoryMB > settings.ramThresholdMB }
    private var isZombie: Bool { display.entry.tcpState.isZombie }
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
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            guard !display.commandSummary.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        }
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

            // Actions (hover) or uptime (idle)
            if isHovered {
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
            .help("Open http://localhost:\(display.entry.port)")

            if isKilling {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 14, height: 14)
            } else {
                Button(action: onKill) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Kill process \(display.entry.processName) (PID \(display.entry.pid))")
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
            if let cpu = display.cpuPercent, cpu > settings.cpuThreshold {
                warningPill(icon: "cpu", text: String(format: "%.0f%% CPU", cpu), color: .orange)
            }
            if ramOver {
                warningPill(icon: "memorychip", text: String(format: "%.0f MB", display.entry.memoryMB), color: .orange)
            }
            Spacer()
        }
    }

    // MARK: - Reusable bits

    private func roleBadge(icon: String, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.3)
        }
        .foregroundStyle(roleColor(label))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(roleColor(label).opacity(0.14), in: Capsule())
        .overlay(
            Capsule().strokeBorder(roleColor(label).opacity(0.25), lineWidth: 0.5)
        )
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
        default:      return Color.secondary
        }
    }
}
