import SwiftUI

struct RepoApp: Identifiable, Hashable {
    var id: String
    var name: String
    var version: String
    var downloadURL: URL?
}

struct RepoSource: Identifiable, Hashable {
    var id: String { url.absoluteString }
    var url: URL
    var name: String
    var apps: [RepoApp] = []
    var failed: Bool = false
}

struct AltStoreFeed: Decodable {
    var name: String?
    var apps: [AltStoreApp]?
}

struct AltStoreApp: Decodable {
    var name: String?
    var bundleIdentifier: String?
    var version: String?
    var downloadURL: URL?
    var versions: [AltStoreVersion]?
}

struct AltStoreVersion: Decodable {
    var version: String?
    var downloadURL: URL?
}

final class SourcesModel: ObservableObject {
    @Published var sources: [RepoSource] = []
    @Published var isLoading = false

    private let storeKey = "nicheloader.sources"

    init() {
        if let data = UserDefaults.standard.data(forKey: storeKey),
           let saved = try? JSONDecoder().decode([SavedSource].self, from: data) {
            sources = saved.compactMap {
                guard let url = URL(string: $0.url) else { return nil }
                return RepoSource(url: url, name: $0.name)
            }
        }
    }

    private func persist() {
        let saved = sources.map { SavedSource(name: $0.name, url: $0.url.absoluteString) }
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    func add(url: URL, name: String) {
        guard !sources.contains(where: { $0.url == url }) else { return }
        sources.append(RepoSource(url: url, name: name.isEmpty ? url.host ?? "Source" : name))
        persist()
        fetch(sources[sources.count - 1])
    }

    func fetchAll() {
        for source in sources { fetch(source) }
    }

    func fetch(_ source: RepoSource) {
        isLoading = true
        URLSession.shared.dataTask(with: source.url) { data, _, _ in
            var apps: [RepoApp] = []
            var ok = false
            if let data,
               let feed = try? JSONDecoder().decode(AltStoreFeed.self, from: data) {
                ok = true
                apps = (feed.apps ?? []).map { entry in
                    RepoApp(
                        id: entry.bundleIdentifier ?? entry.name ?? UUID().uuidString,
                        name: entry.name ?? "Unknown",
                        version: entry.version ?? entry.versions?.first?.version ?? "",
                        downloadURL: entry.downloadURL ?? entry.versions?.first?.downloadURL
                    )
                }
                if let feedName = feed.name, !feedName.isEmpty {
                    DispatchQueue.main.async {
                        if let i = self.sources.firstIndex(where: { $0.url == source.url }) {
                            self.sources[i].name = feedName
                            self.persist()
                        }
                    }
                }
            }
            DispatchQueue.main.async {
                self.isLoading = false
                if let i = self.sources.firstIndex(where: { $0.url == source.url }) {
                    self.sources[i].apps = apps
                    self.sources[i].failed = !ok
                }
            }
        }.resume()
    }

    func remove(_ source: RepoSource) {
        sources.removeAll { $0.id == source.id }
        persist()
    }
}

private struct SavedSource: Codable {
    var name: String
    var url: String
}

struct SourcesView: View {
    @StateObject private var model = SourcesModel()
    @State private var newURL = ""
    @State private var newName = ""
    @State private var downloading: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Add source") {
                    TextField("Name", text: $newName)
                    TextField("https://…", text: $newURL)
                        .textInputAutocapitalization(.never)
                    Button("Add") {
                        let cleaned = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let url = URL(string: cleaned) else { return }
                        withAnimation { model.add(url: url, name: newName) }
                        newURL = ""
                        newName = ""
                    }
                    .disabled(newURL.isEmpty)
                }
                .animation(.default, value: model.sources)
                ForEach(model.sources) { source in
                    Section(source.name) {
                        if source.failed {
                            Text("Could not load this source.").foregroundStyle(.secondary)
                        } else if source.apps.isEmpty {
                            Text("No apps found.").foregroundStyle(.secondary)
                        }
                        ForEach(source.apps) { app in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(app.name).font(.headline)
                                    if !app.version.isEmpty {
                                        Text("v\(app.version)").font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if app.downloadURL != nil {
                                    Button(downloading == app.id ? "Saving…" : "Get") {
                                        download(app)
                                    }
                                    .disabled(downloading != nil)
                                    .buttonStyle(.borderedProminent)
                                    .tint(.purple)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    withAnimation { model.remove(source) }
                                } label: {
                                    Label("Remove source", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .animation(.default, value: model.sources)
            .navigationTitle("Sources")
            .refreshable { model.fetchAll() }
            .overlay {
                if model.isLoading { ProgressView().scaleEffect(1.4) }
            }
            .onAppear {
                if model.sources.contains(where: { $0.apps.isEmpty && !$0.failed }) {
                    model.fetchAll()
                }
            }
        }
    }

    private func download(_ app: RepoApp) {
        guard let link = app.downloadURL else { return }
        downloading = app.id
        URLSession.shared.downloadTask(with: link) { temp, _, _ in
            defer { DispatchQueue.main.async { downloading = nil } }
            guard let temp else { return }
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let dest = docs.appendingPathComponent("Apps", isDirectory: true)
                .appendingPathComponent("\(app.name).ipa")
            try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.moveItem(at: temp, to: dest)
        }.resume()
    }
}
