import SwiftUI
import UniformTypeIdentifiers

struct SigningView: View {
    @EnvironmentObject private var store: CertificateStore
    @Environment(\.dismiss) private var dismiss

    var app: LibraryApp
    var engine: SigningEngine = ZsignEngine()

    @State private var certificateID: String?
    @State private var removeProvisioning = true
    @State private var customName = ""
    @State private var customIdentifier = ""
    @State private var customVersion = ""
    @State private var entitlementsName: String?
    @State private var entitlementsURL: URL?
    @State private var showEntitlementsPicker = false
    @State private var message: String?
    @State private var isSigning = false

    var body: some View {
        NavigationStack {
            Form {
                Section("App") {
                    Text(app.name)
                }
                Section("Certificate") {
                    if store.certificates.isEmpty {
                        Text("No certificate yet. Add one in Settings first.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Certificate", selection: $certificateID) {
                            Text("Select").tag(nil as String?)
                            ForEach(store.certificates) { cert in
                                Text(cert.name).tag(cert.id as String?)
                            }
                        }
                    }
                }
                Section("Options") {
                    Toggle("Remove provisioning file", isOn: $removeProvisioning)
                    TextField("Custom name (optional)", text: $customName)
                    TextField("Custom identifier (optional)", text: $customIdentifier)
                        .textInputAutocapitalization(.never)
                    TextField("Custom version (optional)", text: $customVersion)
                        .textInputAutocapitalization(.never)
                    Button(entitlementsName.map { "Entitlements: \($0)" } ?? "Custom entitlements (optional)") {
                        showEntitlementsPicker = true
                    }
                    if entitlementsName != nil {
                        Button("Clear entitlements", role: .destructive) {
                            entitlementsName = nil
                            entitlementsURL = nil
                        }
                    }
                }
                if let message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Sign app")
            .fileImporter(isPresented: $showEntitlementsPicker, allowedContentTypes: [.nichePlist]) { result in
                if case .success(let url) = result {
                    entitlementsURL = url
                    entitlementsName = url.lastPathComponent
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sign") { run() }.disabled(isSigning || selectedCertificate == nil)
                }
            }
        }
    }

    private var selectedCertificate: CertificatePair? {
        guard let id = certificateID else { return nil }
        return store.certificates.first { $0.id == id }
    }

    private func run() {
        guard let cert = selectedCertificate else { return }
        isSigning = true
        message = nil
        let request = SigningRequest(
            appURL: app.url,
            certificate: cert,
            p12Path: store.p12URL(for: cert).path,
            p12Password: store.password(for: cert),
            provisionPath: store.provisionURL(for: cert).path,
            options: SigningOptions(
                removeProvisioningFile: removeProvisioning,
                customName: customName,
                customIdentifier: customIdentifier,
                customVersion: customVersion,
                entitlementsPath: entitlementsURL?.path ?? ""
            )
        )
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome: String
            do {
                try engine.sign(request)
                outcome = "Signed successfully."
            } catch {
                outcome = error.localizedDescription
            }
            DispatchQueue.main.async {
                message = outcome
                isSigning = false
            }
        }
    }
}
