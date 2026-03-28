import Foundation
import SwiftUI

/// Checks GitHub Releases for new versions and handles the update process.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let repo = "Alex375/port-watch"
    private let apiURL: URL

    var latestVersion: String? = nil
    var updateAvailable: Bool = false
    var isChecking: Bool = false
    var isDownloading: Bool = false
    var downloadProgress: Double = 0
    var error: String? = nil

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private init() {
        apiURL = URL(string: "https://api.github.com/repos/Alex375/port-watch/releases/latest")!
    }

    /// Check GitHub for a newer release. Called at launch + manually.
    func checkForUpdate() async {
        guard !isChecking else { return }
        isChecking = true
        error = nil

        defer { isChecking = false }

        do {
            var request = URLRequest(url: apiURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                error = "Invalid response"
                return
            }

            if http.statusCode == 404 {
                // No release yet
                latestVersion = nil
                updateAvailable = false
                return
            }

            guard http.statusCode == 200 else {
                error = "GitHub API error (HTTP \(http.statusCode))"
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                error = "Failed to parse release info"
                return
            }

            // Strip leading "v" from tag
            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            latestVersion = remoteVersion

            if isNewer(remote: remoteVersion, local: currentVersion) {
                updateAvailable = true
            } else {
                updateAvailable = false
            }
        } catch {
            self.error = "Network error: \(error.localizedDescription)"
        }
    }

    /// Download and install the update.
    func performUpdate() async {
        guard !isDownloading else { return }
        isDownloading = true
        downloadProgress = 0
        error = nil

        defer { isDownloading = false }

        do {
            // 1. Get release assets
            var request = URLRequest(url: apiURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let assets = json["assets"] as? [[String: Any]] else {
                error = "Failed to parse release assets"
                return
            }

            // Find the .zip asset
            guard let zipAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
                  let downloadURLString = zipAsset["browser_download_url"] as? String,
                  let downloadURL = URL(string: downloadURLString) else {
                error = "No .zip file found in release"
                return
            }

            // 2. Download to temp
            downloadProgress = 0.1
            let (zipFileURL, _) = try await URLSession.shared.download(from: downloadURL)
            downloadProgress = 0.6

            // 3. Unzip
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("PortWatch-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-o", zipFileURL.path, "-d", tempDir.path]
            unzipProcess.standardOutput = Pipe()
            unzipProcess.standardError = Pipe()
            try unzipProcess.run()
            unzipProcess.waitUntilExit()

            guard unzipProcess.terminationStatus == 0 else {
                error = "Failed to unzip update"
                return
            }
            downloadProgress = 0.8

            // 4. Find the .app in the extracted files
            let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            guard let newAppURL = contents.first(where: { $0.lastPathComponent.hasSuffix(".app") }) else {
                error = "No .app found in update archive"
                return
            }

            // 5. Write the update script and launch it
            let currentAppPath = Bundle.main.bundlePath
            let scriptContent = """
            #!/bin/bash
            # PortWatch auto-update script
            APP_PID=\(ProcessInfo.processInfo.processIdentifier)
            NEW_APP="\(newAppURL.path)"
            CURRENT_APP="\(currentAppPath)"

            # Wait for the app to quit
            while kill -0 $APP_PID 2>/dev/null; do
                sleep 0.5
            done

            # Replace the app
            rm -rf "$CURRENT_APP"
            cp -R "$NEW_APP" "$CURRENT_APP"

            # Relaunch
            open "$CURRENT_APP"

            # Cleanup
            rm -rf "\(tempDir.path)"
            rm -- "$0"
            """

            let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("portwatch-update.sh")
            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)

            // Make executable
            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["+x", scriptURL.path]
            try chmod.run()
            chmod.waitUntilExit()

            downloadProgress = 1.0

            // 6. Launch the script and quit
            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
            launcher.arguments = [scriptURL.path]
            try launcher.run()

            // Quit the app — the script will replace and relaunch
            NSApplication.shared.terminate(nil)

        } catch {
            self.error = "Update failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Version comparison

    /// Returns true if remote version is newer than local.
    private func isNewer(remote: String, local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        let maxLen = max(r.count, l.count)
        for i in 0..<maxLen {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }
}
