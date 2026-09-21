import SwiftUI

struct RepoApp: Identifiable, Hashable {
    var id: String
    var name: String
    var version: String
    var downloadURL: URL?
    var iconURL: URL?
}

struct RepoSource: Identifiable, Hashable {
    var id: String { url.absoluteString }
    var url: URL
    var name: String
    var apps: [RepoApp] = []
    var failed: Bool = false
    var iconURL: URL?
}

struct AltStoreFeed: Decodable {
    var name: String?
    var iconURL: URL?
    var apps: [AltStoreApp]?
}

struct AltStoreApp: Decodable {
    var name: String?
    var bundleIdentifier: String?
    var version: String?
    var downloadURL: URL?
    var iconURL: URL?
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
            var feedIcon: URL?
            if let data,
               let feed = try? JSONDecoder().decode(AltStoreFeed.self, from: data) {
                ok = true
                feedIcon = feed.iconURL
                apps = (feed.apps ?? []).map { entry in
                    RepoApp(
                        id: entry.bundleIdentifier ?? entry.name ?? UUID().uuidString,
                        name: entry.name ?? "Unknown",
                        version: entry.version ?? entry.versions?.first?.version ?? "",
                        downloadURL: entry.downloadURL ?? entry.versions?.first?.downloadURL,
                        iconURL: entry.iconURL
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
                    if let icon = feedIcon {
                        self.sources[i].iconURL = icon
                    }
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

private struct RepoMenuView: View {
    @ObservedObject var model: SourcesModel
    @Binding var selectedRepo: String?
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selectedRepo = nil
                    isPresented = false
                } label: {
                    HStack {
                        Image(systemName: "square.grid.2x2")
                            .font(.title2)
                            .foregroundStyle(.purple)
                            .frame(width: 44, height: 44)
                        Text("All repositories").font(.headline)
                        Spacer()
                        if selectedRepo == nil {
                            Image(systemName: "checkmark").foregroundStyle(.purple)
                        }
                    }
                }
                ForEach(model.sources) { source in
                    Button {
                        selectedRepo = source.id
                        isPresented = false
                    } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: source.iconURL) { image in
                                image.resizable()
                            } placeholder: {
                                Image(systemName: "globe.desk.fill")
                                    .foregroundStyle(.purple)
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name).font(.headline)
                                Text("\(source.apps.count) apps")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedRepo == source.id {
                                Image(systemName: "checkmark").foregroundStyle(.purple)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            withAnimation {
                                if selectedRepo == source.id { selectedRepo = nil }
                                model.remove(source)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Repositories")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }
}

struct SourcesView: View {
    @StateObject private var model = SourcesModel()
    @State private var newURL = ""
    @State private var newName = ""
    @State private var downloading: String?
    @State private var downloadNotice: String?
    @State private var showRepos = false
    @State private var selectedRepo: String?

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
                ForEach(visibleSources) { source in
                    Section(source.name) {
                        if source.failed {
                            Text("Could not load this source.").foregroundStyle(.secondary)
                        } else if source.apps.isEmpty {
                            Text("No apps found.").foregroundStyle(.secondary)
                        }
                        ForEach(source.apps) { app in
                            HStack(spacing: 10) {
                                AsyncImage(url: app.iconURL) { image in
                                    image.resizable()
                                } placeholder: {
                                    Image(systemName: "app.fill")
                                        .foregroundStyle(.purple)
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
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
            .navigationTitle(selectedTitle)
            .navigationBarItems(
                leading: Button(action: { showRepos = true }) {
                    Image(systemName: "line.3.horizontal")
                }
            )
            .refreshable { model.fetchAll() }
            .sheet(isPresented: $showRepos) {
                RepoMenuView(
                    model: model,
                    selectedRepo: $selectedRepo,
                    isPresented: $showRepos
                )
            }
            .overlay {
                if model.isLoading { ProgressView().scaleEffect(1.4) }
            }
            .overlay(alignment: .bottom) {
                if let downloadNotice {
                    Text(downloadNotice)
                        .font(.footnote)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 12)
                }
            }
            .onAppear {
                if model.sources.contains(where: { $0.apps.isEmpty && !$0.failed }) {
                    model.fetchAll()
                }
            }
        }
    }

    private var visibleSources: [RepoSource] {
        guard let id = selectedRepo else { return model.sources }
        return model.sources.filter { $0.id == id }
    }

    private var selectedTitle: String {
        guard let id = selectedRepo,
              let source = model.sources.first(where: { $0.id == id }) else { return "Sources" }
        return source.name
    }

    private func download(_ app: RepoApp) {
        guard let link = app.downloadURL else { return }
        downloading = app.id
        downloadNotice = nil
        URLSession.shared.downloadTask(with: link) { temp, _, error in
            DispatchQueue.main.async { downloading = nil }
            let message: String
            if let error {
                message = "Download failed: \(error.localizedDescription)"
            } else if let temp {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let dest = docs.appendingPathComponent("Apps", isDirectory: true)
                    .appendingPathComponent("\(app.name).ipa")
                do {
                    try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.moveItem(at: temp, to: dest)
                    message = "Saved to Library."
                } catch {
                    message = "Save failed: \(error.localizedDescription)"
                }
            } else {
                message = "Download failed: empty response."
            }
            DispatchQueue.main.async {
                downloadNotice = message
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    if downloadNotice == message { downloadNotice = nil }
                }
            }
        }.resume()
    }
}
