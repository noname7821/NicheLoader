import Foundation
import Zip

struct IPAInfo: Codable, Hashable {
    var displayName: String
    var bundleID: String
    var version: String
    var thumbnail: String?
}

/// Reads the real name, bundle ID, version and icon out of an .ipa file.
/// The ipa is unzipped to a temp folder, Info.plist + icon are read,
/// then everything is cleaned up again.
enum IPAInspector {
    static func inspect(ipaURL: URL, thumbnailDir: URL) -> IPAInfo? {
        let access = ipaURL.startAccessingSecurityScopedResource()
        defer { if access { ipaURL.stopAccessingSecurityScopedResource() } }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("inspect-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            try Zip.unzipFile(ipaURL, destination: work, overwrite: true, password: nil)
        } catch {
            return nil
        }
        guard let appDir = try? FileManager.default.contentsOfDirectory(
                at: work.appendingPathComponent("Payload"),
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ).first(where: { $0.pathExtension == "app" }),
              FileManager.default.fileExists(atPath: work.appendingPathComponent("Payload").path),
              let plistData = try? Data(contentsOf: appDir.appendingPathComponent("Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else {
            return nil
        }
        let name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? ipaURL.deletingPathExtension().lastPathComponent
        let bundleID = plist["CFBundleIdentifier"] as? String ?? ""
        let version = plist["CFBundleShortVersionString"] as? String ?? ""
        var thumbnail: String?
        if let iconURL = findIcon(in: appDir, plist: plist) {
            try? FileManager.default.createDirectory(at: thumbnailDir, withIntermediateDirectories: true)
            let dest = thumbnailDir.appendingPathComponent("\(UUID().uuidString).png")
            if (try? FileManager.default.copyItem(at: iconURL, to: dest)) != nil {
                thumbnail = dest.lastPathComponent
            }
        }
        return IPAInfo(displayName: name, bundleID: bundleID, version: version, thumbnail: thumbnail)
    }

    private static func findIcon(in appDir: URL, plist: [String: Any]) -> URL? {
        var candidates: [String] = []
        if let icons = plist["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            candidates.append(contentsOf: files)
        }
        if let file = plist["CFBundleIconFile"] as? String {
            candidates.append(file)
        }
        for base in candidates {
            for variant in ["\(base)@3x.png", "\(base)@2x.png", "\(base).png", base] {
                let url = appDir.appendingPathComponent(variant)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
        }
        for fallback in ["Icon.png", "icon.png", "Icon@2x.png", "AppIcon60x60@3x.png", "AppIcon60x60@2x.png", "AppIcon76x76@2x~ipad.png", "iTunesArtwork.png"] {
            let url = appDir.appendingPathComponent(fallback)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}
