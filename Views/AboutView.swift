import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.1"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image("AboutIcon")
                        .resizable()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    Text("NicheLoader")
                        .font(.largeTitle)
                        .bold()
                        .foregroundStyle(.purple)
                    Text("Version \(appVersion) (Build \(appBuild))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(EmptyView())

            Section("Credits") {
                Link(destination: URL(string: "https://github.com/noname7821")!) {
                    HStack {
                        AsyncImage(url: URL(string: "https://github.com/noname7821.png")) { image in
                            image.resizable()
                        } placeholder: {
                            Image(systemName: "person.circle.fill")
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        VStack(alignment: .leading) {
                            Text("mintoo").font(.headline)
                            Text("Solo Developer").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Text("NicheLoader signs and installs your own iOS apps on-device. Import a certificate once, then sign any IPA with your own name, identifier and version.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Our app")
            } footer: {
                Text(Bundle.main.bundleIdentifier ?? "")
            }
        }
        .navigationTitle("About")
    }
}
