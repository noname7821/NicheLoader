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
    var apps: [RepoApp]
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

    func fetch(_ url: URL, name: String) {
        isLoading = true
        URLSession.shared.dataTask(with: url) { data, _, _ in
            defer { DispatchQueue.main.async { self.isLoading = false } }
            guard let data,
                  let feed = try? JSONDecoder().decode(AltStoreFeed.self, from: data) else { return }
            let apps = (feed.apps ?? []).map { entry -> RepoApp in
                let version = entry.version ?? entry.versions?.first?.version ?? ""
                let link = entry.downloadURL ?? entry.versions?.first?.downloadURL
                return RepoApp(
                    id: entry.bundleIdentifier ?? entry.name ?? UUID().uuidString,
                    name: entry.name ?? "Unknown",
                    version: version,
                    downloadURL: link
                )
            }
            let source = RepoSource(url: url, name: feed.name ?? name, apps: apps)
            DispatchQueue.main.async {
                self.sources.removeAll { $0.url == url }
                self.sources.append(source)
            }
        }.resume()
    }

    func remove(_ source: RepoSource) {
        sources.removeAll { $0.id == source.id }
    }
}

struct SourcesView: View {
    @StateObject private var model = SourcesModel()
    @State private var newURL = ""
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Add source") {
                    TextField("Name", text: $newName)
                    TextField("https://…", text: $newURL)
                        .textInputAutocapitalization(.never)
                    Button("Add") {
                        guard let url = URL(string: newURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
                        model.fetch(url, name: newName.isEmpty ? url.host ?? "Source" : newName)
                        newURL = ""
                        newName = ""
                    }
                    .disabled(newURL.isEmpty)
                }
                ForEach(model.sources) { source in
                    Section(source.name) {
                        if source.apps.isEmpty {
                            Text("No apps found.").foregroundStyle(.secondary)
                        }
                        ForEach(source.apps) { app in
                            VStack(alignment: .leading) {
                                Text(app.name).font(.headline)
                                if !app.version.isEmpty {
                                    Text("v\(app.version)").font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) { model.remove(source) } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sources")
            .overlay {
                if model.isLoading { ProgressView().scaleEffect(1.4) }
            }
        }
    }
}
