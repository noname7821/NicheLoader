import SwiftUI

struct InstallView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    var app: StoredApp

    @State private var phase: Phase = .packaging
    @State private var detail = ""
    @State private var server: LocalInstallServer?
    @State private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                statusIcon
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                if phase == .installing {
                    ProgressView()
                }
                if phase == .ready || phase == .finished {
                    Button(phase == .ready ? "Install now" : "Install again") {
                        openInstaller()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }
                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("Install")
            .navigationBarItems(leading: Button("Close") {
                endBackgroundTask()
                server?.stop()
                BackgroundAudioService.shared.stop()
                dismiss()
            })
            .onAppear(perform: start)
            .onDisappear {
                endBackgroundTask()
                server?.stop()
                BackgroundAudioService.shared.stop()
            }
            .onAppear(perform: start)
            .onDisappear {
                server?.stop()
                BackgroundAudioService.shared.stop()
            }
            .onAppear(perform: start)
            .onDisappear {
                server?.stop()
                BackgroundAudioService.shared.stop()
            }
        }
    }

    private enum Phase {
        case packaging, ready, installing, finished, failed
    }

    private var title: String {
        switch phase {
        case .packaging: return "Packaging…"
        case .ready: return "Ready to install"
        case .installing: return "Installing…"
        case .finished: return "Sent to installer"
        case .failed: return "Install failed"
        }
    }

    private var statusIcon: some View {
        Group {
            switch phase {
            case .packaging, .installing:
                ProgressView().scaleEffect(1.6)
            case .ready:
                Image(systemName: "app.badge.checkmark").font(.system(size: 52)).foregroundStyle(.purple)
            case .finished:
                Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(.green)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 52)).foregroundStyle(.red)
            }
        }
        .frame(height: 64)
    }

    private func start() {
        guard server == nil else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let ipa = try library.packageSignedApp(app)
                let icon = library.iconURL(for: app, signed: true)
                    .flatMap { try? Data(contentsOf: $0) }
                    ?? UIImage(named: "AboutIcon")?.pngData()
                    ?? Data()
                let installer = LocalInstallServer()
                installer.ipaURL = ipa
                installer.iconData = icon
                try installer.start()
                installer.manifestData = Data(manifest(
                    bundleID: app.identifier,
                    version: app.version.isEmpty ? "1.0" : app.version,
                    title: app.name,
                    base: "http://127.0.0.1:\(installer.port)"
                ).utf8)
                installer.onPayloadServed = {
                    phase = .finished
                    detail = "iOS is installing the app. Watch your Home Screen."
                }
                DispatchQueue.main.async {
                    self.server = installer
                    self.phase = .ready
                    self.detail = "Tap Install now. Keep this screen open until it starts."
                }
            } catch {
                DispatchQueue.main.async {
                    self.phase = .failed
                    self.detail = error.localizedDescription
                }
            }
        }
    }

    private func openInstaller() {
        guard let server, server.port != 0,
              let url = URL(string: "itms-services://?action=download-manifest&url=http://127.0.0.1:\(server.port)/manifest.plist") else {
            detail = "Could not build the install link."
            return
        }
        phase = .installing
        detail = "Waiting for iOS… confirm on your Home Screen."
        beginBackgroundTask()
        BackgroundAudioService.shared.start()
        UIApplication.shared.open(url)
    }

    private func beginBackgroundTask() {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "NicheLoaderInstall") {
            UIApplication.shared.endBackgroundTask(self.backgroundTask)
            self.backgroundTask = .invalid
        }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    private func manifest(bundleID: String, version: String, title: String, base: String) -> String {
        let safeTitle = title.replacingOccurrences(of: "[<>&]", with: "", options: .regularExpression)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>items</key>
        \t<array>
        \t\t<dict>
        \t\t\t<key>assets</key>
        \t\t\t<array>
        \t\t\t\t<dict>
        \t\t\t\t\t<key>kind</key><string>software-package</string>
        \t\t\t\t\t<key>url</key><string>\(base)/app.ipa</string>
        \t\t\t\t</dict>
        \t\t\t\t<dict>
        \t\t\t\t\t<key>kind</key><string>display-image</string>
        \t\t\t\t\t<key>url</key><string>\(base)/icon.png</string>
        \t\t\t\t</dict>
        \t\t\t</array>
        \t\t\t<key>metadata</key>
        \t\t\t<dict>
        \t\t\t\t<key>bundle-identifier</key><string>\(bundleID)</string>
        \t\t\t\t<key>bundle-version</key><string>\(version)</string>
        \t\t\t\t<key>kind</key><string>software</string>
        \t\t\t\t<key>title</key><string>\(safeTitle)</string>
        \t\t\t</dict>
        \t\t</dict>
        \t</array>
        </dict>
        </plist>
        """
    }
}
