import Observation
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
        } detail: {
            if model.isShowingAttentionCenter {
                AttentionCenterView(model: model)
            } else {
                DriveDetailView(model: model)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $model.searchText, prompt: "Search drives")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh drive data")

                Button {
                    Task { await model.refresh(forcePrivilegePrompt: true) }
                } label: {
                    Label("Refresh as Admin", systemImage: "lock.open.display")
                }
                .help("Refresh using administrator access")

                Menu {
                    Button("Export Diagnostics") {
                        Task { await model.exportDiagnostics() }
                    }

                    Divider()

                    Button("Run Short Self-Test") {
                        Task { await model.runSelfTest(.short) }
                    }
                    .disabled(model.selectedSnapshot == nil)

                    Button("Run Extended Self-Test") {
                        Task { await model.runSelfTest(.extended) }
                    }
                    .disabled(model.selectedSnapshot == nil)
                } label: {
                    Label("Actions", systemImage: "play.circle")
                }
            }

            ToolbarItem(placement: .automatic) {
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Refreshing drives")
                }
            }

            ToolbarItem(placement: .automatic) {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            model.handleScenePhaseChange(isActive: newValue == .active)

            guard newValue == .active else { return }
            Task { await model.recheckMissingSmartctlIfNeeded() }
        }
        .onChange(of: model.selection) { _, _ in
            Task { await model.recheckMissingSmartctlIfNeeded() }
        }
        .task {
            model.handleScenePhaseChange(isActive: scenePhase == .active)
        }
    }
}
