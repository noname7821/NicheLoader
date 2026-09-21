import SwiftUI
import UniformTypeIdentifiers

struct SigningView: View {
    @EnvironmentObject private var store: CertificateStore
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    var app: StoredApp
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
                    if !app.identifier.isEmpty {
                        Text(app.identifier)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Certificate") {
                    if store.certificates.isEmpty {
                        Text("No certificate yet. Add one in Settings first.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.certificates) { cert in
                            Button {
                                withAnimation { certificateID = cert.id }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(cert.name)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        if let info = store.profileInfo(for: cert) {
                                            Text(info.teamName)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if certificateID == cert.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.purple)
                                            .font(.title3)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(.secondary)
                                            .font(.title3)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
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
                if isSigning {
                    Section {
                        HStack {
                            ProgressView()
                            Text(message ?? "Working…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let message {
                    Section("Status") {
                        Text(message).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Sign app")
            .sheet(isPresented: $showEntitlementsPicker) {
                DocumentPicker(types: [.nichePlist], allowsMultiple: false) { urls in
                    showEntitlementsPicker = false
                    if let url = urls.first {
                        entitlementsURL = url
                        entitlementsName = url.lastPathComponent
                    }
                } onCancel: {
                    showEntitlementsPicker = false
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSigning ? "Signing…" : "Sign") { run() }
                        .disabled(isSigning || selectedCertificate == nil)
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
        message = "Unpacking…"
        DispatchQueue.global(qos: .userInitiated).async {
            func fail(_ text: String) {
                DispatchQueue.main.async {
                    message = text
                    isSigning = false
                }
            }
            let prepared: (appDir: URL, root: URL)
            do {
                prepared = try library.prepareForSigning(app)
            } catch {
                fail(error.localizedDescription)
                return
            }
            defer {
                try? FileManager.default.removeItem(at: prepared.root)
            }
            DispatchQueue.main.async { message = "Signing…" }
            let request = SigningRequest(
                appURL: prepared.appDir,
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
            do {
                try engine.sign(request)
            } catch {
                fail(error.localizedDescription)
                return
            }
            DispatchQueue.main.async { message = "Repacking…" }
            let payloadDir = prepared.appDir.deletingLastPathComponent()
            if let error = library.finishSignedApp(
                payloadDir: payloadDir,
                original: app,
                name: customName,
                identifier: customIdentifier,
                version: customVersion
            ) {
                fail(error)
                return
            }
            try? FileManager.default.removeItem(at: prepared.root)
            DispatchQueue.main.async {
                message = "Signed. Find it under Signed."
                isSigning = false
            }
        }
    }
}
