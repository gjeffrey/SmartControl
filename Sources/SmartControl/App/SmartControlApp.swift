import AppKit
import SwiftUI

@main
struct SmartControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("SmartControl") {
            ContentView(model: model)
                .frame(minWidth: 1080, minHeight: 720)
                .task {
                    if model.snapshots.isEmpty {
                        await model.refresh()
                    }
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Drives") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r")

                Button("Refresh with Administrator Access") {
                    Task { await model.refresh(forcePrivilegePrompt: true) }
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
            }

            CommandMenu("SMART") {
                Button("Export Diagnostics") {
                    Task { await model.exportDiagnostics() }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                Button("Run Short Self-Test") {
                    Task { await model.runSelfTest(.short) }
                }
                .disabled(model.selectedSnapshot == nil)

                Button("Run Extended Self-Test") {
                    Task { await model.runSelfTest(.extended) }
                }
                .disabled(model.selectedSnapshot == nil)
            }
        }

        Settings {
            SettingsView(model: model)
                .frame(width: 520)
                .padding(24)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
