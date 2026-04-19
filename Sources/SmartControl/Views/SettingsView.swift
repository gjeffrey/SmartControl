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
                Toggle("Notify when self-tests finish or drive health gets worse", isOn: $model.notificationsEnabled)

                Button("Refresh Now") {
                    Task { await model.refresh(forcePrivilegePrompt: model.preferAdministratorAccess) }
                }
            }

            Section("How SmartControl Works") {
                Text("Drive discovery comes from Disk Utility. Deep health data comes from smartctl JSON so the app can turn low-level output into clear health summaries, metrics, and actions.")
                    .foregroundStyle(.secondary)

                Text("Notifications are only used for meaningful events, like a self-test finishing or a drive moving into a worse health state while SmartControl is not frontmost.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.notificationsEnabled) { oldValue, newValue in
            Task { await model.handleNotificationPreferenceChange(from: oldValue, to: newValue) }
        }
    }
}
