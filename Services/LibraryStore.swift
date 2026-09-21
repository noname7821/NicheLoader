import Foundation
import SwiftUI
import Zip

struct StoredApp: Identifiable, Codable, Hashable {
    var uuid: String
    var name: String
    var identifier: String
    var version: String
    var iconFile: String
    var date: Date
    var id: String { uuid }
}

final class LibraryStore: ObservableObject {
    @Published private(set) var unsignedApps: [StoredApp] = []
    @Published private(set) var signedApps: [StoredApp] = []

    private let unsignedFolder: URL
    private let signedFolder: URL
    private let unsignedKey = "nicheloader.unsignedApps"
    private let signedKey = "nicheloader.signedApps"

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        unsignedFolder = docs.appendingPathComponent("Apps", isDirectory: true)
        signedFolder = docs.appendingPathComponent("Signed", isDirectory: true)
        try? FileManager.default.createDirectory(at: unsignedFolder, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: signedFolder, withIntermediateDirectories: true)
        unsignedApps = Self.load(key: unsignedKey)
        signedApps = Self.load(key: signedKey)
        refresh()
    }

    private static func load(key: String) -> [StoredApp] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([StoredApp].self, from: data) else { return [] }
        return decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(unsignedApps) {
            UserDefaults.standard.set(data, forKey: unsignedKey)
        }
        if let data = try? JSONEncoder().encode(signedApps) {
            UserDefaults.standard.set(data, forKey: signedKey)
        }
    }

    private func baseFolder(signed: Bool) -> URL {
        signed ? signedFolder : unsignedFolder
    }

    func iconURL(for app: StoredApp, signed: Bool) -> URL? {
        guard !app.iconFile.isEmpty else { return nil }
        let url = baseFolder(signed: signed)
            .appendingPathComponent(app.uuid, isDirectory: true)
            .appendingPathComponent("Payload", isDirectory: true)
            .appendingPathComponent(app.iconFile)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Drops records whose folders are gone, and auto-imports loose .ipa
    /// files left in Apps/ by older versions.
    func refresh() {
        unsignedApps = unsignedApps.filter { dirExists(for: $0, signed: false) }
        signedApps = signedApps.filter { dirExists(for: $0, signed: true) }
        migrateLooseIPAs()
        persist()
    }

    private func dirExists(for app: StoredApp, signed: Bool) -> Bool {
        let dir = baseFolder(signed: signed).appendingPathComponent(app.uuid, isDirectory: true)
        return FileManager.default.fileExists(atPath: dir.path)
    }

    private func migrateLooseIPAs() {
        let loose = ((try? FileManager.default.contentsOfDirectory(at: unsignedFolder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
            .filter { $0.pathExtension.lowercased() == "ipa" }
        for file in loose {
            if extractImport(from: file) == nil {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Imports an .ipa by extracting it immediately (like Ksign does).
    /// Returns nil on success, otherwise a message for the user.
    @discardableResult
    func importIPA(from source: URL) -> String? {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        guard source.pathExtension.lowercased() == "ipa" else {
            return "That file is not an .ipa."
        }
        let result = extractImport(from: source)
        refresh()
        return result
    }

    /// Returns nil on success, otherwise a message for the user.
    private func extractImport(from source: URL) -> String? {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            try Unzipper.unzip(ipa: source, to: work)
        } catch {
            return error.localizedDescription
        }
        let payload = work.appendingPathComponent("Payload", isDirectory: true)
        guard FileManager.default.fileExists(atPath: payload.path),
              let meta = IPAInspector.inspectAppDirectory(payloadDir: payload) else {
            return "No app found in this IPA. The file may be broken."
        }
        let uuid = UUID().uuidString
        let dest = unsignedFolder.appendingPathComponent(uuid, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: payload, to: dest.appendingPathComponent("Payload", isDirectory: true))
        } catch {
            return "Import failed: \(error.localizedDescription)"
        }
        unsignedApps.append(StoredApp(
            uuid: uuid,
            name: meta.name,
            identifier: meta.identifier,
            version: meta.version,
            iconFile: meta.iconFile,
            date: Date()
        ))
        unsignedApps.sort { $0.name.lowercased() < $1.name.lowercased() }
        persist()
        return nil
    }

    func removeUnsigned(_ app: StoredApp) {
        try? FileManager.default.removeItem(at: unsignedFolder.appendingPathComponent(app.uuid, isDirectory: true))
        unsignedApps.removeAll { $0.uuid == app.uuid }
        persist()
    }

    func removeSigned(_ app: StoredApp) {
        try? FileManager.default.removeItem(at: signedFolder.appendingPathComponent(app.uuid, isDirectory: true))
        signedApps.removeAll { $0.uuid == app.uuid }
        persist()
    }

    /// Zips a signed app to a temp .ipa for installing or sharing.
    func packageSignedApp(_ app: StoredApp) throws -> URL {
        let payload = signedFolder.appendingPathComponent(app.uuid, isDirectory: true)
            .appendingPathComponent("Payload", isDirectory: true)
        guard FileManager.default.fileExists(atPath: payload.path) else {
            throw SigningError.failed("Signed files are gone. Sign the app again.")
        }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(app.name)-signed.ipa")
        try? FileManager.default.removeItem(at: dest)
        try Zip.zipFiles(paths: [payload], zipFilePath: dest, password: nil, progress: nil)
        return dest
    }

    /// Zips a signed app to a temp .ipa for sharing. Returns nil on failure.
    func exportURL(for app: StoredApp) -> URL? {
        try? packageSignedApp(app)
    }

    /// Copies an unsigned app to a temp folder and returns its .app directory
    /// together with the temp root (delete it when done).
    func prepareForSigning(_ app: StoredApp) throws -> (appDir: URL, root: URL) {
        let src = unsignedFolder.appendingPathComponent(app.uuid, isDirectory: true)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sign-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: src, to: root.appendingPathComponent(app.uuid, isDirectory: true))
        let payload = root.appendingPathComponent(app.uuid, isDirectory: true)
            .appendingPathComponent("Payload", isDirectory: true)
        let contents = try FileManager.default.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        guard let appDir = contents.first(where: { $0.pathExtension == "app" }) else {
            throw SigningError.failed("No .app bundle found in this app.")
        }
        return (appDir, root)
    }

    /// Moves a signed Payload into the Signed folder and records the app.
    /// Returns nil on success, otherwise a message for the user.
    @discardableResult
    func finishSignedApp(payloadDir: URL, original: StoredApp, name: String, identifier: String, version: String) -> String? {
        let uuid = UUID().uuidString
        let dest = signedFolder.appendingPathComponent(uuid, isDirectory: true)
        var meta = IPAInspector.inspectAppDirectory(payloadDir: payloadDir)
        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: payloadDir, to: dest.appendingPathComponent("Payload", isDirectory: true))
        } catch {
            return "Repack failed: \(error.localizedDescription)"
        }
        if meta == nil {
            meta = (original.name, original.identifier, original.version, "")
        }
        signedApps.append(StoredApp(
            uuid: uuid,
            name: name.isEmpty ? (meta?.name ?? original.name) : name,
            identifier: identifier.isEmpty ? (meta?.identifier ?? original.identifier) : identifier,
            version: version.isEmpty ? (meta?.version ?? original.version) : version,
            iconFile: meta?.iconFile ?? "",
            date: Date()
        ))
        signedApps.sort { $0.name.lowercased() < $1.name.lowercased() }
        persist()
        return nil
    }

    static func formattedSize(_ bytes: Int64) -> String {
        if bytes >= 1_048_576 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        if bytes >= 1024 { return "\(bytes / 1024) KB" }
        return "\(bytes) B"
    }
}
