import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image("AboutIcon")
                            .resizable()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("NicheLoader")
                                .font(.headline)
                            Text("by mintoo")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(EmptyView())
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
    @State private var pendingP12: URL?
    @State private var pendingProvision: URL?
    @State private var pendingInfo: ProvisionInfo?
    @State private var certName = ""
    @State private var certPassword = ""
    @State private var notice: String?

    private var canSave: Bool {
        pendingP12 != nil && pendingProvision != nil &&
        !certName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Section("Add certificate") {
            TextField("Name", text: $certName)
            SecureField("P12 password", text: $certPassword)
            Button(pendingP12 == nil ? "Choose .p12 file" : "P12: \(pendingP12?.lastPathComponent ?? "")") {
                PickerPresenter.present(types: [.data], allowsMultiple: false) { urls in
                    handlePicked(urls, target: .p12)
                }
            }
            Button(pendingProvision == nil ? "Choose .mobileprovision file" : "Profile: \(pendingProvision?.lastPathComponent ?? "")") {
                PickerPresenter.present(types: [.data], allowsMultiple: false) { urls in
                    handlePicked(urls, target: .provision)
                }
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
    }

    private enum PickTarget {
        case p12, provision
    }

    private func handlePicked(_ urls: [URL], target: PickTarget) {
        guard let url = urls.first else { return }
        switch target {
        case .p12:
            guard url.pathExtension.lowercased() == "p12" else {
                notice = "That is not a .p12 file."
                return
            }
            pendingP12 = url
            notice = nil
        case .provision:
            guard url.pathExtension.lowercased() == "mobileprovision" else {
                notice = "That is not a .mobileprovision file."
                return
            }
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

    private func save() {
        guard let p12 = pendingP12, let provision = pendingProvision else { return }
        guard let info = ProvisionInfo.parse(url: provision), !info.isExpired else {
            notice = "Cannot save: the provisioning profile is invalid or expired."
            return
        }
        guard P12Validator.verify(at: p12, password: certPassword) else {
            notice = "Bad password. Check the p12 password and try again."
            return
        }
        if let error = store.add(name: certName, p12: p12, provision: provision, password: certPassword) {
            notice = error
        } else {
            notice = "Certificate saved."
            certName = ""
            certPassword = ""
            pendingP12 = nil
            pendingProvision = nil
            pendingInfo = nil
        }
    }
}
