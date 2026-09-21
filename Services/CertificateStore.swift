import Foundation
import SwiftUI

final class CertificateStore: ObservableObject {
    @Published private(set) var certificates: [CertificatePair] = []

    private let folder: URL
    private let metaKey = "nicheloader.certificates"

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = docs.appendingPathComponent("Certificates", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: metaKey),
              let decoded = try? JSONDecoder().decode([CertificatePair].self, from: data) else { return }
        certificates = decoded.filter {
            FileManager.default.fileExists(atPath: p12URL(for: $0).path) &&
            FileManager.default.fileExists(atPath: provisionURL(for: $0).path)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(certificates) {
            UserDefaults.standard.set(data, forKey: metaKey)
        }
    }

    func p12URL(for cert: CertificatePair) -> URL {
        folder.appendingPathComponent(cert.p12FileName)
    }

    func provisionURL(for cert: CertificatePair) -> URL {
        folder.appendingPathComponent(cert.provisionFileName)
    }

    func password(for cert: CertificatePair) -> String {
        KeychainHelper.load(account: cert.id) ?? ""
    }

    func profileInfo(for cert: CertificatePair) -> ProvisionInfo? {
        ProvisionInfo.parse(url: provisionURL(for: cert))
    }

    /// Returns nil on success, otherwise a message for the user.
    @discardableResult
    func add(name: String, p12: URL, provision: URL, password: String) -> String? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return false }
        let id = UUID().uuidString
        let p12Name = id + ".p12"
        let provName = id + ".mobileprovision"
        let p12Access = p12.startAccessingSecurityScopedResource()
        let provAccess = provision.startAccessingSecurityScopedResource()
        defer {
            if p12Access { p12.stopAccessingSecurityScopedResource() }
            if provAccess { provision.stopAccessingSecurityScopedResource() }
        }
        do {
            try FileManager.default.copyItem(at: p12, to: folder.appendingPathComponent(p12Name))
            try FileManager.default.copyItem(at: provision, to: folder.appendingPathComponent(provName))
        } catch {
            return "Copy failed: \(error.localizedDescription)"
        }
        guard KeychainHelper.save(password, account: id) else {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(p12Name))
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(provName))
            return "Could not save the password in Keychain."
        }
        certificates.append(CertificatePair(id: id, name: cleanName, p12FileName: p12Name, provisionFileName: provName))
        persist()
        return nil
    }

    func remove(_ cert: CertificatePair) {
        try? FileManager.default.removeItem(at: p12URL(for: cert))
        try? FileManager.default.removeItem(at: provisionURL(for: cert))
        KeychainHelper.delete(account: cert.id)
        certificates.removeAll { $0.id == cert.id }
        persist()
    }
}
