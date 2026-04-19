import Observation
import SwiftUI

struct AttentionCenterView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                attentionHero
                attentionSummary
                recentEvents
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Attention Center")
    }

    private var attentionHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Attention Center")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("SmartControl surfaces the drives and events that deserve a second look, so you do not have to scan every disk manually.")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task { await model.exportDiagnostics() }
                } label: {
                    Label("Export Diagnostics", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var attentionSummary: some View {
        let items = model.attentionItems

        return VStack(alignment: .leading, spacing: 16) {
            Text("Current Attention")
                .font(.headline)
                .foregroundStyle(.secondary)

            if items.isEmpty {
                Text("No current warnings or critical events. SmartControl will keep watching for changes while the app is open.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    Button {
                        model.selection = item.deviceIdentifier
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.severity == .critical ? "exclamationmark.octagon.fill" : "bell.badge.fill")
                                .foregroundStyle(item.severity == .critical ? .red : .orange)
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.deviceName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(item.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(item.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Formatters.dateTime(item.createdAt))
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(18)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var recentEvents: some View {
        let events = model.allRecentEvents()

        return VStack(alignment: .leading, spacing: 16) {
            Text("Recent Events")
                .font(.headline)
                .foregroundStyle(.secondary)

            if events.isEmpty {
                Text("No recent events yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(events) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.severity == .critical ? "waveform.path.ecg.rectangle.fill" : "dot.radiowaves.left.and.right")
                            .foregroundStyle(item.severity == .critical ? .red : .secondary)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(item.deviceName): \(item.title)")
                                .font(.headline)
                            Text(item.detail)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(Formatters.dateTime(item.createdAt))
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
