import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var onClose: () -> Void
    @State private var showUninstallConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                Text("Settings")
                    .font(.headline)
                Spacer()
            }

            // Thresholds
            VStack(alignment: .leading, spacing: 8) {
                Text("Alert thresholds")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("CPU")
                        .font(.caption)
                        .frame(width: 30, alignment: .leading)
                    Slider(value: $settings.cpuThreshold, in: 10...100, step: 10)
                    Text("\(Int(settings.cpuThreshold))%")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }

                HStack {
                    Text("RAM")
                        .font(.caption)
                        .frame(width: 30, alignment: .leading)
                    Slider(value: $settings.ramThresholdMB, in: 100...2000, step: 100)
                    Text("\(Int(settings.ramThresholdMB)) MB")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
            }

            Divider()

            // Refresh
            VStack(alignment: .leading, spacing: 8) {
                Text("Refresh")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Interval")
                        .font(.caption)
                    Slider(value: $settings.refreshInterval, in: 3...30, step: 1)
                    Text("\(Int(settings.refreshInterval))s")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 28, alignment: .trailing)
                }
            }

            Divider()

            // Notifications
            VStack(alignment: .leading, spacing: 8) {
                Text("Notifications")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Toggle("New port detected", isOn: $settings.notificationsEnabled)
                    .font(.caption)
                    .onChange(of: settings.notificationsEnabled) { _, enabled in
                        if enabled {
                            NotificationManager.shared.requestPermission()
                        }
                    }

                Toggle("Port conflicts", isOn: $settings.notifyPortConflicts)
                    .font(.caption)
            }

            Divider()

            // Role keywords
            VStack(alignment: .leading, spacing: 8) {
                Text("Detection keywords")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                keywordRow(label: "Front", icon: "globe", color: Color(nsColor: .systemBlue), keywords: $settings.frontKeywords)
                keywordRow(label: "Back", icon: "server.rack", color: Color(nsColor: .systemIndigo), keywords: $settings.backKeywords)
                keywordRow(label: "DB", icon: "externaldrive.fill", color: Color(nsColor: .systemBrown), keywords: $settings.dbKeywords)
                keywordRow(label: "DB processes", icon: "externaldrive.fill", color: Color(nsColor: .systemBrown), keywords: $settings.dbProcessNames)
            }

            Button {
                settings.resetToDefaults()
            } label: {
                Label("Reset to defaults", systemImage: "arrow.counterclockwise")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)

            Divider()

            // Uninstall
            if showUninstallConfirm {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                        Text("This will remove PortWatch and all its data.")
                            .font(.caption)
                    }
                    HStack {
                        Spacer()
                        Button("Cancel") {
                            showUninstallConfirm = false
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        Button("Uninstall") {
                            performUninstall()
                        }
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                    }
                }
            } else {
                Button {
                    showUninstallConfirm = true
                } label: {
                    Label("Uninstall PortWatch...", systemImage: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @State private var newKeyword: [String: String] = [:]

    @ViewBuilder
    private func keywordRow(label: String, icon: String, color: Color, keywords: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            FlowLayout(spacing: 4) {
                ForEach(keywords.wrappedValue, id: \.self) { kw in
                    HStack(spacing: 2) {
                        Text(kw)
                            .font(.system(size: 10))
                        Button {
                            keywords.wrappedValue.removeAll { $0 == kw }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 7))
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.1), in: Capsule())
                    .foregroundStyle(color)
                }
                // Add button
                HStack(spacing: 2) {
                    TextField("add", text: Binding(
                        get: { newKeyword[label] ?? "" },
                        set: { newKeyword[label] = $0 }
                    ))
                    .font(.system(size: 10))
                    .textFieldStyle(.plain)
                    .frame(width: 50)
                    .onSubmit {
                        let val = (newKeyword[label] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
                        if !val.isEmpty && !keywords.wrappedValue.contains(val) {
                            keywords.wrappedValue.append(val)
                        }
                        newKeyword[label] = ""
                    }
                    Button {
                        let val = (newKeyword[label] ?? "").trimmingCharacters(in: .whitespaces).lowercased()
                        if !val.isEmpty && !keywords.wrappedValue.contains(val) {
                            keywords.wrappedValue.append(val)
                        }
                        newKeyword[label] = ""
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 8))
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.08), in: Capsule())
            }
        }
    }

    private func performUninstall() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        // Kill the app process after cleanup
        let paths = [
            "\(home)/Library/Application Support/PortWatch",
            "\(home)/Library/Preferences/com.portwatch.plist",
            "\(home)/Library/Caches/PortWatch",
            "\(home)/Library/Logs/PortWatch",
        ]

        for path in paths {
            try? fm.removeItem(atPath: path)
        }

        // Remove UserDefaults
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }

        // Purge pending notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()

        // Remove the .app itself
        let appPath = Bundle.main.bundlePath
        try? fm.removeItem(atPath: appPath)

        // Quit
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
