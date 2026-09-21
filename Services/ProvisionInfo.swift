import Foundation

struct ProvisionInfo {
    var profileName: String
    var teamName: String
    var appID: String
    var expirationDate: Date
    var isExpired: Bool { expirationDate < Date() }

    static func parse(url: URL) -> ProvisionInfo? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let xmlStart = data.range(of: Data("<?xml".utf8)) else { return nil }
        let xml = data.subdata(in: xmlStart.lowerBound..<data.endIndex)
        guard let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any] else { return nil }
        let entitlements = plist["Entitlements"] as? [String: Any]
        guard let name = plist["Name"] as? String,
              let expiry = plist["ExpirationDate"] as? Date else { return nil }
        let team = (entitlements?["com.apple.developer.team-identifier"] as? String)
            ?? (plist["TeamName"] as? String)
            ?? ""
        let appID = entitlements?["application-identifier"] as? String ?? ""
        return ProvisionInfo(profileName: name, teamName: team, appID: appID, expirationDate: expiry)
    }
}
