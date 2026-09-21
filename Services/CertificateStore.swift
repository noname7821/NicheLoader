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

    @discardableResult
    func add(name: String, p12: URL, provision: URL, password: String) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return false }
        let id = UUID().uuidString
        let p12Name = id + ".p12"
        let provName = id + ".mobileprovision"
        do {
            if p12.startAccessingSecurityScopedResource() { defer { p12.stopAccessingSecurityScopedResource() } }
            if provision.startAccessingSecurityScopedResource() { defer { provision.stopAccessingSecurityScopedResource() } }
            try FileManager.default.copyItem(at: p12, to: folder.appendingPathComponent(p12Name))
            try FileManager.default.copyItem(at: provision, to: folder.appendingPathComponent(provName))
        } catch {
            return false
        }
        guard KeychainHelper.save(password, account: id) else {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(p12Name))
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(provName))
            return false
        }
        certificates.append(CertificatePair(id: id, name: cleanName, p12FileName: p12Name, provisionFileName: provName))
        persist()
        return true
    }

    func remove(_ cert: CertificatePair) {
        try? FileManager.default.removeItem(at: p12URL(for: cert))
        try? FileManager.default.removeItem(at: provisionURL(for: cert))
        KeychainHelper.delete(account: cert.id)
        certificates.removeAll { $0.id == cert.id }
        persist()
    }
}
