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

                Button("Refresh Now") {
                    Task { await model.refresh(forcePrivilegePrompt: model.preferAdministratorAccess) }
                }
            }

            Section("How SmartControl Works") {
                Text("Drive discovery comes from Disk Utility. Deep health data comes from smartctl JSON so the app can turn low-level output into clear health summaries, metrics, and actions.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
