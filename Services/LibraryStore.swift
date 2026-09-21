import Foundation
import SwiftUI
import Zip

struct LibraryApp: Identifiable, Hashable {
    var id: String { url.path }
    var url: URL
    var info: IPAInfo?
    var size: Int64

    var displayName: String { info?.displayName ?? url.deletingPathExtension().lastPathComponent }
    var bundleID: String { info?.bundleID ?? "" }
    var version: String { info?.version ?? "" }
}

final class LibraryStore: ObservableObject {
    @Published private(set) var unsignedApps: [LibraryApp] = []
    @Published private(set) var signedApps: [LibraryApp] = []

    private let unsignedFolder: URL
    private let signedFolder: URL
    private let thumbnailFolder: URL
    private let metaKey = "nicheloader.appmeta"
    private let metaQueue = DispatchQueue(label: "com.filmeacc.nicheloader.meta")
    private var meta: [String: IPAInfo] = [:]

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        unsignedFolder = docs.appendingPathComponent("Apps", isDirectory: true)
        signedFolder = docs.appendingPathComponent("Signed", isDirectory: true)
        thumbnailFolder = docs.appendingPathComponent("Thumbnails", isDirectory: true)
        for folder in [unsignedFolder, signedFolder, thumbnailFolder] {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        if let data = UserDefaults.standard.data(forKey: metaKey),
           let decoded = try? JSONDecoder().decode([String: IPAInfo].self, from: data) {
            meta = decoded
        }
        refresh()
    }

    private func metaGet(_ path: String) -> IPAInfo? {
        metaQueue.sync { meta[path] }
    }

    private func metaSet(_ info: IPAInfo, for path: String) {
        metaQueue.sync {
            meta[path] = info
            if let data = try? JSONEncoder().encode(meta) {
                UserDefaults.standard.set(data, forKey: metaKey)
            }
        }
    }

    private func metaPrune(to paths: Set<String>) {
        metaQueue.sync {
            meta = meta.filter { paths.contains($0.key) }
            if let data = try? JSONEncoder().encode(meta) {
                UserDefaults.standard.set(data, forKey: metaKey)
            }
        }
    }

    private func thumbnailURL(for info: IPAInfo) -> URL? {
        guard let file = info.thumbnail else { return nil }
        let url = thumbnailFolder.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func thumbnail(for app: LibraryApp) -> URL? {
        guard let info = app.info else { return nil }
        return thumbnailURL(for: info)
    }

    private func scan(_ folder: URL) -> [LibraryApp] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles))?
            .filter { $0.pathExtension.lowercased() == "ipa" } ?? []
        return urls.map { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return LibraryApp(url: url, info: metaGet(url.path), size: Int64(size))
        }.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    func refresh() {
        unsignedApps = scan(unsignedFolder)
        signedApps = scan(signedFolder)
        let allPaths = Set((unsignedApps + signedApps).map(\.url.path))
        metaPrune(to: allPaths)
        DispatchQueue.global(qos: .utility).async {
            var changed = false
            for url in allPaths where self.metaGet(url) == nil {
                if let info = IPAInspector.inspect(ipaURL: URL(fileURLWithPath: url), thumbnailDir: self.thumbnailFolder) {
                    self.metaSet(info, for: url)
                    changed = true
                }
            }
            if changed {
                DispatchQueue.main.async {
                    self.unsignedApps = self.scan(self.unsignedFolder)
                    self.signedApps = self.scan(self.signedFolder)
                }
            }
        }
    }

    /// Returns nil on success, otherwise a message for the user.
    @discardableResult
    func importIPA(from source: URL) -> String? {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        guard source.pathExtension.lowercased() == "ipa" else {
            return "That file is not an .ipa."
        }
        let dest = unsignedFolder.appendingPathComponent(source.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
            refresh()
            return nil
        } catch {
            return "Import failed: \(error.localizedDescription)"
        }
    }

    func removeUnsigned(_ app: LibraryApp) {
        try? FileManager.default.removeItem(at: app.url)
        refresh()
    }

    func removeSigned(_ app: LibraryApp) {
        try? FileManager.default.removeItem(at: app.url)
        refresh()
    }

    /// Unzips an unsigned IPA and returns the .app directory for signing.
    /// The caller owns the returned temp folder and must delete it after.
    func prepareForSigning(_ app: LibraryApp) throws -> URL {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("sign-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try Zip.unzipFile(app.url, destination: work, overwrite: true, password: nil)
        let contents = try FileManager.default.contentsOfDirectory(at: work.appendingPathComponent("Payload"), includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        guard let appDir = contents.first(where: { $0.pathExtension == "app" }) else {
            throw SigningError.failed("No .app bundle found in this IPA.")
        }
        return appDir
    }

    /// Re-zips a signed .app directory into the Signed folder.
    /// Returns nil on success, otherwise a message for the user.
    @discardableResult
    func finishSignedApp(appDir: URL, originalName: String) -> String? {
        let work = appDir.deletingLastPathComponent().deletingLastPathComponent()
        let payloadCopy = work.appendingPathComponent("IPARoot", isDirectory: true)
            .appendingPathComponent("Payload", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: payloadCopy, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: appDir, to: payloadCopy.appendingPathComponent(appDir.lastPathComponent))
            let dest = signedFolder.appendingPathComponent("\(originalName)-signed.ipa")
            try? FileManager.default.removeItem(at: dest)
            try Zip.zipFiles(
                paths: [payloadCopy],
                zipFilePath: dest,
                password: nil,
                progress: nil
            )
            refresh()
            return nil
        } catch {
            return "Repack failed: \(error.localizedDescription)"
        }
    }

    static func formattedSize(_ bytes: Int64) -> String {
        if bytes >= 1_048_576 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        if bytes >= 1024 { return "\(bytes / 1024) KB" }
        return "\(bytes) B"
    }
}
