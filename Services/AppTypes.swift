import UniformTypeIdentifiers

extension UTType {
    static var nicheIPA: UTType {
        UTType("com.filmeacc.nicheloader.ipa") ?? .data
    }

    static var nicheP12: UTType {
        UTType("com.filmeacc.nicheloader.p12") ?? .data
    }

    static var nicheProvision: UTType {
        UTType("com.filmeacc.nicheloader.provision") ?? .data
    }

    static var nichePlist: UTType {
        UTType(filenameExtension: "plist", conformingTo: .data) ?? .data
    }
}
