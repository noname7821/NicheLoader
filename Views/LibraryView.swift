import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var signTarget: StoredApp?
    @State private var notice: String?
    @State private var tab = 0
    @State private var showExport = false
    @State private var exportURL: URL?

    private func pickIPA() {
        PickerPresenter.present(types: [.data], allowsMultiple: true) { urls in
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
        }
    }

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
                                Button("Import IPA") { pickIPA() }
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
                                    signed: tab == 1,
                                    onSign: { signTarget = app },
                                    onExport: {
                                        if let url = library.exportURL(for: app) {
                                            exportURL = url
                                            showExport = true
                                        }
                                    }
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
            .navigationBarItems(trailing: Button("Add", systemImage: "plus") { pickIPA() })
            .sheet(item: $signTarget) { app in
                SigningView(app: app)
            }
            .sheet(isPresented: $showExport) {
                if let exportURL {
                    ActivitySheet(items: [exportURL])
                }
            }
            .onAppear { library.refresh() }
        }
    }

    private var currentApps: [StoredApp] {
        tab == 0 ? library.unsignedApps : library.signedApps
    }
}

private struct LibraryRowView: View {
    @EnvironmentObject private var library: LibraryStore
    var app: StoredApp
    var signed: Bool
    var onSign: () -> Void
    var onExport: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13)
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.25), .purple.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 54, height: 54)
                if let thumb = library.iconURL(for: app, signed: signed),
                   let image = UIImage(contentsOfFile: thumb.path) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                } else {
                    Image(systemName: "app.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.purple)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.headline).lineLimit(1)
                if !app.identifier.isEmpty {
                    Text(app.identifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !app.version.isEmpty {
                    Text("v\(app.version)")
                        .font(.caption2)
                        .bold()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.purple.opacity(0.15))
                        .foregroundStyle(.purple)
                        .clipShape(Capsule())
                }
            }
            Spacer()
            if signed {
                Button(action: onExport) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.purple)
                }
            } else {
                Button("Sign", action: onSign)
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
            }
        }
        .padding(.vertical, 4)
        .swipeActions {
            Button(role: .destructive) {
                withAnimation {
                    if signed {
                        library.removeSigned(app)
                    } else {
                        library.removeUnsigned(app)
                    }
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
