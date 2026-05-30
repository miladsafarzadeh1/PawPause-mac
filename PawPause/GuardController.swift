import SwiftUI
import AppKit
import UserNotifications
import Combine

@MainActor
final class GuardController: ObservableObject {

    @Published var isArmed = false { didSet { armChanged() } }
    @Published var stayLocked = false { didSet { tap.detector.stayLocked = stayLocked } }
    @Published var threshold: Double = 1.0 { didSet { tap.detector.threshold = threshold } }
    @Published var notifyOnClamp = true
    @Published var soundOnClamp = true
    @Published var isBlocking = false
    @Published var hasPermissions = false

    private let tap = EventTapManager()
    private var pollTimer: Timer?

    private let notifDelegate = NotifDelegate()

    init() {
        tap.onBlockingChanged = { [weak self] blocking in
            guard let self else { return }
            self.isBlocking = blocking
            if blocking { self.announceClamp() }
        }
        UNUserNotificationCenter.current().delegate = notifDelegate   // <-- add this line
        refreshPermissions()
        requestNotificationAuth()
    }

    // MARK: Derived UI state

    var menuSymbol: String {
        if isBlocking { return "pawprint" }
        if isArmed { return "pawprint.fill" }
        return "pawprint"
    }
    var statusText: String {
        if !hasPermissions { return "Permissions needed" }
        if isBlocking { return "Paused — cat detected" }
        if isArmed { return "Armed — watching" }
        return "Off"
    }
    var statusColor: Color {
        if isBlocking { return .red }
        if isArmed { return .green }
        return .secondary
    }

    // MARK: Actions
    
    
    /// Try to (re)activate without a restart: re-read status, and if armed,
    /// tear down and rebuild the tap so a newly-granted permission is picked up.
    func recheckAndReactivate() {
        refreshPermissions()
        guard hasPermissions, isArmed else { return }
        tap.stop()
        _ = tap.start()
    }

    /// Relaunch the app — the reliable way to pick up newly granted permissions.
    func restartApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private func armChanged() {
        if isArmed {
            refreshPermissions()
            guard hasPermissions else {
                EventTapManager.promptAccessibility()
                isArmed = false
                return
            }
            tap.detector.threshold = threshold
            tap.detector.stayLocked = stayLocked
            if tap.start() { startPolling() } else { isArmed = false }
        } else {
            tap.stop()
            stopPolling()
            isBlocking = false
        }
    }

    func manualUnlock() { tap.manualUnlock() }

    func refreshPermissions() {
        hasPermissions = EventTapManager.hasInputMonitoring() && EventTapManager.hasAccessibility()
    }

    func openSettings() {
        EventTapManager.promptAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Clamp feedback

    private func announceClamp() {
        if soundOnClamp { NSSound(named: "Funk")?.play() }
        guard notifyOnClamp else { return }
        let content = UNMutableNotificationContent()
        content.title = "Paw Pause"
        content.body = "Cat detected — keyboard paused. Press Esc to override."
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func requestNotificationAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // Poll covers the case where a cat sits on keys with no keyUp.
    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tap.pollAutoRelease() }
        }
    }
    private func stopPolling() { pollTimer?.invalidate(); pollTimer = nil }
}

final class NotifDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
    
    
}

