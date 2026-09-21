import UniformTypeIdentifiers

extension UTType {
    static var nicheP12: UTType {
        UTType(filenameExtension: "p12", conformingTo: .data) ?? .data
    }

    static var nicheProvision: UTType {
        UTType(filenameExtension: "mobileprovision", conformingTo: .data) ?? .data
    }

    static var nicheIPA: UTType {
        UTType(filenameExtension: "ipa", conformingTo: .data) ?? .data
    }
}
