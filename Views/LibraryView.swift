import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var showImporter = false
    @State private var signTarget: LibraryApp?
    @State private var notice: String?
    @State private var tab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Unsigned").tag(0)
                    Text("Signed").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }

                Group {
                    if currentApps.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text(tab == 0 ? "No unsigned apps" : "No signed apps yet")
                                .font(.headline)
                            Text(tab == 0 ? "Import an .ipa file to get started." : "Sign an app from Unsigned first.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if tab == 0 {
                                Button("Import IPA") { showImporter = true }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.purple)
                                    .padding(.top, 4)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(currentApps) { app in
                                LibraryRowView(
                                    app: app,
                                    showsSignButton: tab == 0,
                                    onSign: { signTarget = app }
                                )
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .animation(.default, value: tab)
            .animation(.default, value: library.unsignedApps)
            .animation(.default, value: library.signedApps)
            .navigationTitle("Library")
            .navigationBarItems(trailing: Button("Add", systemImage: "plus") { showImporter = true })
            .sheet(isPresented: $showImporter) {
                DocumentPicker(types: [.nicheIPA], allowsMultiple: true) { urls in
                    showImporter = false
                    var errors: [String] = []
                    var added = 0
                    for url in urls {
                        if let error = library.importIPA(from: url) {
                            errors.append(error)
                        } else {
                            added += 1
                        }
                    }
                    if added == 0 && errors.first != nil {
                        notice = errors.first
                    } else if added == 0 {
                        notice = "No .ipa file selected."
                    } else {
                        notice = nil
                    }
                } onCancel: {
                    showImporter = false
                }
            }
            .sheet(item: $signTarget) { app in
                SigningView(app: app)
            }
            .onAppear { library.refresh() }
        }
    }

    private var currentApps: [LibraryApp] {
        tab == 0 ? library.unsignedApps : library.signedApps
    }
}

private struct LibraryRowView: View {
    @EnvironmentObject private var library: LibraryStore
    var app: LibraryApp
    var showsSignButton: Bool
    var onSign: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let thumb = library.thumbnail(for: app),
               let image = UIImage(contentsOfFile: thumb.path) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.purple)
                    .frame(width: 52, height: 52)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName).font(.headline).lineLimit(1)
                if !app.bundleID.isEmpty {
                    Text(app.bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(versionLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showsSignButton {
                Button("Sign", action: onSign)
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
            } else {
                ShareLink(item: app.url) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                withAnimation {
                    if showsSignButton {
                        library.removeUnsigned(app)
                    } else {
                        library.removeSigned(app)
                    }
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var versionLine: String {
        var parts: [String] = []
        if !app.version.isEmpty { parts.append("v\(app.version)") }
        parts.append(LibraryStore.formattedSize(app.size))
        return parts.joined(separator: " · ")
    }
}
