import SwiftUI

@main
struct PawPauseApp: App {
    @StateObject private var controller = GuardController()

    var body: some Scene {
        MenuBarExtra {
            MenuView(c: controller)
        } label: {
            Image(systemName: controller.menuSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuView: View {
    @ObservedObject var c: GuardController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: c.menuSymbol)
                    .font(.title2)
                    .foregroundStyle(c.isBlocking ? .red : .primary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Paw Pause").font(.headline)
                    Text(c.statusText).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(c.statusColor).frame(width: 9, height: 9)
            }

            Divider()

            Toggle("Cat Mode armed", isOn: $c.isArmed)
                .toggleStyle(.switch)
                .disabled(!c.hasPermissions)

            Group {
                Toggle("Stay locked until I unlock", isOn: $c.stayLocked)
                Toggle("Notify when paused", isOn: $c.notifyOnClamp)
                Toggle("Play sound when paused", isOn: $c.soundOnClamp)
            }
            .font(.callout)
            .disabled(!c.isArmed)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Sensitivity").font(.callout)
                    Spacer()
                    Text(sensitivityLabel).font(.caption).foregroundStyle(.secondary)
                }
                // Lower threshold = more sensitive, so invert for an intuitive slider.
                Slider(value: $c.threshold, in: 0.6...1.6, step: 0.1)
                    .disabled(!c.isArmed)
            }

            if c.isBlocking {
                Button {
                    c.manualUnlock()
                } label: {
                    Label("Unlock keyboard", systemImage: "lock.open")
                }
                .keyboardShortcut(.defaultAction)
                Text("Tip: pressing Esc always releases.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if !c.hasPermissions {
                Divider()
                Text("App needs permission to watch and pause.")
                    .font(.caption).foregroundStyle(.orange)
                Button("Open System Settings") { c.openSettings() }
                Button("Restart Paw Pause") { c.restartApp() }
                    .font(.caption)
            }

            Divider()
            Button("Quit Paw Pause") { NSApplication.shared.terminate(nil) }
        }
        .padding(14)
        .frame(width: 280)
        .onAppear { c.refreshPermissions() }
    }

    private var sensitivityLabel: String {
        switch c.threshold {
        case ..<0.85: return "High"
        case ..<1.15: return "Balanced"
        default: return "Relaxed"
        }
    }
}
