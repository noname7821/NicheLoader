import SwiftUI

@main
struct NicheLoaderApp: App {
    @StateObject private var certificates = CertificateStore()
    @StateObject private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(certificates)
                .environmentObject(library)
                .tint(Color("AccentColor"))
        }
    }
}
