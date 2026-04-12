// Display Helper — menu bar utility for HiDPI scaling on large and high-resolution monitors
// Created by AL in Dallas

import SwiftUI
import AppKit
import CoreGraphics
import ServiceManagement

/// Names and paths from the app bundle (no hardcoded product string in code).
private enum AppBrand {
    static var displayName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "Display Helper"
    }

    static var versionString: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    private static var executableName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String) ?? "HiDPIDisplay"
    }

    /// Typical install location — used for the launch agent plist `ProgramArguments`.
    static var installedExecutablePath: String {
        "/Applications/\(displayName).app/Contents/MacOS/\(executableName)"
    }
}

/// Set to `true` to re-enable the "Check for Updates" menu items and background update checks.
private let updatesEnabled = false

func debugLog(_ message: String) {
    NSLog("HiDPI: %@", message)
    // Also write to a file for easier debugging
    let logFile = "/tmp/displayhelper.log"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile) {
            if let handle = FileHandle(forWritingAtPath: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: logFile, contents: data)
        }
    }
}

// MARK: - Launch Agent Manager

class LaunchAgentManager {
    static let shared = LaunchAgentManager()

    var isInstalled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func install() -> Bool {
        // Clean up any legacy LaunchAgent plist from older builds
        removeLegacyPlistIfPresent()
        do {
            try SMAppService.mainApp.register()
            debugLog("Registered as login item")
            return true
        } catch {
            debugLog("Login item registration failed: \(error)")
            return false
        }
    }

    func uninstall() -> Bool {
        removeLegacyPlistIfPresent()
        do {
            try SMAppService.mainApp.unregister()
            debugLog("Unregistered login item")
            return true
        } catch {
            debugLog("Login item unregistration failed: \(error)")
            return false
        }
    }

    private func removeLegacyPlistIfPresent() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = "\(home)/Library/LaunchAgents/com.hidpi.displayhelper.launchagent.plist"
        guard FileManager.default.fileExists(atPath: path) else { return }
        do {
            try FileManager.default.removeItem(atPath: path)
            debugLog("Removed legacy launch agent plist")
        } catch {
            debugLog("Failed to remove legacy plist: \(error)")
        }
    }
}

// MARK: - Custom Scale Window

class CustomScaleWindowController {
    private var window: NSWindow?
    private var slider: NSSlider?
    private var scaleValueLabel: NSTextField?
    private var resolutionLabel: NSTextField?
    private var nativeWidth: UInt32 = 0
    private var nativeHeight: UInt32 = 0
    private var ppi: UInt32 = 140
    private var applyCallback: ((PresetConfig) -> Void)?

    static let shared = CustomScaleWindowController()

    func show(nativeWidth: UInt32, nativeHeight: UInt32, ppi: UInt32, onApply: @escaping (PresetConfig) -> Void) {
        self.nativeWidth = nativeWidth
        self.nativeHeight = nativeHeight
        self.ppi = ppi
        self.applyCallback = onApply

        DispatchQueue.main.async { [weak self] in
            self?.createAndShowWindow()
        }
    }

    private func createAndShowWindow() {
        // Close any existing window
        window?.close()

        let windowRect = NSRect(x: 0, y: 0, width: 420, height: 180)
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Custom Scale"
        window.level = .floating
        window.center()

        let contentView = NSView(frame: windowRect)

        // Native resolution label
        let titleLabel = NSTextField(labelWithString: "Native: \(nativeWidth)×\(nativeHeight)")
        titleLabel.frame = NSRect(x: 20, y: 145, width: 380, height: 20)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        contentView.addSubview(titleLabel)

        // Scale factor row
        let scaleLabel = NSTextField(labelWithString: "Scale:")
        scaleLabel.frame = NSRect(x: 20, y: 108, width: 50, height: 20)
        scaleLabel.font = NSFont.systemFont(ofSize: 12)
        contentView.addSubview(scaleLabel)

        let slider = NSSlider(value: 1.4, minValue: 1.1, maxValue: 2.0, target: self, action: #selector(sliderChanged(_:)))
        slider.frame = NSRect(x: 75, y: 108, width: 260, height: 20)
        slider.isContinuous = true
        contentView.addSubview(slider)
        self.slider = slider

        let scaleValueLabel = NSTextField(labelWithString: "1.40x")
        scaleValueLabel.frame = NSRect(x: 345, y: 108, width: 55, height: 20)
        scaleValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        contentView.addSubview(scaleValueLabel)
        self.scaleValueLabel = scaleValueLabel

        // Resolution preview
        let logicalW = UInt32(Double(nativeWidth) / 1.4)
        let logicalH = UInt32(Double(nativeHeight) / 1.4)
        let resLabel = NSTextField(labelWithString: "Resolution: \(logicalW)×\(logicalH) HiDPI")
        resLabel.frame = NSRect(x: 20, y: 75, width: 380, height: 20)
        resLabel.font = NSFont.systemFont(ofSize: 13)
        resLabel.textColor = NSColor.secondaryLabelColor
        contentView.addSubview(resLabel)
        self.resolutionLabel = resLabel

        // Apply button
        let applyButton = NSButton(title: "Apply", target: self, action: #selector(applyClicked(_:)))
        applyButton.frame = NSRect(x: 300, y: 20, width: 100, height: 32)
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"
        contentView.addSubview(applyButton)

        // Cancel button
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked(_:)))
        cancelButton.frame = NSRect(x: 190, y: 20, width: 100, height: 32)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        contentView.addSubview(cancelButton)

        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    @objc func sliderChanged(_ sender: NSSlider) {
        let scale = (sender.doubleValue * 100).rounded() / 100
        let logicalW = UInt32(Double(nativeWidth) / scale)
        let logicalH = UInt32(Double(nativeHeight) / scale)

        scaleValueLabel?.stringValue = String(format: "%.2fx", scale)
        resolutionLabel?.stringValue = "Resolution: \(logicalW)×\(logicalH) HiDPI"
    }

    @objc func applyClicked(_ sender: NSButton) {
        guard let slider = slider else { return }
        let scale = (slider.doubleValue * 100).rounded() / 100

        let logicalW = UInt32(Double(nativeWidth) / scale)
        let logicalH = UInt32(Double(nativeHeight) / scale)

        let config = PresetConfig(
            name: "Custom-\(logicalW)x\(logicalH)",
            width: logicalW * 2,
            height: logicalH * 2,
            logicalWidth: logicalW,
            logicalHeight: logicalH,
            ppi: ppi,
            hiDPI: true
        )

        window?.close()
        window = nil
        applyCallback?(config)
    }

    @objc func cancelClicked(_ sender: NSButton) {
        window?.close()
        window = nil
    }
}

// MARK: - Status Window

class StatusWindowController {
    private var window: NSWindow?
    private var progressIndicator: NSProgressIndicator?
    private var statusLabel: NSTextField?

    static let shared = StatusWindowController()

    private init() {}

    func show(message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.createAndShowWindow(message: message)
        }
    }

    func updateStatus(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel?.stringValue = message
        }
    }

    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.window?.close()
            self?.window = nil
        }
    }

    private func createAndShowWindow(message: String) {
        // Create window
        let windowRect = NSRect(x: 0, y: 0, width: 300, height: 120)
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor
        window.level = .floating
        window.center()

        // Create content view
        let contentView = NSView(frame: windowRect)

        // App icon or display icon
        let iconView = NSImageView(frame: NSRect(x: 30, y: 45, width: 40, height: 40))
        if let icon = NSImage(systemSymbolName: "display", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 32, weight: .medium)
            iconView.image = icon.withSymbolConfiguration(config)
            iconView.contentTintColor = NSColor.controlAccentColor
        }
        contentView.addSubview(iconView)

        // Progress indicator
        let progress = NSProgressIndicator(frame: NSRect(x: 85, y: 65, width: 20, height: 20))
        progress.style = .spinning
        progress.controlSize = .small
        progress.startAnimation(nil)
        contentView.addSubview(progress)
        self.progressIndicator = progress

        // Title label
        let titleLabel = NSTextField(labelWithString: AppBrand.displayName)
        titleLabel.frame = NSRect(x: 110, y: 60, width: 160, height: 24)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.textColor = NSColor.labelColor
        contentView.addSubview(titleLabel)

        // Status label
        let statusLabel = NSTextField(labelWithString: message)
        statusLabel.frame = NSRect(x: 30, y: 20, width: 240, height: 20)
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.alignment = .center
        contentView.addSubview(statusLabel)
        self.statusLabel = statusLabel

        window.contentView = contentView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}

// MARK: - Auto Update Checker

class UpdateChecker {
    static let shared = UpdateChecker()

    private let repoOwner = "aksakalmustafa"
    private let repoName = "HiDPIVirtualDisplay"
    private let currentVersion: String
    private let kLastUpdateCheckKey = "lastUpdateCheck"
    private let kSkippedVersionKey = "skippedVersion"
    private let kAutoCheckUpdatesKey = "autoCheckUpdates"

    private init() {
        // Get current version from bundle
        currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        debugLog("UpdateChecker initialized, current version: \(currentVersion)")
    }

    // Check if auto-update is enabled (default: true)
    var autoCheckEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: kAutoCheckUpdatesKey) == nil {
                return true  // Default to enabled
            }
            return UserDefaults.standard.bool(forKey: kAutoCheckUpdatesKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: kAutoCheckUpdatesKey)
        }
    }

    // Check for updates (called on app launch)
    func checkForUpdatesInBackground() {
        guard autoCheckEnabled else {
            debugLog("Auto-update check disabled")
            return
        }

        // Don't check more than once per hour
        let lastCheck = UserDefaults.standard.double(forKey: kLastUpdateCheckKey)
        let hourAgo = Date().timeIntervalSince1970 - 3600
        if lastCheck > hourAgo {
            debugLog("Skipping update check - checked recently")
            return
        }

        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.fetchLatestRelease { result in
                switch result {
                case .success(let release):
                    self?.handleReleaseInfo(release)
                case .failure(let error):
                    debugLog("Update check failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // Manual check (from menu)
    func checkForUpdatesManually() {
        debugLog("Manual update check initiated")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.fetchLatestRelease { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let release):
                        self?.handleReleaseInfo(release, manual: true)
                    case .failure(let error):
                        self?.showError("Could not check for updates: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func fetchLatestRelease(completion: @escaping (Result<GitHubRelease, Error>) -> Void) {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "UpdateChecker", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: "UpdateChecker", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }

            do {
                let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                completion(.success(release))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func handleReleaseInfo(_ release: GitHubRelease, manual: Bool = false) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: kLastUpdateCheckKey)

        let latestVersion = release.tagName.replacingOccurrences(of: "v", with: "")
        debugLog("Latest version: \(latestVersion), current: \(currentVersion)")

        if isNewerVersion(latestVersion, than: currentVersion) {
            // Check if user skipped this version
            let skippedVersion = UserDefaults.standard.string(forKey: kSkippedVersionKey)
            if !manual && skippedVersion == latestVersion {
                debugLog("User previously skipped version \(latestVersion)")
                return
            }

            DispatchQueue.main.async { [weak self] in
                self?.showUpdateAlert(release: release, latestVersion: latestVersion)
            }
        } else if manual {
            DispatchQueue.main.async { [weak self] in
                self?.showUpToDateAlert()
            }
        }
    }

    private func isNewerVersion(_ new: String, than current: String) -> Bool {
        let newParts = new.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(newParts.count, currentParts.count) {
            let newPart = i < newParts.count ? newParts[i] : 0
            let currentPart = i < currentParts.count ? currentParts[i] : 0

            if newPart > currentPart { return true }
            if newPart < currentPart { return false }
        }
        return false
    }

    private func showUpdateAlert(release: GitHubRelease, latestVersion: String) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "\(AppBrand.displayName) \(latestVersion) is available (you have \(currentVersion)).\n\n\(release.name ?? "")\n\nWould you like to download it?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            downloadUpdate(release: release)
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(latestVersion, forKey: kSkippedVersionKey)
            debugLog("User skipped version \(latestVersion)")
        default:
            break
        }
    }

    private func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "\(AppBrand.displayName) \(currentVersion) is the latest version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func downloadUpdate(release: GitHubRelease) {
        // Find the DMG asset
        guard let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
            debugLog("No DMG found in release")
            // Fallback to opening release page
            if let url = URL(string: release.htmlUrl) {
                NSWorkspace.shared.open(url)
            }
            return
        }

        debugLog("Downloading: \(dmgAsset.browserDownloadUrl)")

        // Show download progress
        StatusWindowController.shared.show(message: "Downloading update...")

        guard let url = URL(string: dmgAsset.browserDownloadUrl) else { return }

        let downloadTask = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, response, error in
            DispatchQueue.main.async {
                StatusWindowController.shared.hide()

                if let error = error {
                    self?.showError("Download failed: \(error.localizedDescription)")
                    return
                }

                guard let tempURL = tempURL else {
                    self?.showError("Download failed: No file received")
                    return
                }

                // Move to Downloads folder
                let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                let destURL = downloadsURL.appendingPathComponent(dmgAsset.name)

                do {
                    // Remove existing file if present
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destURL)

                    debugLog("Downloaded to: \(destURL.path)")

                    // Open the DMG
                    NSWorkspace.shared.open(destURL)

                    // Show instructions
                    self?.showInstallInstructions()

                } catch {
                    self?.showError("Could not save update: \(error.localizedDescription)")
                }
            }
        }
        downloadTask.resume()
    }

    private func showInstallInstructions() {
        let alert = NSAlert()
        alert.messageText = "Update Downloaded"
        alert.informativeText = "The update has been downloaded and opened.\n\n1. Drag the new \(AppBrand.displayName) to Applications\n2. Replace the existing version\n3. Relaunch \(AppBrand.displayName)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// GitHub API Response Models
struct GitHubRelease: Codable {
    let tagName: String
    let name: String?
    let htmlUrl: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlUrl = "html_url"
        case assets
    }
}

struct GitHubAsset: Codable {
    let name: String
    let browserDownloadUrl: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
    }
}

// MARK: - Mirrored display cursor workaround (macOS compositor refresh)

/// Apple Silicon + mirrored virtual displays can leave the cursor laggy or stuck; macOS may skip
/// redraws for power saving. Same class of fix as [BetterDisplay #807](https://github.com/waydabber/BetterDisplay/issues/807#issuecomment-2590505321):
/// an almost-invisible 1×1 window toggling periodically to force light compositor activity.
private final class WorkaroundPixelWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class MirroredCursorRefreshWorkaround {
    private var window: NSWindow?
    private var timer: Timer?
    private var colorToggle = false

    func start() {
        DispatchQueue.main.async { [weak self] in
            self?.startOnMainThread()
        }
    }

    private func startOnMainThread() {
        stop()
        let w = WorkaroundPixelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        w.level = .statusBar
        w.alphaValue = 0.01
        w.backgroundColor = .black
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        w.ignoresMouseEvents = true
        w.isOpaque = false
        w.hasShadow = false
        w.isReleasedWhenClosed = false
        reposition(w)
        w.orderFrontRegardless()
        window = w

        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, let win = self.window else { return }
            self.colorToggle.toggle()
            win.backgroundColor = self.colorToggle ? .white : .black
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        debugLog("Cursor mirror workaround active (~30 Hz)")
    }

    private func reposition(_ w: NSWindow) {
        let screen = NSScreen.screens.max(by: { $0.frame.width < $1.frame.width }) ?? NSScreen.main
        guard let s = screen else { return }
        let vf = s.visibleFrame
        w.setFrameOrigin(NSPoint(x: vf.minX, y: vf.minY))
    }

    /// Call after display layout changes so the pixel stays on the active desktop.
    func refreshPositionIfNeeded() {
        guard let w = window else { return }
        reposition(w)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        window?.close()
        window = nil
    }
}

@main
struct HiDPIDisplayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var currentPresetName = ""
    private var isActive = false
    private var currentVirtualID: CGDirectDisplayID = 0
    private var targetExternalDisplayID: CGDirectDisplayID = 0  // Track which external display we're mirroring to

    // State persistence keys
    private let kLastPresetKey = "lastActivePreset"
    private let kWasCrashKey = "wasRunningWhenCrashed"
    private let kAutoRestoreKey = "autoRestoreOnCrash"
    private let kAutoApplyOnConnectKey = "autoApplyOnConnect"
    private let kRefreshRateKey = "customRefreshRate"  // 0.0 = auto-detect
    private let kBoundMonitorVendorKey = "boundMonitorVendor"
    private let kBoundMonitorModelKey = "boundMonitorModel"
    private let kCursorMirrorWorkaroundKey = "cursorMirrorWorkaroundEnabled"

    private let cursorMirrorWorkaround = MirroredCursorRefreshWorkaround()

    // Track if we're waiting for monitor reconnection
    private var wasDisconnected = false

    // Cache for skipping redundant display enumeration
    private var lastDisplayCount: UInt32 = 0
    private var lastRealMonitorID: CGDirectDisplayID = 0

    // Track if we're in the middle of setting up HiDPI (don't trigger cleanup during setup)
    private var isSettingUp = false
    private var isRestarting = false

    // Track consecutive mirror failures to prevent infinite restart loops
    private let kMirrorFailureCountKey = "consecutiveMirrorFailures"
    private let maxMirrorRetries = 3

    // Display change observer
    private var displayObserver: Any?
    private var displayCheckTimer: Timer?
    private var wakeObserver: Any?

    /// Default on: mitigates stuck/laggy cursor with mirrored virtual displays on Apple Silicon.
    private func cursorMirrorWorkaroundIsOn() -> Bool {
        if UserDefaults.standard.object(forKey: kCursorMirrorWorkaroundKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: kCursorMirrorWorkaroundKey)
    }

    private func updateCursorMirrorWorkaroundState() {
        if isActive && cursorMirrorWorkaroundIsOn() {
            cursorMirrorWorkaround.start()
        } else {
            cursorMirrorWorkaround.stop()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        debugLog("App launched")

        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            if #available(macOS 11.0, *),
               let img = NSImage(systemSymbolName: "display", accessibilityDescription: AppBrand.displayName) {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                button.image = img.withSymbolConfiguration(config)
            } else {
                button.title = "HiDPI"
            }
        }

        // Restore wasDisconnected state from UserDefaults (persists across restart)
        wasDisconnected = UserDefaults.standard.bool(forKey: kWasDisconnectedKey)
        debugLog("Restored wasDisconnected state: \(wasDisconnected)")

        // Clean up any stale state from previous sessions
        cleanupStaleState()

        // If orphaned virtual displays exist from a previous crash and this
        // isn't already a cleanup restart, terminate and relaunch so macOS
        // reclaims the displays (we can't destroy cross-process displays via API)
        if hasOrphanedVirtualDisplay() && !isCleanupRestart() {
            debugLog("Orphaned virtual displays detected from previous crash, restarting to clean up...")
            markCleanupRestart()
            relaunchApp()
            return
        }

        // Check for existing virtual display
        checkCurrentState()

        // Check if we should auto-restore after a crash OR after disconnect restart
        checkAndRestoreFromCrash()

        // Build menu
        rebuildMenu()

        // Mark that the app is running (for crash detection)
        UserDefaults.standard.set(true, forKey: kWasCrashKey)

        // Start monitoring for display changes (disconnect detection)
        startDisplayChangeMonitoring()

        // Check for updates in background
        if updatesEnabled {
            UpdateChecker.shared.checkForUpdatesInBackground()
        }
    }

    func startDisplayChangeMonitoring() {
        // Use NotificationCenter to monitor screen configuration changes
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            debugLog(">>> Display change notification received")
            self?.cursorMirrorWorkaround.refreshPositionIfNeeded()
            self?.handleDisplayConfigurationChange()
        }

        // Backup timer — notifications handle most changes, this catches edge cases
        displayCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.periodicDisplayCheck()
        }

        // Monitor for system wake to restore HiDPI configuration
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            debugLog(">>> System wake notification received")
            self?.handleWakeFromSleep()
        }

        debugLog("Display change monitoring started (notification + timer + wake)")
    }

    func stopDisplayChangeMonitoring() {
        if let observer = displayObserver {
            NotificationCenter.default.removeObserver(observer)
            displayObserver = nil
        }
        if let observer = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            wakeObserver = nil
        }
        displayCheckTimer?.invalidate()
        displayCheckTimer = nil
        debugLog("Display change monitoring stopped")
    }

    func periodicDisplayCheck() {
        // Don't trigger cleanup during setup or pending restart
        if isSettingUp || isRestarting { return }

        // Skip if nothing changed since last check
        var rawDisplayList = [CGDirectDisplayID](repeating: 0, count: 32)
        var currentDisplayCount: UInt32 = 0
        CGGetOnlineDisplayList(32, &rawDisplayList, &currentDisplayCount)

        if isActive && currentDisplayCount == lastDisplayCount && lastRealMonitorID != 0 {
            return
        }

        let realMonitor = findRealPhysicalMonitor()

        lastDisplayCount = currentDisplayCount
        lastRealMonitorID = realMonitor ?? 0

        // Case 1: HiDPI active but monitor disconnected
        if isActive && realMonitor == nil {
            debugLog(">>> Periodic check: Physical monitor gone - cleaning up")
            wasDisconnected = true
            UserDefaults.standard.set(0, forKey: kMirrorFailureCountKey)  // Reset for reconnection
            cleanupAfterDisconnect()
            return
        }

        // Case 1b: Orphaned virtual display exists (monitor gone, but isActive is false)
        // This can happen if mirror failed or app state got out of sync
        if !isActive && realMonitor == nil && hasOrphanedVirtualDisplay() {
            debugLog(">>> Periodic check: Orphaned virtual display detected - cleaning up")
            wasDisconnected = true
            cleanupAfterDisconnect()
            return
        }

        // Case 2: HiDPI not active, monitor reconnected, auto-apply enabled
        if !isActive && wasDisconnected && realMonitor != nil {
            let failCount = UserDefaults.standard.integer(forKey: kMirrorFailureCountKey)
            if failCount >= maxMirrorRetries {
                debugLog(">>> Periodic check: Monitor present but mirror failed \(failCount) times, not retrying (apply manually from menu)")
                wasDisconnected = false
                UserDefaults.standard.set(false, forKey: kWasDisconnectedKey)
                return
            }

            let autoApply = UserDefaults.standard.bool(forKey: kAutoApplyOnConnectKey)
            if autoApply, let lastPreset = UserDefaults.standard.string(forKey: kLastPresetKey), !lastPreset.isEmpty {
                if !connectedMonitorMatchesSavedPreset() {
                    debugLog(">>> Periodic check: Monitor present but doesn't match saved preset — skipping auto-apply")
                    return
                }
                debugLog(">>> Periodic check: Monitor reconnected - auto-applying \(lastPreset)")
                wasDisconnected = false
                UserDefaults.standard.set(false, forKey: kWasDisconnectedKey)
                restorePreset(lastPreset)
            }
        }
    }

    func handleWakeFromSleep() {
        // Don't restore during setup
        if isSettingUp {
            debugLog("Wake: Setup in progress, skipping restore")
            return
        }

        // Check if we have a saved preset to restore
        guard let lastPreset = UserDefaults.standard.string(forKey: kLastPresetKey), !lastPreset.isEmpty else {
            debugLog("Wake: No saved preset to restore")
            return
        }

        // Check if external display is connected
        guard findRealPhysicalMonitor(verbose: true) != nil else {
            debugLog("Wake: No external monitor found, skipping restore")
            return
        }

        if !connectedMonitorMatchesSavedPreset() {
            debugLog("Wake: Connected monitor doesn't match saved preset — skipping restore")
            return
        }

        // Fresh attempt after wake — reset failure counter
        UserDefaults.standard.set(0, forKey: kMirrorFailureCountKey)
        debugLog(">>> Wake: Restoring HiDPI preset after sleep: \(lastPreset)")

        // Mark as setting up to prevent other handlers from interfering
        isSettingUp = true

        // Reset current state - sleep/wake often breaks the virtual display mirroring
        let manager = VirtualDisplayManager.shared()
        manager.resetAllMirroring()
        manager.destroyAllVirtualDisplays()
        currentVirtualID = 0
        isActive = false
        currentPresetName = ""

        // Delay restoration to let the display system fully wake up
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.restorePreset(lastPreset)
        }
    }

    func handleDisplayConfigurationChange() {
        debugLog("Display configuration changed, checking state...")

        // Don't trigger cleanup during setup or pending restart
        if isSettingUp || isRestarting {
            debugLog("Setup/restart in progress, skipping disconnect check")
            return
        }

        // Case 1: HiDPI is active, check if physical monitor was disconnected
        if isActive && currentVirtualID != 0 {
            // Only check if the real physical monitor is still connected
            // Don't check mirroring status - macOS can break mirroring unexpectedly
            let realMonitor = findRealPhysicalMonitor(verbose: true)

            if realMonitor == nil {
                debugLog("Physical monitor disconnected (no real monitor found) - cleaning up")
                wasDisconnected = true
                UserDefaults.standard.set(0, forKey: kMirrorFailureCountKey)  // Reset for reconnection
                cleanupAfterDisconnect()
                return
            } else {
                debugLog("Physical monitor still connected: \(realMonitor!)")
            }
            return
        }

        // Case 2: HiDPI is not active, check if monitor was reconnected
        let realMonitor = findRealPhysicalMonitor(verbose: true)
        if !isActive && realMonitor != nil && wasDisconnected {
            let failCount = UserDefaults.standard.integer(forKey: kMirrorFailureCountKey)
            if failCount >= maxMirrorRetries {
                debugLog("Display reconnected but mirror failed \(failCount) times, not retrying (apply manually from menu)")
                wasDisconnected = false
                UserDefaults.standard.set(false, forKey: kWasDisconnectedKey)
                return
            }

            debugLog("External display reconnected")

            let autoApply = UserDefaults.standard.bool(forKey: kAutoApplyOnConnectKey)
            if autoApply, let lastPreset = UserDefaults.standard.string(forKey: kLastPresetKey), !lastPreset.isEmpty {
                if !connectedMonitorMatchesSavedPreset() {
                    debugLog("Display reconnected but doesn't match saved preset — skipping auto-apply")
                    wasDisconnected = false
                    UserDefaults.standard.set(false, forKey: kWasDisconnectedKey)
                    return
                }
                debugLog("Auto-applying last preset: \(lastPreset)")
                wasDisconnected = false
                UserDefaults.standard.set(false, forKey: kWasDisconnectedKey)

                // Delay to let the display settle
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    self?.restorePreset(lastPreset)
                }
            } else {
                debugLog("Auto-apply disabled or no saved preset")
                wasDisconnected = false
                UserDefaults.standard.set(false, forKey: kWasDisconnectedKey)
            }
        }
    }

    // Find a real physical monitor (not built-in, not virtual, not a ghost/phantom display)
    func findRealPhysicalMonitor(verbose: Bool = false) -> CGDirectDisplayID? {
        var displayList = [CGDirectDisplayID](repeating: 0, count: 32)
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(32, &displayList, &displayCount)

        for i in 0..<Int(displayCount) {
            let displayID = displayList[i]
            let isBuiltin = CGDisplayIsBuiltin(displayID) != 0
            let vendorID = CGDisplayVendorNumber(displayID)

            // Our virtual displays use vendor ID 0x1234 (4660 decimal)
            let isVirtualDisplay = vendorID == 0x1234

            // Vendor 0x756E6B6E (1970170734) = "unkn" in ASCII — macOS placeholder for
            // displays whose EDID hasn't been read yet. These are ghost/phantom displays
            // from Thunderbolt hubs, USB-C ports, or DisplayPort MST during initialization.
            // Mirroring to them always fails.
            let isGhostDisplay = vendorID == 0x756E6B6E

            if verbose {
                // CGDisplayScreenSize on virtual displays kicks off ColorSync lookups that peg the CPU
                if !isVirtualDisplay {
                    let size = CGDisplayScreenSize(displayID)
                    debugLog("  Display \(displayID): builtin=\(isBuiltin), vendor=\(vendorID), virtual=\(isVirtualDisplay), ghost=\(isGhostDisplay), size=\(size.width)mm")
                } else {
                    debugLog("  Display \(displayID): builtin=\(isBuiltin), vendor=\(vendorID), virtual=\(isVirtualDisplay), size=skipped")
                }
            }

            // Real monitors are: not built-in, not virtual (0x1234), not ghost (0x756E6B6E "unkn")
            if !isBuiltin && !isVirtualDisplay && !isGhostDisplay {
                if verbose {
                    debugLog("Found real physical monitor: \(displayID) (vendor: \(vendorID))")
                }
                return displayID
            }
        }
        if verbose {
            debugLog("No real physical monitor found")
        }
        return nil
    }

    // Check if there's an orphaned virtual display (vendor 0x1234) that we created
    func hasOrphanedVirtualDisplay() -> Bool {
        var displayList = [CGDirectDisplayID](repeating: 0, count: 32)
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(32, &displayList, &displayCount)

        for i in 0..<Int(displayCount) {
            let displayID = displayList[i]
            // Skip the display we currently own — it's not orphaned
            if currentVirtualID != 0 && displayID == currentVirtualID { continue }
            let vendorID = CGDisplayVendorNumber(displayID)
            // Our virtual displays use vendor ID 0x1234 (4660 decimal)
            if vendorID == 0x1234 {
                debugLog("Found orphaned virtual display: \(displayID)")
                return true
            }
        }
        return false
    }

    func cleanupAfterDisconnect() {
        debugLog(">>> Starting disconnect cleanup")

        // Move all windows to main display first
        moveAllWindowsToMainDisplay()

        // Mark that we're disconnected (for auto-restore on reconnect)
        UserDefaults.standard.set(true, forKey: kWasDisconnectedKey)

        // The CGVirtualDisplay framework doesn't actually destroy displays when we release
        // the object - they persist until the app terminates. The only reliable way to
        // clean up orphaned virtual displays is to restart the app.
        debugLog(">>> Restarting app to clean up virtual displays...")

        // Relaunch the app
        relaunchApp()
    }

    private let kWasDisconnectedKey = "wasDisconnected"

    func relaunchApp() {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 1 && open \"\(Bundle.main.bundlePath)\""]
        task.launch()

        // Terminate current instance
        NSApp.terminate(nil)
    }

    private let cleanupMarkerPath = "/tmp/displayhelper-cleanup-marker"

    /// Check if this launch is a cleanup restart (prevent infinite restart loops)
    func isCleanupRestart() -> Bool {
        guard FileManager.default.fileExists(atPath: cleanupMarkerPath) else { return false }
        // Only treat as cleanup restart if marker is recent (within 30 seconds)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: cleanupMarkerPath),
              let date = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(date) < 30 else {
            try? FileManager.default.removeItem(atPath: cleanupMarkerPath)
            return false
        }
        try? FileManager.default.removeItem(atPath: cleanupMarkerPath)
        return true
    }

    /// Mark that we're about to do a cleanup restart
    func markCleanupRestart() {
        FileManager.default.createFile(atPath: cleanupMarkerPath, contents: nil)
    }

    // Disable HiDPI when monitor is disconnected - preserves preset for auto-restore
    func disableHiDPIForDisconnect() {
        debugLog("Disabling HiDPI for disconnect (preserving preset) - currentVirtualID: \(currentVirtualID)")

        let manager = VirtualDisplayManager.shared()

        // Reset ALL mirroring to ensure clean state
        manager.resetAllMirroring()

        // Destroy our virtual display
        manager.destroyAllVirtualDisplays()

        currentVirtualID = 0
        targetExternalDisplayID = 0
        isActive = false
        currentPresetName = ""

        // DO NOT clear saved preset - we want to restore it when monitor reconnects
        debugLog("HiDPI disabled (preset preserved for reconnection)")
        setHiDPIMirrorActiveFlag(false)
        updateCursorMirrorWorkaroundState()
    }

    func moveAllWindowsToMainDisplay() {
        debugLog("Moving all windows to main display...")

        // Use AppleScript to move windows since it's more reliable for cross-app windows
        let script = """
            tell application "System Events"
                set allProcesses to every process whose background only is false
                repeat with proc in allProcesses
                    try
                        tell proc
                            repeat with w in windows
                                set position of w to {100, 100}
                            end repeat
                        end tell
                    end try
                end repeat
            end tell
            """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                debugLog("AppleScript error moving windows: \(error)")
            } else {
                debugLog("Windows moved to main display")
            }
        }
    }

    func checkAndRestoreFromCrash() {
        let wasRunning = UserDefaults.standard.bool(forKey: kWasCrashKey)
        let autoRestore = UserDefaults.standard.bool(forKey: kAutoRestoreKey)

        // Default to auto-restore enabled
        if UserDefaults.standard.object(forKey: kAutoRestoreKey) == nil {
            UserDefaults.standard.set(true, forKey: kAutoRestoreKey)
        }

        // Default to auto-apply on reconnect enabled
        if UserDefaults.standard.object(forKey: kAutoApplyOnConnectKey) == nil {
            UserDefaults.standard.set(true, forKey: kAutoApplyOnConnectKey)
        }

        // If we restarted after disconnect (not crash), don't try to restore here
        // Let the reconnect detection handle it when monitor is plugged back in
        if wasDisconnected {
            debugLog("Restarted after disconnect - waiting for monitor reconnection")
            return
        }

        if wasRunning && autoRestore {
            if let lastPreset = UserDefaults.standard.string(forKey: kLastPresetKey),
               !lastPreset.isEmpty {
                // Only restore if external display is connected
                if findExternalDisplay() != nil {
                    if !connectedMonitorMatchesSavedPreset() {
                        debugLog("Detected restart after crash, but connected monitor doesn't match saved preset — skipping auto-restore")
                        return
                    }
                    debugLog("Detected restart after crash, auto-restoring preset: \(lastPreset)")

                    // Delay restoration to let the system settle
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.restorePreset(lastPreset)
                    }
                } else {
                    debugLog("Detected restart after crash, but no external display - waiting for reconnection")
                    wasDisconnected = true
                    UserDefaults.standard.set(true, forKey: kWasDisconnectedKey)
                }
            }
        }

        // Clear the crash flag (will be set again when app is running)
        UserDefaults.standard.set(false, forKey: kWasCrashKey)
    }

    func restorePreset(_ presetName: String) {
        let config: PresetConfig

        if let dyn = PresetConfig(dynamicPresetKey: presetName) {
            config = dyn
        } else if let native = PresetConfig(native1xPresetKey: presetName) {
            config = native
        } else if presetName.hasPrefix("custom-"),
                  let dict = UserDefaults.standard.dictionary(forKey: "customPresetConfig"),
                  let name = dict["name"] as? String,
                  let width = (dict["width"] as? NSNumber)?.uint32Value,
                  let height = (dict["height"] as? NSNumber)?.uint32Value,
                  let logicalWidth = (dict["logicalWidth"] as? NSNumber)?.uint32Value,
                  let logicalHeight = (dict["logicalHeight"] as? NSNumber)?.uint32Value,
                  let ppi = (dict["ppi"] as? NSNumber)?.uint32Value,
                  let hiDPI = dict["hiDPI"] as? Bool {
            config = PresetConfig(name: name, width: width, height: height, logicalWidth: logicalWidth, logicalHeight: logicalHeight, ppi: ppi, hiDPI: hiDPI)
        } else {
            debugLog("ERROR: Unknown preset for restore: \(presetName). Choose a scale from the menu again.")
            return
        }

        debugLog(">>> Auto-restoring preset: \(presetName)")

        // Mark that we're setting up (don't trigger cleanup during setup)
        isSettingUp = true

        StatusWindowController.shared.show(message: "Restoring display configuration...")

        let manager = VirtualDisplayManager.shared()
        manager.resetAllMirroring()
        manager.destroyAllVirtualDisplays()
        currentVirtualID = 0
        isActive = false
        currentPresetName = ""

        // Schedule creation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            autoreleasepool {
                self?.createVirtualDisplayAsync(config: config)
            }
        }

        // Re-save the preset since we're using it
        saveCurrentPreset(presetName)
    }

    func saveCurrentPreset(_ presetName: String) {
        UserDefaults.standard.set(presetName, forKey: kLastPresetKey)
        UserDefaults.standard.set(true, forKey: kWasCrashKey)
        debugLog("Saved preset for crash recovery: \(presetName)")
    }

    func clearSavedPreset() {
        UserDefaults.standard.removeObject(forKey: kLastPresetKey)
        UserDefaults.standard.set(false, forKey: kWasCrashKey)
        debugLog("Cleared saved preset")
    }

    func cleanupStaleState() {
        debugLog("Cleaning up stale display state...")
        let manager = VirtualDisplayManager.shared()

        // Check if we have an external display connected
        let hasExternalDisplay = findExternalDisplay() != nil
        debugLog("External display connected: \(hasExternalDisplay)")

        // If no external display, move windows to main display first
        // This handles the case where app was killed/crashed while HiDPI was active
        if !hasExternalDisplay {
            debugLog("No external display - moving windows to main display")
            moveAllWindowsToMainDisplay()
        }

        // Reset any existing mirroring that might be left over
        manager.resetAllMirroring()

        // Destroy any virtual displays from previous session
        manager.destroyAllVirtualDisplays()

        debugLog("Stale state cleanup complete")
    }

    /// Writes a flag to a shared UserDefaults suite readable by Shortcuts / scripts.
    /// Key: `com.hidpi.displayhelper.mirrorActive`
    /// Use this in a Shortcuts automation: "When display helper mirror changes → toggle Focus"
    private func setHiDPIMirrorActiveFlag(_ active: Bool) {
        let suite = UserDefaults(suiteName: "com.hidpi.displayhelper") ?? UserDefaults.standard
        suite.set(active, forKey: "mirrorActive")
        suite.synchronize()
        debugLog("HiDPI mirror flag: \(active)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        debugLog("App terminating - cleaning up...")

        // Stop monitoring
        stopDisplayChangeMonitoring()

        setHiDPIMirrorActiveFlag(false)

        // Move windows to main display before cleanup
        if isActive {
            moveAllWindowsToMainDisplay()
        }

        // Disable HiDPI but preserve preset for auto-restore on next launch
        disableHiDPIForDisconnect()

        debugLog("Cleanup complete, terminating")
    }

    func checkCurrentState() {
        // Check if there's an active mirror setup
        var displayList = [CGDirectDisplayID](repeating: 0, count: 32)
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(32, &displayList, &displayCount)

        for i in 0..<Int(displayCount) {
            let displayID = displayList[i]
            let mirrorOf = CGDisplayMirrorsDisplay(displayID)
            if mirrorOf != kCGNullDirectDisplay {
                // Found a display that's mirroring something
                if let mode = CGDisplayCopyDisplayMode(mirrorOf) {
                    let width = mode.width
                    let height = mode.height
                    currentPresetName = "\(width)x\(height)"
                    isActive = true
                    debugLog("Found existing mirror: \(displayID) mirrors \(mirrorOf) at \(width)x\(height)")
                }
                break
            }
        }
    }

    func rebuildMenu() {
        let menu = NSMenu()

        // Status header
        if isActive {
            let statusItem = NSMenuItem(title: "Active: \(currentPresetName)", action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
            menu.addItem(NSMenuItem.separator())

            let disableItem = NSMenuItem(title: "Disable HiDPI", action: #selector(disableHiDPIAction), keyEquivalent: "")
            disableItem.target = self
            menu.addItem(disableItem)
            menu.addItem(NSMenuItem.separator())
        } else {
            let statusItem = NSMenuItem(title: "No HiDPI active", action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)
            menu.addItem(NSMenuItem.separator())
        }

        appendDynamicHiDPIMenuItems(to: menu)

        // Show cleanup option if orphaned virtual displays exist
        if hasOrphanedVirtualDisplay() {
            menu.addItem(NSMenuItem.separator())
            let cleanupItem = NSMenuItem(title: "Clean Up Phantom Displays", action: #selector(cleanUpDisplays), keyEquivalent: "")
            cleanupItem.target = self
            menu.addItem(cleanupItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Settings submenu
        let settingsMenu = NSMenu()

        let startAtLoginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleStartAtLogin(_:)), keyEquivalent: "")
        startAtLoginItem.target = self
        startAtLoginItem.state = LaunchAgentManager.shared.isInstalled ? .on : .off
        settingsMenu.addItem(startAtLoginItem)

        let autoApplyItem = NSMenuItem(title: "Auto-Apply on Reconnect", action: #selector(toggleAutoApply(_:)), keyEquivalent: "")
        autoApplyItem.target = self
        autoApplyItem.state = UserDefaults.standard.bool(forKey: kAutoApplyOnConnectKey) ? .on : .off
        settingsMenu.addItem(autoApplyItem)

        let autoRestoreItem = NSMenuItem(title: "Auto-Restore After Crash", action: #selector(toggleAutoRestore(_:)), keyEquivalent: "")
        autoRestoreItem.target = self
        autoRestoreItem.state = UserDefaults.standard.bool(forKey: kAutoRestoreKey) ? .on : .off
        settingsMenu.addItem(autoRestoreItem)

        let cursorWorkaroundItem = NSMenuItem(title: "Cursor Lag Workaround (Mirrored Screen)", action: #selector(toggleCursorMirrorWorkaround(_:)), keyEquivalent: "")
        cursorWorkaroundItem.target = self
        cursorWorkaroundItem.state = cursorMirrorWorkaroundIsOn() ? .on : .off
        settingsMenu.addItem(cursorWorkaroundItem)

        if updatesEnabled {
            let autoUpdateItem = NSMenuItem(title: "Check for Updates Automatically", action: #selector(toggleAutoUpdate(_:)), keyEquivalent: "")
            autoUpdateItem.target = self
            autoUpdateItem.state = UpdateChecker.shared.autoCheckEnabled ? .on : .off
            settingsMenu.addItem(autoUpdateItem)
        }

        settingsMenu.addItem(NSMenuItem.separator())

        // Refresh rate submenu
        let refreshMenu = NSMenu()
        let currentRate = UserDefaults.standard.double(forKey: kRefreshRateKey)
        let rates: [(String, Double)] = [
            ("Auto (detect from monitor)", 0.0),
            ("60 Hz", 60.0),
            ("120 Hz", 120.0),
            ("144 Hz", 144.0),
            ("165 Hz", 165.0),
            ("240 Hz", 240.0),
        ]
        for (title, rate) in rates {
            let item = NSMenuItem(title: title, action: #selector(setRefreshRate(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = rate as NSNumber
            item.state = (currentRate == rate) ? .on : .off
            refreshMenu.addItem(item)
        }
        let refreshItem = NSMenuItem(title: "Refresh Rate", action: nil, keyEquivalent: "")
        refreshItem.submenu = refreshMenu
        settingsMenu.addItem(refreshItem)

        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        if updatesEnabled {
            let checkUpdateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
            checkUpdateItem.target = self
            menu.addItem(checkUpdateItem)
        }

        let aboutItem = NSMenuItem(title: "About \(AppBrand.displayName)", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        updateCursorMirrorWorkaroundState()
    }

    @objc func toggleStartAtLogin(_ sender: NSMenuItem) {
        let wasInstalled = LaunchAgentManager.shared.isInstalled
        let success: Bool
        if wasInstalled {
            success = LaunchAgentManager.shared.uninstall()
            debugLog("Start at Login disabled: \(success)")
        } else {
            success = LaunchAgentManager.shared.install()
            debugLog("Start at Login enabled: \(success)")
        }
        rebuildMenu()
        if !success {
            let alert = NSAlert()
            alert.messageText = wasInstalled ? "Could Not Disable Start at Login" : "Could Not Enable Start at Login"
            alert.informativeText = "Make sure \(AppBrand.displayName).app is installed in /Applications and try again."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    @objc func toggleAutoApply(_ sender: NSMenuItem) {
        let current = UserDefaults.standard.bool(forKey: kAutoApplyOnConnectKey)
        UserDefaults.standard.set(!current, forKey: kAutoApplyOnConnectKey)
        debugLog("Auto-apply on reconnect: \(!current)")
        rebuildMenu()
    }

    @objc func toggleAutoRestore(_ sender: NSMenuItem) {
        let current = UserDefaults.standard.bool(forKey: kAutoRestoreKey)
        UserDefaults.standard.set(!current, forKey: kAutoRestoreKey)
        debugLog("Auto-restore after crash: \(!current)")
        rebuildMenu()
    }

    @objc func toggleCursorMirrorWorkaround(_ sender: NSMenuItem) {
        let newValue = !cursorMirrorWorkaroundIsOn()
        UserDefaults.standard.set(newValue, forKey: kCursorMirrorWorkaroundKey)
        debugLog("Cursor mirror workaround: \(newValue)")
        rebuildMenu()
    }

    @objc func toggleAutoUpdate(_ sender: NSMenuItem) {
        UpdateChecker.shared.autoCheckEnabled = !UpdateChecker.shared.autoCheckEnabled
        debugLog("Auto-check updates: \(UpdateChecker.shared.autoCheckEnabled)")
        rebuildMenu()
    }

    @objc func setRefreshRate(_ sender: NSMenuItem) {
        guard let rate = sender.representedObject as? NSNumber else { return }
        UserDefaults.standard.set(rate.doubleValue, forKey: kRefreshRateKey)
        debugLog("Refresh rate set to: \(rate.doubleValue == 0 ? "Auto" : "\(rate.doubleValue) Hz")")
        rebuildMenu()
    }

    @objc func checkForUpdates() {
        UpdateChecker.shared.checkForUpdatesManually()
    }

    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = AppBrand.displayName
        alert.informativeText = """
            Version \(AppBrand.versionString)

            Unlocks crisp HiDPI scaling on external displays when macOS does not offer it.

            Created by AL in Dallas
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func addPresetItem(to menu: NSMenu, preset: String, title: String) {
        let item = NSMenuItem(title: title, action: #selector(applyPreset(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = preset
        menu.addItem(item)
    }

    func addCustomScaleItem(to menu: NSMenu, nativeWidth: UInt32, nativeHeight: UInt32, ppi: UInt32) {
        menu.addItem(NSMenuItem.separator())
        let item = NSMenuItem(title: "Custom Scale...", action: #selector(showCustomScale(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = ["width": nativeWidth, "height": nativeHeight, "ppi": ppi] as [String: UInt32]
        menu.addItem(item)
    }

    /// Largest pixel mode for this display (typical panel native / max resolution).
    private func maxPixelMode(for displayID: CGDirectDisplayID) -> (UInt32, UInt32)? {
        guard let modes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] else { return nil }
        var bestArea: Int64 = 0
        var bestW: Int32 = 0
        var bestH: Int32 = 0
        for mode in modes {
            let w = Int32(mode.pixelWidth)
            let h = Int32(mode.pixelHeight)
            let area = Int64(w) * Int64(h)
            if area > bestArea {
                bestArea = area
                bestW = w
                bestH = h
            }
        }
        guard bestArea > 0 else { return nil }
        return (UInt32(bestW), UInt32(bestH))
    }

    /// PPI for the virtual display: prefer EDID physical size from the real panel.
    private func estimatedPPI(for displayID: CGDirectDisplayID, nativeWidth: UInt32, nativeHeight: UInt32) -> UInt32 {
        let size = CGDisplayScreenSize(displayID)
        if size.width > 1 && size.height > 1 {
            let wIn = Double(size.width) / 25.4
            let hIn = Double(size.height) / 25.4
            guard wIn > 0.1 && hIn > 0.1 else { return fallbackPPI(nativeWidth: nativeWidth, nativeHeight: nativeHeight) }
            let ppiW = Double(nativeWidth) / wIn
            let ppiH = Double(nativeHeight) / hIn
            let ppi = (ppiW + ppiH) / 2.0
            return UInt32(min(240, max(96, ppi.rounded())))
        }
        return fallbackPPI(nativeWidth: nativeWidth, nativeHeight: nativeHeight)
    }

    private func fallbackPPI(nativeWidth: UInt32, nativeHeight: UInt32) -> UInt32 {
        let mx = max(nativeWidth, nativeHeight)
        let mn = min(nativeWidth, nativeHeight)
        if mx >= 7000 { return 140 }
        if mx >= 5000 && mn >= 2000 { return 118 }
        if mx >= 5000 { return 109 }
        if mx >= 3800 && mn >= 2000 { return 163 }
        if mx >= 3800 { return 110 }
        return 110
    }

    /// HiDPI logical resolutions = panel max pixels ÷ scale; one block for the connected monitor only.
    private func appendDynamicHiDPIMenuItems(to menu: NSMenu) {
        guard let displayID = findRealPhysicalMonitor() else {
            let note = NSMenuItem(title: "Connect an external display to see HiDPI scale options", action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
            return
        }

        let nw: UInt32
        let nh: UInt32
        if let m = maxPixelMode(for: displayID) {
            (nw, nh) = m
        } else if let mode = CGDisplayCopyDisplayMode(displayID) {
            nw = UInt32(mode.pixelWidth)
            nh = UInt32(mode.pixelHeight)
            debugLog("Using current display mode as panel size: \(nw)×\(nh)")
        } else {
            let note = NSMenuItem(title: "Could not read the panel’s resolution", action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
            return
        }

        guard nw > 0, nh > 0 else {
            let note = NSMenuItem(title: "Could not read the panel’s resolution", action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
            return
        }

        let ppi = estimatedPPI(for: displayID, nativeWidth: nw, nativeHeight: nh)
        let hint = NSMenuItem(title: "Panel max: \(nw) × \(nh)", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        // 1× entry — native panel resolution, no HiDPI scaling
        let native1xKey = PresetConfig.native1xPresetKey(width: nw, height: nh, ppi: ppi)
        addPresetItem(to: menu, preset: native1xKey, title: "\(nw)×\(nh) (1×)")

        let scales: [Double] = [1.25, 1.30, 4.0 / 3.0, 1.36, 1.40, 1.45, 1.50, 1.60, 1.75, 2.00]

        // Framebuffer widths (= logical * 2) that macOS Sequoia/Sonoma classify as AirPlay /
        // presentation targets, triggering "What do you want to show on…" and auto-enabling
        // Do Not Disturb for the session. Nudge the logical width by +1 so the framebuffer
        // misses these thresholds while keeping the scale step in the menu.
        let airPlayFramebufferWidths: Set<UInt32> = [7680, 8192]

        var seenLogical = Set<UInt64>()
        for scale in scales {
            var lw = UInt32(Double(nw) / scale)
            let lh = UInt32(Double(nh) / scale)
            if lw < 640 || lh < 480 { continue }
            // If framebuffer width would hit an AirPlay magic number, nudge by +1 logical pixel
            // (= +2 framebuffer pixels) to avoid the presentation-mode classification.
            if airPlayFramebufferWidths.contains(lw * 2) { lw += 1 }
            let key = (UInt64(lw) << 32) | UInt64(lh)
            if seenLogical.contains(key) { continue }
            seenLogical.insert(key)

            let roundedScale = (scale * 1000).rounded() / 1000
            let title = "\(lw)×\(lh) (\(String(format: "%.2f", roundedScale))×)"

            let presetKey = PresetConfig.dynamicPresetKey(logicalWidth: lw, logicalHeight: lh, ppi: ppi)
            addPresetItem(to: menu, preset: presetKey, title: title)
        }

        addCustomScaleItem(to: menu, nativeWidth: nw, nativeHeight: nh, ppi: ppi)
    }

    @objc func showCustomScale(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: UInt32],
              let nativeW = info["width"],
              let nativeH = info["height"],
              let ppi = info["ppi"] else { return }

        CustomScaleWindowController.shared.show(nativeWidth: nativeW, nativeHeight: nativeH, ppi: ppi) { [weak self] config in
            self?.applyCustomConfig(config)
        }
    }

    func applyCustomConfig(_ config: PresetConfig) {
        // User manually applying — reset failure counter for fresh attempt
        UserDefaults.standard.set(0, forKey: kMirrorFailureCountKey)
        // Save custom config to UserDefaults for crash recovery
        let presetKey = "custom-\(config.logicalWidth)x\(config.logicalHeight)"
        let customDict: [String: Any] = [
            "name": config.name,
            "width": config.width,
            "height": config.height,
            "logicalWidth": config.logicalWidth,
            "logicalHeight": config.logicalHeight,
            "ppi": config.ppi,
            "hiDPI": config.hiDPI
        ]
        UserDefaults.standard.set(customDict, forKey: "customPresetConfig")
        saveCurrentPreset(presetKey)

        // If a virtual display is already active, restart to switch cleanly
        if isActive || hasOrphanedVirtualDisplay() {
            debugLog("Active display exists, restarting to apply custom config cleanly...")
            isRestarting = true
            StatusWindowController.shared.show(message: "Switching preset...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                relaunchApp()
            }
            return
        }

        isSettingUp = true
        StatusWindowController.shared.show(message: "Preparing display configuration...")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            autoreleasepool {
                self?.createVirtualDisplayAsync(config: config)
            }
        }
    }

    @objc func applyPreset(_ sender: NSMenuItem) {
        guard let presetName = sender.representedObject as? String else { return }
        debugLog(">>> Applying preset: \(presetName)")

        // User manually applying — reset failure counter for fresh attempt
        UserDefaults.standard.set(0, forKey: kMirrorFailureCountKey)

        guard let config = PresetConfig(dynamicPresetKey: presetName)
                        ?? PresetConfig(native1xPresetKey: presetName) else {
            debugLog("ERROR: Unknown preset \(presetName)")
            return
        }

        // If a virtual display is already active, we must restart the app to switch.
        // CGVirtualDisplay objects persist until the process exits — releasing them
        // does NOT remove the display. Restarting lets macOS reclaim the old one,
        // and checkAndRestoreFromCrash() applies the new preset on relaunch.
        if isActive || hasOrphanedVirtualDisplay() {
            debugLog("Active display exists, saving new preset and restarting to switch cleanly...")
            isRestarting = true
            StatusWindowController.shared.show(message: "Switching preset...")
            saveCurrentPreset(presetName)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                relaunchApp()
            }
            return
        }

        // Mark that we're setting up (don't trigger cleanup during setup)
        isSettingUp = true

        // Show status window
        StatusWindowController.shared.show(message: "Preparing display configuration...")

        // Save the preset for crash recovery
        saveCurrentPreset(presetName)

        // Schedule creation after a delay using DispatchQueue instead of Timer
        // This gives us better control over autorelease pool behavior
        debugLog("Scheduling display creation in 1.5 seconds...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            autoreleasepool {
                self?.createVirtualDisplayAsync(config: config)
            }
        }
    }

    // Disable HiDPI when user explicitly requests it - clears preset (no auto-restore)
    func disableHiDPISync() {
        debugLog("Disabling HiDPI (user action) - currentVirtualID: \(currentVirtualID)")

        let manager = VirtualDisplayManager.shared()

        // Reset ALL mirroring to ensure clean state
        manager.resetAllMirroring()

        // Destroy our virtual display
        manager.destroyAllVirtualDisplays()

        currentVirtualID = 0
        targetExternalDisplayID = 0
        isActive = false
        currentPresetName = ""

        // Clear saved preset - user explicitly disabled, don't auto-restore
        clearSavedPreset()

        // Also clear the disconnected flag since user is taking explicit action
        wasDisconnected = false
        UserDefaults.standard.set(false, forKey: kWasDisconnectedKey)

        debugLog("HiDPI disabled (preset cleared)")
        setHiDPIMirrorActiveFlag(false)
        updateCursorMirrorWorkaroundState()
    }

    /// Get the refresh rate for the virtual display.
    /// Checks user's custom setting first, then auto-detects from physical monitor.
    func getDisplayRefreshRate(_ displayID: CGDirectDisplayID) -> Double {
        let customRate = UserDefaults.standard.double(forKey: kRefreshRateKey)
        if customRate > 0 {
            debugLog("Using custom refresh rate: \(customRate) Hz")
            return customRate
        }

        guard let mode = CGDisplayCopyDisplayMode(displayID) else {
            debugLog("Could not get display mode for \(displayID), defaulting to 60 Hz")
            return 60.0
        }
        let rate = mode.refreshRate
        debugLog("Display \(displayID) reports refresh rate: \(rate) Hz")
        return rate > 0 ? rate : 60.0
    }

    func createVirtualDisplayAsync(config: PresetConfig) {
        debugLog("Creating virtual display: \(config.width)x\(config.height)")

        StatusWindowController.shared.updateStatus("Detecting external display...")

        guard let externalID = findExternalDisplay() else {
            debugLog("ERROR: No external display found")
            isSettingUp = false  // Clear setup flag so reconnect detection works
            StatusWindowController.shared.updateStatus("No external display found")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                StatusWindowController.shared.hide()
            }
            rebuildMenu()
            return
        }
        debugLog("Using external display: \(externalID)")

        StatusWindowController.shared.updateStatus("Creating virtual display...")

        // Match the physical monitor's refresh rate to prevent flicker
        let refreshRate = getDisplayRefreshRate(externalID)
        debugLog("Will create virtual display at \(refreshRate) Hz to match physical monitor")

        // Create virtual display with color primaries matching the physical display.
        // This lets ColorSync use an identity transform instead of doing expensive
        // per-frame color conversion that was causing WindowServer deadlocks.
        let manager = VirtualDisplayManager.shared()
        debugLog("Calling createVirtualDisplay (matching display \(externalID))...")
        let virtualID = manager.createVirtualDisplay(
            withWidth: config.width,
            height: config.height,
            ppi: config.ppi,
            hiDPI: config.hiDPI,
            name: config.name,
            refreshRate: refreshRate,
            matchingDisplay: externalID
        )
        debugLog("createVirtualDisplay returned: \(virtualID)")

        if virtualID == 0 || virtualID == UInt32.max {
            debugLog("ERROR: Failed to create virtual display (returned \(virtualID))")
            isSettingUp = false  // Clear setup flag so reconnect detection works
            StatusWindowController.shared.updateStatus("Failed to create virtual display")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                StatusWindowController.shared.hide()
            }
            rebuildMenu()
            return
        }
        debugLog("Created virtual display: \(virtualID)")
        currentVirtualID = virtualID

        StatusWindowController.shared.updateStatus("Configuring display mirror...")

        // Wait for display to initialize
        debugLog("Scheduling mirror in 3 seconds...")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            autoreleasepool {
                self?.performMirror(virtualID: virtualID, externalID: externalID, config: config)
            }
        }
    }

    func performMirror(virtualID: CGDirectDisplayID, externalID: CGDirectDisplayID, config: PresetConfig) {
        debugLog("Setting up mirror: \(virtualID) -> \(externalID)")
        let manager = VirtualDisplayManager.shared()
        let success = manager.mirrorDisplay(virtualID, toDisplay: externalID)
        debugLog("Mirror result: \(success)")

        // Setup is complete (whether successful or not)
        isSettingUp = false

        if success {
            isActive = true
            currentPresetName = "\(config.logicalWidth)x\(config.logicalHeight)"
            targetExternalDisplayID = externalID  // Track target for disconnect detection
            UserDefaults.standard.set(0, forKey: kMirrorFailureCountKey)  // Reset failure counter
            saveMonitorFingerprint(externalID)
            setHiDPIMirrorActiveFlag(true)
            StatusWindowController.shared.updateStatus("HiDPI enabled: \(config.logicalWidth)x\(config.logicalHeight)")
            debugLog(">>> HiDPI setup complete, monitoring for disconnect")

            // Verify actual backing scale after display configuration settles
            if config.hiDPI {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.verifyBackingScale(externalID: externalID, config: config)
                }
            }
        } else {
            debugLog("Mirror failed, cleaning up...")
            manager.destroyVirtualDisplay(virtualID)
            currentVirtualID = 0
            isActive = false
            currentPresetName = ""

            // Track consecutive failures to prevent infinite restart loops
            let failCount = UserDefaults.standard.integer(forKey: kMirrorFailureCountKey) + 1
            UserDefaults.standard.set(failCount, forKey: kMirrorFailureCountKey)

            if failCount < maxMirrorRetries {
                // Allow retry — set wasDisconnected so periodic check will auto-apply
                wasDisconnected = true
                UserDefaults.standard.set(true, forKey: kWasDisconnectedKey)
                debugLog("Mirror failure \(failCount)/\(maxMirrorRetries), will retry when monitor is ready")
                StatusWindowController.shared.updateStatus("Waiting for display...")
            } else {
                // Too many failures — stop the auto-retry loop
                wasDisconnected = false
                UserDefaults.standard.set(false, forKey: kWasDisconnectedKey)
                debugLog("Mirror failed \(failCount) times, stopping auto-retry. Use menu to apply manually.")
                StatusWindowController.shared.updateStatus("Setup failed — apply manually from menu")
            }
        }

        // Hide status window after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            StatusWindowController.shared.hide()
        }

        rebuildMenu()
    }

    func verifyBackingScale(externalID: CGDirectDisplayID, config: PresetConfig) {
        var actualScale: CGFloat = 0
        var matchedScreen: NSScreen?

        for screen in NSScreen.screens {
            let deviceDesc = screen.deviceDescription
            if let screenNumber = deviceDesc[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                if screenNumber == externalID || screenNumber == currentVirtualID {
                    matchedScreen = screen
                    actualScale = screen.backingScaleFactor
                    break
                }
            }
        }

        // Mirrors collapse into a single NSScreen, fall back to main
        if matchedScreen == nil {
            if let main = NSScreen.main {
                matchedScreen = main
                actualScale = main.backingScaleFactor
            }
        }

        let isActuallyHiDPI = actualScale >= 2.0
        debugLog("Backing scale verification: scale=\(actualScale), isHiDPI=\(isActuallyHiDPI)")

        if let screen = matchedScreen {
            let frame = screen.frame
            let visibleFrame = screen.visibleFrame
            debugLog("  Screen frame: \(frame.width)x\(frame.height), visible: \(visibleFrame.width)x\(visibleFrame.height)")
        }

        if isActuallyHiDPI {
            debugLog("Verified: display is running at \(actualScale)x backing scale (true HiDPI)")
            currentPresetName = "\(config.logicalWidth)x\(config.logicalHeight)"
            StatusWindowController.shared.updateStatus("HiDPI active: \(config.logicalWidth)x\(config.logicalHeight) @\(Int(actualScale))x")
        } else {
            debugLog("WARNING: backing scale is \(actualScale)x — display is NOT in true HiDPI mode")
            currentPresetName = "\(config.logicalWidth)x\(config.logicalHeight) (1x)"
            StatusWindowController.shared.updateStatus("\(config.logicalWidth)x\(config.logicalHeight) active (not HiDPI — \(actualScale)x scale)")
        }

        cursorMirrorWorkaround.refreshPositionIfNeeded()
        rebuildMenu()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            StatusWindowController.shared.hide()
        }
    }

    func findExternalDisplay() -> CGDirectDisplayID? {
        var displayList = [CGDirectDisplayID](repeating: 0, count: 32)
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(32, &displayList, &displayCount)

        debugLog("findExternalDisplay: found \(displayCount) displays, currentVirtualID=\(currentVirtualID)")

        // Collect candidate displays with their physical sizes
        var candidates: [(id: CGDirectDisplayID, size: CGSize)] = []

        for i in 0..<Int(displayCount) {
            let displayID = displayList[i]
            let isBuiltin = CGDisplayIsBuiltin(displayID) != 0
            let vendorID = CGDisplayVendorNumber(displayID)
            let isVirtualDisplay = vendorID == 0x1234  // Our virtual displays use vendor 0x1234
            let isGhostDisplay = vendorID == 0x756E6B6E  // "unkn" — phantom display without EDID

            // Skip builtin, virtual, and ghost/phantom displays
            if !isBuiltin && !isVirtualDisplay && !isGhostDisplay {
                // Only call CGDisplayScreenSize on real displays — calling it on
                // virtual displays triggers expensive ColorSync profile lookups
                // that can deadlock colorsync.displayservices and freeze WindowServer.
                let size = CGDisplayScreenSize(displayID)
                debugLog("  Display \(displayID): builtin=\(isBuiltin), vendor=\(vendorID), size=\(size.width)x\(size.height)mm")
                candidates.append((id: displayID, size: size))
            } else {
                debugLog("  Display \(displayID): builtin=\(isBuiltin), vendor=\(vendorID), isVirtual=\(isVirtualDisplay) — skipped")
            }
        }

        // Prefer displays with large physical size (real monitors vs virtual).
        // Sort by width descending to prefer larger displays.
        candidates.sort { $0.size.width > $1.size.width }

        if let best = candidates.first {
            debugLog("  -> Selected external display: \(best.id) (\(best.size.width)mm wide)")
            return best.id
        }

        debugLog("  -> No external display found")
        return nil
    }

    func saveMonitorFingerprint(_ displayID: CGDirectDisplayID) {
        let vendor = Int(CGDisplayVendorNumber(displayID))
        let model = Int(CGDisplayModelNumber(displayID))
        UserDefaults.standard.set(vendor, forKey: kBoundMonitorVendorKey)
        UserDefaults.standard.set(model, forKey: kBoundMonitorModelKey)
        debugLog("Saved monitor fingerprint: vendor=\(vendor), model=\(model)")
    }

    func connectedMonitorMatchesSavedPreset() -> Bool {
        guard UserDefaults.standard.object(forKey: kBoundMonitorVendorKey) != nil else {
            return true
        }

        let savedVendor = UserDefaults.standard.integer(forKey: kBoundMonitorVendorKey)
        let savedModel = UserDefaults.standard.integer(forKey: kBoundMonitorModelKey)

        guard let displayID = findRealPhysicalMonitor() else { return false }

        let currentVendor = Int(CGDisplayVendorNumber(displayID))
        let currentModel = Int(CGDisplayModelNumber(displayID))

        let matches = (currentVendor == savedVendor && currentModel == savedModel)
        if !matches {
            debugLog("Monitor mismatch: saved=(\(savedVendor),\(savedModel)) current=(\(currentVendor),\(currentModel)) — skipping auto-apply")
        }
        return matches
    }

    @objc func cleanUpDisplays() {
        debugLog("Manual cleanup requested by user")
        isRestarting = true
        StatusWindowController.shared.show(message: "Cleaning up phantom displays...")

        // Reset mirroring and destroy any in-process displays
        let manager = VirtualDisplayManager.shared()
        manager.resetAllMirroring()
        manager.destroyAllVirtualDisplays()

        isActive = false
        currentPresetName = ""
        currentVirtualID = 0
        updateCursorMirrorWorkaroundState()

        // Keep kLastPresetKey — user wants to clean phantoms, not lose their preset.
        // checkAndRestoreFromCrash() will re-apply it after the restart.

        StatusWindowController.shared.updateStatus("Restarting to finish cleanup...")

        // Restart the app — macOS reclaims virtual displays from the dead process
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            markCleanupRestart()
            relaunchApp()
        }
    }

    @objc func disableHiDPIAction() {
        // Virtual displays persist until process exit — must restart to truly remove them
        if isActive || hasOrphanedVirtualDisplay() {
            StatusWindowController.shared.show(message: "Disabling HiDPI...")
            isRestarting = true
            // Clear preset so relaunch does NOT restore
            clearSavedPreset()
            wasDisconnected = false
            UserDefaults.standard.set(false, forKey: kWasDisconnectedKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                relaunchApp()
            }
            return
        }
        // No active display — just clean up in-process state
        disableHiDPISync()
        rebuildMenu()
    }

    @objc func quitApp() {
        debugLog("Quit requested by user")

        // Move windows before quitting
        if isActive {
            moveAllWindowsToMainDisplay()
        }

        disableHiDPISync()
        NSApp.terminate(nil)
    }
}

// MARK: - Preset Configurations

struct PresetConfig {
    let name: String
    let width: UInt32      // Framebuffer width
    let height: UInt32     // Framebuffer height
    let logicalWidth: UInt32
    let logicalHeight: UInt32
    let ppi: UInt32
    let hiDPI: Bool
}

extension PresetConfig {
    /// HiDPI scaled entry: `dyn:<logicalW>:<logicalH>:<ppi>` — framebuffer = logical × 2
    static func dynamicPresetKey(logicalWidth: UInt32, logicalHeight: UInt32, ppi: UInt32) -> String {
        "dyn:\(logicalWidth):\(logicalHeight):\(ppi)"
    }

    init?(dynamicPresetKey key: String) {
        guard key.hasPrefix("dyn:") else { return nil }
        let rest = String(key.dropFirst(4))
        let parts = rest.split(separator: ":")
        guard parts.count == 3,
              let lw = UInt32(parts[0]), let lh = UInt32(parts[1]), let ppi = UInt32(parts[2]),
              lw > 0, lh > 0, ppi > 0 else { return nil }
        self.init(
            name: "Virtual Screen",
            width: lw * 2,
            height: lh * 2,
            logicalWidth: lw,
            logicalHeight: lh,
            ppi: ppi,
            hiDPI: true
        )
    }

    /// 1× native entry: `dyn1x:<w>:<h>:<ppi>` — framebuffer = logical (no 2× scaling)
    static func native1xPresetKey(width: UInt32, height: UInt32, ppi: UInt32) -> String {
        "dyn1x:\(width):\(height):\(ppi)"
    }

    init?(native1xPresetKey key: String) {
        guard key.hasPrefix("dyn1x:") else { return nil }
        let rest = String(key.dropFirst(6))
        let parts = rest.split(separator: ":")
        guard parts.count == 3,
              let w = UInt32(parts[0]), let h = UInt32(parts[1]), let ppi = UInt32(parts[2]),
              w > 0, h > 0, ppi > 0 else { return nil }
        self.init(
            name: "Virtual Screen",
            width: w,
            height: h,
            logicalWidth: w,
            logicalHeight: h,
            ppi: ppi,
            hiDPI: false
        )
    }
}
