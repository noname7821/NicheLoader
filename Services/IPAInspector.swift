import Foundation

/// Reads name, identifier, version and icon out of an extracted .app folder.
/// Returns the icon path relative to the Payload directory.
enum IPAInspector {
    static func inspectAppDirectory(payloadDir: URL) -> (name: String, identifier: String, version: String, iconFile: String)? {
        guard let appDir = try? FileManager.default.contentsOfDirectory(
            at: payloadDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ).first(where: { $0.pathExtension == "app" }),
              let plistData = try? Data(contentsOf: appDir.appendingPathComponent("Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else {
            return nil
        }
        let fallback = appDir.deletingPathExtension().lastPathComponent
        let name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? fallback
        let identifier = plist["CFBundleIdentifier"] as? String ?? ""
        let version = plist["CFBundleShortVersionString"] as? String ?? ""
        let iconFile = findIcon(in: appDir, plist: plist, fallbackAppName: fallback) ?? ""
        return (name, identifier, version, iconFile)
    }

    private static func findIcon(in appDir: URL, plist: [String: Any], fallbackAppName: String) -> String? {
        var candidates: [String] = []
        if let icons = plist["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            candidates.append(contentsOf: files)
        }
        if let file = plist["CFBundleIconFile"] as? String {
            candidates.append(file)
        }
        candidates.append(contentsOf: [
            "Icon.png", "icon.png", "Icon@2x.png",
            "AppIcon60x60@3x.png", "AppIcon60x60@2x.png",
            "AppIcon76x76@2x~ipad.png", "iTunesArtwork.png",
            "\(fallbackAppName).png",
        ])
        let appName = appDir.lastPathComponent
        for base in candidates {
            for variant in ["\(base)@3x.png", "\(base)@2x.png", "\(base).png", base] {
                let relative = "\(appName)/\(variant)"
                if FileManager.default.fileExists(atPath: appDir.appendingPathComponent(variant).path) {
                    return relative
                }
            }
        }
        return nil
    }
}
