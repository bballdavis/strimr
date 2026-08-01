import SwiftUI

@MainActor
struct SettingsDownloadsView: View {
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        List {
            Section {
                Toggle(
                    "settings.downloads.wifiOnly",
                    isOn: Binding(
                        get: { settingsManager.downloads.wifiOnly },
                        set: { settingsManager.setDownloadWiFiOnly($0) },
                    ),
                )
            } footer: {
                Text("settings.downloads.wifiOnly.footer")
            }

            Section {
                Picker(
                    "Download Quality",
                    selection: Binding(
                        get: { settingsManager.downloads.quality },
                        set: { settingsManager.setDownloadQuality($0) },
                    ),
                ) {
                    ForEach(DownloadQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                .pickerStyle(.navigationLink)
            } header: {
                Text("Download Quality")
            } footer: {
                Text("Applies to future downloads. Lower qualities are prepared by Plex Media Server before transfer.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("settings.downloads.title")
    }
}
