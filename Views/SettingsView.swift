import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                CertificateListView()
                CertificateAddView()
                Section {
                    NavigationLink(destination: AboutView()) {
                        Label("About", systemImage: "info.circle")
                    }
                    Link(destination: URL(string: "https://github.com/noname7821/NicheLoader")!) {
                        Label("GitHub Repository", systemImage: "safari")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct CertificateListView: View {
    @EnvironmentObject private var store: CertificateStore

    var body: some View {
        Section("Certificates") {
            if store.certificates.isEmpty {
                Text("No certificates yet.").foregroundStyle(.secondary)
            }
            ForEach(store.certificates) { cert in
                VStack(alignment: .leading, spacing: 2) {
                    Text(cert.name).font(.headline)
                    if let info = store.profileInfo(for: cert) {
                        Text("\(info.teamName) · expires \(info.expirationDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline)
                            .foregroundStyle(info.isExpired ? .red : .secondary)
                    } else {
                        Text("Added \(cert.addedDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { store.remove(cert) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .animation(.default, value: store.certificates)
    }
}

private struct CertificateAddView: View {
    @EnvironmentObject private var store: CertificateStore
    @State private var showP12 = false
    @State private var showProvision = false
    @State private var pendingP12: URL?
    @State private var pendingProvision: URL?
    @State private var pendingInfo: ProvisionInfo?
    @State private var certName = ""
    @State private var certPassword = ""
    @State private var notice: String?

    private var p12Type: UTType { UTType(filenameExtension: "p12") ?? .data }
    private var provisionType: UTType { UTType(filenameExtension: "mobileprovision") ?? .data }

    private var canSave: Bool {
        pendingP12 != nil && pendingProvision != nil &&
        !certName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Section("Add certificate") {
            TextField("Name", text: $certName)
            SecureField("P12 password", text: $certPassword)
            Button(pendingP12 == nil ? "Choose .p12 file" : "P12: \(pendingP12?.lastPathComponent ?? "")") {
                showP12 = true
            }
            Button(pendingProvision == nil ? "Choose .mobileprovision file" : "Profile: \(pendingProvision?.lastPathComponent ?? "")") {
                showProvision = true
            }
            if let info = pendingInfo {
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.profileName).font(.subheadline).bold()
                    Text("\(info.teamName) · expires \(info.expirationDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.footnote)
                        .foregroundStyle(info.isExpired ? .red : .secondary)
                }
            }
            Button("Save certificate") { save() }
                .disabled(!canSave)
            if let notice {
                Text(notice).foregroundStyle(.secondary)
            }
        }
        .fileImporter(isPresented: $showP12, allowedContentTypes: [p12Type]) { result in
            if case .success(let url) = result { pendingP12 = url }
        }
        .fileImporter(isPresented: $showProvision, allowedContentTypes: [provisionType]) { result in
            if case .success(let url) = result {
                pendingProvision = url
                pendingInfo = ProvisionInfo.parse(url: url)
                if pendingInfo == nil {
                    notice = "This is not a valid provisioning profile."
                } else if pendingInfo?.isExpired == true {
                    notice = "Warning: this profile is expired."
                } else {
                    notice = nil
                }
            }
        }
    }

    private func save() {
        guard let p12 = pendingP12, let provision = pendingProvision else { return }
        guard let info = ProvisionInfo.parse(url: provision), !info.isExpired else {
            notice = "Cannot save: the provisioning profile is invalid or expired."
            return
        }
        if store.add(name: certName, p12: p12, provision: provision, password: certPassword) {
            notice = "Certificate saved."
            certName = ""
            certPassword = ""
            pendingP12 = nil
            pendingProvision = nil
            pendingInfo = nil
        } else {
            notice = "Could not save. Check the files and try again."
        }
    }
}
