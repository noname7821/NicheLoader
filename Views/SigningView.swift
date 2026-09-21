import SwiftUI

struct SigningView: View {
    @EnvironmentObject private var store: CertificateStore
    @Environment(\.dismiss) private var dismiss

    var app: LibraryApp
    var engine: SigningEngine = UnavailableEngine()

    @State private var certificateID: String?
    @State private var removeProvisioning = true
    @State private var customName = ""
    @State private var customIdentifier = ""
    @State private var customVersion = ""
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
                }
                if let message {
                    Section { Text(message).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Sign app")
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
                customVersion: customVersion
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
