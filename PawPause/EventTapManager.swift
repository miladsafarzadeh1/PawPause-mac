import Foundation
import CoreGraphics
import ApplicationServices

/// Owns the global CGEvent tap. Routes keyboard events through CatDetector and
/// swallows them system-wide while clamped. Escape is never swallowed — it is
/// the guaranteed human override.
final class EventTapManager {

    let detector = CatDetector()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Fired on the main thread whenever the clamp state flips, for UI + notifications.
    var onBlockingChanged: ((Bool) -> Void)?

    // MARK: Permissions

    static func hasInputMonitoring() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }
    static func hasAccessibility() -> Bool { AXIsProcessTrusted() }
    static func promptAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }

    // MARK: Lifecycle

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let ptr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,           // active tap: may swallow events
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: ptr
        ) else { return false }

        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = src
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes) }
        tap = nil
        runLoopSource = nil
        setBlocking(false)
        detector.reset()
    }

    func manualUnlock() {
        detector.unlock()
        setBlocking(false)
    }

    /// Called from a timer to handle the "cat parked on the keys" auto-release case.
    func pollAutoRelease() {
        if detector.tickAutoRelease() { setBlocking(false) }
    }

    // MARK: Event handling

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system disables the tap on timeout/heavy load — re-enable and pass through.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let code = event.getIntegerValueField(.keyboardEventKeycode)

        // Escape is the human override: while clamped it releases instead of typing.
        if type == .keyDown && code == CatDetector.escapeKey {
            if detector.blocking {
                manualUnlock()
                return nil // consume this Esc so it doesn't reach apps
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            let repeating = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let wasBlocking = detector.blocking
            let block = detector.feedDown(code, repeating: repeating)
            if block && !wasBlocking { setBlocking(true) }
            if detector.blocking { return nil }    // swallow

        case .keyUp:
            detector.feedUp(code)
            if detector.tickAutoRelease() { setBlocking(false); return Unmanaged.passUnretained(event) }
            if detector.blocking { return nil }

        case .flagsChanged:
            if detector.blocking { return nil }

        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private func setBlocking(_ v: Bool) {
        DispatchQueue.main.async { [weak self] in self?.onBlockingChanged?(v) }
    }
}

private func tapCallback(proxy: CGEventTapProxy, type: CGEventType,
                         event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let mgr = Unmanaged<EventTapManager>.fromOpaque(userInfo).takeUnretainedValue()
    return mgr.handle(type, event)
}
