import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            FilesView()
                .tabItem { Label("Files", systemImage: "folder.fill") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.grid.2x2") }
            SourcesView()
                .tabItem { Label("Sources", systemImage: "globe.desk") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.2") }
        }
    }
}
