import Foundation
import Security

enum P12Validator {
    /// Checks the p12 password using the system keychain import,
    /// without storing anything.
    static func verify(at url: URL, password: String) -> Bool {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return false }
        let options = [kSecImportExportPassphrase as String: password]
        var items: CFArray?
        return SecPKCS12Import(data as CFData, options as CFDictionary, &items) == errSecSuccess
    }
}
