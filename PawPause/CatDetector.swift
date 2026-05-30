import Foundation
import CoreGraphics

/// Paw Pause detection engine — a direct port of the published library core
/// (the same six weighted signals, 1.5s window, threshold 1.0, 1s auto-release).
/// Framework-agnostic: it only knows about key codes and time, not the DOM or AppKit.
final class CatDetector {

    // Tunables — identical defaults to the JS library.
    var threshold: Double = 1.0
    var stayLocked: Bool = false
    private let windowSeconds: TimeInterval = 1.5
    private let releaseSilence: TimeInterval = 1.0

    // Signal weights.
    private let wConcurrent = 0.7   // 3+ keys held at once
    private let wConcurrentHi = 0.7 // 5+ keys held — sitting on it
    private let wBurst = 0.4        // 8+ keys/sec
    private let wCluster = 0.4      // 3+ consecutive adjacent keys (paw roll)
    private let wRepeat = 0.3       // same key 6+ times
    private let wNoStruct = 0.2     // 6+ keys, no space/return/delete/tab

    /// The set of signal ids currently firing — surfaced to the UI for the live readout.
    private(set) var firing: Set<String> = []
    private(set) var score: Double = 0

    private struct Stroke { let code: Int64; let time: TimeInterval }
    private var window: [Stroke] = []
    private var keysDown: Set<Int64> = []
    private var lastEvent: TimeInterval = 0
    private(set) var blocking = false

    // CGKeyCode of Escape — the guaranteed human override; never scored, never swallowed.
    static let escapeKey: Int64 = 53
    // Keys that count as "human structure".
    private static let structural: Set<Int64> = [49, 36, 51, 48, 76] // space, return, delete, tab, keypadEnter

    private func now() -> TimeInterval { Date().timeIntervalSinceReferenceDate }

    /// Feed a keyDown. Returns true if input should be suppressed (cat detected).
    func feedDown(_ code: Int64, repeating: Bool) -> Bool {
        let t = now()
        lastEvent = t
        if !repeating { keysDown.insert(code) }
        window.append(Stroke(code: code, time: t))
        prune(t)
        recompute()
        if score >= threshold { blocking = true }
        return blocking
    }

    func feedUp(_ code: Int64) {
        keysDown.remove(code)
    }

    /// Drive auto-release. Call on keyUp and on a timer. Returns true on the tick it releases.
    func tickAutoRelease() -> Bool {
        guard blocking, !stayLocked else { return false }
        if keysDown.isEmpty && (now() - lastEvent) >= releaseSilence {
            reset()
            return true
        }
        return false
    }

    func unlock() { reset() }

    func reset() {
        window.removeAll()
        keysDown.removeAll()
        blocking = false
        score = 0
        firing = []
    }

    private func prune(_ t: TimeInterval) {
        window.removeAll { t - $0.time > windowSeconds }
    }

    private func recompute() {
        var s = 0.0
        var fired = Set<String>()

        let held = keysDown.count
        if held >= 3 { s += wConcurrent; fired.insert("concurrent") }
        if held >= 5 { s += wConcurrentHi; fired.insert("concurrentHi") }

        let rate = Double(window.count) / windowSeconds
        if rate >= 8 { s += wBurst; fired.insert("burst") }

        var run = 0
        if window.count >= 2 {
            for i in 1..<window.count where Self.areAdjacent(window[i-1].code, window[i].code) { run += 1 }
        }
        if run >= 3 { s += wCluster; fired.insert("cluster") }

        var counts: [Int64: Int] = [:]
        for st in window { counts[st.code, default: 0] += 1 }
        if counts.values.contains(where: { $0 >= 6 }) { s += wRepeat; fired.insert("repeat") }

        let usedStructure = window.contains { Self.structural.contains($0.code) }
        if window.count >= 6 && !usedStructure { s += wNoStruct; fired.insert("nostruct") }

        score = s
        firing = fired
    }

    // MARK: QWERTY adjacency (by CGKeyCode, US layout)

    static func areAdjacent(_ a: Int64, _ b: Int64) -> Bool {
        guard a != b else { return false }
        return adjacency[a]?.contains(b) ?? false
    }

    private static let adjacency: [Int64: Set<Int64>] = {
        let rows: [[Int64]] = [
            [12,13,14,15,17,16,32,34,31,35], // q w e r t y u i o p
            [0,1,2,3,5,4,38,40,37],          // a s d f g h j k l
            [6,7,8,9,11,45,46,43,47],        // z x c v b n m , .
        ]
        var map: [Int64: Set<Int64>] = [:]
        for (r, row) in rows.enumerated() {
            for (c, key) in row.enumerated() {
                var n = Set<Int64>()
                if c > 0 { n.insert(row[c-1]) }
                if c < row.count - 1 { n.insert(row[c+1]) }
                for dr in [r-1, r+1] where dr >= 0 && dr < rows.count {
                    for oc in [c-1, c, c+1] where oc >= 0 && oc < rows[dr].count {
                        n.insert(rows[dr][oc])
                    }
                }
                map[key, default: []].formUnion(n)
            }
        }
        return map
    }()
}
