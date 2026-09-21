import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: CertificateStore
    @State private var showP12 = false
    @State private var showProvision = false
    @State private var pendingP12: URL?
    @State private var certName = ""
    @State private var certPassword = ""
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Certificates") {
                    if store.certificates.isEmpty {
                        Text("No certificates yet.").foregroundStyle(.secondary)
                    }
                    ForEach(store.certificates) { cert in
                        VStack(alignment: .leading) {
                            Text(cert.name).font(.headline)
                            Text("Added \(cert.addedDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) { store.remove(cert) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                Section("Add certificate") {
                    TextField("Name", text: $certName)
                    SecureField("P12 password", text: $certPassword)
                    Button(pendingP12 == nil ? "Choose .p12 file" : "P12 selected") { showP12 = true }
                    Button("Choose .mobileprovision & save") { showProvision = true }
                        .disabled(pendingP12 == nil || certName.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let notice {
                        Text(notice).foregroundStyle(.secondary)
                    }
                }
                Section {
                    NavigationLink(destination: AboutView()) {
                        Label("About", systemImage: "info.circle")
                    }
                    Link(destination: URL(string: "https://github.com/noname7821/NicheLoaderr")!) {
                        Label("GitHub Repository", systemImage: "safari")
                    }
                }
            }
            .navigationTitle("Settings")
            .fileImporter(isPresented: $showP12, allowedContentTypes: [UTType(filenameExtension: "p12") ?? .data]) { result in
                if case .success(let urls) = result, let first = urls.first {
                    pendingP12 = first
                }
            }
            .fileImporter(isPresented: $showProvision, allowedContentTypes: [UTType(filenameExtension: "mobileprovision") ?? .data]) { result in
                guard let p12 = pendingP12,
                      case .success(let urls) = result,
                      let provision = urls.first else { return }
                if store.add(name: certName, p12: p12, provision: provision, password: certPassword) {
                    notice = "Certificate saved."
                    certName = ""
                    certPassword = ""
                    pendingP12 = nil
                } else {
                    notice = "Could not save the certificate. Check the files and try again."
                }
            }
        }
    }
}
