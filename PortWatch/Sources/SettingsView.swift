import SwiftUI
import UserNotifications

/// Full Settings panel — grouped sections (macOS-style), clear typography, editable tag lists.
struct SettingsView: View {
    @Bindable var settings: AppSettings
    var onClose: () -> Void
    @State private var showUninstallConfirm = false
    @State private var showClearSnapshotsConfirm = false
    @State private var showDisableHistoryConfirm = false
    @State private var updater = UpdateChecker.shared
    @State private var snapshotStore = SnapshotStore.shared
    @State private var newKeyword: [String: String] = [:]
    /// Remembered slider value used when "Keep forever" is toggled off — so the UI restores
    /// the previous retention instead of snapping to the minimum.
    @State private var lastFiniteTTLMinutes: Int = {
        let current = AppSettings.shared.snapshotTTLMinutes
        return current > 0 ? current : 60
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    monitoringSection
                    notificationsSection
                    detectionSection
                    ignoredProcessesSection
                    restartHistorySection
                    aboutSection
                    dangerZone
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 580)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onClose) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Settings")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            // Empty spacer to balance the Back button
            Text("")
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Monitoring

    private var monitoringSection: some View {
        settingsSection(icon: "speedometer", title: "Monitoring", color: .orange) {
            sliderRow(
                label: "CPU alert",
                value: $settings.cpuThreshold,
                range: 10...100,
                step: 10,
                format: { "\(Int($0))%" },
                valueWidth: 42
            )
            sliderRow(
                label: "RAM alert",
                value: $settings.ramThresholdMB,
                range: 100...2000,
                step: 100,
                format: { "\(Int($0)) MB" },
                valueWidth: 58
            )
            sliderRow(
                label: "Refresh every",
                value: $settings.refreshInterval,
                range: 3...30,
                step: 1,
                format: { "\(Int($0))s" },
                valueWidth: 32
            )
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        settingsSection(icon: "bell.badge", title: "Notifications", color: .blue) {
            notificationPicker(
                label: "New ports",
                caption: "When a new TCP port starts listening",
                selection: $settings.notifyNewPorts
            )
            Divider().padding(.vertical, 2)
            notificationPicker(
                label: "Port conflicts",
                caption: "When two processes fight for the same port",
                selection: $settings.notifyConflicts
            )
        }
    }

    // MARK: - Detection

    private var detectionSection: some View {
        settingsSection(icon: "tag", title: "Role detection keywords", color: .indigo) {
            Text("Match against folder, process, and command line to tag ports with a role.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            keywordRow(label: "Front", icon: "globe", color: Color(nsColor: .systemBlue), keywords: $settings.frontKeywords)
            keywordRow(label: "Back", icon: "server.rack", color: Color(nsColor: .systemIndigo), keywords: $settings.backKeywords)
            keywordRow(label: "DB folders", icon: "externaldrive.fill", color: Color(nsColor: .systemBrown), keywords: $settings.dbKeywords)
            keywordRow(label: "DB processes", icon: "externaldrive.fill", color: Color(nsColor: .systemBrown), keywords: $settings.dbProcessNames)
            keywordRow(label: "MCP", icon: "cpu", color: Color(nsColor: .systemPurple), keywords: $settings.mcpKeywords)
            keywordRow(label: "Claude", icon: "ClaudeLogo", color: Color(red: 204/255, green: 124/255, blue: 94/255), keywords: $settings.claudeKeywords)
        }
    }

    // MARK: - Ignored processes (NEW)

    private var ignoredProcessesSection: some View {
        settingsSection(icon: "eye.slash", title: "Ignored processes", color: .gray) {
            Text("Process names listed here are hidden from PortWatch, even when they're listening on local ports. Useful for IDE/tool internals (Claude, Discord, PyCharm…) that open loopback servers for IPC.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            keywordRow(
                label: "Ignore",
                icon: "eye.slash",
                color: .gray,
                keywords: $settings.ignoredProcesses,
                hint: "process name (e.g. claude)"
            )

            Divider().opacity(0.4)

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show ignored in popover")
                        .font(.system(size: 11))
                    Text("Toggle quickly with ⌘I from the popover.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $settings.showIgnored)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
        }
    }

    // MARK: - Restart history (TTL + clear)

    private var restartHistorySection: some View {
        settingsSection(icon: "clock.arrow.circlepath", title: "Restart history", color: .green) {
            Text("Stopped processes are remembered so you can relaunch them later.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            historyEnabledToggle

            // Disabling-history confirmation banner. Flipping the toggle ON → OFF
            // stages the destructive action here so the user can back out before
            // any snapshots are wiped.
            if showDisableHistoryConfirm {
                disableHistoryConfirmBanner
            }

            // Retention controls only appear when history is on — hiding them rather
            // than greying out keeps the section readable and removes the awkward
            // pair of sibling switches (Enable history + Keep forever) at the same
            // visual level.
            if settings.historyEnabled {
                retentionSubBlock
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            snapshotCountRow
        }
        .animation(.easeInOut(duration: 0.18), value: settings.historyEnabled)
    }

    /// Indented sub-card containing the TTL controls. Sits visually under the
    /// master "Enable history" toggle.
    private var retentionSubBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "timer")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text("Retention")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                Spacer()
                Text("Older snapshots are discarded.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            ttlRow
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
    }

    private var snapshotCountRow: some View {
        let count = snapshotStore.snapshots.count
        return HStack(spacing: 6) {
            Text("\(count) snapshot\(count == 1 ? "" : "s") stored")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            if showClearSnapshotsConfirm {
                Button("Cancel") { showClearSnapshotsConfirm = false }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button {
                    snapshotStore.clearAll()
                    showClearSnapshotsConfirm = false
                } label: {
                    Text("Clear all")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
                .disabled(count == 0)
            } else {
                Button {
                    showClearSnapshotsConfirm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                        Text("Clear all")
                            .font(.system(size: 11))
                    }
                }
                .buttonStyle(.borderless)
                .disabled(count == 0)
            }
        }
    }

    /// Master toggle. Turning it ON is unconditional. Turning it OFF stages a confirmation
    /// banner (`showDisableHistoryConfirm`) before any snapshots are cleared, since the
    /// disable path also wipes whatever's currently stored. We bind to a derived Boolean
    /// rather than `settings.historyEnabled` directly so we can intercept the OFF transition
    /// and either confirm-then-clear or revert. When the store is already empty there's
    /// nothing to wipe, so we skip the banner and flip the flag immediately.
    private var historyEnabledToggle: some View {
        let binding = Binding<Bool>(
            get: { settings.historyEnabled },
            set: { newValue in
                if newValue {
                    // ON path: re-enable immediately, drop any stale confirm banner.
                    showDisableHistoryConfirm = false
                    settings.historyEnabled = true
                } else if snapshotStore.snapshots.isEmpty {
                    // Nothing to clear → no need to confirm.
                    showDisableHistoryConfirm = false
                    settings.historyEnabled = false
                } else {
                    // OFF path: stage the confirm banner. The toggle visually stays ON
                    // until the user clicks "Disable & clear" — Cancel restores it.
                    showDisableHistoryConfirm = true
                }
            }
        )
        return Toggle(isOn: binding) {
            Text("Enable history")
                .font(.system(size: 11))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var disableHistoryConfirmBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 11))
                Text("Disabling will clear all current snapshots. Continue?")
                    .font(.system(size: 11, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    // Toggle binding already left `historyEnabled` untouched, so we just
                    // hide the banner.
                    showDisableHistoryConfirm = false
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                Button {
                    snapshotStore.clearAll()
                    settings.historyEnabled = false
                    showDisableHistoryConfirm = false
                } label: {
                    Text("Disable & clear")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5)
        )
    }

    /// "Keep forever" toggle + logarithmic slider for retention across 4 orders of
    /// magnitude (1 min → 30 days). A linear slider over that range would waste 99 % of
    /// its travel on values no one picks. Log-spaced travel gives roughly equal precision
    /// per decade: the first third covers minutes, the middle third hours, the last third
    /// days. Storage stays in minutes; `0` means no auto-prune ("forever").
    private var ttlRow: some View {
        let sliderMinMinutes: Double = 1
        let sliderMaxMinutes: Double = 30 * 24 * 60 // 43200
        let logMin = log(sliderMinMinutes)
        let logMax = log(sliderMaxMinutes)

        let keepForeverBinding = Binding<Bool>(
            get: { settings.snapshotTTLMinutes == 0 },
            set: { newVal in
                if newVal {
                    if settings.snapshotTTLMinutes > 0 {
                        lastFiniteTTLMinutes = settings.snapshotTTLMinutes
                    }
                    settings.snapshotTTLMinutes = 0
                } else {
                    settings.snapshotTTLMinutes = max(1, min(Int(sliderMaxMinutes), lastFiniteTTLMinutes))
                }
            }
        )
        let keepForever = keepForeverBinding.wrappedValue

        // Slider works in log-space (units: ln(minutes)); we snap the converted value to
        // nice integers so drag feedback feels discrete (5 min, 10, 15, 30, 1h, 2h, 1d…)
        // instead of jittering between e.g. 42 and 43 min.
        let logBinding = Binding<Double>(
            get: {
                let m = max(Int(sliderMinMinutes), keepForever ? lastFiniteTTLMinutes : settings.snapshotTTLMinutes)
                return log(Double(m))
            },
            set: { newLog in
                let snapped = Self.snapTTLMinutes(exp(newLog))
                let clamped = max(Int(sliderMinMinutes), min(Int(sliderMaxMinutes), snapped))
                lastFiniteTTLMinutes = clamped
                if !keepForever { settings.snapshotTTLMinutes = clamped }
            }
        )

        return VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: keepForeverBinding) {
                Text("Keep forever")
                    .font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Keep for")
                        .font(.system(size: 11))
                    Spacer()
                    Text(formatTTL(Double(keepForever ? lastFiniteTTLMinutes : settings.snapshotTTLMinutes)))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .trailing)
                }
                Slider(value: logBinding, in: logMin...logMax)
                    .controlSize(.mini)
            }
            .disabled(keepForever)
            .opacity(keepForever ? 0.5 : 1.0)
        }
    }

    /// Snap a raw minute count (typically produced by `exp()` from the log-slider) to a
    /// unit-appropriate tick so drag feedback feels discrete across all four orders of
    /// magnitude. Tiers: 1-minute precision < 10 min, 5-minute steps up to 1 h,
    /// 15-minute steps up to 6 h, 1-hour steps up to 1 day, 12-hour steps up to 1 week,
    /// then 1-day steps up to the 30-day ceiling.
    static func snapTTLMinutes(_ raw: Double) -> Int {
        let v = max(1.0, raw)
        if v < 10 { return Int(v.rounded()) }
        if v < 60 {
            let m = Int(v.rounded())
            return ((m + 2) / 5) * 5
        }
        if v < 6 * 60 {
            let m = Int(v.rounded())
            return ((m + 7) / 15) * 15
        }
        if v < 24 * 60 {
            let m = Int(v.rounded())
            return ((m + 30) / 60) * 60
        }
        let hours = Int((v / 60).rounded())
        if hours < 7 * 24 { return ((hours + 6) / 12) * 12 * 60 }
        return ((hours + 12) / 24) * 24 * 60
    }

    /// Convert TTL minutes into a compact human-readable label: "5 min", "1h", "23h", "7d", "30d".
    private func formatTTL(_ minutes: Double) -> String {
        let m = Int(minutes)
        if m < 60 { return "\(m) min" }
        let hours = m / 60
        let minRem = m % 60
        if hours < 24 {
            return minRem == 0 ? "\(hours)h" : "\(hours)h\(minRem)"
        }
        let days = hours / 24
        let hRem = hours % 24
        return hRem == 0 ? "\(days)d" : "\(days)d\(hRem)h"
    }

    // MARK: - About

    private var aboutSection: some View {
        settingsSection(icon: "info.circle", title: "About", color: .teal) {
            HStack {
                Text("PortWatch")
                    .font(.system(size: 12, weight: .medium))
                Text("v\(updater.currentVersion)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                if updater.isChecking {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("Checking…")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        Task { await updater.checkForUpdate() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9))
                            Text("Check for update")
                                .font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }

            // Status line
            updateStatusLine
        }
    }

    @ViewBuilder
    private var updateStatusLine: some View {
        if let err = updater.error {
            statusLine(icon: "exclamationmark.circle.fill", text: err, color: .red)
        } else if updater.updateAvailable, let v = updater.latestVersion {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.system(size: 11))
                Text("v\(v) available")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
                Spacer()
                if updater.isDownloading {
                    ProgressView(value: updater.downloadProgress)
                        .frame(width: 80)
                        .controlSize(.mini)
                } else {
                    Button("Install") {
                        Task { await updater.performUpdate() }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.small)
                }
            }
        } else if !updater.isChecking && updater.latestVersion != nil {
            statusLine(icon: "checkmark.circle.fill", text: "Up to date", color: .green)
        }
    }

    private func statusLine(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Danger zone (reset + uninstall)

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                settings.resetToDefaults()
            } label: {
                Label("Reset all settings to defaults", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)

            if showUninstallConfirm {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.system(size: 11))
                        Text("Permanently remove PortWatch and all its data?")
                            .font(.system(size: 11, weight: .medium))
                    }
                    HStack {
                        Spacer()
                        Button("Cancel") { showUninstallConfirm = false }
                            .buttonStyle(.borderless)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Button(action: performUninstall) {
                            Text("Uninstall")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.red.opacity(0.25), lineWidth: 0.5)
                )
            } else {
                Button {
                    showUninstallConfirm = true
                } label: {
                    Label("Uninstall PortWatch…", systemImage: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Reusable section wrapper (grouped card style)

    @ViewBuilder
    private func settingsSection<Content: View>(
        icon: String,
        title: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(12)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Slider row

    private func sliderRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String,
        valueWidth: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                Spacer()
                Text(format(value.wrappedValue))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: valueWidth, alignment: .trailing)
            }
            Slider(value: value, in: range, step: step)
                .controlSize(.mini)
        }
    }

    // MARK: - Notification picker

    private func notificationPicker(label: String, caption: String, selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("", selection: selection) {
                Text("Off").tag(0)
                Text("Projects only").tag(1)
                Text("All").tag(2)
            }
            .pickerStyle(.segmented)
            .controlSize(.mini)
            .labelsHidden()
            .onChange(of: selection.wrappedValue) { _, val in
                if val > 0 { NotificationManager.shared.requestPermission() }
            }
        }
    }

    // MARK: - Keyword row (editable tags)

    @ViewBuilder
    private func keywordRow(
        label: String,
        icon: String,
        color: Color,
        keywords: Binding<[String]>,
        hint: String = "add"
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                iconView(icon: icon, size: 9)
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Text("\(keywords.wrappedValue.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            FlowLayout(spacing: 4) {
                ForEach(keywords.wrappedValue, id: \.self) { kw in
                    tagChip(kw: kw, color: color) {
                        keywords.wrappedValue.removeAll { $0 == kw }
                    }
                }
                addTagField(label: label, keywords: keywords, hint: hint)
            }
        }
    }

    private func tagChip(kw: String, color: Color, onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 3) {
            Text(kw)
                .font(.system(size: 10, weight: .medium))
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .opacity(0.6)
            }
            .buttonStyle(.borderless)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 0.5))
    }

    /// Render an icon that may be either an asset catalog image (rendered with native colors)
    /// or an SF Symbol (inherits the parent foregroundStyle).
    @ViewBuilder
    private func iconView(icon: String, size: CGFloat) -> some View {
        if NSImage(named: icon) != nil {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: size + 2, height: size + 2)
        } else {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
        }
    }

    private func addTagField(label: String, keywords: Binding<[String]>, hint: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "plus")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
            TextField(hint, text: Binding(
                get: { newKeyword[label] ?? "" },
                set: { newKeyword[label] = $0 }
            ))
            .font(.system(size: 10))
            .textFieldStyle(.plain)
            .frame(minWidth: 60, idealWidth: 90, maxWidth: 120)
            .onSubmit { commitKeyword(label: label, keywords: keywords) }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5))
    }

    private func commitKeyword(label: String, keywords: Binding<[String]>) {
        let val = (newKeyword[label] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard !val.isEmpty, !keywords.wrappedValue.contains(val) else {
            newKeyword[label] = ""
            return
        }
        keywords.wrappedValue.append(val)
        newKeyword[label] = ""
    }

    // MARK: - Uninstall

    private func performUninstall() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        let paths = [
            "\(home)/Library/Application Support/PortWatch",
            "\(home)/Library/Preferences/com.portwatch.plist",
            "\(home)/Library/Caches/PortWatch",
            "\(home)/Library/Logs/PortWatch",
        ]

        for path in paths {
            try? fm.removeItem(atPath: path)
        }

        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }

        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

        let appPath = Bundle.main.bundlePath
        try? fm.removeItem(atPath: appPath)

        NSApplication.shared.terminate(nil)
    }
}

/// Simple flow layout that wraps children horizontally.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
