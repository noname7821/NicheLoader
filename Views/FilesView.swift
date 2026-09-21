import SwiftUI

struct FilesView: View {
    @State private var current: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    @State private var entries: [FileEntry] = []
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            List {
                if isDocumentRoot {
                    Section("Quick access") {
                        ForEach(quickAccess, id: \.name) { folder in
                            Button {
                                withAnimation {
                                    current = folder.url
                                    reload()
                                }
                            } label: {
                                Label(folder.name, systemImage: "folder.fill")
                                    .foregroundStyle(.purple)
                            }
                        }
                    }
                }
                Section("Contents") {
                    if entries.isEmpty {
                        Text("Empty folder.").foregroundStyle(.secondary)
                    }
                    ForEach(entries) { entry in
                        if entry.isDirectory {
                            Button {
                                withAnimation {
                                    current = entry.url
                                    reload()
                                }
                            } label: {
                                HStack {
                                    Label(entry.name, systemImage: "folder.fill")
                                        .foregroundStyle(.purple)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) { delete(entry) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        } else {
                            HStack {
                                Label(entry.name, systemImage: "doc.fill")
                                Spacer()
                                Text(entry.sizeText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions {
                                Button(role: .destructive) { delete(entry) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .transition(.slide)
                }
            }
            .animation(.default, value: entries)
            .navigationTitle(title)
            .overlay(alignment: .bottom) {
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 12)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !isDocumentRoot {
                        Button("Back", systemImage: "chevron.left") {
                            withAnimation {
                                current = current.deletingLastPathComponent()
                                reload()
                            }
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Folder", systemImage: "folder.badge.plus") { showNewFolder = true }
                        .alert("New folder", isPresented: $showNewFolder) {
                            TextField("Name", text: $newFolderName)
                            Button("Create") {
                                let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    try? FileManager.default.createDirectory(at: current.appendingPathComponent(trimmed), withIntermediateDirectories: true)
                                    newFolderName = ""
                                    withAnimation { reload() }
                                }
                            }
                            Button("Cancel", role: .cancel) { newFolderName = "" }
                        }
                    Button("Add", systemImage: "plus") { pickFiles() }
                }
            }
            .onAppear(perform: reload)
        }
    }

    private func pickFiles() {
        PickerPresenter.present(types: [.item], allowsMultiple: true) { urls in
            importURLs(urls)
        }
    }

    private func importURLs(_ urls: [URL]) {
        var added = 0
        var lastError: String?
        for url in urls {
            do {
                try FileManager.default.copyItem(at: url, to: current.appendingPathComponent(url.lastPathComponent))
                added += 1
            } catch {
                lastError = error.localizedDescription
            }
        }
        notice = added == 0 ? (lastError.map { "Copy failed: \($0)" } ?? "Nothing selected.") : nil
        withAnimation { reload() }
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
        let urls = (try? FileManager.default.contentsOfDirectory(at: current, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: .skipsHiddenFiles)) ?? []
        entries = urls.map { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            return FileEntry(url: url, isDirectory: values?.isDirectory ?? false, size: Int64(values?.fileSize ?? 0))
        }.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func delete(_ entry: FileEntry) {
        try? FileManager.default.removeItem(at: entry.url)
        withAnimation { reload() }
    }
}

private struct FileEntry: Identifiable, Hashable {
    var id: String { url.path }
    var url: URL
    var isDirectory: Bool
    var size: Int64
    var name: String { url.lastPathComponent }
    var sizeText: String {
        if isDirectory { return "" }
        if size >= 1_048_576 { return String(format: "%.1f MB", Double(size) / 1_048_576) }
        if size >= 1024 { return "\(size / 1024) KB" }
        return "\(size) B"
    }
}
