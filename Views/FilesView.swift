import SwiftUI

struct FilesView: View {
    @State private var current: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    @State private var entries: [FileEntry] = []
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            List {
                if isDocumentRoot {
                    Section("Quick access") {
                        ForEach(quickAccess, id: \.self) { folder in
                            Button {
                                current = folder.url
                                reload()
                            } label: {
                                Label(folder.name, systemImage: "folder.fill")
                            }
                        }
                    }
                }
                Section("Contents") {
                    ForEach(entries) { entry in
                        if entry.isDirectory {
                            Button {
                                current = entry.url
                                reload()
                            } label: {
                                Label(entry.name, systemImage: "folder.fill")
                            }
                        } else {
                            Label(entry.name, systemImage: "doc.fill")
                        }
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !isDocumentRoot {
                        Button("Back", systemImage: "chevron.left") {
                            current = current.deletingLastPathComponent()
                            reload()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", systemImage: "plus") { showImporter = true }
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    for url in urls {
                        if url.startAccessingSecurityScopedResource() { defer { url.stopAccessingSecurityScopedResource() } }
                        try? FileManager.default.copyItem(at: url, to: current.appendingPathComponent(url.lastPathComponent))
                    }
                    reload()
                }
            }
            .onAppear(perform: reload)
        }
    }

    private var isDocumentRoot: Bool {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return current.standardizedFileURL == docs.standardizedFileURL
    }

    private var title: String {
        isDocumentRoot ? "Files" : current.lastPathComponent
    }

    private var quickAccess: [(name: String, url: URL)] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return ["Apps", "Certificates", "Archives"].map {
            (name: $0, url: docs.appendingPathComponent($0, isDirectory: true))
        }
    }

    private func reload() {
        try? FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        let urls = (try? FileManager.default.contentsOfDirectory(at: current, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        entries = urls.map { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return FileEntry(url: url, isDirectory: isDir)
        }.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}

private struct FileEntry: Identifiable, Hashable {
    var id: String { url.path }
    var url: URL
    var isDirectory: Bool
    var name: String { url.lastPathComponent }
}
