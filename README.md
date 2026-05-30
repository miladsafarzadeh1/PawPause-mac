# 🐾 Paw Pause for macOS

A menu bar app that detects when your cat walks on the keyboard and **pauses the
keyboard system-wide** — so nothing types into Slack, Terminal, or anywhere, and
no key combos can fire shortcuts. Same detection model as the `pawpause` library
(six weighted signals, 1.5s window, threshold 1.0, ~1s auto-release).

## What happens when a cat is detected (behavior spec)

1. **Clamp.** When the rolling score crosses the threshold, Paw Pause swallows
   every keyboard event before it reaches any application. Typing and shortcuts
   are both blocked.
2. **Feedback.** The menu bar icon turns into a filled red paw; an optional
   notification and soft sound fire once.
3. **Release**, by any of:
   - **Auto-release** — the moment the keyboard is quiet and no keys are held
     (~1s). This also covers a cat *parked* on the keys: keys stay held → still
     clamped → releases when it leaves.
   - **Escape** — the one key Paw Pause never swallows. Your guaranteed human
     override; press it and the clamp lifts instantly.
   - **Unlock** in the menu, or turning off Cat Mode.
   - "Stay locked until I unlock" disables auto-release for a persistent cat.

### Honest limitation
Unlike the browser library that you can find in my profile, a system-wide tap **cannot roll back** text already
typed into arbitrary apps — it has no way to know or undo what landed in which
app. So native mode is *suppression only*: it stops the burst going forward, and
a few characters may slip through before the score crosses the threshold. Raise
the sensitivity (lower threshold) to clamp sooner. This is inherent to catching
input live across the whole OS.

## Build (personal use, run locally)

1. Install Xcode. File → New → Project → macOS → **App**.
   - Product Name: `PawPause` · Interface: **SwiftUI** · Language: **Swift**
2. Delete the generated `ContentView.swift` and the default `…App.swift`.
3. Drag these four files into the project:
   `PawPauseApp.swift`, `GuardController.swift`, `EventTapManager.swift`, `CatDetector.swift`
4. Apply the keys from `Info.plist` (target → Info tab), especially:
   - `Application is agent (UIElement)` = **YES** (`LSUIElement`)
   - the Input Monitoring + Apple Events usage strings
5. **Signing & Capabilities:** set your Team (a free personal Apple ID works for
   local runs). **Remove the App Sandbox capability** if present — event taps do
   NOT work sandboxed. This is the #1 gotcha.
6. Build & run. The app appears only in the menu bar.

## Granting permissions (one time, required)

On first arm, macOS blocks the tap until you grant both:

- **System Settings → Privacy & Security → Input Monitoring** → enable Paw Pause
- **System Settings → Privacy & Security → Accessibility** → enable Paw Pause

Then quit and relaunch Paw Pause so the grants take effect. The menu shows an
orange notice with a shortcut button until both are on.

## Testing without a cat

- Mash 4–5 adjacent keys at once (a s d f g) → red paw, keyboard pauses.
- Type a normal sentence with spaces → passes through.
- Press Esc while clamped → instant release.
- Drag the **Sensitivity** slider and re-test to tune `threshold` for your cat.



