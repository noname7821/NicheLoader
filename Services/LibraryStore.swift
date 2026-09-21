import Foundation
import SwiftUI

struct LibraryApp: Identifiable, Hashable {
    var id: String { url.path }
    var url: URL
    var name: String { url.deletingPathExtension().lastPathComponent }
    var size: Int64
}

final class LibraryStore: ObservableObject {
    @Published private(set) var apps: [LibraryApp] = []

    private let folder: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = docs.appendingPathComponent("Apps", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        refresh()
    }

    func refresh() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles))?
            .filter { $0.pathExtension.lowercased() == "ipa" } ?? []
        apps = urls.map { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return LibraryApp(url: url, size: Int64(size))
        }.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    @discardableResult
    func importIPA(from source: URL) -> Bool {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let dest = folder.appendingPathComponent(source.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: source, to: dest)
            refresh()
            return true
        } catch {
            return false
        }
    }

    func remove(_ app: LibraryApp) {
        try? FileManager.default.removeItem(at: app.url)
        refresh()
    }

    static func formattedSize(_ bytes: Int64) -> String {
        if bytes >= 1_048_576 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        if bytes >= 1024 { return "\(bytes / 1024) KB" }
        return "\(bytes) B"
    }
}
