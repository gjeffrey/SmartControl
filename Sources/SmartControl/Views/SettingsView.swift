import Observation
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("smartctl") {
                TextField("/opt/homebrew/sbin/smartctl", text: $model.smartctlPathOverride)
                    .textFieldStyle(.roundedBorder)

                MarkdownText("Recommended install: [Homebrew](https://brew.sh). Leave this blank to auto-detect smartctl from common Homebrew locations first.")
                    .foregroundStyle(.secondary)

                InstallCommandRow(command: "brew install smartmontools")

                Toggle("Always use administrator access when reading SMART data", isOn: $model.preferAdministratorAccess)
                    .contextualHelp(TermGlossary.setting("Always use administrator access when reading SMART data"))
                Toggle("Notify when self-tests finish or drive health gets worse", isOn: $model.notificationsEnabled)
                    .contextualHelp(TermGlossary.setting("Notify when self-tests finish or drive health gets worse"))

                notificationStatusView

                Button("Refresh Now") {
                    Task { await model.refresh(forcePrivilegePrompt: false, respectAdminPreference: false) }
                }
            }

            Section("Monitoring") {
                Picker("Background Checks", selection: $model.monitoringCadence) {
                    ForEach(MonitoringCadence.allCases) { cadence in
                        Text(cadence.title).tag(cadence)
                    }
                }
                .contextualHelp(TermGlossary.setting("Background Checks"))

                Toggle("Only monitor external drives", isOn: $model.monitoringExternalOnly)
                    .contextualHelp(TermGlossary.setting("Only monitor external drives"))

                Text("Monitoring runs only while SmartControl is open. It checks connected drives quietly without prompting for administrator access.")
                    .foregroundStyle(.secondary)
            }

            Section("App") {
                Label("Version \(bundleVersion) (\(bundleBuild))", systemImage: "shippingbox")
                    .foregroundStyle(.secondary)

                Text("Local release builds are currently ad-hoc signed for testing. Public GitHub releases should move to Developer ID signing and notarization before Sparkle auto-update is added.")
                    .foregroundStyle(.secondary)
            }

            Section("How SmartControl Works") {
                Text("Drive discovery comes from Disk Utility. Deep health data comes from smartctl JSON so the app can turn low-level output into clear health summaries, metrics, and actions.")
                    .foregroundStyle(.secondary)

                Text("Notifications are only used for meaningful events, like a self-test finishing or a drive moving into a worse health state while SmartControl is not frontmost.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            await model.refreshNotificationAuthorizationStatus()
        }
        .onChange(of: model.notificationsEnabled) { oldValue, newValue in
            Task { await model.handleNotificationPreferenceChange(from: oldValue, to: newValue) }
        }
        .onChange(of: model.monitoringCadence) { _, _ in
            model.updateMonitoringPreferences()
        }
        .onChange(of: model.monitoringExternalOnly) { _, _ in
            model.updateMonitoringPreferences()
        }
    }

    @ViewBuilder
    private var notificationStatusView: some View {
        switch model.notificationAuthorizationStatus {
        case .authorized, .provisional:
            Label("macOS notifications are allowed for SmartControl.", systemImage: "bell.badge")
                .foregroundStyle(.secondary)
        case .notDetermined:
            Label("Turn this on and macOS should ask once for notification permission.", systemImage: "bell")
                .foregroundStyle(.secondary)
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                Label("macOS notifications are currently turned off for SmartControl.", systemImage: "bell.slash")
                    .foregroundStyle(.secondary)

                Button("Open Notification Settings") {
                    model.openNotificationSettings()
                }
                .buttonStyle(.link)
            }
        case .unknown:
            Label("SmartControl could not confirm notification permission yet.", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private var bundleVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Dev"
    }

    private var bundleBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
}
