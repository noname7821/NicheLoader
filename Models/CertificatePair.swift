import Foundation

struct CertificatePair: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var p12FileName: String
    var provisionFileName: String
    var addedDate: Date

    init(id: String = UUID().uuidString, name: String, p12FileName: String, provisionFileName: String) {
        self.id = id
        self.name = name
        self.p12FileName = p12FileName
        self.provisionFileName = provisionFileName
        self.addedDate = Date()
    }
}
