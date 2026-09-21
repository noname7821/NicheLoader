import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @State private var showImporter = false
    @State private var signTarget: LibraryApp?

    var body: some View {
        NavigationStack {
            Group {
                if library.apps.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No apps yet")
                            .font(.headline)
                        Text("Import an .ipa file to get started.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(library.apps) { app in
                            LibraryRowView(app: app, onSign: { signTarget = app })
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarItems(trailing: Button("Add", systemImage: "plus") { showImporter = true })
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data]) { result in
                if case .success(let url) = result {
                    library.importIPA(from: url)
                }
            }
            .sheet(item: $signTarget) { app in
                SigningView(app: app)
            }
            .onAppear { library.refresh() }
        }
    }
}

private struct LibraryRowView: View {
    @EnvironmentObject private var library: LibraryStore
    var app: LibraryApp
    var onSign: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "app.fill")
                .font(.title2)
                .foregroundStyle(.purple)
            VStack(alignment: .leading) {
                Text(app.name).font(.headline).lineLimit(1)
                Text(LibraryStore.formattedSize(app.size))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Sign", action: onSign)
                .buttonStyle(.borderedProminent)
                .tint(.purple)
        }
        .swipeActions {
            Button(role: .destructive) { library.remove(app) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
